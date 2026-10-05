# D2D 112G PAM4 PHY SI Behavioral Model

这是一个 MATLAB/Simulink 系统级、可观测、可回归的 D2D 112G PAM4 PHY 行为模型。当前 VLSI2024 XSR 路径覆盖 Raw PCS、x8 TX/RX、signed 3/6-tap FFE、206-level 行为 DAC、28 GHz analytic IL、AC/CTLE、sampler roles、decision-directed BB-CDR/PI、有限样本 BER 和训练/适配 trace；PAM4 固定使用 Gray contract `00→−3、01→−1、11→+1、10→+3`。

本项目是 architecture/trend reproduction，不是 3nm transistor、IBIS-AMI、真实 S 参数/MIMO、功耗模型或 silicon/sign-off。论文 <1e-12/<1e-14 BER、约 0.9 pJ/b、194 fs integrated jitter 和 COM 等只作为 paper context；模型结果必须带 seed、measured_bits 和 ber_upper_95。

## 快速开始

要求 MATLAB R2024b；打开或生成 Simulink 模型还需要 Simulink license。

~~~matlab
root = 'E:\Master_Record\XSR_Link_MATLAB-SI-Model';
cd(root);
addpath(genpath(fullfile(root,'src')));
addpath(fullfile(root,'test'));
addpath(fullfile(root,'gui'));
addpath(fullfile(root,'simulink'));
~~~

一次理想 core smoke：

~~~matlab
cfg = phyConfig('ideal');
phy = D2DPHY('quick_link',8);
phy.configure(cfg);
result = phy.run();
fprintf('Aggregate BER = %.3e\n',result.aggregateBer);
~~~

一次 VLSI Typical paper debug：

~~~matlab
cfg = phyConfig('vlsi2024_xsr_typical');
[debug,~] = run_vlsi2024_xsr('debug_link',4096,'Config',cfg);
disp(debug.status);
disp(debug.trainedParameters);
~~~

debug_link 是 in-memory 训练型 x8 debug，不写正式 results 或共享 Simulink 快照。先看 status 和 berValid，再看 BER。

## Paper-only GUI

~~~matlab
addpath('gui');
app = launchD2DWorkbench();
~~~

GUI 只有 VLSI2024 XSR paper 工作流：

- 左侧：VLSI2024 XSR hierarchy；
- 中央：VLSI Typical/VLSI Ideal、paper 参数表、Apply + Sync、Load from Simulink 和 paper actions；
- 右侧：Lane/All Lanes probes、post-lock Metrics、trainedParameters 和日志。

Run x8 Link 执行 bounded offline training、final x8 CDR 和一个 global first-valid-lock-plus-guard post-lock window，仅返回内存结果；首次有效锁定后若任一 lane unlock、level invalid 或 cycle slip，整次 measurement invalid，不重选 reacquisition window。Baseline、Static A-D / FFE / IL / AC-CTLE、BB-CDR / PI / Jitter Evidence、Calibration / Adaptation 和 Full VLSI2024 Regression 会写 documented paper artifacts。GUI 的同步默认目标是 D2D_PHY_SI_Simulink；只有 Simulink license 存在且该模型已加载时读写其 Model Workspace。GUI 细节见 [gui/README.md](gui/README.md) 和 [canonical 完整指南](GuideDoc/VLSI2024_XSR_SerDes_完整复现与演示指南.md)。

## CLI 入口

~~~matlab
root = pwd;
cfg = phyConfig('vlsi2024_xsr_typical');
[baseline,~] = run_vlsi2024_xsr('baseline',2^18,'Config',cfg);
[loss,~] = run_vlsi2024_xsr('loss_sweep',2^14,'Config',cfg);
[static,~] = run_vlsi2024_xsr('static_checkpoint',2^14);
[adapt,~] = run_vlsi2024_xsr('adaptation',2^14,'Config',cfg);
full = run_vlsi2024_regression('full',4096);
ok = validate_vlsi2024_artifacts(fullfile(root,'results','vlsi2024_xsr'));
~~~

run_vlsi2024_xsr 支持 baseline、debug_1lane、loss_sweep、static_checkpoint（别名 static/milestone）、adaptation 和 debug_link；第一个数值参数或 nBits 可覆盖样本数，Config 和 enablePaperAdaptation 是 name/value 选项。run_vlsi2024_regression 只支持 full，可传 nBits。

