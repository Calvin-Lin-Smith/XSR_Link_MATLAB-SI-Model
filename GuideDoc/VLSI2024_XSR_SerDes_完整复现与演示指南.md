# VLSI2024 XSR SerDes 完整复现与演示指南

本文是本仓库 VLSI2024 XSR 行为复现的 canonical 文档。它描述当前代码真正执行的路径、配置、测量窗口和结果契约；[参数台账](参数.md) 负责逐项参数，[Test 回调契约](Test回调.md) 负责 GUI callback 细节，[工程学习](工程学习.md) 负责从零阅读路线。

## 0. 先明确复现对象

目标论文为 A 0.9 pJ/b 9.8–113 Gb/s XSR SerDes with 6-Tap TX FFE and AC Coupling RX in 3nm FinFET Technology。这里复现的是 architecture/trend behavioral model：

- 论文事实只用于架构和上下文：8 lanes + PLL、3/optional 6-tap TX FFE、7.5-bit/206-level SST DAC、单级 CTLE 0–6 dB 且步进 0.2 dB、data/edge/spare sampler roles、2 DLL + PI + BB-CDR、PRBS31、1–80 mm/0.5–10 dB 通道上下文、NEXT/FEXT −40/−38 dB @28 GHz、约 194 fs PLL+TX integrated-jitter measurement context、0.9 pJ/b quote。
- 模型以 112.5 Gb/s line-rate / 56.25 GBd PAM4 作为 baseline；报告同时保留 112 Gb/s BER context 和 113 Gb/s headline context，因为论文文字本身存在三种口径。
- 模型使用 signed FFE、206-level 行为量化、28 GHz calibrated analytic IL、AC high-pass、单级一阶 CTLE、sampler role metadata、64-code behavioral PI 和 decision-directed BB-CDR。
- 模型没有真实 3nm 晶体管、SST 分段、电源、T-coil、反射、Touchstone/S 参数、MIMO 串扰、完整 DLL/PI transfer、硅校准逻辑、功耗分解或无限长 BER。

因此，有限 BER 只能说明本配置、本 seed、本 measured_bits 下的 empirical observation。即使 error 为 0，也不能证明论文的 <1e-12 或 <1e-14；0.9 pJ/b 只能引用，不能由本模型预测。

## 1. 环境与初始化

### 1.1 要求

- MATLAB R2024b；core DSP 和 MATLAB class model 只需要 MATLAB。
- 打开或生成 Simulink 模型需要 Simulink license。
- Windows 命令示例以当前仓库根目录 E:\Master_Record\D2D_matlab_model 为准。
- 不要把父仓 E:\Master_Record 的其他改动当作本子仓文件；论文结果和共享快照均是可写 artifact。

### 1.2 MATLAB 初始化

~~~matlab
root = 'E:\Master_Record\D2D_matlab_model';
cd(root);
addpath(genpath(fullfile(root,'src')));
addpath(fullfile(root,'test'));
addpath(fullfile(root,'gui'));
addpath(fullfile(root,'simulink'));
~~~

首次先跑短的理想 core smoke：

~~~matlab
root = 'E:\Master_Record\D2D_matlab_model';
cd(root);
addpath(genpath(fullfile(root,'src')));
addpath(fullfile(root,'test'));
cfg = phyConfig('ideal');
nBits = 128;
cfg.link.nBits = nBits;
phy = D2DPHY('quick_link',8);
phy.configure(cfg);
result = phy.run();
fprintf('aggregate BER = %.3e\n',result.aggregateBer);
disp(result.errCnt);
disp(result.nMeasured);
~~~

典型行为 profile 和论文 profile 是不同 schema：

~~~matlab
typical = phyConfig('typical');              % 旧兼容模型
ideal = phyConfig('ideal');                  % 旧兼容理想基线
paperT = phyConfig('vlsi2024_xsr_typical'); % VLSI Typical
paperI = phyConfig('vlsi2024_xsr_ideal');   % VLSI Ideal
~~~

### 1.3 入口速查

~~~matlab
root = 'E:\Master_Record\D2D_matlab_model';
cd(root);
addpath(genpath(fullfile(root,'src')));
addpath(fullfile(root,'test'));
cfg = phyConfig('vlsi2024_xsr_typical');
nBits = 256;
[out,cfgOut] = run_vlsi2024_xsr('baseline',nBits,'Config',cfg);
disp(out.result);
[out,cfgOut] = run_vlsi2024_xsr('debug_1lane',nBits,'Config',cfg);
disp(out.result);
[out,cfgOut] = run_vlsi2024_xsr('loss_sweep',nBits,'Config',cfg);
disp(out.metrics);
[out,cfgOut] = run_vlsi2024_xsr('static_checkpoint',nBits);
disp(out.summary);
[out,cfgOut] = run_vlsi2024_xsr('adaptation',nBits,'Config',cfg);
disp(out.stateTrace);
[out,cfgOut] = run_vlsi2024_xsr('debug_link',nBits,'Config',cfg);
disp(out.trainedParameters);
out = run_vlsi2024_regression('full',nBits);
ok = validate_vlsi2024_artifacts(fullfile(root,'results','vlsi2024_xsr'),'ignore_summary');
disp(ok);
~~~

run_vlsi2024_xsr 的可选 name/value 是 nBits、enablePaperAdaptation、Config；第一个数值参数也可作为 nBits。run_vlsi2024_regression 只支持 full，可传数值 nBits 或 name/value nBits。validate_vlsi2024_artifacts 可额外传 ignore_summary 做 schema 检查而不要求 summary 全部为 1。

## 2. 架构与主数据流

### 2.1 类树

~~~text
D2DPHY
├─ RawPcs
├─ TxPma x8
│  ├─ TxSupport → Pll
│  └─ TxLane x8 → Ffe → Serializer → Driver
├─ Channel x8
└─ RxPma x8
   ├─ RxSupport → Pll
   └─ RxLane x8
      ├─ Afe → Term → AC pre → Ctle → AC post → optional AGC
      ├─ Slicer → data / edge / spare / quarter-rate probes
      └─ Deserializer
~~~

正式 VLSI paper path 在 RxLane 中设置 model.useReferenceAlign=false、model.trainingMode='decision_directed'。实际 D2DPHY 链路由 RxSupport.Pll 生成/处理采样 jitter；TxSupport.Pll 当前没有被 TxPma.run 调用。dspBbCdr/dspPiClock 负责 final decision-directed timing；它们不是门级 DLL/PI。

### 2.2 bit 到 BER

1. RawPcs.run 生成 PRBS31 referenceBits；dspMap 使用唯一 Gray PAM4 contract（`00→−3、01→−1、11→+1、10→+3`）映射 bit pair。
2. TxLane 依次执行 signed FFE、Serializer 过采样和 Driver；paper Driver 在 logical `[-3,3]`/`logicalOuterLevel` 域执行 gainError、校准与 DAC quantization，`targetSwing` 只作为 physical swing metadata，不是 logical clipping bound。
3. 每个 lane 经过 Channel。paper mode 使用 dspChannel 的 analytic_il，在 refFreq_GHz=28、baud_GBd=56.25 处校准 lossAtRef_dB。
4. D2DPHY.run 在 channel output 上按 link.seed 加入由 snr_dB 指定的 RMS 高斯噪声。
5. RxPma 生成 jitter；RxLane 经过 Afe，再选择 legacy reference alignment、manual phase 或 BB-CDR。
6. Slicer 保存 data/edge/spare roles，Deserializer 返回 rxBits；dspBbCdr/dspPiClock 从不读取 referenceBits。每次 D2DPHY.run 都调用 RawPcs.check(rxBits,skipUI)，由 RawPcs 对象内部 referenceBits 作比较；debug_link 再以 berStartUI 调用同一 checker 重算 final Result。

legacy alignment 使用 dspAlign 穷举 delay 和 phase 并读取 txBits；formal paper CDR 不使用这些 reference bits 更新相位。

## 3. 论文对应关系

| 论文描述 | 当前模型对应 | 结论 |
|---|---|---|
| 8 TX + 8 RX lanes + PLL | D2DPHY/TxPma/RxPma nLane=8，TxSupport/RxSupport 持有 Pll | 架构映射；PLL 仅行为抽象 |
| 9.8–113 Gb/s PAM4/NRZ | paper rateRange_Gbps=[9.8 113]；baseline 112.5 Gb/s/56.25 GBd | 记录 rate context；未做完整硅后速率覆盖 |
| 3/optional 6-tap TX FFE | dspFfeVector + ffeMode/offsets/coeffs | 支持 3/6 tap；系数为 model-selected |
| 7.5-bit/206-level SST DAC | Driver.dacLevels=206、量化/摆幅校准 | 只有离散电平行为，不是 SST 电路 |
| 1–80 mm、0.5–10 dB、10.8 dB @28 GHz | channel.lossSweep_dB 与 lossAtRef_dB | 只有 calibrated analytic IL；无长度/真实 S 参数 |
| NEXT/FEXT −40/−38 dB @28 GHz | cfg.paper.facts 和结果 context | 记录事实；未注入 MIMO crosstalk |
| AC leveling、CTLE 前后耦合 | Afe 的 AC pre/post 与 level-shift probes | 一阶 high-pass 行为抽象 |
| 单级 CTLE 0–6 dB、0.2 dB | Ctle paper_grid、ctleGrid_dB=0:0.2:6 | 零点 fz=0.25 是模型假设 |
| 12 data + 4 edge + 4 spare | samplerRoles metadata 与 Slicer 输出 | role 可观察；不是 20 个电路对象 |
| DLL1/PI/DLL2、BB-CDR | dspPiClock 64 codes、dspBbCdr early/late | phase/lock 趋势行为；环路参数自设 |
| PI mismatch < +/-0.5 LSB | mismatchBoundLSB=0.49、deterministic sine | 在范围内的模型扰动 |
| PRBS31、194 fs、0.9 pJ/b、COM 2.5 dB @1e-6 | paper facts/assumptions 文本 | 只保留为论文上下文，不由模型估计 |

