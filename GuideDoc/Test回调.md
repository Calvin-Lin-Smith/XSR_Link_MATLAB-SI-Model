# Paper GUI 回调与测试契约

本文只说明当前 D2DWorkbench 的 VLSI2024 XSR paper actions。GUI 是 paper-only 入口；通用 profile 和兼容回归只能从 MATLAB 命令行调用。完整操作示例见 [VLSI2024 XSR 完整复现与演示指南](VLSI2024_XSR_SerDes_完整复现与演示指南.md)。

## 回调总表

| GUI 操作 | MATLAB callback | 后端模式/函数 | 是否写正式结果 | 主要输入与输出 |
|---|---|---|---|---|
| Apply + Sync | app.applyConfigTable(true) → syncD2DConfig | 当前已验证 paper d2dCfg，默认 modelName=D2D_PHY_SI_Simulink | 否（不写 formal results）；总会写 base workspace，saveShared=true 时写 simulink/d2d_shared_config.mat；仅在 Simulink license 存在且默认模型已加载时写 Model Workspace | 输入编辑后的 paper 表；输出为 app.Cfg 与共享 d2dCfg |
| Load from Simulink | app.loadSharedConfig() → loadD2DSharedConfig | 默认读取 modelName=D2D_PHY_SI_Simulink；只有 Simulink license 存在且该模型已加载时读取其 Model Workspace | 不写 | 输入当前默认模型/会话/共享快照；输出刷新 app.Cfg 和参数表 |
| Run x8 Link | app.runLink() → run_vlsi2024_xsr('debug_link',…) | 单次训练型 x8 in-memory debug link | 否，不写正式 paper results、共享 MAT 或已跟踪 SLX | 输入 requested paper cfg；输出 Debug、Result、Phy、trainedParameters、post-lock probes |
| VLSI2024 Baseline | app.runPaperBaseline() | run_vlsi2024_xsr('baseline',nBits,'Config',cfg) | 是，更新 results/vlsi2024_xsr | 输出 baseline_metrics.csv、CDR/PI trace、baseline_probes.mat、config.json 等 |
| Static A-D / FFE / IL / AC-CTLE | app.runPaperStatic() | run_vlsi2024_xsr('static_checkpoint',min(nBits,2^14),'Config',cfg) | 是，更新静态检查点结果 | 输出 channel IL、3/6-tap、AC/CTLE、static summary |
| BB-CDR / PI / Jitter Evidence | app.runPaperEvidence() | run_vlsi2024_regression('full',min(nBits,2^14)) | 是；此按钮实际启动 bounded full runner | 输出 CDR/PI/jitter、adaptation、comparison、artifact schema 和 legacy_t1_t9 |
| Calibration / Adaptation | app.runPaperAdaptation() | run_vlsi2024_xsr('adaptation',min(nBits,2^14),'Config',cfg) | 是，更新 adaptation_state_trace.csv、ctle_adaptation_trace.csv、config.json | 输出五状态 trace 和 CTLE 候选 trace |
| Full VLSI2024 Regression | app.runPaperRegression() | run_vlsi2024_regression('full',cfg.link.nBits) | 是，完整 paper 结果和 legacy_t1_t9 | 输出 regression_summary.csv 及验证器要求的全部文件 |

Run x8 Link、Baseline、Static、Evidence、Adaptation 和 Full Regression 经 app.execute 包装：状态标签显示 Running/Passed/Failed，异常写入 LogArea，并用 uialert 提示。Apply + Sync、Load from Simulink 和两个 utility button 不经该包装。Passed 只表示 callback 没有抛出异常；Run x8 Link 的结果状态仍须看 Debug.status 和 Result.berValid。Open Paper Results 只是打开结果目录，Clear Log 只是清空日志，不是测量动作。

## 配置编辑与同步

参数表由 D2DWorkbench.paperConfigPaths() 生成。Cell edit 先在候选结构上解析、校验，成功后才替换 app.Cfg；失败时恢复上一份有效表并记录 Invalid paper control。校验失败不会部分写入 requested cfg。

