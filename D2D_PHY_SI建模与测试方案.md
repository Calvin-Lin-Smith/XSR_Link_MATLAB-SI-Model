# Die-to-Die 112G USR/XSR x8 PHY — MATLAB 系统级 SI 建模与测试方案

> 对象：Synopsys DesignWare `dwc_d2d_sr112_phy_tsmc12ffc_x8ns`
> 依据：`Reference/Die-to-Die 112G USRXSR x8 PHY for TSMC 12-nm FFC1.8V Databook.pdf`（v2.02a）
> 目标：只用 databook，在 **MATLAB R2024b** 里搭一个**系统级信号完整性（SI）行为模型**，能跑眼图 / BER / 均衡调参测试。
> 性质：行为级/系统级模型，**不是**与硅片逐比特一致的 RTL/晶体管级模型。

---

## 0. 结论摘要（TL;DR）

| 项 | 结论 |
|---|---|
| 建模层次 | 系统级 SI 链路模型（TX 码型源 → FFE → 驱动 → 信道 → CTLE → 判决 → BER 统计） |
| 核心工具 | MATLAB R2024b，**手写 DSP 链路模型为主**（逐块对照 databook 公式），**SerDes Toolbox / Signal Integrity Toolbox 做眼图/BER/浴盆曲线交叉验证** |
| 数据率覆盖 | NRZ 2.5–56 Gbps；PAM4 56–112 Gbps（波特率 1.75–112 GSps） |
| 主要测试 | 眼图、BER vs 信道损耗、FFE 三抽头扫描、CTLE 0–8 dB 扫描、PRBS7/15/31 + PRQS10、PAM4 vs NRZ、时钟模式、三级 loopback 等价验证 |
| 最大不确定点 | 无官方 S 参数 / AMI → 信道用解析损耗模型近似（≤10 dB D2D 约束） |

---

## 1. 背景与范围

### 1.1 这个 IP 是什么

一个 Die-to-Die（封装内互连）SerDes PHY 硬核，分两个独立宏：x8 TX、x8 RX。链路结构：

```
Raw PCS(软宏,RTL) ──> TX PMA(3-tap FFE + 电流模驱动) ──> 信道(≤10dB) ──> RX PMA(AFE: TERM+CTLE → Slicer → 解串) ──> Raw PCS
```

关键特性（databook §1.3、§4）：
- 发送：3-tap 数字 FFE（主抽头 C0、前抽头 C-1、后抽头 C1），电流模低压驱动，50 Ω 端接。
- 接收：AFE 含 ATT + CTLE（0–8 dB 可编程 boost + 带宽控制），Slicer 采样后解串到 4UI 域。
- 信号：PAM4 与 NRZ 双模；PLL 双级联（LC-tank + 环形振荡器），7–14 GHz，支持四分之一/半/全速率及 2x/4x 过采样。
- 测试：PRBS31/15/7 + PRQS10(PAM4) 生成/校验、128-bit 可编程码型 + 误码注入、三级 loopback、片上眼图。

### 1.2 范围界定

**In scope（做）**
- PAM4 / NRZ 的符号映射与判决。
- 3-tap FFE、CTLE 的等效 DSP 模型（公式完全取自 databook）。
- 信道损耗模型（解析近似 / 可选导入 S 参数）。
- 抖动（RJ 高斯 + DJ/ISI）与时钟（forwarded clock / CDR）模型。
- 眼图、BER/浴盆、均衡参数扫描与自动化回归测试。

**Out of scope（不做 / 后置）**
- 寄存器级（APB/JTAG/CCM）功能模型、PIPE Lite 协议模型、固件行为 —— 属「功能级建模」，是另一条路线。
- 晶体管级/供电/ESD/热 等物理实现细节。
- 与官方 Synopsys Verilog 模型的逐比特对齐（无交付件，无法做到）。

---

## 2. 关键参数台账（从 databook 提取，直接进模型）

