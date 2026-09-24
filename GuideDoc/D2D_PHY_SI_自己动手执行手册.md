# D2D 112G USR/XSR x8 PHY — 自己动手执行手册（MATLAB）

> 配套文档：`D2D_PHY_SI建模与测试方案.md`（架构/参数台账/风险在此）、`D2D_PHY_SI_层级化架构设计.md`（**databook 同构层级 + 白盒观测**，模型结构以它为准）。
> 前提：本机 MATLAB R2024b 已激活，且 SerDes / Signal Integrity / Communications / DSP System / Signal Processing 工具箱齐备。
> 目标：从零搭一个**系统级 SI 链路模型**（非黑盒，层级对齐 databook），跑出眼图 / BER / 均衡调参结果。
>
> ⚠️ 结构说明：本手册 §3 的每个函数是「叶子块的算法」，最终按层级架构文档 §9 的类树组装成 `D2DPHY`（非黑盒）。先看架构文档，再回本手册实现算法。

---

## 0. 快速开始（先看到结果，再逐个吃透）

分类源码就位后，在 MATLAB 命令行运行：

```matlab
addpath(genpath('src'));
cfg = phyConfig('ideal');
phy = D2DPHY();
phy.configure(cfg);
r = phy.run();
fprintf('BER = %.3e\n', r.aggregateBer);
plotEye(phy.rxPma.lane(1).afe.ctleOut, cfg.link.sps);
```

预期：理想信道（无损耗/无噪声/无抖动）下 `BER = 0.000e+00`，内部探针和眼图均可访问。

> 约定：`.m` 文件按职责放在 `src/dsp`、`src/utils`、`src/leaf`、`src/composite`、`src/config`，入口统一执行 `addpath(genpath('src'))`。

---

## 1. 环境自检（5 分钟）

在 MATLAB 命令行运行，确认依赖都在：

```matlab
assert(exist('bilinear','file'),    '缺 Signal Processing Toolbox');
assert(exist('findpeaks','file'),   '缺 Signal Processing Toolbox');
assert(exist('repelem','builtin'),  'MATLAB 版本过旧(R2015a+)');
disp('环境 OK');
```

目录建议：

```
E:\Desktop_use\D2D_Modelization\
├── src\          # 所有 .m（本手册代码）
├── test\         # 阶段 5 的回归脚本
└── results\      # 眼图/BER/报告输出
```

---

## 2. 阶段 0：参数台账（`params.m`）

全部可调量集中在一个函数里，每个字段注释标注 databook 出处。

**文件 `src/params.m`：**

```matlab
function p = params()
% params —— D2D 112G USR/XSR x8 PHY 系统级 SI 模型参数
% 每个字段注释标注 databook 章节号，数值对应方案文档 §2 台账。

% ---------- 链路速率 ----------
p.baud_Gbps = 56;        % 波特率 [Gbaud]。PAM4 56Gbaud=112Gbps；NRZ 28Gbaud=28Gbps（§5.5）
p.modulation = 'PAM4';   % 'PAM4' | 'NRZ'（§1.3）
p.sps = 32;              % 每符号(UI)采样点数，眼图分辨率（越大越细、越慢）
p.nBits = 2e5;           % 仿真比特数（PAM4 时须为偶数）

% ---------- 符号电平（§7.3 Table 7-2）----------
p.pam4Levels = [-3 -1 +1 +3];
p.nrzLevels  = [-1 +1];
p.nrzAmp     = 2;        % tx_nrz_amp_ctrl=10 -> ±2（§3.8 信号描述）

% ---------- TX 3-tap FFE（§4.3.2.4）----------
% C0=tx_eq_main；|C-1|=tx_eq_pre；|C1|=tx_eq_post；后两者为负值
p.txEqMain = 1.0;
p.txEqPre  = 0.0;
p.txEqPost = 0.0;
p.ffeNormalize = true;   % true: 抽头归一化 |C-1|+C0+|C1|=满幅

% ---------- 信道（§1.2 / §9.2：D2D ≤10 dB）----------
p.channelLossNyq_dB = 0;  % Nyquist(baud/2) 处插损 [dB]，扫描 0/4/8/10
p.channelPoles      = 3;  % 级联一阶低通阶数（决定滚降陡峭度）

% ---------- RX CTLE（§4.3.1.1：0–8 dB）----------
p.ctleBoost_dB = 0;       % 0..8 dB 可编程 boost
p.ctleFz      = 0.25;     % 零点位置（归一化 cycles/UI），近似 boost 带宽

% ---------- 噪声 / 抖动 ----------
p.snr_dB   = inf;         % 判决前加性 AWGN 信噪比 [dB]，inf=不加
p.rjUI_rms = 0;           % 随机抖动 RMS [UI]
p.djUI_pp  = 0;           % 确定性抖动峰峰 [UI]

% ---------- 码型（§1.3 / §6.2）----------
p.pattern   = 'PRBS31';   % 'PRBS7'|'PRBS15'|'PRBS31'|'PRQS10'(近似)
p.errInject = 0;          % 注入误码数（测试 T6）
p.skipUI    = 50;         % 测量前跳过的起始 UI 数（滤除滤波器瞬态）

% ---------- 时钟 / CDR（§5.6）----------
p.clockMode = 'forwarded';% 'forwarded' | 'cdr'
p.cdrBw     = 0.01;       % CDR 环路带宽（相对 baud，仅 clockMode='cdr' 用）
end
```