Apply + Sync 调用无 modelName 参数的 syncD2DConfig(cfg)，因此使用默认模型 D2D_PHY_SI_Simulink。该函数总会把 d2dCfg 放入 MATLAB base workspace；saveShared 为 true 时写入 simulink/d2d_shared_config.mat；只有 Simulink license 存在且 D2D_PHY_SI_Simulink 已加载时，才更新该模型的 Model Workspace。Run x8 Link 只调用 applyConfigTable(false)，因此只改变 app.Cfg，不触发同步。自定义模型名不会被 GUI 自动发现；请从 CLI 传给 syncD2DConfig(cfg,'MyModel',...) 或 loadD2DSharedConfig('MyModel')。

Load from Simulink 使用默认 modelName 的 loadD2DSharedConfig()；只有 Simulink license 存在且 D2D_PHY_SI_Simulink 已加载时才启用第一项。固定优先级：

1. 默认模型 D2D_PHY_SI_Simulink 的 Model Workspace 中的 d2dCfg；
2. MATLAB base workspace 中的 d2dCfg；
3. simulink/d2d_shared_config.mat；
4. phyConfig() 默认配置。

读回后会通过 D2DWorkbench.validatePaperConfig。当前源码只断言 paper.id、paper.preset、model.debugStages 存在，FFE offsets 与 coeffs 等长且 offsets 唯一/含 0，以及 PAM4 thresholdAssumptions 长度为 3；参数表 cell parser 另行检查类型和若干范围。这不是完整 schema validator；结果目录的完整文件/字段契约由 validate_vlsi2024_artifacts(root[, 'ignore_summary']) 负责。

## Run x8 Link 的真实时序

runLink 把参数表作为 requested cfg，调用 run_vlsi2024_xsr('debug_link',requested.link.nBits,'Config',requested)。backend 会把 lane 数固定为 8，并令 stage.runTraining=true；model.enablePaperAdaptation 不会替代五个 debug stage toggle。

训练表中的固定顺序是：

1. startup_calibration：启动摆幅/端接校准；
2. clock_training：static phase skew 与 duty correction；
3. sampler_calibration：samplerOffsetCodes；
4. ctle_training：CTLE 网格候选；
5. ffe_training：signed 3/6-tap 候选；
6. 依据 model.debugStages.cdrEnabled 与 model.cdrOptions.enabled 的合取决定 CDR；
7. final x8 decision-directed CDR run；
8. 各 lane lock 后进入一个全局 latest-lock post-lock measurement window。

stageTrace 是表格，列为 stage、status、enabled、trainingBudgetUI、consumedUI、evaluationCount、cumulativeTrainingEndUI、totalTrainingBudgetUI、postLockWaitUI、cdrEnabled、paperPreset。启用的 stage 为 executed，consumedUI 等于其配置预算；禁用的 stage 为 skipped_manual_value，consumedUI 和 evaluationCount 为 0。训练预算是离线候选/校准预算，不是 final pass 已发送的数据量。

## lock、等待与测量窗口

对启用 CDR 的 x8 link：

1. 每个 lane 的 RxLane 通过 dspBbCdr，只看接收波形和此前的 data decision；dspBbCdr/dspPiClock 的相位更新从不读取 referenceBits。
2. lockIndex 来自 dspBbCdr：最近 lockWindow 个 UI 至少有 minTransitions 个转换，transition residual 不超过 lockToleranceUI，PI code span 不超过 maxCodeSpanCodes。
3. 所有 lane 锁定时，latestLockUI = max(laneLockUI(laneLocked))。
4. final BER 起点为 berStartUI = max(originalSkipUI, latestLockUI + postLockWaitUI)；这就是最新锁定 lane 之后的一个全局等待窗口，不是每 lane 各自裁剪。每次 D2DPHY.run 内部先调用 RawPcs.check(rxBits,skipUI)，该方法将 rxBits 与对象内部 referenceBits 比较；debug_link 再用 berStartUI 调用同一个 checker 重算 final Result。
5. 样本下标采用 MATLAB 一基编号：measurementStartSample = measurementStartUI*sps + 1。data/edge/spare/level-shifted sample 从同一 UI 边界裁剪；CTLE 波形从该 sample 裁剪。
6. eye height、sample-level distribution、ISI/margin、BER 全部只由此窗口计算。完整 acquisition、CDR lock、PI trace 可用于诊断，但 pre-lock 数据不能进入性能结论。