论文事实来源是本工程实施方案、论文精读笔记和本地 Reference 资料；代码中的 model-selected 数值不应倒写成论文原始数据。

## 4. GUI：区域、参数和按钮

### 4.1 启动

~~~matlab
cd('E:\Master_Record\D2D_matlab_model');
addpath(genpath(fullfile(pwd,'src')));
addpath(fullfile(pwd,'test'));
addpath(fullfile(pwd,'gui'));
app = launchD2DWorkbench();
~~~

GUI 启动即加载 VLSI Typical。D2DWorkbench 的三个区域如下：

| 区域 | 内容 | 运行后如何使用 |
|---|---|---|
| 左侧 VLSI2024 XSR hierarchy | D2DPHY x8、signed FFE/DAC、analytic IL、AC/CTLE/sampler、BB-CDR/PI 的节点树 | 选节点会切换 Lane 和 probe；没有 run 时只显示结构 |
| 中央 Paper configuration and evidence | preset、可编辑 paper table、Apply + Sync、Load from Simulink、paper actions | 编辑只改 requested app.Cfg；明确同步或运行才消费 |
| 右侧 Paper probes and results | Probe、Lane、波形轴、Metrics、trainedParameters、操作提示 | Run x8 Link 后看 post-lock performance；All Lanes 可叠图 |

### 4.2 GUI 参数表的完整路径

以下路径来自 D2DWorkbench.paperConfigPaths()，就是 GUI 可编辑的 paper schema。详细默认值和约束见 [参数台账](参数.md)。

~~~text
link.modulation
link.baud_Gbps
link.baud_GBd
link.lineRate_Gbps
link.sps
link.nBits
link.skipUI
link.snr_dB
link.rjUI_rms
link.djUI_pp
link.djFreq
link.cdrBw
link.seed
txPma.lane.ffeMode
txPma.lane.ffeOffsets
txPma.lane.ffeCoeffs
txPma.lane.ffeNormalize
txPma.lane.ffeCurrentConstraint
txPma.lane.sixTapPreset.offsets
txPma.lane.sixTapPreset.coeffs
txPma.lane.enableDacQuantization
txPma.lane.dacLevels
txPma.lane.targetSwing
txPma.lane.gainError
txPma.lane.enableSwingCalibration
channel.mode
channel.refFreq_GHz
channel.baud_GBd
channel.lossAtRef_dB
channel.poles
rxPma.lane.terminationMode
rxPma.lane.termGain
rxPma.lane.enableAcPre
rxPma.lane.enableAcPost
rxPma.lane.acPreCorner_UI
rxPma.lane.acPostCorner_UI
rxPma.lane.acInitialState
rxPma.lane.ctlePolicy
rxPma.lane.ctleBoost_dB
rxPma.lane.ctleGrid_dB
rxPma.lane.ctleAppliedBoost_dB
rxPma.lane.enableAgc
rxPma.lane.samplerRoles.enabled
rxPma.lane.samplerRoles.quarterRateBranches
rxPma.lane.samplerRoles.roleCounts.data
rxPma.lane.samplerRoles.roleCounts.edge
rxPma.lane.samplerRoles.roleCounts.spare
rxPma.lane.samplerRoles.roleCounts.total
rxPma.lane.samplerRoles.levelShiftCodes.data
rxPma.lane.samplerRoles.levelShiftCodes.edge
rxPma.lane.samplerRoles.levelShiftCodes.spare
rxPma.lane.samplerRoles.samplerOffsetCodes
rxPma.lane.samplerRoles.thresholdAssumptions
model.resultRoot
model.enablePaperAdaptation
model.trainingMode
model.useManualPhase
model.manualPhaseUI
model.manualDelayUI
model.cdrOptions.nCodes
model.cdrOptions.initialPhaseUI
model.cdrOptions.loopGainCodes
model.cdrOptions.loopBandwidthProxy
model.cdrOptions.updateCadence
model.cdrOptions.lockWindow
model.cdrOptions.lockToleranceUI
model.cdrOptions.mismatchBoundLSB
model.cdrOptions.mismatchSeed
model.cdrOptions.enabled
model.cdrOptions.maxStepCodes
model.debugStages.startupCalibration
model.debugStages.ctleTraining
model.debugStages.ffeTraining
model.debugStages.samplerCalibration
model.debugStages.clockTraining
model.debugStages.cdrEnabled
model.debugStages.startupCalibrationBudgetUI
model.debugStages.ctleTrainingBudgetUI
model.debugStages.ffeTrainingBudgetUI
model.debugStages.samplerCalibrationBudgetUI
model.debugStages.clockTrainingBudgetUI
model.debugStages.postLockWaitUI
~~~

rawPcs.pattern、rawPcs.errInject、channel.lossSweep_dB、model.debugOptions.preLockSentinel 和 cdrOptions.minTransitions/maxCodeSpanCodes 是关键后台字段，不在 GUI 表中。

### 4.3 preset

| preset | requested 初值 | 用途 |
|---|---|---|
| VLSI Typical | PAM4、112.5 Gb/s、56.25 GBd、sps=16、2^18 bits、SNR=28 dB、RJ=0.005 UI、DJ=0.02 UI、3-tap [−0.01 0.98 −0.01]、206 DAC、IL=8 dB、AC pre/post、CTLE=4 dB、CDR/训练全开 | 名义 paper behavioral setup |
| VLSI Ideal | 同一 paper identity/schema；SNR=inf、RJ/DJ=0、IL=0、FFE [0 1 0]、DAC quantization off、AC pre/post off、CTLE=0、PI mismatch=0 | debug reference；检查路径与趋势 |

选择 preset 只重填初始表；它不自动同步 Simulink，也不写结果。之后的 cell edit 仍是本地 requested cfg。

### 4.4 按钮和写盘行为

| 按钮 | 实际动作 | 结果 |
|---|---|---|
| Apply + Sync | applyConfigTable(true) → 无 modelName 参数的 syncD2DConfig(app.Cfg) | 总写 base d2dCfg；默认 saveShared=true 写 shared MAT；仅 Simulink license 存在且默认模型 D2D_PHY_SI_Simulink 已加载时更新其 Model Workspace |
| Load from Simulink | 无 modelName 参数的 loadD2DSharedConfig() → validatePaperConfig | 只有 Simulink license 存在且 D2D_PHY_SI_Simulink 已加载时才读其 Model Workspace，然后按 base、shared MAT、默认配置回退；不写 |
| Run x8 Link | applyConfigTable(false) → run_vlsi2024_xsr('debug_link',nBits,'Config',cfg) | 训练型 in-memory debug；不写正式结果/共享快照 |
| VLSI2024 Baseline | run_vlsi2024_xsr('baseline',nBits,'Config',cfg) | 写 baseline 和 CDR/PI/probe artifacts |
| Static A-D / FFE / IL / AC-CTLE | run_vlsi2024_xsr('static_checkpoint',min(nBits,2^14),'Config',cfg) | 写 IL、3/6-tap、AC/CTLE、static artifacts |
| BB-CDR / PI / Jitter Evidence | run_vlsi2024_regression('full',min(nBits,2^14)) | 实际执行 bounded full runner；写完整 paper artifacts |
| Calibration / Adaptation | run_vlsi2024_xsr('adaptation',min(nBits,2^14),'Config',cfg) | 写五状态 adaptation 和 CTLE trace |
| Full VLSI2024 Regression | run_vlsi2024_regression('full',cfg.link.nBits) | 写完整 paper artifacts 与 legacy_t1_t9 |

所有上述 paper action（同步和 Load 除外）经 app.execute 包装。GUI StatusLabel 的 Passed 只表示 callback 未抛异常；必须继续查看 Debug.status、Result.berValid 和文件字段。Open Paper Results 只打开目录，Clear Log 只清空日志。

注意：当前 static_checkpoint 内部重新调用不带 Config 的 baseline/loss_sweep；GUI 传入 Config 不能改变这些内部默认 paper 子运行。当前 full regression 也只接受 mode/nBits，不接 GUI Config。要验证自定义值，优先用 Run x8 Link 或单独的 baseline/loss_sweep Config 调用。