| # | 参数 | 数值 | 出处 | 模型用途 |
|---|---|---|---|---|
| P1 | 数据率 | NRZ 2.5–56 Gbps；PAM4 56–112 Gbps | §1.1 / §5.5 | 扫频点设定 |
| P2 | 波特率 | 1.75–112 GSps | §1.3 | 采样率设定 |
| P3 | PLL 时钟 | 7–14 GHz | §5.5 Table 5-5 | 时钟域换算 |
| P4 | 速率模式 | quarter/half/full + 2x/4x 过采样 | §5.5 | 每 UI 样本数 |
| P5 | PAM4 电平 | +3 / +1 / −1 / −3（编码 11/10/01/00） | §7.3 Table 7-2 | 符号映射/判决阈值 |
| P6 | NRZ 电平 | tx_nrz_amp_ctrl：11=±3, 10=±2 … | §3.8（信号描述） | NRZ 幅度 |
| P7 | FFE 结构 | 3-tap：C0 主、C-1 前、C1 后（后两者为负） | §4.3.2.4 | FFE 滤波 |
| P8 | FFE 系数 | C0=tx_eq_main；\|C-1\|=tx_eq_pre；\|C1\|=tx_eq_post | §4.3.2.4 | 系数→寄存器映射 |
| P9 | FFE 增益公式 | PRE=20log10((C0−C-1−C1)/(C0+C-1−C1))；POST=20log10((C0−C-1−C1)/(C0−C-1+C1)) | §4.3.2.4 | 预/后加重换算与校验 |
| P10 | CTLE 增益 | 0–8 dB 可编程 boost + 带宽(rtrim) | §4.3.1.1 | CTLE 传输函数 |
| P11 | RX 端接 | 50 Ω 单端，92.5 Ω 差分；pull-up / floating | §4.3.1.1 / §9.2 | 端接反射 |
| P12 | 信道损耗 | D2D ≤10 dB；SI 建议 <4 dB @28 GHz | §1.2 / §9.2 | 信道模型约束 |
| P13 | 回损 | < −15 dB 到 28 GHz | §9.2 | 信道模型约束 |
| P14 | 码型 | PRBS7/15/31、PRQS10(PAM4)、128-bit 自定义 + 误码注入 | §1.3 / §6.2 | 激励源 |
| P15 | 时钟模式 | forwarded(默认)/common/CDR assist(embedded) | §5.6 | CDR 建模 |
| P16 | 数据通路时延 | TX≈146 UI(2.62 ns)、RX≈164 UI(2.93 ns) 最小 | §5.4.3 | 模型时延 sanity check |
| P17 | Loopback | shallow(raw PCS 并行)、逐 lane 串行、die-to-die(仅 NRZ) | §6.2.1 | 回环测试等价 |

> 注意：P9 公式原文为 `20*LOG10(...)`；模型中先按符号幅度归一化实现，再用该公式做「寄存器设定值 ↔ dB」双向换算与自检。

---

## 3. 模型架构（分块）

整体为一个 MATLAB 函数/类管线 `tx_symbols → channel → rx_symbols → ber`，每块一个独立函数，便于单测与替换。

```
[码型源] → [符号映射] → [TX FFE] → [驱动/幅度] → [信道] → [RX CTLE] → [判决 Slicer] → [解串+对齐] → [BER 统计]
                 ↑                                                            ↑
            [抖动注入 RJ/DJ/ISI]                                      [时钟: forwarded / CDR 恢复]
```

### 3.1 码型源（`genPattern.m`）
- PRBS7 / PRBS15 / PRBS31（NRZ 用），PRQS10（PAM4 用），128-bit 可编程码型 + 误码注入（对应 P14）。
- 用 `comm.PRBSGenerator` / `comm.PRBSDecorrelation` 或自写 LFSR；PRQS10 可自写 quaternary LFSR。

### 3.2 符号映射（`mapSymbols.m`）
- PAM4：bits → {−3, −1, +1, +3}（编码与 §7.3 Table 7-2 一致）。
- NRZ：bits → {−amp, +amp}（幅度按 P6）。
- 归一化到单位电平便于 FFE/CTLE 计算，最后再乘回电压摆幅。

### 3.3 TX FFE（`applyFFE.m`）
- 3-tap FIR：`y[n] = C-1·x[n+1] + C0·x[n] + C1·x[n-1]`（注意 C-1、C1 为负值，P7/P8）。
- 归一化约束：`|C-1| + C0 + |C1| = 满幅`（电流模 driver 的抽头总和守恒）。
- 暴露 `pre/post/main` 三个参数，内部按 P9 公式回算 dB，便于与 databook 数值互校。

