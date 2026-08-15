# D2D 112G USR/XSR x8 PHY — 层级化（非黑盒）建模架构设计

> 目标：模型结构**镜像 databook 的块级层级**，每个 databook 模块对应一个 MATLAB 类，块与块之间信号可追踪、内部节点可观测（白盒），而不是一根 `runLink` 脚本的黑盒。
> 算法内容（FFE/CTLE/信道/判决的 DSP）继续复用 `D2D_PHY_SI_自己动手执行手册.md` §3 的函数，本文件只定义**结构**。

---

## 1. 层级映射（databook ↔ MATLAB 类）

databook 的功能分解（§4）与寄存器块（§11：`RX_RX_j`、`SUP_RX_SUP`、`TX_TX_j`、`SUP_TX_SUP`、`RAW_PCS_RAW_PCS`）直接对应下面的类树：

```
dwc_d2d_sr112_phy_tsmc12ffc_x8ns            D2DPHY        （PHY 顶层，§4.1）
│
├── raw_pcs  (RAW_PCS_RAW_PCS)              RawPcs        （软宏：PRBS 生成/校验、128-bit 码型、误码注入、逐 lane 控制）
│
├── TX PMA   (dwc_d2d_sr112_tx_top_x8)      TxPma
│   ├── SUP_TX_SUP                          TxSupport     （PLL 级联 / 参考时钟 / 偏置 / 端接校准，§4.3.3）
│   └── TX_TX_j  × 8                        TxLane
│       ├── TX Serializer (P2S)             Serializer    （并行→过采样串行波形，§4.3.2.1）
│       └── TX Driver                       Driver        （3-tap FFE + 电流模驱动 + 幅度 + 端接，§4.3.2.2/3/4）
│              └── FFE                      Ffe           （C-1 / C0 / C1，§4.3.2.4）
│
├── RX PMA   (dwc_d2d_sr112_rx_top_x8)      RxPma
│   ├── SUP_RX_SUP                          RxSupport     （PLL / 参考时钟 / 偏置 / CDR，§4.3.3）
│   └── RX_RX_j  × 8                        RxLane
│       ├── RX AFE                          Afe           （TERM 端接 + CTLE 0–8dB，§4.3.1.1）
│       │     ├── TERM                      Term
│       │     └── CTLE                      Ctle
│       ├── RX Slicer                       Slicer        （PAM4 3 阈值 / NRZ 1 阈值，§4.3.1.2）
│       └── RX Deserializer                 Deserializer  （串行→并行符号/比特，§4.3.1.2）
│
└── Die-to-Die Channel  × 8                 Channel       （封装互连损耗 ≤10dB，§9.2，TX 与 RX 之间）
```

**可选接口层（后置，先留占位）**：`Apb` / `Jtag` / `PipeLite` / `Ccm`（对应 §3、§5.7）。当前 SI 模型不实现协议行为，但 `cfg` 结构体即扮演「寄存器映射」角色（见 §4），未来加接口类不改层级。

---

## 2. 设计原则（保证「非黑盒」）

1. **一块一类**：databook 每个命名块 = 一个 MATLAB `classdef`，类名与 databook 块名对齐（大小写区分 MATLAB 类名）。
2. **组合即层级**：复合类持有子块对象（`TxLane` 持有 `Serializer/Ffe/Driver`），`dump()` 递归打印整棵树，运行时可直接查看结构。
3. **块间只传信号**：每个块 `run(in) -> out`，不直接改别的块的状态；配置走 `configure(cfg)`（单向、如寄存器写入）。
4. **全节点可观测**：每个块把输入/输出写进 `log`，顶层持有全部子块引用，可 `phy.rxPma.lane(1).afe.ctleOut` 直接取内部波形 —— 等价 databook §6.2 的「Analog Test Bus / on-chip eye scope」。
5. **DSP 与结构分离**：算法函数（`dspChannel/dspCtle/dspFfe/dspSlice…`）是叶子类内部调用的纯函数，换算法不影响层级。

---

## 3. 基类 `Blk`（所有块的公共契约）

**文件 `src/leaf/Blk.m`：**

```matlab
classdef (Abstract) Blk < handle
    properties
        name (1,:) char = ''      % 层级化命名，如 'dwc_d2d_sr112_phy.tx_pma.lane1.driver'
        cfg  struct = struct()    % 该块的寄存器/参数（configure 写入）
        log  struct = struct()    % 内部节点波形（白盒观测）
    end
    methods
        function obj = Blk(name)
            obj.name = name;
        end
        function configure(obj, c)
            obj.cfg = c;          % 子类覆写以解析具体字段
        end
        function out = run(obj, in) %#ok<INUSD> 子类必须实现
            error('Blk:abstract', '[%s] run() 未实现', class(obj));
        end
        function record(obj, nodeName, data)
            obj.log.(nodeName) = data;   % 记录内部节点
        end
        function dump(obj, indent)
            if nargin < 2, indent = ''; end
            fprintf('%s%s  <%s>\n', indent, obj.name, class(obj));
            if ~isempty(obj.log)
                fprintf('%s    节点: %s\n', indent, strjoin(fieldnames(obj.log), ', '));
            end
        end
    end
end
```