## 5. Run x8 Link：训练、锁定和 final pass

### 5.1 固定执行顺序

run_vlsi2024_xsr('debug_link',nBits,'Config',requestedCfg) 的实际顺序是：

1. 将 nBits 写入 requestedCfg.link.nBits，将 lane 数固定为 8；
2. 在最多 min(nBits,2^14) bits 上运行 bounded offline training；
3. 训练 stageTrace 的固定行顺序：startup_calibration、clock_training、sampler_calibration、ctle_training、ffe_training；
4. 用 enabled stage 的结果构造 trainedCfg；禁用 stage 保留 requested 手动值；
5. 重新运行 x8 final model，formal path 强制 useReferenceAlign=false；
6. 读取每 lane cdrTrace.lockIndex；
7. 计算 final measurement window；全部 lane lock 后用一个 global latest-lock post-lock window；
8. Final window 中对 rxBits 做 BER count，比较基准是 RawPcs 对象内部 referenceBits；D2DPHY.run 的早期检查也使用同一内部基准，referenceBits 从不参与 CDR/PI 相位更新。随后输出 performance 和 trainedParameters。

debug link 内部将 stage.runTraining=true，所以五个训练 toggle 不由 model.enablePaperAdaptation 代替。model.enablePaperAdaptation 是单独的 background adaptation 配置；专用 adaptation mode 的 enablePaperAdaptation name/value 可显式控制它。

### 5.2 每个 training toggle、budget 和手动保留

| toggle | 训练控制量 | Typical/Ideal budget | 关闭时 |
|---|---|---:|---|
| model.debugStages.startupCalibration | gainError、termGain、swing calibration | 64 UI | 保留 requested gainError/termGain/swing 设置 |
| model.debugStages.clockTraining | staticPhaseSkewUI、staticDutyCorrectionUI | 64 UI | 保留 requested phase/duty |
| model.debugStages.samplerCalibration | samplerOffsetCodes | 64 UI | 保留 requested offset |
| model.debugStages.ctleTraining | CTLE 网格候选与 applied boost | 128 UI | 保留 requested CTLE；无 candidate trace 时不附 candidate_4.13 行 |
| model.debugStages.ffeTraining | 有限 3/6-tap signed candidate set | 128 UI | 保留 requested FFE mode/offset/coeff |
| model.debugStages.cdrEnabled | 是否允许 decision-directed CDR | 无独立 budget | 与 cdrOptions.enabled 合取 |
| model.debugStages.postLockWaitUI | latest-lock 后统一等待 | 16 UI | CDR off 时不额外形成 final BER |

启用行的 stageTrace.status=executed、consumedUI=该预算；禁用行是 skipped_manual_value、consumedUI=0、evaluationCount=0。stageTrace 还给出 evaluationCount、cumulativeTrainingEndUI、totalTrainingBudgetUI、postLockWaitUI、cdrEnabled、paperPreset。

离线时间轴：

~~~text
trainingEndUI = sum(stageTrace.consumedUI)
totalTrainingBudgetUI = trainingEndUI
~~~

它表示候选/校准预算，不是 final pass 已发送的 UI，也不直接等于 lock 时间。

### 5.3 requested / trained / applied

- requestedCfg：参数表通过解析和 validatePaperConfig 后的原始请求。
- trainedCfg：从 requestedCfg 复制；只有 enabled stage 所拥有的控制量可改变，其他值保持 requested。
- appliedCfg：从 final D2DPHY 对象读取；反映 FFE normalization/current constraint、DAC meta、实际 CTLE 网格值、term gain、sampler offset 和 CDR/manual mode。

trainedParameters table 的固定列为 stage、parameterPath、enable、status、requested、trained、applied、residual、constraint、unit。基础路径完整列表：

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
~~~

当 CTLE trace 非空，最后附加 rxPma.lane.ctleBoost_dB[candidate_4.13]；candidate 行的 requested=4.13、candidate applied=4.2、candidate residual=0.07 只是 off-grid quantization evidence，不是最终 selected/trained/applied CTLE。最终值必须分别读取 trainedCfg.rxPma.lane.ctleBoost_dB、appliedCfg.rxPma.lane.ctleBoost_dB 和 final model 的 Afe.ctle.appliedBoost_dB。只有 adaptation mode（GUI Calibration / Adaptation 或 full regression 内部 adaptation）写 ctle_adaptation_trace.csv；debug_link 的 ctleTrace 只在内存，static_checkpoint 不写该文件。

### 5.4 CDR lock 和 global latest-lock window

dspBbCdr 是 reference-free early/late decision-directed loop。每 UI 由 PI 得到 data/edge phase，在接收波形取 data/early/late sample，再由前一 decision 和 early-late metric 更新 code。dspPiClock 将 rawCode round 后 modulo nCodes，加 deterministic mismatch，再输出 phaseUI。

对每个 lane，锁定条件包括：

- 最近 lockWindow 个 UI 至少有 minTransitions 个 received transitions；
- transition residualPhaseUI 不超过 lockToleranceUI；
- recent PI code span 不超过 maxCodeSpanCodes。

默认后台值为 minTransitions=max(4,ceil(lockWindow/8))、maxCodeSpanCodes=8；它们不是 GUI 行。

所有 lane lock 时：

~~~text
latestLockUI = max(laneLockUI(laneLocked))
berStartUI = max(originalSkipUI, latestLockUI + postLockWaitUI)
measurementStartSample = measurementStartUI*sps + 1
totalWaitedUI = totalTrainingBudgetUI + berStartUI
~~~

这是一个 global latest-lock post-lock window：不能每 lane 用自己的 lockUI 得到不同的 performance 起点。CTLE waveform 从 measurementStartSample 一基下标裁剪；data/edge/spare/level-shifted samples 从 measurementStartUI 对应的 symbol 位置裁剪。eye height、sample-level distribution、ISI/margin 和 final BER 都只使用该窗口。完整 fullLockTrace、PI code、CDR error 可用于诊断，但 pre-lock 不属于 performance。

### 5.5 状态和 BER

| status | 条件 | 输出口径 |
|---|---|---|
| trained | effective CDR 开启、8 lane 全 lock、final window 有足够 bits | Result.berValid=true；Result 用 berStartUI 重新计数 |
| invalid_no_lock | effective CDR 开启但至少一 lane 未 lock | berValid=false；errCnt/ber 为 NaN，nMeasured=0 |
| invalid_insufficient_bits | 全 lock 但 berStartUI 后没有足够 bits | berValid=false；BER 无效 |
| debug_no_cdr | debugStages.cdrEnabled 与 cdrOptions.enabled 的合取为 false | useManualPhase=true；manualPhaseUI/manualDelayUI 用于 debug；不形成 formal paper BER |

当 CDR off 时，RxLane 的 manual phase 为 round(manualPhaseUI*sps)，delay 为 manualDelayUI。GUI 的 model.useManualPhase 会在 debug link 根据 effective CDR 结果重写；手动相位/延迟值本身仍可保留并在 no-CDR path 使用。

## 6. 命令行复现流程

### 6.1 Baseline

~~~matlab
root = 'E:\Master_Record\D2D_matlab_model';
cd(root);
addpath(genpath(fullfile(root,'src')));
addpath(fullfile(root,'test'));
cfg = phyConfig('vlsi2024_xsr_typical');
nBits = 2^18;
cfg.link.nBits = nBits;
[out,cfgOut] = run_vlsi2024_xsr('baseline',nBits,'Config',cfg);
~~~

该模式写 results/vlsi2024_xsr/config.json、assumptions.md、baseline_metrics.csv、cdr_lock_trace.csv、pi_code_trace.csv、residual_phase_histogram.csv、plots/cdr_residual_phase.png 和 baseline_probes.mat。baseline 采用 formal useReferenceAlign=false，不是 legacy oracle alignment。

### 6.2 Static checkpoints

~~~matlab
root = 'E:\Master_Record\D2D_matlab_model';
cd(root);
addpath(genpath(fullfile(root,'src')));
addpath(fullfile(root,'test'));
cfg = phyConfig('vlsi2024_xsr_typical');
nBits = 2^14;
cfg.link.nBits = nBits;
[out,cfgOut] = run_vlsi2024_xsr('static_checkpoint',nBits,'Config',cfg);
disp(out.summary);
~~~

输出 channel_il_at_28GHz.csv、channel_response.csv、channel_il.csv、loss_sweep_metrics.csv、ffe_3_vs_6.csv、ac_ctle.csv、static_regression_summary.csv。static_checkpoint 内部使用默认 paper runner 子调用；需要自定义 cfg 时分别调用：

~~~matlab
root = 'E:\Master_Record\D2D_matlab_model';
cd(root);
addpath(genpath(fullfile(root,'src')));
addpath(fullfile(root,'test'));
cfg = phyConfig('vlsi2024_xsr_typical');
nBits = 2^14;
cfg.link.nBits = nBits;
[loss,cfgOut] = run_vlsi2024_xsr('loss_sweep',nBits,'Config',cfg);
[base,cfgOut] = run_vlsi2024_xsr('baseline',nBits,'Config',cfg);
~~~