**验收**：`p = params()` 不报错，字段齐全。

---

## 3. 阶段 1：理想链路（先跑通，出第一张眼图）

目标：码型源 → 符号映射 → FFE → 驱动 →（无损耗信道）→（无 CTLE）→ 判决 → BER，`BER=0`。

### 3.1 码型源

**文件 `src/prbs.m`（自写 LFSR，零依赖）：**

```matlab
function bits = prbs(taps, n)
% 自写 LFSR 生成 PRBS（Fibonacci 型），taps 为反馈抽头(1-based，含最高位)
% PRBS7: taps=[7 6]; PRBS15: [15 14]; PRBS31: [31 28]
order = max(taps);
reg = ones(1, order);              % 初值全 1（非零即可）
bits = zeros(n, 1);
for i = 1:n
    bits(i) = reg(order);          % 输出最末位
    fb = mod(sum(reg(taps)), 2);   % 抽头异或（=求和 mod 2）
    reg = [fb, reg(1:end-1)];      % 右移，新位进最前
end
end
```

**文件 `src/genPattern.m`：**

```matlab
function bits = genPattern(p)
% 生成测试比特流（§1.3/§6.2：PRBS7/15/31、PRQS10 近似、误码注入）
switch upper(p.pattern)
    case 'PRBS7',  bits = prbs([7 6],  p.nBits);
    case 'PRBS15', bits = prbs([15 14], p.nBits);
    case 'PRBS31', bits = prbs([31 28], p.nBits);
    case 'PRQS10'
        % 简化：两条独立 PRBS 分别驱动 PAM4 的 MSB/LSB。
        % 严格 PRQS10(GF(4) 10 阶四进制 LFSR) 作为后续可选实现。
        m = ceil(p.nBits/2);
        msb = prbs([10 7], m); lsb = prbs([10 3], m);
        bits = reshape([msb(:) lsb(:)]', [], 1);
    otherwise, error('未知码型: %s', p.pattern);
end
% 误码注入（测试 T6）
if p.errInject > 0
    pos = randi(numel(bits), p.errInject, 1);
    bits(pos) = 1 - bits(pos);
end
end
```

### 3.2 符号映射（§7.3 编码）

**文件 `src/mapSymbols.m`：**

```matlab
function [syms, bps] = mapSymbols(bits, p)
% 比特 -> 符号。PAM4: 2 比特/符号，唯一 Gray contract（00=-3, 01=-1, 11=+1, 10=+3）
if strcmp(p.modulation, 'PAM4')
    bps = 2;
    nSym = floor(numel(bits)/bps);
    pairs = reshape(bits(1:nSym*bps), bps, nSym)';
    c = dspPam4Contract(); [~,idx] = ismember(pairs,c.bitPairs,'rows');
    syms = c.levels(idx)';
else
    bps = 1;
    syms = 2*bits(:) - 1;                           % 0->-1, 1->+1
end
end
```

