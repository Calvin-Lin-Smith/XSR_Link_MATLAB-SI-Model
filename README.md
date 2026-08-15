# D2D 112G PAM4 PHY SI Behavioral Model

一个面向 Die-to-Die 112G PAM4 PHY 的 MATLAB / Simulink 系统级信号完整性（SI）行为模型。

本工程以可观测、可配置、可回归为目标，覆盖从 Raw PCS、TX PMA、Die-to-Die Channel 到 RX PMA 的完整 x8 链路，并提供：

- 可直接运行的 MATLAB 分层白盒模型
- 原生 MATLAB `uifigure` 参数与波形分析 GUI
- 独立的 Simulink 可视化 block-diagram 实现
- NRZ / PAM4、PRBS7 / PRBS15 / PRBS31、FFE、Channel、CTLE、采样、CDR 和 BER 分析
- Loss、CTLE、RJ、CDR、FFE + CTLE 参数扫描
- T1-T9 自动化回归、眼图、bathtub、CSV / MAT / JSON / JUnit 结果输出
- MATLAB GUI 与 Simulink 之间通过共享 `d2dCfg` 进行双向参数同步

> 这是一个行为级、相对趋势验证模型，不是晶体管级、IBIS-AMI 或生产级 SerDes sign-off 模型。BER 和眼高应结合模型假设、采样长度和配置进行解释。

## 项目结构

```text
.
├── src/
│   ├── dsp/                  # 纯 DSP 函数：PRBS、映射、FFE、Channel、CTLE、采样、切片、对齐
│   ├── leaf/                 # 白盒叶级模块：Serializer、Ffe、Driver、Term、Ctle、PLL 等
│   ├── composite/            # 分层 PHY：RawPcs、TxLane、RxLane、TX/RX PMA、D2DPHY
│   ├── config/               # phyConfig、共享 d2dCfg 的加载与同步
│   └── utils/                # 眼图、眼高、FFE dB、Channel 校验等工具
├── gui/
│   ├── D2DWorkbench.m        # MATLAB 原生 GUI
│   └── launchD2DWorkbench.m  # GUI 启动入口
├── simulink/
│   ├── buildD2DSimulinkModel.m       # Simulink 模型生成器
│   ├── D2D_PHY_SI_Simulink.slx       # 已生成的 Simulink 模型
│   └── d2d_shared_config.mat         # 共享参数快照
├── test/
│   ├── run_all_tests.m       # T1-T9 标准回归入口
│   ├── behavior_tests.m      # Loss / CTLE / RJ / CDR 行为趋势
│   ├── sweep_eq.m            # FFE + CTLE 扫描
│   ├── test_dsp.m            # DSP API 验收
│   ├── test_leaf_classes.m   # 叶级类验收
│   └── test_hierarchy.m      # 分层模型和白盒探针验收
├── GuideDoc/                 # 架构、参数、执行手册和测试说明
├── Reference/                # D2D PHY databook 与提取文本
└── results/                  # 回归、扫描、眼图和探针结果
```

## 环境要求

- MATLAB R2024b 或兼容版本
- MATLAB 基础环境用于 DSP 模型和 GUI
- Simulink License 仅在打开或重新生成 Simulink 模型时需要
- Windows 下默认 MATLAB 路径示例：`D:\MATLAB\R2024b\bin\matlab.exe`

## 快速开始

在 MATLAB 当前目录切换到工程根目录后运行：

```matlab
root = pwd;
addpath(genpath(fullfile(root, 'src')));
addpath(genpath(fullfile(root, 'test')));
addpath(fullfile(root, 'gui'));
```

### 运行一次完整 x8 链路

```matlab
cfg = phyConfig('typical');
phy = D2DPHY('quick_link', 8);
phy.configure(cfg);
result = phy.run();

fprintf('Aggregate BER = %.3e\n', result.aggregateBer);
disp(result.errCnt);
disp(result.nMeasured);
```