### 3.4 驱动/端接（`driver.m`，可选简化）
- 电流模、50 Ω 源端 + 92.5 Ω 差分负载；DC 耦合、floating/pull-up 端接（P11）。
- 若只关心 ISI/BER，可退化为「理想电压源 + 归一化」，端接反射作为可开关项。

### 3.5 信道（`channel.m`）
三选一，按数据可得性：
1. **解析损耗模型（默认）**：单/多极点低通 + 群时延，拟合「≤10 dB@Nyquist、<4 dB@28 GHz」；或用微带线 RLGC 近似。最简单，立即可跑。
2. **导入 S 参数（Touchstone .s4p）**：`sparameters()`（RF Toolbox）+ `rationalfit` → `rfmodel.rational` 转时域，或直接给 SerDes Toolbox 当信道。
3. **RF PCB Toolbox 生成**：按 die-to-die 基板参数合成微带线 S 参数。

### 3.6 RX CTLE（`applyCTLE.m`）
- 一阶/二阶高通（AC 增益），DC 增益 −8…0 dB、峰值 boost 0–8 dB（P10），带 boost 与带宽(rtrim)两个可调量。
- 等效为「低频衰减 + 高频抬升」传输函数，或用 `serdes.CTLE` 交叉校验。

### 3.7 判决 Slicer（`slice.m`）
- PAM4：阈值 {−2, 0, +2}；NRZ：阈值 {0}。
- 可选：判决前加自动增益/偏移校正（对应 ATT / CCA 概念）。

### 3.8 时钟与抖动（`addJitter.m` / `cdr.m`）
- 抖动：RJ（高斯）+ DJ（确定性，可用正弦/数据相关 ISI 表示），加到采样相位。
- 时钟：forwarded clock 模式 = 相位对齐、无 CDR；CDR assist = 一阶/二阶 PLL CDR 模型（鉴相 + 环路滤波 + VCO 相位累积），扫 CDR 带宽看 BER 敏感度。

### 3.9 解串 + BER（`alignAndCount.m`）
- 移除链路时延（可用 P16 的 UI 量级做初值，再做互相关对齐）。
- BER：逐比特计数；或对快速扫描用 Q 因子/高斯近似。

---

## 4. 工具链与工具箱映射

| 模块 | 首选 | 备选 |
|---|---|---|
| 码型源 | `comm.PRBSGenerator`（Communications） | 自写 LFSR |
| 滤波/FFE | 自写 FIR（基 MATLAB） | `serdes.FFE` / `dsp.FIRFilter` |
| CTLE | 自写传输函数 | `serdes.CTLE` |
| 信道 | `sparameters`+`rationalfit`（RF Toolbox） | 解析低通 / RF PCB Toolbox |
| 判决 | 自写阈值 | `serdes.Slicer` |
| 眼图/浴盆 | `serdes.EyeDiagram` / `comm.EyeDiagram` | 自写 2D 直方图 |
| BER 统计 | 自写计数 | `biterr`（Communications） |
| 均衡调参扫描 | `optimization`（fmincon）/ Global Optimization | 网格/随机扫描 |
| 并行加速 | Parallel Computing Toolbox（`parfor`） | — |
| 回归/自动化 | MATLAB Test / Simulink Test | 脚本 + 断言 |
| 报告 | MATLAB Report Generator / Live Script | 导出 PNG |

> 已确认本机 R2024b 全部就位（SerDes、Signal Integrity、Communications、DSP System、RF、Mixed-Signal、Optimization、Parallel、MATLAB Test 均在）。

---

## 5. 分阶段实施计划

### Phase 0 — 环境与参数台账（0.5 天）
- 建项目目录（见 §7）、`params.m` 集中管理所有 P1–P17 参数。
- 产出：`params.m` + 参数来源注释（databook 章节号）。

### Phase 1 — 理想链路（无信道损耗）（1 天）
- 完成 §3.1/3.2/3.3/3.7/3.9：码型源 → 映射 → FFE → 无信道 → 判决 → BER。
- 验收：NRZ 28G、PAM4 112G 在理想信道下 BER=0（无噪声时），FFE 抽头=0 时眼图全开。

### Phase 2 — 加信道与 CTLE（1–2 天）
- 完成 §3.5/3.6：解析损耗信道（≤10 dB）+ CTLE 0–8 dB。
- 验收：能画出「损耗信道 + 未均衡」的闭合眼图；加 CTLE 后眼高恢复，且 boost 越大眼高变化符合预期。