### 3.3 TX 3-tap FFE（§4.3.2.4）

**文件 `src/applyFFE.m`：**

```matlab
function y = applyFFE(syms, p)
% 3-tap FFE（符号级）。§4.3.2.4：C-1 前游标、C1 后游标均为负值
% y[n] = C0*s[n] + C_{-1}*s[n+1] + C_{+1}*s[n-1]
C0  = p.txEqMain;
Cm1 = -p.txEqPre;   % 前游标(负)，乘未来符号
Cp1 = -p.txEqPost;  % 后游标(负)，乘过去符号

y = C0*syms;
y = y + Cm1*[syms(2:end); 0];        % s[n+1]
y = y + Cp1*[0; syms(1:end-1)];      % s[n-1]

% 归一化：|C-1|+C0+|C1| = 满幅（电流模 driver 抽头和守恒）
if p.ffeNormalize
    tot = abs(Cm1) + C0 + abs(Cp1);
    y = y / tot;
end
end
```

**文件 `src/ffeEqDb.m`（用 §4.3.2.4 公式回算预/后加重 dB，便于互校）：**

```matlab
function [preDb, postDb] = ffeEqDb(p)
C0 = p.txEqMain; Cm1 = -p.txEqPre; Cp1 = -p.txEqPost;
preDb  = 20*log10((C0 - Cm1 - Cp1)/(C0 + Cm1 - Cp1));
postDb = 20*log10((C0 - Cm1 - Cp1)/(C0 - Cm1 + Cp1));
end
```

### 3.4 信道（阶段 1 先跑零损耗版，阶段 2 才开启）

**文件 `src/channel.m`：**

```matlab
function y = channel(x, p)
% 级联一阶低通信道，目标：Nyquist(0.5 cyc/UI) 处插损 = p.channelLossNyq_dB（§9.2）
% 单级 |H(f)|^2 = 1/(1+(f/fp)^2)，K 级联 => loss_dB(f) = K*10*log10(1+(f/fp)^2)
sps  = p.sps;
fnyq = 0.5;                                 % 归一化 Nyquist (cycles/UI)
K    = max(1, round(p.channelPoles));
Llin = 10^(p.channelLossNyq_dB/10);         % 功率比
fp   = fnyq / sqrt(Llin^(1/K) - 1);         % 单级 -3dB 点 (cycles/UI)
a    = exp(-2*pi*fp/sps);                   % 离散一阶极点（冲激不变近似）
y = x;
for k = 1:K
    y = filter(1-a, [1 -a], y);             % 每级 DC 增益 = 1
end
end
```

### 3.5 CTLE（阶段 2 才开启，先建好）

**文件 `src/applyCTLE.m`：**

```matlab
function y = applyCTLE(x, p)
% CTLE（§4.3.1.1）：H(s)=(s+ωz)/(s+ωp)，DC 衰减=boost_dB，高频增益=1
% ωp = ωz * 10^(boost/20)，故 boost = 20log10(ωp/ωz)
sps = p.sps;
fz  = max(p.ctleFz, 1e-3);                 % 零点 (cycles/UI)
fp  = fz * 10^(p.ctleBoost_dB/20);         % 极点
wz = 2*pi*fz; wp = 2*pi*fp;
[num, den] = bilinear([1 wz], [1 wp], sps);% 双线性离散化（Signal Processing Toolbox）
y = filter(num, den, x);
end
```

### 3.6 判决 Slicer（§3.7 + §7.3）

**文件 `src/slice.m`：**

```matlab
function bits = slice(yDec, p)
% 判决：PAM4 阈值 -2,0,+2；NRZ 阈值 0；按 Gray contract 编码回比特
if strcmp(p.modulation, 'PAM4')
    v = yDec(:);
    c = dspPam4Contract(); idx = 1 + sum(v >= c.thresholds,2); sym = c.levels(idx)';
    bits = zeros(2*numel(sym), 1);
    for k = 1:numel(sym)
        switch sym(k)
            case  3, b = [1 0];
            case  1, b = [1 1];
            case -1, b = [0 1];
            otherwise, b = [0 0];
        end
        bits(2*k-1:2*k) = b;
    end
else
    bits = double(yDec(:) >= 0);
end
end
```