返回结构中 trainingEndUI 是所有 enabled stage 的 consumedUI 总和；totalTrainingBudgetUI 同值；totalWaitedUI = totalTrainingBudgetUI + berStartUIInFinalPass。Debug.performance.lane(k) 保存每 lane 同一 measurementStartUI、measurementStartSample 及裁剪后的 ctleOut、dataSamples、edgeSamples、edgeDetectorOutput、spareSamples、levelShiftedSamples、sampleLevelDistribution、eyeHeight 和 isiMargin。

状态及 BER 口径：

| Debug.status | 条件 | Result.berValid、BER |
|---|---|---|
| trained | CDR 有效且 8 lane 全部 lock，且 final window 有足够 bits | true；Result 使用 berStartUI 重新计数 |
| invalid_no_lock | CDR 有效但至少一个 lane 未 lock | false；errCnt/ber 为 NaN，nMeasured 为 0 |
| invalid_insufficient_bits | 全部 lock，但 berStartUI 后没有足够 bits | false；BER 无效 |
| debug_no_cdr | CDR 关闭或 cdrOptions.enabled 为 false | false；使用 manualPhaseUI/manualDelayUI 进行 debug，但不形成 formal paper BER |

若设置 model.debugOptions.preLockSentinel，backend 只为诊断把窗口之前的 probe 和 raw bit 改成 sentinel；performance window 不应包含 sentinel。这是 test_stage_h.m 检查的边界。

## requested / trained / applied 与完整报告

- requested：表格解析并验证后的 app.Cfg，代表用户本次请求，不是训练结果。
- trained：从 requested 开始，只让启用 stage 改变其拥有的控制量；禁用 stage 保留 requested 手动值并标记 skipped_manual_value。
- applied：从实际 D2DPHY 对象读取的值，包含 FFE normalization/current constraint、DAC quantization、CTLE 网格化、term/AC、sampler offset 和实际 CDR/manual mode。

trainedParameters 是 table，列固定为 stage、parameterPath、enable、status、requested、trained、applied、residual、constraint、unit。完整基础路径如下，CTLE 训练启用时还会附加 candidate_4.13 行：

~~~text
rxPma.lane.terminationMode
rxPma.lane.termGain
txPma.lane.gainError
txPma.lane.targetSwing
txPma.lane.enableDacQuantization
txPma.lane.dacLevels
txPma.lane.enableSwingCalibration
txPma.lane.ffeMode
txPma.lane.ffeOffsets
txPma.lane.ffeCoeffs
txPma.lane.ffeCurrent
rxPma.lane.ctlePolicy
rxPma.lane.ctleBoost_dB
rxPma.lane.samplerRoles.samplerOffsetCodes
rxPma.lane.samplerRoles.thresholdAssumptions
model.cdrOptions.staticPhaseSkewUI
model.cdrOptions.staticDutyCorrectionUI
model.cdrOptions.nCodes
model.cdrOptions.initialPhaseUI
model.cdrOptions.loopGainCodes
model.cdrOptions.enabled
model.cdrOptions.maxStepCodes
model.cdrOptions.mismatchBoundLSB
model.cdrOptions.mismatchSeed
model.cdrOptions.loopBandwidthProxy
model.cdrOptions.updateCadence
model.cdrOptions.lockToleranceUI
model.cdrOptions.lockWindow
model.debugStages.cdrEnabled
model.debugStages.postLockWaitUI
model.useManualPhase
model.manualPhaseUI
model.manualDelayUI
rxPma.lane.ctleBoost_dB[candidate_4.13]
~~~

candidate_4.13 的固定 trace 行报告 requested=4.13、candidate applied=4.2、candidate residual=0.07；它只是 CTLE training 的 off-grid quantization evidence，不代表最终 selected/trained/applied CTLE。最终值要分别看 trainedCfg.rxPma.lane.ctleBoost_dB、appliedCfg.rxPma.lane.ctleBoost_dB 和 final model 的 Afe.ctle.appliedBoost_dB。只有 adaptation mode 生成 ctle_adaptation_trace.csv；debug_link 的 ctleTrace 只在内存中，static_checkpoint 不生成该文件。

