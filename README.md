# XSR Link MATLAB SI Model

基于 MATLAB / Simulink 的 x8 D2D PAM4 PHY 行为模型，用于学习链路架构、观察信号完整性趋势，以及复现 VLSI2024 XSR 相关的系统级行为。

> 本 README 由 **GPT-6.1 Sol** 撰写。

## 1. 项目内容与环境

模型覆盖 Raw PCS、TX FFE / DAC、解析信道损耗、AC 耦合 / CTLE、采样与判决、BB-CDR / PI，以及有限样本 BER 测量和训练流程。

- **MATLAB R2024b**：运行 MATLAB 模型、GUI 和回归入口。
- **Simulink 许可证**：仅在打开或生成 Simulink 模型时需要。
- 使用前将 MATLAB 当前目录切换到本项目根目录。

| 目录 | 用途 |
|---|---|
| [src/](src/) | 配置、层级化模型、DSP 算法和结果校验工具 |
| [gui/](gui/) | 图形工作台 |
| [simulink/](simulink/) | Simulink 模型、生成器及共享配置 |
| [test/](test/) | CLI 运行入口、回归与专项测试 |
| [results/](results/) | 已保存的结果及后续运行输出 |
| [Reference/](Reference/) | 参考资料 |

`GuideDoc/` 是本地资料目录，不纳入 Git；以下使用步骤不依赖该目录。

## 2. 快速开始：运行图形工作台

在 MATLAB 中执行以下代码。`pwd` 必须是本项目根目录：

```matlab
root = pwd;
addpath(genpath(fullfile(root, 'src')));
addpath(fullfile(root, 'test'));
addpath(fullfile(root, 'gui'));
addpath(fullfile(root, 'simulink'));

app = launchD2DWorkbench();
```

推荐操作顺序：

1. 保持默认 **VLSI Typical**；也可选择 **VLSI Ideal** 作为理想参考。
2. 在中央参数表调整所需参数。
3. 点击 **Run x8 Link**，运行训练与链路测量。
4. 在右侧选择 Lane / Probe 查看波形，检查 `status`、`berValid`、Metrics 和 `trainedParameters`。
5. 需要保存正式结果时，再使用 Baseline、Calibration / Adaptation 或 Full VLSI2024 Regression。

**Run x8 Link 仅返回内存结果。** **Apply + Sync** 会写入共享配置 `simulink/d2d_shared_config.mat`，并在默认模型 `D2D_PHY_SI_Simulink` 已加载且 Simulink 许可证可用时同步其 Model Workspace。单击运行不会隐式同步配置。

GUI 的 Baseline、Calibration / Adaptation 和 Full VLSI2024 Regression 按钮对应下节的命令行入口，均会写入正式结果目录。

## 3. 命令行运行

以下示例均在完成上面的路径初始化后执行。

### 3.1 先做一次短链路调试

```matlab
cfg = phyConfig('vlsi2024_xsr_typical');
[debug, cfgUsed] = run_vlsi2024_xsr('debug_link', 4096, 'Config', cfg);
disp(debug.status);
disp(debug.berValid);
disp(debug.trainedParameters);
```

`debug_link` 执行 x8 训练和测量，不写正式结果目录。短样本适合检查流程，可能不足以得到有效 BER。理想参考配置使用 `phyConfig('vlsi2024_xsr_ideal')`。

### 3.2 保存基线、扫描或训练结果

按需要单独选择一条执行；这些入口会写入并可能覆盖 `results/vlsi2024_xsr/` 中的同名结果，保留旧结果时应先备份该目录。

```matlab
cfg = phyConfig('vlsi2024_xsr_typical');
[baseline, cfgUsed] = run_vlsi2024_xsr('baseline', 2^18, 'Config', cfg);
[loss, ~] = run_vlsi2024_xsr('loss_sweep', 2^14, 'Config', cfg);
[checkpoint, ~] = run_vlsi2024_xsr('static_checkpoint', 2^14, 'Config', cfg);
[adaptation, ~] = run_vlsi2024_xsr('adaptation', 2^14, 'Config', cfg);
```

| 模式 | 用途 |
|---|---|
| `debug_link` | 内存中的 x8 训练、波形和测量调试 |
| `baseline` | x8 基线及探针、CDR 结果 |
| `debug_1lane` | 单 lane 基线，写入同一结果目录 |
| `loss_sweep` | 信道损耗扫描 |
| `static_checkpoint` | 基线、损耗、3/6-tap FFE 与 AC / CTLE 检查 |
| `adaptation` | 校准与适配过程记录 |

### 3.3 完整回归与结果校验