### 3.7 采样 + 抖动（阶段 3 才开启，先建好）

**文件 `src/sampleWithJitter.m`：**

```matlab
function yDec = sampleWithJitter(x, ph, d, p)
% 每个 UI 判决时刻采样（含 RJ/DJ；可选一阶 CDR 跟踪，§3.8/§5.6）
sps = p.sps;
bps = 1 + strcmp(p.modulation,'PAM4');
nSym = floor(p.nBits/bps);
n = (0:nSym-1)';

rj = p.rjUI_rms * randn(nSym,1);
dj = (p.djUI_pp/2) * sin(2*pi*1e-3*n);       % 慢速正弦 DJ
jitUI = rj + dj;

if strcmp(p.clockMode, 'cdr')                % 一阶 CDR：追踪慢漂移、抑制高频 RJ
    K = 2*pi*p.cdrBw;
    jitUI = filter(K, [1 -(1-K)], jitUI);
end

idx = (0:nSym-1)*sps + ph + 1 + d*sps + round(sps*jitUI);
idx = max(1, min(numel(x), idx));
yDec = x(idx);
end
```

### 3.8 对齐 + BER 测量（暴力搜索时序，最稳）

**文件 `src/alignAndMeasure.m`：**

```matlab
function [ber, d, ph, nErr, nBits] = alignAndMeasure(x, txBits, p)
% 暴力搜索 (整数符号时延 d, 相位 ph) 使误码最小，返回 BER 与最佳时序。
% 这是仿真自检台：我们知道发端比特，用搜索自动吸收群时延与相位。
sps = p.sps;
bps = 1 + strcmp(p.modulation,'PAM4');
nSym = floor(p.nBits/bps);
dRange = -12:12;
bestErr = inf; bestD = 0; bestPh = 0;

for dd = dRange
    for pp = 0:sps-1
        idx = (0:nSym-1)*sps + pp + 1 + dd*sps;
        idx = idx(idx >= 1 & idx <= numel(x));
        if numel(idx) < nSym*0.8, continue; end
        rxBits = slice(x(idx), p);
        nb = min(numel(txBits), numel(rxBits));
        start = p.skipUI*bps + 1;                    % 跳过滤波器起始瞬态
        txSeg = txBits(start:nb);
        rxSeg = rxBits(start:nb);
        err = sum(txSeg ~= rxSeg);
        if err < bestErr, bestErr = err; bestD = dd; bestPh = pp; end
    end
end
nErr = bestErr; nBits = p.nBits; ber = nErr/nBits;
d = bestD; ph = bestPh;
end
```

### 3.9 眼图 + 眼高

**文件 `src/plotEye.m`：**

```matlab
function plotEye(x, p)
sps = p.sps;
nUI = floor(numel(x)/sps) - 1;
seg = reshape(x(1:nUI*sps), sps, nUI);
t = (0:sps-1)/sps;
figure;
plot(t, seg, 'Color', [0 0 0.6 0.08]);
xlabel('UI'); ylabel('幅度 (归一化)');
title(sprintf('%s 眼图  (%.0f Gbaud)', p.modulation, p.baud_Gbps));
grid on;
end
```

**文件 `src/eyeHeight.m`：**

```matlab
function h = eyeHeight(x, ph, p)
% 在相位 ph 采样，直方图找电平峰，眼高 = 相邻峰最小间距
sps = p.sps;
nLvl = 2 + 2*strcmp(p.modulation,'PAM4');   % NRZ=2, PAM4=4
s = x(ph+1 : sps : end);
[ct, edges] = histcounts(s, 256);
centers = (edges(1:end-1) + edges(2:end))/2;
w = smooth(ct, 9);
[pks, locs] = findpeaks(w, 'MinPeakDistance', 20, 'SortStr','descend', 'NPeaks', nLvl);
if numel(locs) < 2, h = 0; return; end
lv = sort(centers(locs));
h = min(diff(lv));
end
```

### 3.10 顶层 `runLink.m`