## 其他 paper action 的输出和异常

### Baseline

baseline 运行 D2DPHY x8 formal profile，调用 D2DPHY.run() 后写入 baseline_metrics.csv 和 CDR/PI artifacts。baseline_metrics.csv 每 lane 一行，包含 lane、errors、measured_bits、empirical_BER、seed、ber_upper_95、mode、rate_context_Gbps、line_rate_Gbps、lane_context、sample_bits。baseline_probes.mat 包含 probes 与 probeManifest，核心 probe 为 txPad、channelOut、ctleOut、slicerIn、rxBits，另含 data/edge/spare/level-shifted samples 与 sampler metadata。

### Static A-D / FFE / IL / AC-CTLE

static_checkpoint 生成：

- channel_il_at_28GHz.csv 与 channel_response.csv：0.5、2、4、6、8、10 dB 请求值的 measured loss、error、tolerance、28 GHz/56.25 GBd context；
- channel_il.csv：增加 measured_bits 与 rate_context_Gbps；
- ffe_3_vs_6.csv：three_tap/six_tap、tap_count、coefficients 及 BER/UCB；
- ac_ctle.csv：AC 开关、CTLE requested/applied、long_run_offset 及 BER/UCB；
- static_regression_summary.csv：baseline、ffe_3tap、ffe_6tap、ac_off、ac_on。

当前函数的 static_checkpoint 内部会重新调用不带 Config 的 baseline 和 loss_sweep；因此 GUI 传入的 Config 只在外层进入，静态子运行使用 runner 默认 paper profile。需要验证自定义请求时使用 Run x8 Link 或单独的 baseline/loss_sweep 调用，并检查 config.json。

### BB-CDR / PI / Jitter Evidence

GUI 的 evidence callback 实际调用 run_vlsi2024_regression('full',boundedBits)，因此会执行 baseline、static_checkpoint、adaptation、jitter tolerance、paper comparison、artifact validator 和 run_all_tests(legacyRoot)。异常可能来自任一阶段；查看 LogArea 和 results/vlsi2024_xsr/regression_summary.csv。

### Calibration / Adaptation

adaptation runner 的状态顺序固定为 RESET → STARTUP_IMPEDANCE_CAL → CLOCK_CAL → INITIAL_EQ_TRAIN → MISSION_TRACK。它将训练样本数限制为 min(link.nBits,2^14)，目标是 minimum adjacent decision-level margin，不以有限 BER 为优化目标；MISSION_TRACK 先施加 CTLE drift，再恢复已选控制。只有 run_vlsi2024_xsr('adaptation',...)（以及 GUI Calibration / Adaptation，或 full regression 内部的 adaptation）写 adaptation_state_trace.csv 和 ctle_adaptation_trace.csv；static_checkpoint 只写 ac_ctle.csv 等静态文件，不生成 ctle_adaptation_trace.csv。

## T1–T9 兼容回归（仅 CLI）

T1–T9 不是 GUI 操作。命令行入口为：

~~~matlab
root = pwd;
addpath(genpath(fullfile(root,'src')));
addpath(fullfile(root,'test'));
summary = run_all_tests();
~~~

也可把输出目录作为唯一参数，例如 summary = run_all_tests(fullfile(root,'results','vlsi2024_xsr','legacy_t1_t9'));。测试覆盖眼图矩阵、损耗趋势、经验 bathtub、FFE/CTLE 扫描、CTLE 趋势、PRBS/注错、NRZ/PAM4、CDR 带宽趋势和 x8 loopback。T1–T9 结果只用于兼容性证据；论文 GUI 不显示这些旧兼容动作。

相关测试：[test_stage_h.m](../test/test_stage_h.m)、[test_vlsi2024_profile.m](../test/test_vlsi2024_profile.m)、[test_vlsi2024_regression.m](../test/test_vlsi2024_regression.m)、[test_fix_artifact_invariants.m](../test/test_fix_artifact_invariants.m)。