### 6.3 Calibration / adaptation

~~~matlab
root = 'E:\Master_Record\D2D_matlab_model';
cd(root);
addpath(genpath(fullfile(root,'src')));
addpath(fullfile(root,'test'));
cfg = phyConfig('vlsi2024_xsr_typical');
nBits = 2^14;
cfg.link.nBits = nBits;
[out,cfgOut] = run_vlsi2024_xsr('adaptation',nBits,'Config',cfg);
~~~

adaptation runner 的有效训练样本为 min(cfg.link.nBits,2^14)，固定五状态 RESET、STARTUP_IMPEDANCE_CAL、CLOCK_CAL、INITIAL_EQ_TRAIN、MISSION_TRACK。objective 是 minimum adjacent decision-level margin；MISSION_TRACK 先引入 CTLE drift，再恢复训练后的控制。专用 adaptation mode 默认 enablePaperAdaptation=true；需要关闭行为时显式传 name/value：

~~~matlab
root = 'E:\Master_Record\D2D_matlab_model';
cd(root);
addpath(genpath(fullfile(root,'src')));
addpath(fullfile(root,'test'));
cfg = phyConfig('vlsi2024_xsr_typical');
nBits = 4096;
cfg.link.nBits = nBits;
[out,cfgOut] = run_vlsi2024_xsr('adaptation',nBits,'Config',cfg,'enablePaperAdaptation',false);
disp(out.stateTrace);
~~~

### 6.4 Full regression

~~~matlab
root = 'E:\Master_Record\D2D_matlab_model';
cd(root);
addpath(genpath(fullfile(root,'src')));
addpath(fullfile(root,'test'));
cfg = phyConfig('vlsi2024_xsr_typical');
nBits = 2^18;
cfg.link.nBits = nBits;
out = run_vlsi2024_regression('full',nBits);
~~~

为了先做 smoke，可用：

~~~matlab
root = 'E:\Master_Record\D2D_matlab_model';
cd(root);
addpath(genpath(fullfile(root,'src')));
addpath(fullfile(root,'test'));
cfg = phyConfig('vlsi2024_xsr_typical');
nBits = 4096;
cfg.link.nBits = nBits;
out = run_vlsi2024_regression('full',nBits);
~~~

full runner 顺序为 baseline → static_checkpoint → baseline restore → adaptation → bounded jitter tolerance → paper comparison → fresh run_all_tests(legacyRoot) → validate_vlsi2024_artifacts。它会写全量 paper 结果和 results/vlsi2024_xsr/legacy_t1_t9。不要把 GUI 当前编辑 cfg 当作 full runner 的输入；当前函数签名没有 Config option。

### 6.5 T1–T9 兼容 CLI

~~~matlab
root = 'E:\Master_Record\D2D_matlab_model';
cd(root);
addpath(genpath(fullfile(root,'src')));
addpath(fullfile(root,'test'));
cfg = phyConfig('ideal');
nBits = 6000;
cfg.link.nBits = nBits;
summary = run_all_tests();
summary = run_all_tests(fullfile(root,'results','vlsi2024_xsr','legacy_t1_t9'));
~~~

T1–T9 是旧兼容命令行路径，覆盖 16 组眼图、损耗趋势、经验 bathtub、FFE/CTLE、码型注错、NRZ/PAM4、CDR 带宽和 x8 loopback。它们不属于 GUI paper actions；full regression 将它们隔离写到 legacy_t1_t9。

## 7. Simulink 生成、同步和安全验证

Simulink 是独立框图路径，MATLAB class/DSP 仍是算法源。顶层结构为 TX Bits → Raw PCS → TX PMA x8 → Die-to-Die Channel x8 → RX PMA x8 → BER_Results → RX Bits；各 lane 使用 Interpreted MATLAB Function 引用 src/dsp。

### 7.1 builder 选项

buildD2DSimulinkModel 的当前签名和 name/value：

~~~matlab
root = 'E:\Master_Record\D2D_matlab_model';
cd(root);
addpath(genpath(fullfile(root,'src')));
addpath(fullfile(root,'simulink'));
cfg = phyConfig('vlsi2024_xsr_typical');
mdl = buildD2DSimulinkModel( ...
    'ModelName','D2D_PHY_SI_Simulink', ...
    'Open',true, ...
    'Save',true, ...
    'Config',cfg, ...
    'ModelPath','', ...
    'Overwrite',true);
~~~

- ModelName：不带 .slx 的模型名；默认 D2D_PHY_SI_Simulink。
- ModelPath：显式 .slx 输出路径；为空时写 simulink/ModelName.slx。
- Config：显式 cfg；为空时调用 loadD2DSharedConfig(ModelName)。
- Open：是否打开生成模型；Save：是否写 SLX。
- Overwrite：目标文件存在且为 false 时立即报错保护。
- Simulink license 不可用时立即报错；builder 不会替代 D2DPHY 或 GUI。

### 7.2 paper/legacy 与 AC 路径

用 Config=phyConfig('vlsi2024_xsr_typical') 生成 paper visual model；旧 typical/ideal 也可以传给 builder 作为 legacy/compatibility 图。RX lane 的 ACPre 和 ACPost block 只有在 terminationMode='AC' 且对应 enableAcPre/enableAcPost 为 true 时调用 dspAcCouple；DC 或关闭开关时旁路。builder 同时保留 BB-CDR PI Adaptation 的 Unit Delay stateful boundary，真正的 dspBbCdr trace 仍在 MATLAB core。

### 7.3 共享配置安全

builder 会把 Config 放入 MATLAB base workspace 和模型 Model Workspace，即使 Save=false 也会改变当前会话的 base d2dCfg；它不自动写 d2d_shared_config.mat。要安全做临时模型：

~~~matlab
root = 'E:\Master_Record\D2D_matlab_model';
cd(root);
addpath(genpath(fullfile(root,'src')));
addpath(fullfile(root,'simulink'));
cfg = phyConfig('vlsi2024_xsr_typical');
tmp = buildD2DSimulinkModel('ModelName','stage_h_tmp', ...
    'ModelPath',fullfile(root,'simulink','stage_h_tmp.slx'), ...
    'Config',cfg,'Open',false,'Save',true,'Overwrite',false);
~~~

完成检查后由调用者清理临时 SLX；不要用临时模型名覆盖 tracked D2D_PHY_SI_Simulink.slx。该临时/custom 模型不能用 GUI 的无参 Load from Simulink 做 round-trip：GUI 只针对默认 D2D_PHY_SI_Simulink。临时/custom 模型请用 CLI loadD2DSharedConfig(customName) 或 evalin(get_param(customName,'ModelWorkspace'),'d2dCfg') 检查。Apply + Sync 才会写 shared MAT；Load from Simulink 只读。

### 7.4 同步流程

~~~matlab
root = 'E:\Master_Record\D2D_matlab_model';
cd(root);
addpath(genpath(fullfile(root,'src')));
addpath(fullfile(root,'simulink'));
cfg = phyConfig('vlsi2024_xsr_typical');
syncD2DConfig(cfg,'D2D_PHY_SI_Simulink',true);
cfgBack = loadD2DSharedConfig('D2D_PHY_SI_Simulink');
~~~

同步前后应比较 paper schema、ffe offsets/coeffs、channel IL、AC enables、CTLE、sampler roles、CDR 和 debugStages。临时验证优先 Open=false、Overwrite=false，并在写盘前记录目标路径。

## 8. 结果目录、字段和 UCB

### 8.1 目录

~~~text
results/vlsi2024_xsr/
├─ config.json
├─ assumptions.md
├─ baseline_metrics.csv
├─ baseline_probes.mat
├─ loss_sweep_metrics.csv
├─ channel_il_at_28GHz.csv
├─ channel_response.csv
├─ channel_il.csv
├─ ffe_3_vs_6.csv
├─ ac_ctle.csv
├─ static_regression_summary.csv
├─ adaptation_state_trace.csv
├─ ctle_adaptation_trace.csv
├─ cdr_lock_trace.csv
├─ pi_code_trace.csv
├─ residual_phase_histogram.csv
├─ jitter_tolerance.csv
├─ paper_comparison.csv
├─ paper_comparison.md
├─ regression_summary.csv
├─ plots/cdr_residual_phase.png
└─ legacy_t1_t9/
   ├─ summary.csv, junit.xml, manifest.json, probes.json, regression.mat
   ├─ T1_eye_metrics.csv, T1_eye_*.png, T3_bathtub.csv/png
   └─ T6_patterns.csv, T7_modulation.csv, T9_loopback.csv
~~~

### 8.2 主要 CSV 字段