**文件 `src/runLink.m`：**

```matlab
function out = runLink(p)
% 顶层：bits -> symbols -> FFE -> 驱动 -> 信道 -> CTLE -> 噪声 -> 抖动采样 -> 判决 -> BER
if nargin<1 || isempty(p), p = params(); end
if strcmp(p.modulation,'PAM4') && mod(p.nBits,2), error('PAM4 下 nBits 须为偶数'); end

txBits = genPattern(p);                 % 1 码型
[syms, ~] = mapSymbols(txBits, p);      % 2 符号映射
symsEq = applyFFE(syms, p);             % 3 TX FFE
x = repelem(symsEq(:), p.sps, 1);       % 4 驱动（每符号保持 sps 样本）
x = channel(x, p);                      % 5 信道
x = applyCTLE(x, p);                    % 6 CTLE
if isfinite(p.snr_dB)                   % 7 加性噪声
    x = x + 10^(-p.snr_dB/20)*rms(symsEq)*randn(size(x));
end
[ber, d, ph, nErr, nBits] = alignAndMeasure(x, txBits, p);  % 8 时序搜索+BER
eyeH = eyeHeight(x, ph, p);             % 9 眼高

out = struct('txBits',txBits,'x',x,'symsEq',symsEq, ...
             'ber',ber,'nErr',nErr,'nBits',nBits, ...
             'delaySym',d,'bestPhase',ph,'eyeHeight',eyeH);
end
```

### 3.11 阶段 1 验收

```matlab
p = params();              % 默认理想：loss=0, boost=0, snr=inf, jitter=0
r = runLink(p);
fprintf('BER = %.3e   眼高 = %.3f   时延 = %d UI   相位 = %d\n', ...
        r.ber, r.eyeHeight, r.delaySym, r.bestPhase);
plotEye(r.x, p);
```

✅ **验收标准**：`BER == 0`，眼图 4 条（PAM4）清晰分开、无交叉。

---

## 4. 阶段 2：加信道损耗 + CTLE

### 4.1 先验证信道插损曲线（可选但建议）

**文件 `src/verifyChannel.m`：**

```matlab
function verifyChannel(p)
% 正弦扫频测实际插损，验证 Nyquist 处 ≈ p.channelLossNyq_dB
sps = p.sps; n = 2^14;
t = (0:n-1)/sps;
freqs = [0.1 0.25 0.5];                 % 测试频点 (cycles/UI)
for f = freqs
    y = channel(sin(2*pi*f*t(:)), p);
    ss = floor(n*0.8);
    fprintf('f=%.2f cyc/UI: loss = %.2f dB\n', f, ...
            20*log10(rms(y(ss:end))/rms(sin(2*pi*f*t(ss:end)))));
end
end
```

### 4.2 阶段 2 验收

```matlab
% (a) 8dB 损耗信道 + 未均衡 → 眼图闭合、BER 上升
p1 = params(); p1.channelLossNyq_dB = 8; p1.snr_dB = 30;
r1 = runLink(p1);
fprintf('未均衡:   BER = %.3e   眼高 = %.3f\n', r1.ber, r1.eyeHeight);
plotEye(r1.x, p1); title('8dB 损耗信道 + 未均衡');

% (b) 同样信道 + CTLE boost=8dB → 眼图重开、BER 下降
p2 = p1; p2.ctleBoost_dB = 8;
r2 = runLink(p2);
fprintf('CTLE 8dB: BER = %.3e   眼高 = %.3f\n', r2.ber, r2.eyeHeight);
plotEye(r2.x, p2); title('8dB 损耗信道 + CTLE 8dB');
```

✅ **验收标准**：`r2.ber < r1.ber`（CTLE 有效），`r2.eyeHeight > r1.eyeHeight`。

---

## 5. 阶段 3：抖动 / 噪声 / CDR

### 5.1 验收