T1–T9 是 CLI 兼容回归，不是 GUI 操作：

~~~matlab
summary = run_all_tests();
~~~

当前 static_checkpoint 内部重新调用不带 Config 的默认 paper 子运行；full runner 也没有 Config 参数。要核对自定义请求，使用 debug_link 或单独的 baseline/loss_sweep Config 调用，并读回 config.json。

## 结果与验证

论文结果写入 results/vlsi2024_xsr，包括：

- config.json、assumptions.md；
- baseline_metrics.csv、baseline_probes.mat；
- loss/IL、ffe_3_vs_6、ac_ctle、static_regression_summary；
- adaptation_state_trace、ctle_adaptation_trace；
- cdr_lock_trace、pi_code_trace、residual_phase_histogram、plots/cdr_residual_phase.png；
- jitter_tolerance、paper_comparison、regression_summary；
- legacy_t1_t9/ 下隔离的 T1–T9 CSV/PNG/MAT/JSON/JUnit。

每个 BER 表至少同时看 errors、measured_bits、empirical_BER、seed、ber_upper_95；零误码时 95% 有限样本 UCB 为 3/N。无锁、样本不足、no-CDR 的 BER 不得改写为 0。

验证器入口：

~~~matlab
resultRoot = fullfile(root,'results','vlsi2024_xsr');
[ok,detail] = validate_vlsi2024_artifacts(resultRoot);
disp(ok);
disp(detail);
~~~

仓库中保存的 regression_summary.csv 是一份既有结果快照；它不是本次文档更新期间重新运行 full regression 的证明。

## Simulink

~~~matlab
cfg = phyConfig('vlsi2024_xsr_typical');
mdl = buildD2DSimulinkModel('Config',cfg,'Open',false, ...
    'ModelName','stage_h_tmp','ModelPath', ...
    fullfile(root,'simulink','stage_h_tmp.slx'), ...
    'Save',true,'Overwrite',false);
~~~

builder 生成 TX Bits → Raw PCS → TX PMA x8 → Die-to-Die Channel x8 → RX PMA x8 → BER_Results → RX Bits 框图，使用共享 d2dCfg。它支持 ModelName、ModelPath、Config、Open、Save、Overwrite；Config 为空时，只有 Simulink license 存在且 ModelName 对应模型已加载才先读取其 Model Workspace，随后回退 base、shared MAT、默认配置。生成器会更新当前会话 base/Model Workspace，但不会隐式写 shared MAT。详见 [simulink/README.md](simulink/README.md)。

## 文档导航

- [VLSI2024 XSR 完整复现与演示指南](GuideDoc/VLSI2024_XSR_SerDes_完整复现与演示指南.md)：canonical 环境、架构、GUI、CLI、Simulink、artifacts、全工况演示和验收。
- [Test回调.md](GuideDoc/Test回调.md)：每个 GUI action、callback、写盘、lock/等待/测量边界。
- [参数.md](GuideDoc/参数.md)：所有 paper 参数、后台字段、Typical/Ideal、约束和训练语义。
- [工程学习.md](GuideDoc/工程学习.md)：从零学习路线、类树、数据流、探针阅读和安全扩展。
- [功能描述.md](GuideDoc/功能描述.md)：功能矩阵、输入输出、验证状态和限制。
- [D2D_PHY_SI_层级化架构设计.md](GuideDoc/D2D_PHY_SI_层级化架构设计.md)：历史架构背景。
- [D2D_PHY_SI建模与测试方案.md](GuideDoc/D2D_PHY_SI建模与测试方案.md)：早期建模方案背景。
- [D2D_PHY_SI_自己动手执行手册.md](GuideDoc/D2D_PHY_SI_自己动手执行手册.md)：legacy CLI 学习材料。

## 参考与边界

本仓库的 [Reference/databook_text.txt](Reference/databook_text.txt) 与 Databook PDF 用于 D2D 架构背景；VLSI2024 论文事实、模型假设和当前结果在 results/vlsi2024_xsr/assumptions.md、paper_comparison.md 中分开记录。
