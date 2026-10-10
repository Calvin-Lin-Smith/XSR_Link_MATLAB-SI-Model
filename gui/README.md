# VLSI2024 XSR Paper GUI

这是 paper-only workbench，不是通用 profile 或 T1–T9 GUI。入门步骤、命令行运行与结果解读见 [项目 README](../README.md)。

## 启动

在 MATLAB R2024b 从项目根目录执行：

~~~matlab
addpath(genpath(fullfile(pwd,'src')));
addpath(fullfile(pwd,'test'));
addpath('gui');
app = launchD2DWorkbench();
~~~

启动默认加载 VLSI Typical。下拉框只含 VLSI Typical 与 VLSI Ideal；选择 preset 只重填初值，后续 cell edit 仍是本地 requested cfg。

## 三个区域

- 左侧 VLSI2024 XSR hierarchy：D2DPHY x8、Raw bits、signed FFE/DAC、analytic IL、AC/CTLE/sampler、BB-CDR/PI。选择节点会联动 Lane 和 probe。
- 中央 Paper configuration and evidence：paper 参数表、Apply + Sync、Load from Simulink 和 paper actions。输入错误时保留上一份有效 requested cfg。
- 右侧 Paper probes and results：Probe/Lane 选择、波形轴、Metrics、trainedParameters 和日志。Run x8 Link 前 probe 为空，Axes 标题为 No paper link run yet；运行后 performance probe 从统一 post-lock 窗口开始。

## 操作

| 操作 | 作用 | 写盘 |
|---|---|---|
| Apply + Sync | 验证 paper 表并调用无 modelName 参数的 syncD2DConfig；更新 base d2dCfg、默认 shared MAT；仅 Simulink license 存在且默认 D2D_PHY_SI_Simulink 已加载时更新其 Model Workspace | 是（共享配置，不是 formal results） |
| Load from Simulink | 调用无 modelName 参数的 loadD2DSharedConfig；仅在 Simulink license 存在且默认 D2D_PHY_SI_Simulink 已加载时读取其 Model Workspace，然后回退 base → shared MAT →默认配置并验证 paper schema | 否 |
| Run x8 Link | 调用 run_vlsi2024_xsr('debug_link',nBits,'Config',cfg)，执行 bounded training 和 final x8 debug | 否；只在内存 |
| VLSI2024 Baseline | 调用 baseline runner | results/vlsi2024_xsr |
| Static A-D / FFE / IL / AC-CTLE | 调用 static checkpoint runner | results/vlsi2024_xsr |
| BB-CDR / PI / Jitter Evidence | 调用 bounded run_vlsi2024_regression('full',…) | results/vlsi2024_xsr |
| Calibration / Adaptation | 调用 adaptation runner | results/vlsi2024_xsr |
| Full VLSI2024 Regression | 调用 full runner | results/vlsi2024_xsr |

Open Paper Results 只打开结果目录，Clear Log 只清空 LogArea。GUI StatusLabel 的 Passed 表示 callback 未抛异常；性能是否有效要看 Debug.status 与 Result.berValid。

Run x8 Link 的五个训练开关是 startupCalibration、clockTraining、samplerCalibration、ctleTraining、ffeTraining；另有 cdrEnabled、每阶段 UI budget、postLockWaitUI、manualPhaseUI/manualDelayUI。每行都在 trainedParameters 中分开报告 requested、trained、applied、residual、constraint、unit。CDR 有效时，8 lane 必须全部 lock；BER、eye、margin 和 performance 使用一个 global first-valid-lock-plus-guard post-lock window。

## Simulink round-trip

默认模型名是 D2D_PHY_SI_Simulink。先在 MATLAB 中打开或生成该模型，再在其 Model Workspace 修改 paper d2dCfg，回到 GUI 点击 Load from Simulink；没有 Simulink license 或模型未加载时，GUI 不会读取 Model Workspace。GUI 修改要写回默认模型和 shared MAT 时，明确点击 Apply + Sync。自定义模型名不会被 GUI 自动发现，需从 CLI 使用对应 modelName 调用 buildD2DSimulinkModel、syncD2DConfig 或 loadD2DSharedConfig。Run x8 Link 不会隐式同步。

相关实现：[D2DWorkbench.m](D2DWorkbench.m)、[launchD2DWorkbench.m](launchD2DWorkbench.m)、[simulink/README.md](../simulink/README.md)。