| 文件 | 关键字段 |
|---|---|
| baseline_metrics.csv | lane、errors、measured_bits、empirical_BER、seed、ber_upper_95、mode、rate_context_Gbps、line_rate_Gbps、lane_context、sample_bits |
| loss_sweep_metrics.csv | lossAtRef_dB、errors、measured_bits、empirical_BER、seed、ber_upper_95、aggregateBer、mode、rate/lane/sample context |
| channel_il_at_28GHz.csv | requested_loss_dB、measured_loss_dB、referenceFrequency_GHz、baud_GBd、error_dB、tolerance_dB、mode、unmodeledCrosstalk |
| channel_response.csv | frequency_GHz、baud_GBd、requested/measured loss、error/tolerance、mode、unmodeledCrosstalk |
| channel_il.csv | channel_il_at_28GHz 字段加 measured_bits、rate_context_Gbps |
| ffe_3_vs_6.csv | tap_count、coefficients、variant、errors、measured_bits、empirical_BER、seed、ber_upper_95 和 contexts |
| ac_ctle.csv | ac_enabled、ctle_requested_dB、ctle_applied_dB、long_run_offset、BER/UCB、contexts |
| cdr_lock_trace.csv | sample、locked、transition、pi_raw_code、pi_wrapped_code、pi_applied_code、pi_mismatch_LSB、pi_wrap_count、data_phase_UI、edge_phase_UI、residual_phase_UI、lane、seed、training_mode |
| pi_code_trace.csv | PI code 字段加 pi_trace_stride、trace_context；是 downsampled audit trace |
| residual_phase_histogram.csv | residual_phase_UI_bin、count、sample_count、seed；所有 bin 总数应等于 sample_count |
| jitter_tolerance.csv | jitter_UI_rms、errors、measured_bits、empirical_BER、seed、ber_upper_95、sample_bits、sweep_context、contexts |
| adaptation_state_trace.csv | state、objective、disturbed/recovered_objective、control_changed、CTLE、FFE current、gain/term、DLL/DCC、sampler、lock、measured_bits、seed、DAC metadata |
| ctle_adaptation_trace.csv | requested/applied dB、objective、initial/residual error、measured_bits、disturbed/recovered objective、control_changed、recovered |
| regression_summary.csv | stage、pass、detail；formal stages 为 baseline_cdr_pi、static_link、adaptation、legacy_t1_t9、artifact_schema |

baseline_probes.mat 不是 CSV，变量为 probes 和 probeManifest。核心 probes 为 txPad、channelOut、ctleOut、slicerIn、rxBits，另有 dataSamples、dataDecisions、edgeSamples、edgeDetectorOutput、spareSamples、spareMonitorOutput、levelShiftedSamples、quarterRateSamples、levelShiftCodes、comparatorThresholds、samplerRoleCounts。

### 8.3 BER 和 UCB

每一行 BER 必须同时解释：

~~~text
empirical_BER = errors / measured_bits
~~~

代码的 ber_upper_95 是有限样本 95% upper confidence bound：measured_bits≤0 时为 NaN；errors=0 时为 3/measured_bits；其他情况使用 betaincinv(0.95,errors+1,measured_bits-errors)。因此：

- “0 error” 只能写成 N 个 measured bits 内未观察到错误，95% UCB=3/N；
- UCB 不是论文 BER 的证明，也不是硅片可靠性指标；
- 先确认 status=trained、berValid=true，再讨论 final BER；no-lock 的 NaN 不应被替换为 0。

## 9. 按论文逻辑复现的完整步骤

1. 完成 MATLAB 初始化，运行 Ideal core smoke，确认 D2DPHY.configure/run 和对象 probe 可访问。
2. 创建 VLSI Typical cfg，运行短 debug_link；检查 requested/trained/applied、stageTrace、laneLockUI、measurementStartSample 和 performance。
3. 运行 baseline，保存 config.json、assumptions.md、baseline_metrics.csv、baseline_probes.mat 和 CDR/PI trace。
4. 运行 static_checkpoint，检查 IL 误差、3/6 tap、AC on/off、CTLE grid 和 static summary。不要把 6-tap 不劣写成强制验收，除非该次数据支持。
5. 运行 adaptation，检查五状态顺序、disturbed_objective < recovered_objective、CTLE residual 和 control_changed。
6. 运行 full regression；它会生成 paper comparison、jitter、artifact schema 和隔离的 legacy T1–T9。
7. 运行 validate_vlsi2024_artifacts(resultRoot)，逐项核对 required files、CSV columns、UCB、PI trace、adaptation residual、legacy summary/JUnit。
8. 阅读 paper_comparison.csv/md 和 assumptions.md，把论文事实、模型输出、模型假设、未建模项分开写入报告。
9. 若需 GUI 演示，先用 Apply + Sync 发布已确认 cfg；再用 Run x8 Link 做不写盘 debug；正式证据动作最后执行。
10. 若需 Simulink 演示且目标是 GUI round-trip，必须使用默认模型 D2D_PHY_SI_Simulink，并在有 Simulink license 且模型已加载时先更新其 Model Workspace，再点 GUI Load from Simulink。临时或 custom ModelName/ModelPath 只用 CLI 的 loadD2DSharedConfig(customName) 或直接检查对应 Model Workspace；GUI 不会自动发现它们。

## 10. 可独立复制的演示工况

以下每项都给出目的、独立设置、完整命令或 GUI 步骤、预期趋势、查看位置和不能得出的结论。每个 MATLAB 示例都从 root、路径、cfg、nBits 开始；debug_link 只在内存运行，明确写出的 paper runner 才写 results/vlsi2024_xsr。

### D1：VLSI Ideal 对比 VLSI Typical

目的：在相同 paper schema 下隔离零损耗/零噪声参考和 nominal impairments。

~~~matlab
root = 'E:\Master_Record\D2D_matlab_model';
cd(root);
addpath(genpath(fullfile(root,'src')));
addpath(fullfile(root,'test'));
cfg = phyConfig('vlsi2024_xsr_typical');
nBits = 256;
cfg.link.nBits = nBits;
[outTypical,~] = run_vlsi2024_xsr('debug_link',nBits,'Config',cfg);
cfg = phyConfig('vlsi2024_xsr_ideal');
nBits = 256;
cfg.link.nBits = nBits;
[outIdeal,~] = run_vlsi2024_xsr('debug_link',nBits,'Config',cfg);
disp(outTypical.status);
disp(outIdeal.status);
disp([outTypical.berValid outIdeal.berValid]);
disp(outTypical.appliedCfg.txPma.lane.enableDacQuantization);
disp(outIdeal.appliedCfg.txPma.lane.enableDacQuantization);
~~~

GUI 步骤：加入 src、test、gui 路径；执行 app = launchD2DWorkbench()；在 Paper preset 选择 VLSI Typical，点击 Run x8 Link，记录 StatusLabel、Metrics、CDR lock 和 RX CTLE output；再选择 VLSI Ideal，点击 Load Paper Preset 后再次 Run x8 Link。预期：Ideal 的 channel/noise/jitter/AC/DAC impairment 更少；具体 status 和 berValid 必须以返回值为准。查看 Debug.appliedCfg、Debug.performance.lane、TX DAC / pad、RX CTLE output 和 CDR lock。该对比不证明 PVT、silicon margin 或论文 BER。

### D2：28 GHz analytic IL loss sweep

目的：验证 28 GHz 标定插损和不同 loss 请求下的模型趋势。

~~~matlab
root = 'E:\Master_Record\D2D_matlab_model';
cd(root);
addpath(genpath(fullfile(root,'src')));
addpath(fullfile(root,'test'));
cfg = phyConfig('vlsi2024_xsr_typical');
nBits = 2^14;
cfg.link.nBits = nBits;
[out,~] = run_vlsi2024_xsr('loss_sweep',nBits,'Config',cfg);
disp(out.metrics);
disp(out.channelIL);
il = readtable(fullfile(root,'results','vlsi2024_xsr','channel_response.csv'));
disp(il(:,{'frequency_GHz','requested_loss_dB','measured_loss_dB','error_dB'}));
~~~

GUI 步骤：执行 app = launchD2DWorkbench()；选择 VLSI Typical；点击 Static A-D / FFE / IL / AC-CTLE；到 results/vlsi2024_xsr 查看文件。预期 measured_loss 接近 requested_loss，损耗增大通常提高 ISI 压力，但 BER 是否单调必须查看本次 loss_sweep_metrics.csv。查看 loss_sweep_metrics.csv、channel_il_at_28GHz.csv、channel_response.csv 和 Channel output。该演示不证明长度到 IL 的真实映射、反射或 MIMO 串扰。

### D3：signed 3-tap 与 6-tap

目的：观察 tap count、offset 和 model-selected coefficients 的相对行为，避免把候选系数当作论文原始系数。