```matlab
full = run_vlsi2024_regression('full', 4096);
resultRoot = fullfile(root, 'results', 'vlsi2024_xsr');
[ok, detail] = validate_vlsi2024_artifacts(resultRoot);
disp(ok);
disp(detail);
```

`4096` 用于短样本回归；需要更长样本时可改为 `2^18`，运行耗时会增加。完整回归只支持 `full` 模式，没有 `Config` 参数；它使用默认 paper 配置并执行 AC 候选扫描。自定义配置请使用上一节的单项入口。

旧版 T1–T9 兼容回归可单独运行：

```matlab
summary = run_all_tests();
```

它默认写入 `results/`；完整 paper 回归会将其输出放在 `results/vlsi2024_xsr/legacy_t1_t9/`。

## 4. 打开或生成 Simulink 模型

查看仓库已保存的模型：

```matlab
open_system(fullfile(root, 'simulink', 'D2D_PHY_SI_Simulink.slx'));
```

根据当前配置生成一个新模型：

```matlab
cfg = phyConfig('vlsi2024_xsr_typical');
mdl = buildD2DSimulinkModel( ...
    'Config', cfg, ...
    'ModelName', 'xsr_demo', ...
    'ModelPath', fullfile(root, 'simulink', 'xsr_demo.slx'), ...
    'Open', true, 'Save', true, 'Overwrite', false);
```

若 `xsr_demo.slx` 已存在，请换一个名称和路径。生成器会设置当前 MATLAB base workspace 和模型中的 `d2dCfg`，不会自动写共享 MAT 文件。

框图信号流为 TX Bits → Raw PCS → TX PMA x8 → Channel x8 → RX PMA x8 → BER / RX Bits。正式链路测量使用 MATLAB CLI 或 GUI 入口；Simulink 图用于结构展示和配置同步。生成器支持 `Config`、`ModelName`、`ModelPath`、`Open`、`Save` 和 `Overwrite` 选项。

## 5. 如何阅读结果

主要结果位于 [results/vlsi2024_xsr/](results/vlsi2024_xsr/)：

| 文件 / 类别 | 查看内容 |
|---|---|
| `config.json`、`assumptions.md` | 实际配置与建模假设 |
| `baseline_metrics.csv`、`baseline_probes.mat` | BER 指标和链路探针 |
| `loss_sweep_metrics.csv`、`ffe_3_vs_6.csv`、`ac_ctle.csv` | 损耗、均衡和 AC / CTLE 对比 |
| `adaptation_state_trace.csv`、`ctle_adaptation_trace.csv` | 训练状态及参数变化 |
| `cdr_lock_trace.csv`、`pi_code_trace.csv` | 时钟恢复与相位调整过程 |
| `regression_summary.csv`、`paper_comparison.md` | 回归状态与论文对比 |

先确认测量有效，再读 BER。x8 调试使用各 lane 的首次有效锁定 `firstValidLockUI`，以最晚的首次锁定加 `postLockWaitUI` 建立统一测量窗口；窗口内必须保持连续锁定（`continuousTailLock`）。若出现失锁、四电平无效或 cycle slip，测量失效，不重新选择后续锁定窗口。

BER 应同时查看 `errors`、`measured_bits`、`empirical_BER`、`seed` 和 `ber_upper_95`。零误码的有限样本 95% 上界约为 `3/N`，不能据此宣称达到论文的超低 BER。仓库已有结果是历史快照，是否通过当前验证应以实际运行输出为准。

## 6. 常见问题与模型边界

- **找不到函数**：确认当前目录是本项目根目录，并重新执行第 2 节的 `addpath`。
- **没有有效 BER**：检查锁定、电平和测量窗口；必要时增大样本数。GUI 的 Passed 仅表示回调未抛异常。
- **GUI 与 Simulink 配置不同**：GUI 使用默认模型名 `D2D_PHY_SI_Simulink`；用 Apply + Sync 写回，或用 Load from Simulink 读入。自定义模型需通过 CLI 指定模型名。
- **没有 Simulink 许可证**：使用 MATLAB CLI 或 GUI 的链路运行功能；模型打开与生成需要 Simulink。

本项目复现架构与行为趋势，使用解析信道损耗，不提供晶体管级电路、真实 S 参数 / MIMO 串扰、功耗或硅后签核结果。PAM4 使用 Gray 映射 `00→−3、01→−1、11→+1、10→+3`；`targetSwing` 只作为 physical swing metadata，DAC 逻辑尺度由 `logicalOuterLevel` 保持在 ±3。论文功耗、抖动和超低 BER 等指标仅作参考背景。