```matlab
% (a) BER 随 RJ 幅度单调上升
p = params(); p.channelLossNyq_dB = 4; p.ctleBoost_dB = 4; p.snr_dB = 30;
for rj = [0 0.02 0.05 0.1 0.2]
    q = p; q.rjUI_rms = rj;
    r = runLink(q);
    fprintf('RJ=%.2f UI -> BER=%.3e\n', rj, r.ber);
end

% (b) CDR 带宽扫描（存在最优区间）
p = params(); p.channelLossNyq_dB = 4; p.ctleBoost_dB = 4; p.snr_dB = 30;
p.rjUI_rms = 0.05; p.djUI_pp = 0.1; p.clockMode = 'cdr';
for bw = [0.001 0.003 0.01 0.03 0.1 0.3]
    q = p; q.cdrBw = bw;
    r = runLink(q);
    fprintf('CDR bw=%.3f -> BER=%.3e\n', bw, r.ber);
end
```

✅ **验收标准**：(a) BER 随 RJ 单调上升；(b) BER 随 bw 先降后升（存在最优带宽）。

---

## 6. 阶段 4：均衡调参自动扫描

**文件 `test/sweep_eq.m`：**

```matlab
% sweep_eq —— FFE(pre/post) × CTLE(boost) 网格扫描，找最小 BER
p = params();
p.channelLossNyq_dB = 8;   % 固定信道
p.snr_dB = 30;             % 固定噪声
p.nBits  = 2e5;
preList  = 0:0.1:0.5;
postList = 0:0.1:0.5;
boostList = 0:2:8;

best = struct('ber', inf);
for pre = preList
    for post = postList
        for boost = boostList
            q = p; q.txEqPre = pre; q.txEqPost = post; q.ctleBoost_dB = boost;
            r = runLink(q);
            if r.ber < best.ber
                best = r; best.pre = pre; best.post = post; best.boost = boost;
            end
        end
    end
end
fprintf('最优: pre=%.1f post=%.1f boost=%.0f dB -> BER=%.3e\n', ...
        best.pre, best.post, best.boost, best.ber);
[preDb, postDb] = ffeEqDb(setfield(p,{'txEqPre','txEqPost'},{best.pre,best.post}));
fprintf('对应加重: PRE=%.2f dB  POST=%.2f dB\n', preDb, postDb);
```

> 注意：扫描时保持 `txEqMain=1` 且 `txEqPre+txEqPost < 1`，避免抽头过度导致电平坍塌。

✅ **验收标准**：跑出最优 (pre, post, boost) 组合，BER 显著低于「不均衡」基线；`ffeEqDb` 输出的 dB 与手算一致。

---

## 7. 阶段 5：测试平台化（回归 + 报告）

把 §6 测试项（T1–T9）固化成脚本 `test/run_all_tests.m`，一条命令出报告。

**文件 `test/run_all_tests.m`（骨架）：**

```matlab
function report = run_all_tests()
addpath('../src');
report = table();   % 每行一条测试结果

% T1 眼图（保存 PNG）
p = params(); p.channelLossNyq_dB = 8; p.ctleBoost_dB = 6;
r = runLink(p); plotEye(r.x, p);
print('../results/eye_112G_PAM4_8dB.png','-dpng');

% T2 BER vs 信道损耗
p = params(); p.snr_dB = 30; p.ctleBoost_dB = 6; p.nBits = 2e5;
for L = [0 4 8 10]
    q = p; q.channelLossNyq_dB = L;
    rr = runLink(q);
    fprintf('T2 loss=%2ddB -> BER=%.3e\n', L, rr.ber);
end

% T3 浴盆曲线（扫采样相位看误码）
p = params(); p.channelLossNyq_dB = 8; p.ctleBoost_dB = 6; p.snr_dB = 30;
r = runLink(p);
sps = p.sps; bps = 1 + strcmp(p.modulation,'PAM4'); nSym = floor(p.nBits/bps);
for off = 0:sps-1
    idx = (0:nSym-1)*sps + off + 1 + r.delaySym*sps;
    idx = idx(idx>=1 & idx<=numel(r.x));
    rb = slice(r.x(idx), p);
    nb = min(numel(r.txBits), numel(rb));
    fprintf('T3 phase=%-2d -> BER=%.3e\n', off, sum(r.txBits(1:nb)~=rb(1:nb))/nb);
end

% T4/T5/T6/T7/T8/T9 …（按方案文档 §6 逐项补全，结构同上）
end
```