### Phase 3 — 抖动 / 噪声 / CDR（1–2 天）
- 完成 §3.8：RJ/DJ 注入 + forwarded/CDR 两模式。
- 验收：BER 随 RJ 幅度单调上升；CDR 带宽扫描出现最优区间。

### Phase 4 — 均衡调参与自动化扫描（1–2 天）
- FFE 三抽头 + CTLE boost 的网格/优化扫描，目标：固定信道与噪声下 BER 最小 / 眼图裕量最大。
- 用 P9 公式做「寄存器值 ↔ dB」双向自检。
- 验收：输出最优 (pre, main, post, ctle_boost) 组合及对应 BER/眼图。

### Phase 5 — 测试平台化与报告（1–2 天）
- 固化 §6 测试项为回归脚本 + 报告；可选 SerDes Toolbox 交叉验证同一链路。
- 验收：一条命令跑完全部测试并出报告。

**总计约 5–9 个工作日**（单 lane；x8 并行复用同一模型）。

---

## 6. 测试计划

| 测试项 | 输入/条件 | 指标 | 验收参考 |
|---|---|---|---|
| T1 眼图 | 28G NRZ / 56G NRZ / 56G PAM4 / 112G PAM4，损耗 0/4/8/10 dB | 眼高、眼宽、裕量 | 眼图随损耗单调恶化 |
| T2 BER vs 信道损耗 | 固定均衡，扫 0–10 dB 损耗 | BER 曲线（对数） | 单调上升，10 dB 处 BER 有意义 |
| T3 浴盆曲线 | 固定信道，扫采样相位 | 水平裕量 @BER=1e-12 | 浴盆开口宽度 |
| T4 FFE 扫描 | 扫 pre/main/post | PRE_EQ/POST_EQ dB（用 P9 公式） | 与公式/文档互校 |
| T5 CTLE 扫描 | boost 0–8 dB、带宽扫描 | 最优 boost、BER 改善量 | boost 过大出现过冲/眼高下降 |
| T6 码型校验 | PRBS7/15/31、PRQS10、128-bit + 误码注入 | 误码注入→BER 精确增加 | 注入 N 个错→测到 N 个错 |
| T7 PAM4 vs NRZ | 同 baud 对比 | BER/眼图对比 | PAM4 对噪声更敏感（符合预期） |
| T8 时钟模式 | forwarded vs CDR，扫 CDR 带宽 | BER/锁定时间 | CDR 带宽有最优区间 |
| T9 Loopback 等价 | shallow / 逐 lane / die-to-die(NRZ) | 数据无错回传 | 三模式皆可跑通 |

---

## 7. 建议目录结构

```
E:\Desktop_use\D2D_Modelization\
├── Reference\                          # 原始 databook（已有）
├── src\                                # 分类后的模型核心
│   ├── dsp\                            # 8 个纯 DSP 算法函数
│   ├── utils\                          # 眼图、眼高、dB 与信道校验工具
│   ├── leaf\                           # Blk 基类与 9 个叶子块
│   ├── composite\                      # AFE、lane、PMA、Raw PCS 与 D2DPHY
│   └── config\phyConfig.m              # 寄存器映射式配置入口
├── test\                               # 测试脚本 T1–T9
├── results\                            # 眼图/BER/报告输出
└── 方案文档（本文件）
```

---

## 8. 风险与假设

1. **无官方 S 参数 / AMI**（最大风险）：信道与模拟前端只能近似，结果用于**相对趋势与调参**，不代表硅片绝对 BER。缓解：支持导入 S 参数替换解析模型。
2. **寄存器默认值不全**：databook 给的是范围而非默认组合，建模时把关键量（FFE/CTLE/幅度/速率）做成可扫参数。
3. **部分数值标注 preliminary / under review**（如时延、功耗）：仅作 sanity check，不作验收硬指标。
4. **PAM4 的 PRQS10 与自适应 CTLE(asm_*)**：先做固定/扫描版本，自适应留作后续可选。

---

## 9. 下一步（可立即开工）

1. 我按 §7 建目录与 `params.m`（把 §2 台账直接落成代码 + 注释）。
2. 完成 Phase 1（理想链路），跑出第一张 112G PAM4 眼图与 BER=0 自检，验证工具链可用。
3. 之后依次推进 Phase 2→5。

**确认后我就从 Phase 0/1 开始动手。**