`phyConfig()` 默认返回 typical 配置，也可以显式指定：

```matlab
cfg = phyConfig('typical');  % 非理想、带 Channel loss / CTLE / jitter
cfg = phyConfig('ideal');    % 理想验证基线，目标 BER = 0
```

### 启动 MATLAB GUI

```matlab
addpath('gui');
app = launchD2DWorkbench();
```

GUI 包含三列工作区：

1. **D2D IP Hierarchy**：查看 `D2DPHY -> Raw PCS -> TX PMA x8 -> Channel x8 -> RX PMA x8` 分层结构。
2. **Configuration and Tests**：编辑模型参数，运行 link、sweep、behavior suite 和 T1-T9。
3. **White-box Probes and Results**：查看 TX pad、Channel、CTLE、slicer、PLL 等内部节点，并选择单 lane 或 `All Lanes` 叠加显示。

运行 x8 link 后，Metrics 表会显示 Aggregate 和每个 lane 的 BER、Errors、Measured bits、Best sampling phase、Delay UI、CTLE gain、Eye height，以及 Worst lane 日志。

GUI 详细说明见 [`gui/README.md`](gui/README.md)。

## Simulink 模型

Simulink 实现是独立的 block-diagram 路径，不替换 MATLAB GUI，也不把 GUI 嵌入 Simulink。

打开已有模型：

```matlab
open_system('simulink/D2D_PHY_SI_Simulink.slx');
```

重新生成模型：

```matlab
addpath('simulink');
mdl = buildD2DSimulinkModel();
```

不自动打开模型或使用自定义模型名：

```matlab
buildD2DSimulinkModel('Open', false);
buildD2DSimulinkModel('ModelName', 'MyD2DModel');
```

顶层数据流为：

```text
TX Bits -> Raw PCS -> TX PMA x8 -> Die-to-Die Channel x8 -> RX PMA x8 -> BER / Results -> RX Bits
```

Simulink 详细说明见 [`simulink/README.md`](simulink/README.md)。

## GUI 与 Simulink 参数同步

共享参数结构名为 `d2dCfg`，同步位置包括 MATLAB base workspace、已加载 Simulink 模型的 Model Workspace 和 `simulink/d2d_shared_config.mat`。

GUI 中的操作：

- **Apply + Sync**：将当前 GUI 参数写入共享配置和 Simulink。
- **Load from SLX**：读取当前 Simulink Model Workspace 的配置并刷新 GUI。
- **Reset Typical**：恢复典型非理想配置并同步。
- **Reset Ideal**：恢复理想验证配置并同步。

也可以从 MATLAB 命令行同步：

```matlab
cfg = phyConfig('typical');
syncD2DConfig(cfg);
```

## 模型层级

```text
D2DPHY
├── RawPcs
├── TxPma x8
│   ├── TxSupport / PLL
│   └── TxLane x8
│       ├── Ffe
│       ├── Serializer
│       └── Driver
├── Channel x8
└── RxPma x8
    ├── RxSupport / PLL / CDR
    └── RxLane x8
        ├── Afe
        │   ├── Term
        │   └── Ctle
        ├── Slicer
        └── Deserializer
```

模型保留白盒访问路径，例如：

```matlab
phy.rxPma.lane(1).afe.ctleOut
phy.rxPma.lane(1).slicer.samples
phy.txPma.lane(1).ffe.out
phy.channel(1).out
phy.rxPma.support.pll.residualUI
```

## 默认配置

`phyConfig('typical')` 的主要默认值：

| 参数 | 默认值 |
|---|---:|
| Modulation | PAM4 |
| Baud rate | 56 GBaud |
| Samples per symbol | 16 |
| Simulation bits | 12000 |
| SNR | 28 dB |
| RJ RMS | 0.005 UI |
| DJ peak-to-peak | 0.02 UI |
| TX FFE main / pre / post | 0.98 / 0.01 / 0.01 |
| Channel loss at Nyquist | 8 dB |
| CTLE boost | 8 dB |
| Clock mode | forwarded |
| Pattern | PRBS31 |