~~~matlab
root = 'E:\Master_Record\D2D_matlab_model';
cd(root);
addpath(genpath(fullfile(root,'src')));
addpath(fullfile(root,'test'));
cfg = phyConfig('vlsi2024_xsr_typical');
nBits = 256;
cfg.link.nBits = nBits;
cfg.txPma.lane.ffeMode = 'three_tap';
cfg.txPma.lane.ffeOffsets = [-1 0 1];
cfg.txPma.lane.ffeCoeffs = [-0.01 0.98 -0.01];
[out3,~] = run_vlsi2024_xsr('debug_link',nBits,'Config',cfg);
cfg = phyConfig('vlsi2024_xsr_typical');
nBits = 256;
cfg.link.nBits = nBits;
cfg.txPma.lane.ffeMode = 'six_tap';
cfg.txPma.lane.ffeOffsets = cfg.txPma.lane.sixTapPreset.offsets;
cfg.txPma.lane.ffeCoeffs = cfg.txPma.lane.sixTapPreset.coeffs;
[out6,~] = run_vlsi2024_xsr('debug_link',nBits,'Config',cfg);
disp(out3.appliedCfg.txPma.lane.ffeCoeffs);
disp(out6.appliedCfg.txPma.lane.ffeCoeffs);
disp(out3.trainedParameters);
disp(out6.trainedParameters);
~~~

GUI 步骤：执行 app = launchD2DWorkbench()；选择 VLSI Typical；在 ffeMode、ffeOffsets、ffeCoeffs 行填入三抽头并 Run x8 Link；再填入 six_tap 及 sixTapPreset 的 offset/coeff 并 Run x8 Link。预期 tapMeta 的 offsets/coeffs 发生变化；6-tap 不保证 BER 或 eye 一定更好。若要生成正式 ffe_3_vs_6.csv，另执行 run_vlsi2024_xsr('static_checkpoint',2^14)。查看 Debug.trainedParameters、TX FFE output、model.txPma.lane(1).ffe.tapMeta 和 ffe_3_vs_6.csv。该演示不声称系数来自论文，也不声称 6-tap 必然改善。

### D4：DAC quantization on/off

目的：隔离 Driver 的 206-level logical PAM4 量化和 swing metadata；logical clipping bound 为 `logicalOuterLevel`，`targetSwing` 只记录 physical target。

~~~matlab
root = 'E:\Master_Record\D2D_matlab_model';
cd(root);
addpath(genpath(fullfile(root,'src')));
addpath(fullfile(root,'test'));
cfg = phyConfig('vlsi2024_xsr_typical');
nBits = 256;
cfg.link.nBits = nBits;
cfg.txPma.lane.enableDacQuantization = true;
[outOn,~] = run_vlsi2024_xsr('debug_link',nBits,'Config',cfg);
cfg = phyConfig('vlsi2024_xsr_typical');
nBits = 256;
cfg.link.nBits = nBits;
cfg.txPma.lane.enableDacQuantization = false;
[outOff,~] = run_vlsi2024_xsr('debug_link',nBits,'Config',cfg);
disp(outOn.model.txPma.lane(1).driver.dacMeta);
disp(outOff.model.txPma.lane(1).driver.dacMeta);
disp(outOn.appliedCfg.txPma.lane.enableDacQuantization);
disp(outOff.appliedCfg.txPma.lane.enableDacQuantization);
~~~

GUI 步骤：执行 app = launchD2DWorkbench()；选择 VLSI Typical；将 enableDacQuantization 设 true 后 Run x8 Link，记录 TX DAC / pad 和 Debug.appliedCfg；改为 false 后重新 Run x8 Link。预期 on 时 TX pad 在 `[-logicalOuterLevel,+logicalOuterLevel]` 内按 `6/(dacLevels−1)` 离散，`targetSwing` 只出现在 dacMeta physical metadata，off 时 dacMeta 标记 enabled=false。查看 Driver.dacMeta 和 TX DAC / pad。该演示不推导 SST 段权重、7.5-bit 电路、功耗或真实电压 swing。

### D5：AC/DC 与 AC pre/post

目的：分离 termination mode、CTLE 前 AC 和 CTLE 后 AC 的行为。

~~~matlab
root = 'E:\Master_Record\D2D_matlab_model';
cd(root);
addpath(genpath(fullfile(root,'src')));
cfg = phyConfig('vlsi2024_xsr_typical');
nBits = 128;
cfg.link.nBits = nBits;
cfg.rxPma.lane.terminationMode = 'AC';
cfg.rxPma.lane.enableAcPre = true;
cfg.rxPma.lane.enableAcPost = true;
phyAC = D2DPHY('ac_demo',1);
phyAC.configure(cfg);
resAC = phyAC.run();
cfg = phyConfig('vlsi2024_xsr_typical');
nBits = 128;
cfg.link.nBits = nBits;
cfg.rxPma.lane.terminationMode = 'DC';
cfg.rxPma.lane.enableAcPre = true;
cfg.rxPma.lane.enableAcPost = true;
phyDC = D2DPHY('dc_demo',1);
phyDC.configure(cfg);
resDC = phyDC.run();
disp(norm(phyAC.rxPma.lane(1).afe.acPreOut - phyAC.rxPma.lane(1).afe.termOut));
disp(norm(phyDC.rxPma.lane(1).afe.acPreOut - phyDC.rxPma.lane(1).afe.termOut));
disp(resAC.aggregateBer);
disp(resDC.aggregateBer);
~~~

GUI 步骤：执行 app = launchD2DWorkbench()；选择 VLSI Typical；依次改 terminationMode 为 AC/DC、enableAcPre/enableAcPost 为 true/false，每次点击 Run x8 Link；在右侧选择 RX termination、RX AC pre、RX CTLE output、RX AC post。预期 AC 且 enable 时相应波形变化，DC 或关闭开关时旁路；查看 Afe.termOut、acPreOut、ctleRaw、acPostOut、ctleOut。该演示不代表真实 transformer/leveling 电路频响。

### D6：CTLE grid 与 off-grid candidate

目的：展示 paper_grid 的 0.2 dB 网格，以及 4.13 仅是 candidate trace，不是最终选择值。

~~~matlab
root = 'E:\Master_Record\D2D_matlab_model';
cd(root);
addpath(genpath(fullfile(root,'src')));
addpath(fullfile(root,'test'));
cfg = phyConfig('vlsi2024_xsr_typical');
nBits = 256;
cfg.link.nBits = nBits;
cfg.model.debugStages.ctleTraining = true;
cfg.rxPma.lane.ctleBoost_dB = 4.13;
[out,~] = run_vlsi2024_xsr('debug_link',nBits,'Config',cfg);
candidate = out.trainedParameters(contains(string(out.trainedParameters.parameterPath),'candidate_4.13'),:);
finalRow = out.trainedParameters(strcmp(string(out.trainedParameters.parameterPath), ...
    'rxPma.lane.ctleBoost_dB'),:);
disp(candidate);
disp(finalRow);
disp(out.trainedCfg.rxPma.lane.ctleBoost_dB);
disp(out.appliedCfg.rxPma.lane.ctleBoost_dB);
~~~

GUI 步骤：执行 app = launchD2DWorkbench()；选择 VLSI Typical；将 ctleBoost_dB 改为 4.13；点击 Run x8 Link；在 trainedParameters 查看 candidate_4.13 与普通 ctleBoost_dB 两行。预期 candidate 行为 requested=4.13、candidate applied=4.2、candidate residual=0.07；最终 selected/trained/applied 值由 CTLE training objective 从网格和 FFE 候选中选择，必须读取 out.trainedCfg、out.appliedCfg 与最终 Afe.ctle.appliedBoost_dB。只有 run_vlsi2024_xsr('adaptation',...)、GUI Calibration / Adaptation 或 full regression 内部 adaptation 写 ctle_adaptation_trace.csv；static_checkpoint 不写该文件，debug_link 的 ctleTrace 只在内存。该演示不把 4.13 当正式档位，也不声称零极点是论文值。

### D7：CDR on/off 的合取

目的：确认 effective CDR 是 cdrEnabled 与 cdrOptions.enabled 的逻辑与，并区分 manual debug。

~~~matlab
root = 'E:\Master_Record\D2D_matlab_model';
cd(root);
addpath(genpath(fullfile(root,'src')));
addpath(fullfile(root,'test'));
combos = [true true; true false; false true; false false];
for k = 1:size(combos,1)
    cfg = phyConfig('vlsi2024_xsr_typical');
    nBits = 256;
    cfg.link.nBits = nBits;
    cfg.model.debugStages.cdrEnabled = combos(k,1);
    cfg.model.cdrOptions.enabled = combos(k,2);
    cfg.model.manualPhaseUI = 0.5;
    cfg.model.manualDelayUI = 0;
    [out,~] = run_vlsi2024_xsr('debug_link',nBits,'Config',cfg);
    disp([combos(k,:) out.effectiveCdrEnabled]);
    disp(out.status);
    disp(out.appliedCfg.model.cdrOptions.enabled);
end
~~~

GUI 步骤：执行 app = launchD2DWorkbench()；保持 VLSI Typical；分别编辑 model.debugStages.cdrEnabled 和 model.cdrOptions.enabled 的四种 true/false 组合，每次 Run x8 Link；观察 Status、CDR lock、PI code 和 manual phase。预期两者都 true 才 effectiveCdrEnabled=true；任一为 false 时 status=debug_no_cdr、useManualPhase=true，manualPhaseUI/manualDelayUI 生效。查看 Debug.status、effectiveCdrEnabled、fullLockTrace、PI code、CDR error 和 trainedParameters。no-CDR 结果不属于 formal paper BER，不能与 lock path 等价。