> 关键映射（SI 模型里怎么表达 databook 的概念）：
> - **T6 码型校验**：`p.errInject = N` 后，`r.nErr` 应精确等于 N（无噪声时）。
> - **T9 三级 loopback**：`shallow` ≈ 无信道直接环回（FFE 后即返回）；`die-to-die` ≈ 信道串联两次 `channel(channel(x))`（TX→RX→TX→RX 往返），且仅 NRZ。
> - **PAM4 vs NRZ（T7）**：同 baud 下改 `p.modulation`，PAM4 对噪声更敏感（BER 更高）符合预期。

---

## 8. 调试 FAQ

| 现象 | 原因 / 处理 |
|---|---|
| 理想信道 BER 也不为 0 | 检查 `skipUI` 是否过小（瞬态未滤除）；或 `txEqPre/Post` 过大导致电平坍塌（保持和 < 主抽头） |
| 眼图为空/全 0 | `plotEye` 前确认 `numel(r.x) >= sps*100`；`nBits` 别太小 |
| `bilinear`/`findpeaks` 报错 | Signal Processing Toolbox 未在路径，跑第 1 节自检 |
| BER 扫描极慢 | 降 `p.nBits`（1e5 足够）、降 `sps`（16 起）、或用 `parfor`（Parallel Computing Toolbox）并行外层循环 |
| 眼高为 0 | `findpeaks` 没找到足够电平峰：增大 `smooth` 窗口或 `histcounts` 的 bin 数；确认信道未完全闭合 |

---

## 9. 交付物清单（做完后应有）

**类层级（结构，见 `D2D_PHY_SI_层级化架构设计.md`）：**

```
D2D_Modelization/
├── src/
│   ├── dsp/                # 8 个 dsp* 纯算法函数
│   ├── utils/              # plotEye/eyeHeight/verifyChannel/ffeEqDb
│   ├── leaf/               # Blk + 9 个叶子类
│   ├── composite/          # Afe、lane、PMA、support、RawPcs、D2DPHY
│   └── config/phyConfig.m  # 寄存器映射式配置
├── test/                   # smoke、行为、均衡和 T1–T9 回归
└── results/                # PNG、CSV、MAT、JSON、JUnit 输出
```

**纯算法函数（手册 §3，供叶子类调用，`*` 为改名后的 `dsp*` 名）：**

```
src/dsp/   dspChannel.m, dspCtle.m, dspFfe.m, dspSlice.m,
           dspPrbs.m, dspMap.m, dspSample.m, dspAlign.m
src/utils/ plotEye.m, eyeHeight.m, verifyChannel.m, ffeEqDb.m
```

---

## 10. 任务点执行清单（建议的推进路线，逐个打勾）

> 铁律：① 先算法后结构（任务点 2 先行）；② 每个任务点验收通过再进下一个；③ 每完成一块就用 `phy.xxx.dump()` / 探针确认「不是黑盒」。

| # | 任务点 | 产出 | 预计 | 依赖 |
|---|---|---|---|---|
| 1 | ✅ 环境与目录 | `src/ test/ results/` + 工具箱自检通过 | 0.5h | — |
| 2 | ✅ DSP 算法函数 | `src/dsp/dsp*.m` ×8 + `src/utils/` 工具 | 2–3h | 1 |
| 3 | ✅ 叶子类 | `Blk` + `Serializer/Ffe/Driver/Term/Ctle/Slicer/Deserializer/Channel/Pll` | 1–2h | 2 |
| 4 | ✅ 复合类 + 顶层 | `TxLane/RxLane/TxPma/RxPma/TxSupport/RxSupport/RawPcs/D2DPHY/phyConfig` | 1–2h | 3 |
| 5 | ✅ 基线验证 | 理想链路 BER=0 + 白盒探针全部可观测 | 1h | 4 |
| 6 | ✅ 行为测试 | 信道/CTLE/抖动/CDR 趋势测试脚本 | 1–2h | 5 |
| 7 | ✅ 均衡调参扫描 | 最优 (pre,post,boost) + `ffeEqDb` 自检 | 1–2h | 5 |
| 8 | ✅ 回归平台 + 报告 | `run_all_tests.m`（T1–T9）+ `results/` 输出 | 1–2h | 6,7 |