---

## 4. 配置 = 寄存器映射（`cfg` 用 databook 寄存器名）

模型「编程」方式对齐 databook 的寄存器语义，让配置看起来像写寄存器：

**文件 `src/config/phyConfig.m`：**

```matlab
function cfg = phyConfig()
% 生成与 databook 寄存器块对应的配置结构（名字尽量贴近寄存器/引脚）
cfg.rawPcs.pattern    = 'PRBS31';   % RAW_PCS_RAW_PCS: 码型
cfg.rawPcs.errInject  = 0;          % 误码注入

cfg.txPma.lane.txEqPre  = 0.1;      % TX_TX_j: tx_eq_pre
cfg.txPma.lane.txEqMain = 0.8;      % TX_TX_j: tx_eq_main
cfg.txPma.lane.txEqPost = 0.1;      % TX_TX_j: tx_eq_post
cfg.txPma.lane.nrzAmp   = 2;        % tx_nrz_amp_ctrl（NRZ 幅度分级）
cfg.txPma.sup.pllClkGHz = 14;       % SUP_TX_SUP: PLL 时钟（§5.5）

cfg.rxPma.lane.ctleBoost = 6;       % RX_RX_j: rx_ana_afe_ctle_boost（0–8dB）
cfg.rxPma.lane.ctleRtrim = 0.25;    % RX_RX_j: rx_ana_afe_ctle_rtrim（boost 带宽）
cfg.rxPma.lane.termMode  = 'float'; % rxX_afe_term_ctrl: pullup|float

cfg.channel.lossNyq_dB = 8;         % §9.2: Nyquist 处插损
cfg.channel.poles      = 3;         % 滚降阶数（近似封装损耗斜率）

cfg.link.modulation = 'PAM4';       % PAM4 | NRZ
cfg.link.baud_Gbps  = 56;           % 56Gbaud = 112Gbps PAM4
cfg.link.sps        = 32;           % 每 UI 采样点
cfg.link.nBits      = 2e5;
cfg.link.clockMode  = 'forwarded';  % forwarded | cdr
cfg.link.snr_dB     = 30;
cfg.link.rjUI_rms   = 0;
cfg.link.djUI_pp    = 0;
end
```

> 想更贴近 databook，可把 `cfg` 再按 32-bit 寄存器 + 位域组织（如 `TXS_CFG_0`、`ANA_OVRDVAL_*`）。SI 阶段用字段名即可，功能级阶段再升级为寄存器地址+位域。

---

## 5. 叶子类示例（算法最小单元）

以 `Channel` 为例，其余叶子（`Ffe/Ctle/Slicer/Term/Serializer/Deserializer/Pll`）同模式，内部调用手册 §3 的 DSP 函数。

**文件 `src/leaf/Channel.m`：**

```matlab
classdef Channel < Blk
    properties
        lossNyq_dB = 4
        poles = 3
        sps = 32
    end
    methods
        function obj = Channel(name)
            obj@Blk(name);
        end
        function configure(obj, c)
            configure@Blk(obj, c);
            obj.lossNyq_dB = c.lossNyq_dB;
            obj.poles      = c.poles;
            obj.sps        = c.sps;
        end
        function out = run(obj, in)
            out = dspChannel(in, obj.sps, obj.lossNyq_dB, obj.poles); % 复用 §3.4 算法
            obj.record('in', in);  obj.record('out', out);
        end
    end
end
```

> DSP 函数命名与类区分开，避免同名冲突：`channel.m→dspChannel.m`、`applyCTLE.m→dspCtle.m`、`applyFFE.m→dspFfe.m`、`slice.m→dspSlice.m`（手册 §3 的函数体不变，只改文件名与入参）。

---

## 6. 复合类示例（组合即层级）

**文件 `src/composite/TxLane.m`：**

```matlab
classdef TxLane < Blk
    properties
        serializer Serializer
        ffe        Ffe
        driver     Driver
    end
    methods
        function obj = TxLane(name)
            obj@Blk(name);
            obj.serializer = Serializer([name '.serializer']);
            obj.ffe        = Ffe([name '.ffe']);
            obj.driver     = Driver([name '.driver']);
        end
        function out = run(obj, syms)          % 并行符号进
            w = obj.serializer.run(syms);       % P2S 过采样波形
            w = obj.ffe.run(w);                 % 3-tap FFE
            out = obj.driver.run(w);            % 幅度/端接
            obj.record('txPad', out);           % 串行发送端
        end
        function dump(obj, indent)
            dump@Blk(obj, indent);
            obj.serializer.dump([indent '  ']);
            obj.ffe.dump([indent '  ']);
            obj.driver.dump([indent '  ']);
        end
    end
end
```

`RxLane` 同理：`Afe(Term+Ctle) → Slicer → Deserializer`。`TxPma/RxPma` 再各持有 8 个 lane + 1 个 support。

---