### D8：no-lock invalid

目的：用小样本和极大 lockWindow 明确制造“没有足够 UI 锁定”的 invalid_no_lock，而不是把 BER 当作 0。

~~~matlab
root = 'E:\Master_Record\D2D_matlab_model';
cd(root);
addpath(genpath(fullfile(root,'src')));
addpath(fullfile(root,'test'));
cfg = phyConfig('vlsi2024_xsr_typical');
nBits = 256;
cfg.link.nBits = nBits;
cfg.model.cdrOptions.lockWindow = 100000;
[out,~] = run_vlsi2024_xsr('debug_link',nBits,'Config',cfg);
assert(strcmp(out.status,'invalid_no_lock'));
assert(~out.berValid);
disp(out.status);
disp(out.laneLocked);
disp(out.result.ber);
~~~

GUI 步骤：执行 app = launchD2DWorkbench()；将 link.nBits 设 256、model.cdrOptions.lockWindow 设 100000；点击 Run x8 Link；查看 Status、Lane lock、BER。预期 status=invalid_no_lock、berValid=false、Result.ber/errCnt 为 NaN。查看 Debug.laneLocked、laneLockUI、fullLockTrace、stageTrace。不能把 NaN 改成 0，也不能把 pre-lock 波形当性能。

### D9：postLock 与统一 measurement window

目的：验证 latest lane lock 之后的全局等待和 measurementStartUI/sample。

~~~matlab
root = 'E:\Master_Record\D2D_matlab_model';
cd(root);
addpath(genpath(fullfile(root,'src')));
addpath(fullfile(root,'test'));
waitValues = [0 32];
for k = 1:numel(waitValues)
    cfg = phyConfig('vlsi2024_xsr_typical');
    nBits = 256;
    cfg.link.nBits = nBits;
    cfg.model.debugStages.postLockWaitUI = waitValues(k);
    [out,~] = run_vlsi2024_xsr('debug_link',nBits,'Config',cfg);
    disp([waitValues(k) out.requiredLaneLockUI out.measurementStartUI ...
        out.measurementStartSample out.totalWaitedUI]);
    starts = arrayfun(@(x)x.measurementStartSample,out.performance.lane(:));
    assert(all(starts == out.measurementStartSample));
end
~~~

GUI 步骤：执行 app = launchD2DWorkbench()；选择 VLSI Typical；分别把 model.debugStages.postLockWaitUI 设为 0 和 32；每次点击 Run x8 Link；查看 Metrics 的 Lock UI、BER start UI、Waited UI。预期 measurementStartUI 不小于 latestLockUI+postLockWaitUI 与 originalSkipUI，且所有 lane 的 start 相同。查看 measurementStartUI、measurementStartSample、berStartUIInFinalPass、totalWaitedUI、Debug.performance.lane。post-lock wait 不等同于真实 CDR settling time 的定量复现。

### D10：training toggles 与 manual retention

目的：逐个关闭五个独立 training stage，确认 stageTrace 标记和 requested 手动值保留。GUI 与 CLI 的输入边界如下：

| 输入来源 | 本演示可设置的字段 |
|---|---|
| GUI paper table | 五个 debugStages toggle；txPma.lane.gainError、rxPma.lane.termGain、rxPma.lane.samplerRoles.samplerOffsetCodes、rxPma.lane.ctleBoost_dB、txPma.lane.ffeCoeffs 等可见行 |
| CLI Config only | model.cdrOptions.staticPhaseSkewUI、model.cdrOptions.staticDutyCorrectionUI；它们不在 GUI 的 paperConfigPaths 参数表中 |

下面 CLI 示例显式设置两项 runtime/backend 字段，GUI 步骤不要求用户输入不存在的字段。

~~~matlab
root = 'E:\Master_Record\D2D_matlab_model';
cd(root);
addpath(genpath(fullfile(root,'src')));
addpath(fullfile(root,'test'));
toggleNames = {'startupCalibration','clockTraining','samplerCalibration','ctleTraining','ffeTraining'};
for k = 1:numel(toggleNames)
    cfg = phyConfig('vlsi2024_xsr_typical');
    nBits = 128;
    cfg.link.nBits = nBits;
    cfg.model.debugStages.(toggleNames{k}) = false;
    cfg.txPma.lane.gainError = 0.11;
    cfg.rxPma.lane.termGain = 0.88;
    cfg.model.cdrOptions.staticPhaseSkewUI = 0.07;
    cfg.model.cdrOptions.staticDutyCorrectionUI = 0.03;
    cfg.rxPma.lane.samplerRoles.samplerOffsetCodes = 0.25;
    cfg.rxPma.lane.ctleBoost_dB = 5;
    cfg.txPma.lane.ffeCoeffs = [-0.02 0.96 -0.02];
    [out,~] = run_vlsi2024_xsr('debug_link',nBits,'Config',cfg);
    row = strcmp(string(out.stageTrace.stage),strrep(toggleNames{k},'Calibration','_calibration'));
    if strcmp(toggleNames{k},'ctleTraining'), row=strcmp(string(out.stageTrace.stage),'ctle_training'); end
    if strcmp(toggleNames{k},'ffeTraining'), row=strcmp(string(out.stageTrace.stage),'ffe_training'); end
    if strcmp(toggleNames{k},'samplerCalibration'), row=strcmp(string(out.stageTrace.stage),'sampler_calibration'); end
    if strcmp(toggleNames{k},'clockTraining'), row=strcmp(string(out.stageTrace.stage),'clock_training'); end
    disp(out.stageTrace(row,:));
    disp(out.trainedCfg);
end
~~~

GUI 步骤：执行 app = launchD2DWorkbench()；每次只把 startupCalibration、clockTraining、samplerCalibration、ctleTraining 或 ffeTraining 中一个设为 false；仅在 GUI 可见的参数行输入对应 gain/term、sampler offset、CTLE 或 FFE 手动值，staticPhaseSkewUI/staticDutyCorrectionUI 不在 GUI 表中，需用上面的 CLI Config 示例设置；点击 Run x8 Link；在 stageTrace 和 trainedParameters 检查。预期对应行 status=skipped_manual_value、consumedUI=0，trainedCfg 保留该 stage 所有 requested 值。查看 stageTrace、trainedParameters 的 requested/trained/applied 和 trainedCfg。不能由此说明关闭训练后链路仍具备硅校准能力。

### D11：sampler offset

目的：观察 samplerOffsetCodes 如何进入 role probes，以及 samplerCalibration 如何归零。

~~~matlab
root = 'E:\Master_Record\D2D_matlab_model';
cd(root);
addpath(genpath(fullfile(root,'src')));
addpath(fullfile(root,'test'));
cfg = phyConfig('vlsi2024_xsr_typical');
nBits = 256;
cfg.link.nBits = nBits;
cfg.model.debugStages.samplerCalibration = false;
cfg.rxPma.lane.samplerRoles.samplerOffsetCodes = 0.25;
[outOff,~] = run_vlsi2024_xsr('debug_link',nBits,'Config',cfg);
cfg = phyConfig('vlsi2024_xsr_typical');
nBits = 256;
cfg.link.nBits = nBits;
cfg.model.debugStages.samplerCalibration = true;
cfg.rxPma.lane.samplerRoles.samplerOffsetCodes = 0.25;
[outOn,~] = run_vlsi2024_xsr('debug_link',nBits,'Config',cfg);
disp(outOff.trainedCfg.rxPma.lane.samplerRoles.samplerOffsetCodes);
disp(outOn.trainedCfg.rxPma.lane.samplerRoles.samplerOffsetCodes);
disp(outOff.performance.lane(1).levelShiftedSamples(1:min(4,end),:));
disp(outOff.performance.lane(1).spareSamples(1:min(4,end)));
~~~

GUI 步骤：执行 app = launchD2DWorkbench()；选择 VLSI Typical；先将 samplerCalibration=false、samplerOffsetCodes=0.25 后 Run x8 Link；再将 samplerCalibration=true 保持 offset=0.25 后 Run x8 Link；选择 RX level-shifted samples、RX data samples、RX spare samples。预期关闭训练保留 0.25 code，开启训练目标为 0；level-shifted data/spare probes 可见变化。不能估计真实 LOFF RDAC 分辨率、失调 sigma 或亚稳态。

### D12：jitter 与 CDR residual

目的：在不把论文 194 fs 或 CEI mask 当作模型输出的前提下观察 RJ/DJ 进入 sampling/CDR trace。

~~~matlab
root = 'E:\Master_Record\D2D_matlab_model';
cd(root);
addpath(genpath(fullfile(root,'src')));
addpath(fullfile(root,'test'));
cfg = phyConfig('vlsi2024_xsr_typical');
nBits = 256;
cfg.link.nBits = nBits;
cfg.link.rjUI_rms = 0.04;
cfg.link.djUI_pp = 0.08;
cfg.link.djFreq = 0.001;
[out,~] = run_vlsi2024_xsr('debug_link',nBits,'Config',cfg);
disp(out.status);
disp(out.fullLockTrace{1}.residualPhaseUI(1:min(16,end)));
disp(out.fullLockTrace{1}.piCodeTrace(1:min(16,end)));
~~~