### 任务点 1 — 环境与目录
```matlab
mkdir src test results
assert(exist('bilinear','file')); assert(exist('findpeaks','file')); assert(exist('repelem','builtin'));
disp('环境 OK');
```
✅ 命令行输出 `环境 OK`。

### 任务点 2 — DSP 算法函数（最大的一块代码）
- 按手册 §3 抄代码、改名、改成显式入参（类里按块传参）：
  `dspPrbs(taps,n)`、`dspMap(bits,modulation)`、`dspFfe(syms,main,pre,post,norm)`、`dspChannel(x,sps,lossDb,poles)`、`dspCtle(x,sps,boostDb,fz)`、`dspSlice(y,modulation)`、`dspSample(x,ph,d,sps,jitUI)`、`dspAlign(x,txBits,modulation,sps,skipUI)`。
- 另建 `plotEye.m / eyeHeight.m / ffeEqDb.m / verifyChannel.m`（手册 §3.9、§3.4、§3.3）。
✅ 最小自测：
```matlab
dspChannel(sin((0:1000)'/32),32,0,3)   % 0dB -> 与输入几乎一致
dspMap([0 0 0 1 1 1 1 0]','PAM4')'     % 预期 [-3 -1 1 3]
dspFfe([-3 -1 1 3]',1,0,0,true)        % pre=post=0 -> 原样
```

### 任务点 3 — 叶子类
按架构文档 §3/§5：先 `Blk.m`，再逐个叶子类（每块：属性=参数、`configure` 解析、`run` 调 `dsp*` 并 `record`）。
✅ 逐个验收：
```matlab
ch = Channel('ch0');
ch.configure(struct('lossNyq_dB',4,'poles',3,'sps',32));
out = ch.run(randn(3200,1)); ch.dump();   % 打印名字+节点列表，out 长度不变
```

### 任务点 4 — 复合类 + 顶层组装
按架构文档 §6/§7 骨架补全 `TxLane/RxLane/TxPma/RxPma/TxSupport/RxSupport/RawPcs`，最后 `D2DPHY` + `phyConfig.m`。
✅ 全链路跑通：
```matlab
cfg = phyConfig('ideal'); phy = D2DPHY(); phy.configure(cfg);
res = phy.run(); phy.dump();               % 打印整棵 databook 同构层级树
```

### 任务点 5 — 基线验证（第一个里程碑）
把 `phyConfig` 设为理想：`loss=0, boost=0, snr=inf, jitter=0`。
✅ 验收：
```matlab
fprintf('BER=%.3e\n', res.ber);           % 预期 0
plotEye(phy.rxPma.lane(1).afe.ctleOut, cfg.link.sps);  % 眼图全开
phy.txPma.lane(1).driver.txPad             % 探针有波形
```

### 任务点 6 — 行为测试（信道/CTLE/抖动/CDR）
建 `test/behavior_tests.m`（手册 §4/§5 的验收代码搬进来，`runLink(p)` → `phy.run()`）。
✅ 四个趋势都符合预期：BER 随损耗上升；CTLE 恢复眼图；BER 随 RJ 单调；CDR 带宽存在最优。

### 任务点 7 — 均衡调参扫描
建 `test/sweep_eq.m`（手册 §6），在类上扫 FFE(pre/post)×CTLE(boost)。
✅ 输出最优组合 + BER 显著低于基线；`ffeEqDb` 的 PRE/POST dB 与手算一致。

### 任务点 8 — 回归平台 + 报告
建 `test/run_all_tests.m` 固化 T1–T9（手册 §7），结果写 `results/`。
✅ 一条命令跑完全部测试，`results/` 有眼图 PNG + BER 汇总表。

---

需要的话，我可以**直接把这套类骨架 + `dsp*` 算法函数 + 测试脚本全部生成到 `src/` 和 `test/`**，你拿到手只做两件事：读代码 + 按任务点 5–8 逐条验收；也可以你照本手册自己逐个敲（更利于吃透）。你说用哪种方式，我就照做。
