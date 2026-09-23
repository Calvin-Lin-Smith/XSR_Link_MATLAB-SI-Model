# Simulink D2D PHY 路径

Simulink 路径是独立的可视化 block diagram；MATLAB src/dsp 与 class model 仍是算法源，不把 GUI 嵌入模型。完整 paper 操作见 [VLSI2024 XSR 完整复现与演示指南](../GuideDoc/VLSI2024_XSR_SerDes_完整复现与演示指南.md)。

## 生成器与选项

需要 MATLAB R2024b 和 Simulink license。当前入口是 buildD2DSimulinkModel(varargin)：

~~~matlab
cd('E:\Master_Record\D2D_matlab_model');
addpath(genpath('src'));
addpath('simulink');
cfg = phyConfig('vlsi2024_xsr_typical');
mdl = buildD2DSimulinkModel( ...
    'ModelName','D2D_PHY_SI_Simulink', ...
    'Open',true, ...
    'Save',true, ...
    'Config',cfg, ...
    'ModelPath','', ...
    'Overwrite',true);
~~~

选项语义：

| 选项 | 默认值 | 作用 |
|---|---|---|
| ModelName | D2D_PHY_SI_Simulink | 模型名，不带 .slx |
| ModelPath | 空 | 空时写 simulink/ModelName.slx；非空时作为显式 .slx 目标路径 |
| Config | 空 | 显式 cfg；为空时调用 loadD2DSharedConfig(ModelName) |
| Open | true | 生成后打开模型 |
| Save | true | 是否保存生成的 SLX |
| Overwrite | true | 目标文件已存在时是否允许覆盖；false 会报错退出 |

builder 先检查 Simulink license，再创建模型、设置 base/Model Workspace 的 d2dCfg、更新 block，并按 Save/Open 决定写盘/打开。它不会自动调用 syncD2DConfig，也不会隐式写 simulink/d2d_shared_config.mat。

## 当前框图

顶层信号流：

~~~text
TX Bits → Raw PCS → TX PMA x8 → Die-to-Die Channel x8
        → RX PMA x8 → BER_Results → RX Bits
~~~

TX lane 包含 FFE vector、Serializer、DAC/Driver；Channel lane 调用 dspChannel；RX lane 展开 AFE TERM、AC pre、CTLE、AC post、Sampler roles、Sampler、Slicer、Deserializer。Interpreted MATLAB Function block 读取 d2dCfg 并调用 src/dsp 函数。

## Paper 与 legacy 配置

paper 图使用：

~~~matlab
cfg = phyConfig('vlsi2024_xsr_typical');
buildD2DSimulinkModel('Config',cfg,'Open',false, ...
    'ModelName','vlsi2024_visual','Overwrite',false);
~~~

phyConfig('vlsi2024_xsr_ideal') 可作同一 paper schema 的 debug reference。typical/ideal 兼容 cfg 也能生成 legacy visual model，但图中不因此获得 paper CDR、真实 S 参数或 silicon 行为。

RX 的 ACPre/ACPost block 只有当 terminationMode='AC' 且对应 enableAcPre/enableAcPost 为 true 时调用 dspAcCouple；DC 模式或关闭开关时旁路。Channel 的 paper mode 使用 lossAtRef_dB/refFreq_GHz/baud_GBd 的 analytic_il；没有 Touchstone/S 参数或 MIMO crosstalk。

## Stateful BB-CDR / PI boundary

每条 RX lane 包含名为 BB-CDR PI Adaptation 的子系统和一个 Unit Delay 状态块，用于在图上标出 stateful boundary。真正的 reference-free decision-directed CDR/PI trace 由 MATLAB 的 dspBbCdr 与 dspPiClock 产生；该简化子系统不是门级 DLL/PI，也不替代 run_vlsi2024_xsr 的 final measurement window。

## 共享配置安全

builder 的 Config 为空时，只有在 Simulink license 存在且 ModelName 对应模型已加载时才读取该模型的 Model Workspace；随后回退到 MATLAB base d2dCfg → shared MAT → phyConfig() 默认值。无论 Save 是否为 false，builder 都会把 cfg 写入当前 MATLAB base workspace 和新模型 Model Workspace；Save=false 只是不保存 SLX，不能视为完全无副作用。

GUI 侧只有 Apply + Sync 会调用无 modelName 参数的 syncD2DConfig，目标默认模型为 D2D_PHY_SI_Simulink；只有 Simulink license 存在且该模型已加载时更新其 Model Workspace，并默认写 shared MAT。Run x8 Link 只在内存使用 requested cfg，不更新 Simulink。要从默认模型反读 GUI，请修改 D2D_PHY_SI_Simulink 的 Model Workspace 中的 paper d2dCfg，再点击 Load from Simulink；自定义模型名需从 CLI 传入对应的 modelName。

## 临时模型与验证

优先使用显式临时名称、路径和 Overwrite=false：

~~~matlab
root = 'E:\Master_Record\D2D_matlab_model';
cfg = phyConfig('vlsi2024_xsr_typical');
mdl = buildD2DSimulinkModel('ModelName','stage_h_tmp', ...
    'ModelPath',fullfile(root,'simulink','stage_h_tmp.slx'), ...
    'Config',cfg,'Open',false,'Save',true,'Overwrite',false);
load_system(mdl);
modelCfg = evalin(get_param(mdl,'ModelWorkspace'),'d2dCfg');
~~~

最小验证应确认返回模型名、目标 SLX 存在、Model Workspace 的关键 paper fields 与 cfg 一致、存在 BB-CDR PI Adaptation、ACPre/ACPost 的 MATLABFcn 含 terminationMode 与 enableAcPre/enableAcPost。test_stage_h.m 提供同一类临时模型检查；完成后由调用者关闭并清理临时模型，不要覆盖 tracked D2D_PHY_SI_Simulink.slx。

## 限制

生成的 SLX 是展示和同步 artifact，不替换 D2DPHY、D2DWorkbench 或 CLI regression。BER 仍是有限样本行为测量；不得把 Simulink 图、0.9 pJ/b、论文超低 BER 或 quoted jitter 当作 sign-off。