GUI 步骤：执行 app = launchD2DWorkbench()；选择 VLSI Typical；修改 link.rjUI_rms、link.djUI_pp、link.djFreq；点击 Run x8 Link；选择 PI code、CDR error、CDR lock。若要写 jitter_tolerance.csv，另执行 run_vlsi2024_regression('full',2^14)，再读取该文件。预期 jitter 改变 sampling timing、residual 和可能的 lock/BER；比较必须固定 seed 与 measured_bits。不能由此复现 CEI mask、194 fs 的滤波测量或 PVT 曲线。

### D13：adaptation disturbance/recovery

目的：展示五状态 calibration/adaptation 的受扰与恢复，而不是以 BER 训练。

~~~matlab
root = 'E:\Master_Record\D2D_matlab_model';
cd(root);
addpath(genpath(fullfile(root,'src')));
addpath(fullfile(root,'test'));
cfg = phyConfig('vlsi2024_xsr_typical');
nBits = 2^14;
cfg.link.nBits = nBits;
[out,cfgOut] = run_vlsi2024_xsr('adaptation',nBits,'Config',cfg);
disp(cfgOut.model.enablePaperAdaptation);
disp(out.stateTrace(:,{'state','objective','disturbed_objective','recovered_objective','control_changed'}));
disp(out.ctleTrace(:,{'requested_dB','applied_dB','residual_ctle_error_dB','recovered'}));
stateFile = fullfile(root,'results','vlsi2024_xsr','adaptation_state_trace.csv');
ctleFile = fullfile(root,'results','vlsi2024_xsr','ctle_adaptation_trace.csv');
disp(readtable(stateFile));
disp(readtable(ctleFile));
~~~

GUI 步骤：执行 app = launchD2DWorkbench()；选择 VLSI Typical；点击 Calibration / Adaptation；等待 callback 完成后打开 results/vlsi2024_xsr 下两个 trace。预期 RESET 后出现 disturbed objective，MISSION_TRACK 的 recovered objective 高于 disturbed objective，CTLE residual 在限制内。查看 adaptation_state_trace.csv、ctle_adaptation_trace.csv 和 Adaptation objective。不能把 objective recovery 写成 finite BER 优化或硅背景跟踪。

### D14：x8 debug 与 final full

目的：先观察 8 lane lock/统一 post-lock，再生成正式全量 artifacts。

~~~matlab
root = 'E:\Master_Record\D2D_matlab_model';
cd(root);
addpath(genpath(fullfile(root,'src')));
addpath(fullfile(root,'test'));
cfg = phyConfig('vlsi2024_xsr_typical');
nBits = 256;
cfg.link.nBits = nBits;
[debugOut,~] = run_vlsi2024_xsr('debug_link',nBits,'Config',cfg);
disp(debugOut.status);
disp(debugOut.laneLockUI);
disp(debugOut.measurementStartUI);
disp(debugOut.measurementStartSample);
disp(debugOut.result.berValid);
disp(debugOut.trainedParameters);
~~~

GUI 步骤：执行 app = launchD2DWorkbench()；选择 VLSI Typical；点击 Run x8 Link；在 Metrics 选择 Aggregate/Lane 1–8，确认所有 lane 使用同一 BER start UI；再点击 Full VLSI2024 Regression。命令行正式 full：

~~~matlab
root = 'E:\Master_Record\D2D_matlab_model';
cd(root);
addpath(genpath(fullfile(root,'src')));
addpath(fullfile(root,'test'));
nBits = 4096;
cfg = phyConfig('vlsi2024_xsr_typical');
cfg.link.nBits = nBits;
fullOut = run_vlsi2024_regression('full',nBits);
resultRoot = fullOut.resultRoot;
[ok,detail] = validate_vlsi2024_artifacts(resultRoot);
disp(fullOut.summary);
disp(ok);
disp(detail);
disp(readtable(fullfile(resultRoot,'regression_summary.csv')));
~~~

预期 debug 输出 laneLockUI、Metrics 和 global post-lock performance；full 输出 regression_summary.csv、paper comparison、jitter/adaptation/PI/IL artifacts 和 legacy_t1_t9。查看 MetricsTable、Debug.performance、regression_summary.csv 和 legacy_t1_t9。保存的 pass 或有限样本结果都不能升级为论文 silicon sign-off。

## 11. 常见错误与排障

| 症状 | 检查 |
|---|---|
| Undefined function phyConfig/D2DPHY | 当前目录是否为 D2D_matlab_model；是否 addpath(genpath(src)) |
| paper schema rejected | paper.id、preset、FFE offsets/coeffs 长度和 main offset 0、PAM4 三阈值 |
| GUI edit 报 invalid paper control | 数值是否有限/整数；CTLE 是否 0–6；loss 是否非负；logical 是否 true/false；AC/DC 和 policy 是否为允许枚举 |
| Run x8 Link 改了共享文件 | 检查是否误点 Apply + Sync；Run x8 Link 本身只调用 applyConfigTable(false) |
| GUI Status Passed 但 BER 是 NaN | 看 Debug.status/berValid；invalid_no_lock、invalid_insufficient_bits、debug_no_cdr 都不是有效 BER |
| 全 lane 没有 lock | 读 CDR error、transitionTrace、PI raw/wrapped/applied code、residualPhaseUI；调整 nBits、lockWindow、tolerance 仅作为模型实验 |
| no-CDR 结果相位不对 | 检查 effective CDR 合取，使用 manualPhaseUI[0,1) 和整数 manualDelayUI |
| CTLE 请求 4.13 与 applied 不同 | 这是 candidate 的 paper_grid round 到 4.2；candidate_4.13 不是最终 selected/trained/applied 值，检查 final trainedCfg/appliedCfg；不要改成连续档位 |
| AC pre 没变化 | terminationMode 必须为 AC 且 enableAcPre=true；DC 模式强制旁路 |
| static action 没采用当前 Config | 当前 static_checkpoint 内部 baseline/loss_sweep 不带 Config；用独立 baseline/loss_sweep Config 调用 |
| full regression 没采用 GUI 编辑 | 当前 run_vlsi2024_regression('full',…) 没有 Config 参数；检查 config.json 的实际 runner profile |
| artifact validator 缺文件 | 先按结果目录清单运行 baseline/static/adaptation/full；确认没有把 legacy_t1_t9 当主目录 |
| Simulink builder 覆盖已有模型 | 使用 ModelPath、ModelName 临时名和 Overwrite=false；先确认 license |
| Load from Simulink 读到旧值 | 按 Model Workspace → base → shared MAT 优先级逐层检查；必要时显式 Load 或 Apply + Sync |

## 12. 验收清单

### 源码与文档

- [ ] MATLAB R2024b 初始化可执行，Ideal core smoke 有输出。
- [ ] VLSI Typical/Ideal 保持 paper identity/schema，GUI 只有 paper preset/actions。
- [ ] GUI 参数路径与 D2DWorkbench.paperConfigPaths() 一致。
- [ ] 五个 training toggle、各 UI budget、cdrEnabled、postLockWaitUI、manual phase/delay 都能在表和文档中找到。
- [ ] trainedParameters 含 requested/trained/applied/residual/constraint/unit 和完整路径。

### 运行与窗口

- [ ] formal baseline/debug link 为 useReferenceAlign=false、trainingMode=decision_directed。
- [ ] final BER 仅从 berStartUI/measurementStartSample 起算。
- [ ] latest-lock global post-lock 起点对所有 lane 相同。
- [ ] no-lock、insufficient bits、no-CDR 都将 BER 标为 invalid，而不是 0。
- [ ] pre-lock trace 可诊断但不进入 eye/BER/performance。

### artifact

- [ ] baseline、IL、3/6-tap、AC/CTLE、CDR/PI、jitter、adaptation、comparison、regression_summary 文件存在。
- [ ] UCB 与 errors/measured_bits 关系正确；zero-error 使用 3/N。
- [ ] legacy_t1_t9 与主 paper artifacts 分离。
- [ ] validate_vlsi2024_artifacts(root) 返回 ok=true 后，才把本次 full 作为结构完整。

### 边界声明

- [ ] 报告把 paper facts、model assumptions、model outputs、limitations 分栏。
- [ ] 未把 <1e-12/<1e-14、0.9 pJ/b、194 fs 或 COM 当作模型 sign-off。
- [ ] 未声称有真实 S 参数、MIMO、T-coil、功耗、硅校准或完整速率覆盖。

## 13. 当前模型边界与可安全扩展方向

如果后续获得真实 Touchstone/MIMO 数据，可以新增独立 channel mode 和结果目录，不应替换 analytic_il 旧证据。若要加入更真实的 SST/DLL/PI/offset/power，先定义输入数据、独立验证和新的 artifact schema；不要把未知电路细节填进现有 paper fields。任何扩展仍应保持 MATLAB DSP 为算法源、GUI 为 paper-only、legacy T1–T9 仅 CLI 兼容。