理想配置会关闭噪声、RJ、DJ 和 Channel loss，并使用无前后游标的理想 TX FFE，适合验证 BER = 0、层级连接和 DSP 恒等关系。

## 运行测试

### T1-T9 标准回归

```matlab
addpath(genpath('src'));
addpath('test');
summary = run_all_tests();
```

回归结果写入 `results/`，包括 `summary.csv`、`junit.xml`、`manifest.json`、`probes.json`、`regression.mat`、`T1_eye_*.png`、`T3_bathtub.png` 以及 T6 / T7 / T9 CSV 结果。

### 行为测试

```matlab
report = behavior_tests();
```

覆盖 Channel loss、CTLE、RJ 和 CDR 的 BER / eye / residual phase 趋势。

### FFE + CTLE 扫描

```matlab
best = sweep_eq();
```

该测试会验证 FFE dB 计算，并在总 tap magnitude 约束下扫描 FFE pre/post 和 CTLE boost。

### 独立底层验收

```matlab
test_dsp;
test_leaf_classes;
test_hierarchy;
```

这三个脚本是命令行验收入口，不属于 T1-T9 中的编号测试，也没有单独的 GUI 按钮。

## 当前回归状态

仓库中已保存一份完整回归结果，`results/summary.csv` 显示 T1-T9 全部通过：

```text
T1  PASS
T2  PASS
T3  PASS
T4  PASS
T5  PASS
T6  PASS
T7  PASS
T8  PASS
T9  PASS
```

已生成的结果还包括 16 组 T1 眼图、T3 bathtub 图、行为测试 CSV、FFE + CTLE 扫描结果和白盒 probe manifest。

## 重要模型说明

- PAM4 映射采用：`00 -> -3`、`01 -> -1`、`10 -> 1`、`11 -> 3`。
- DSP API 使用列向量作为主要输入输出格式。
- BER 是有限长度仿真的 empirical BER，不应解读为无穷长理论 BER。
- `PRQS10_SURROGATE` 是明确标记的 surrogate pattern，不等同于真实 PRQS10 标准序列。
- Channel 使用解析型损耗模型，参数为 Nyquist loss 和 pole 数，不是来自完整版图或 S 参数的频域模型。
- Simulink 中的 Interpreted MATLAB Function blocks 调用 `src/dsp` 中已有函数，以保持 MATLAB 与 Simulink 算法一致。

## 参考资料

- [`Reference/Die-to-Die 112G USRXSR x8 PHY for TSMC 12-nm FFC1.8V Databook.pdf`](Reference/Die-to-Die%20112G%20USRXSR%20x8%20PHY%20for%20TSMC%2012-nm%20FFC1.8V%20Databook.pdf)
- [`Reference/databook_text.txt`](Reference/databook_text.txt)
- [`GuideDoc/D2D_PHY_SI_层级化架构设计.md`](GuideDoc/D2D_PHY_SI_层级化架构设计.md)
- [`GuideDoc/D2D_PHY_SI建模与测试方案.md`](GuideDoc/D2D_PHY_SI建模与测试方案.md)
- [`GuideDoc/D2D_PHY_SI_自己动手执行手册.md`](GuideDoc/D2D_PHY_SI_自己动手执行手册.md)
- [`GuideDoc/功能描述.md`](GuideDoc/功能描述.md)
- [`GuideDoc/参数.md`](GuideDoc/参数.md)
- [`GuideDoc/Test回调.md`](GuideDoc/Test回调.md)

## License

本仓库当前未附带单独的开源许可证文件。若计划公开发布，请根据 databook、参考资料和代码的实际授权情况补充 `LICENSE`，并确认参考 PDF 是否允许随仓库分发。