## 7. 顶层 `D2DPHY`（组装 + 全链路白盒）

**文件 `src/composite/D2DPHY.m`：**

```matlab
classdef D2DPHY < Blk
    properties
        rawPcs RawPcs
        txPma  TxPma
        rxPma  RxPma
        channel Channel     % nLane×1 向量（die-to-die 互连）
        nLane = 8
    end
    methods
        function obj = D2DPHY(name, nLane)
            if nargin<1, name = 'dwc_d2d_sr112_phy_tsmc12ffc_x8ns'; end
            if nargin<2, nLane = 8; end
            obj@Blk(name); obj.nLane = nLane;
            obj.rawPcs = RawPcs([name '.raw_pcs'], nLane);
            obj.txPma  = TxPma ([name '.tx_pma'],  nLane);
            obj.rxPma  = RxPma ([name '.rx_pma'],  nLane);
            for j = 1:nLane
                obj.channel(j) = Channel(sprintf('%s.channel%d', name, j));
            end
        end
        function configure(obj, cfg)
            configure@Blk(obj, cfg);
            obj.rawPcs.configure(cfg.rawPcs);
            obj.txPma.configure(cfg.txPma);
            obj.rxPma.configure(cfg.rxPma);
            for j = 1:obj.nLane, obj.channel(j).configure(cfg.channel); end
        end
        function out = run(obj)
            syms = obj.rawPcs.run();              % 生成逐 lane 并行符号
            pad  = obj.txPma.run(syms);           % 每 lane 串行波形(cell)
            ch = cell(1, obj.nLane);
            for j = 1:obj.nLane
                ch{j} = obj.channel(j).run(pad{j});
            end
            out = obj.rxPma.run(ch);              % 判决回并行比特
            out.errCnt = obj.rawPcs.check(out.rxBits);  % PRBS 校验器
            out.ber = out.errCnt / obj.rawPcs.nBits;
        end
        function dump(obj)
            dump@Blk(obj, '');
            obj.rawPcs.dump('  ');
            obj.txPma.dump('  ');
            obj.rxPma.dump('  ');
        end
    end
end
```

---

## 8. 白盒使用方式（与黑盒的对比）

```matlab
cfg = phyConfig();
phy = D2DPHY();                % 组装整棵层级树
phy.configure(cfg);

res = phy.run();               % 跑一次
fprintf('BER = %.3e\n', res.ber);

phy.dump();                    % 打印完整层级 + 每块内部节点（结构可视化）

% —— 任意内部节点观测（= databook 的 Analog Test Bus / eye scope）——
phy.txPma.lane(1).ffe.out          % FFE 输出
phy.txPma.lane(1).driver.txPad     % TX 焊盘端波形
phy.channel(1).out                 % 信道输出
phy.rxPma.lane(1).afe.ctleOut      % CTLE 输出（眼图观测点）
phy.rxPma.lane(1).slicer.in        % 判决前波形
phy.rxPma.lane(1).deserializer.rxBits
phy.rawPcs.errCnt                  % PRBS 校验器误码数

plotEye(phy.rxPma.lane(1).afe.ctleOut, cfg.link.sps);   % 任意节点画眼图
```

黑盒 vs 白盒对照：

| 黑盒（旧 `runLink`） | 白盒（本架构） |
|---|---|
| 一根函数从比特算到 BER | 每块一个类，块间信号可见 |
| 只能看最终 BER/眼图 | 任意内部节点可探针/画眼图 |
| 结构不透明 | `dump()` 打印 databook 同构层级 |
| 改算法要动主函数 | 只换对应叶子类的 DSP，层级不动 |

---

## 9. 文件布局（类版）

```
D2D_Modelization/
├── src/
│   ├── dsp/                # dspPrbs/dspMap/dspFfe/dspChannel/dspCtle/dspSlice/dspSample/dspAlign
│   ├── utils/              # plotEye/eyeHeight/ffeEqDb/verifyChannel
│   ├── leaf/               # Blk + Serializer/Ffe/Driver/Term/Ctle/Slicer/Deserializer/Channel/Pll
│   ├── composite/          # Afe、lane、PMA、support、RawPcs、D2DPHY
│   └── config/phyConfig.m  # 寄存器映射式配置
├── test/                   # smoke、行为、均衡和 T1–T9 回归
└── results/
```

> 可选：用 **System Composer**（本机已装）画一张与上面树一致的架构图，作为「databook 层级」的可视化交付物；代码仍用上述类结构。

---

## 10. 与执行手册的关系

- 手册 §3 的每个函数（`channel/applyCTLE/applyFFE/slice/…`）→ 改名为 `dsp*`，变成对应叶子类的内部算法。
- 手册 §3.10 的 `runLink` 顶层 → 被 `D2DPHY.run()` 取代，但其数据流（码型→映射→FFE→驱动→信道→CTLE→判决→BER）在类树中不变。
- 手册 §6 测试与 §7 平台化保持不变，只是把 `runLink(p)` 换成 `phy = D2DPHY(); phy.configure(cfg); phy.run()`。
