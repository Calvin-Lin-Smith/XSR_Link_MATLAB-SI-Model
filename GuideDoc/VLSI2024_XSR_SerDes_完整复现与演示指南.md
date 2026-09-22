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
cfg = phyConfig('ideal');
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
[out,cfg] = run_vlsi2024_xsr('baseline',2^18);
[out,cfg] = run_vlsi2024_xsr('debug_1lane',4096);
[out,cfg] = run_vlsi2024_xsr('loss_sweep',2^14);
[out,cfg] = run_vlsi2024_xsr('static_checkpoint',2^14);
[out,cfg] = run_vlsi2024_xsr('adaptation',2^14);
[out,cfg] = run_vlsi2024_xsr('debug_link',4096,'Config',paperT);
out = run_vlsi2024_regression('full',4096);
ok = validate_vlsi2024_artifacts(fullfile(root,'results','vlsi2024_xsr'));
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

正式 VLSI paper path 在 RxLane 中设置 model.useReferenceAlign=false、model.trainingMode='decision_directed'。RxSupport.Pll 生成 jitter/recovered-clock 行为源，dspBbCdr/dspPiClock 负责 final decision-directed timing；它们不是门级 DLL/PI。

### 2.2 bit 到 BER

1. RawPcs.run 生成 PRBS31 referenceBits；dspMap 将 PAM4 bit pair 映射为 −3、−1、+1、+3。
2. TxLane 依次执行 signed FFE、Serializer 过采样和 Driver；Driver 可执行 targetSwing 钳位、gainError 与 DAC quantization。
3. 每个 lane 经过 Channel。paper mode 使用 dspChannel 的 analytic_il，在 refFreq_GHz=28、baud_GBd=56.25 处校准 lossAtRef_dB。
4. D2DPHY.run 在 channel output 上按 link.seed 加入由 snr_dB 指定的 RMS 高斯噪声。
5. RxPma 生成 jitter；RxLane 经过 Afe，再选择 legacy reference alignment、manual phase 或 BB-CDR。
6. Slicer 保存 data/edge/spare roles，Deserializer 返回 rxBits；RawPcs.check 只在 BER checker 阶段将 rxBits 与 referenceBits 对比。

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
| Apply + Sync | applyConfigTable(true) → syncD2DConfig(app.Cfg) | 写 base d2dCfg；默认还写 shared MAT，并更新已加载模型 workspace |
| Load from Simulink | loadD2DSharedConfig() → validatePaperConfig | 按 Model Workspace、base、shared MAT、默认配置的优先级读回；不写 |
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
8. 只在 final window 对 RawPcs.referenceBits 计数，并输出 performance 和 trainedParameters。

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

当 CTLE trace 非空，最后附加 rxPma.lane.ctleBoost_dB[candidate_4.13]，其报告值为 requested=4.13、trained=4.13、applied=4.2、residual=0.07；这是 off-grid quantization evidence，不是正式 4.13 档位。

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
cfg = phyConfig('vlsi2024_xsr_typical');
[out,cfg] = run_vlsi2024_xsr('baseline',2^18,'Config',cfg);
~~~

该模式写 results/vlsi2024_xsr/config.json、assumptions.md、baseline_metrics.csv、cdr_lock_trace.csv、pi_code_trace.csv、residual_phase_histogram.csv、plots/cdr_residual_phase.png 和 baseline_probes.mat。baseline 采用 formal useReferenceAlign=false，不是 legacy oracle alignment。

### 6.2 Static checkpoints

~~~matlab
[out,cfg] = run_vlsi2024_xsr('static_checkpoint',2^14);
~~~

输出 channel_il_at_28GHz.csv、channel_response.csv、channel_il.csv、loss_sweep_metrics.csv、ffe_3_vs_6.csv、ac_ctle.csv、static_regression_summary.csv。static_checkpoint 内部使用默认 paper runner 子调用；需要自定义 cfg 时分别调用：

~~~matlab
cfg = phyConfig('vlsi2024_xsr_typical');
[loss,cfg] = run_vlsi2024_xsr('loss_sweep',2^14,'Config',cfg);
[base,cfg] = run_vlsi2024_xsr('baseline',2^14,'Config',cfg);
~~~

### 6.3 Calibration / adaptation

~~~matlab
cfg = phyConfig('vlsi2024_xsr_typical');
[out,cfg] = run_vlsi2024_xsr('adaptation',2^14,'Config',cfg);
~~~

adaptation runner 的有效训练样本为 min(cfg.link.nBits,2^14)，固定五状态 RESET、STARTUP_IMPEDANCE_CAL、CLOCK_CAL、INITIAL_EQ_TRAIN、MISSION_TRACK。objective 是 minimum adjacent decision-level margin；MISSION_TRACK 先引入 CTLE drift，再恢复训练后的控制。专用 adaptation mode 默认 enablePaperAdaptation=true；需要关闭行为时显式传 name/value：

~~~matlab
[out,cfg] = run_vlsi2024_xsr('adaptation',4096,'Config',cfg,'enablePaperAdaptation',false);
~~~

### 6.4 Full regression

~~~matlab
out = run_vlsi2024_regression('full');
~~~

为了先做 smoke，可用：

~~~matlab
out = run_vlsi2024_regression('full',4096);
~~~

full runner 顺序为 baseline → static_checkpoint → baseline restore → adaptation → bounded jitter tolerance → paper comparison → fresh run_all_tests(legacyRoot) → validate_vlsi2024_artifacts。它会写全量 paper 结果和 results/vlsi2024_xsr/legacy_t1_t9。不要把 GUI 当前编辑 cfg 当作 full runner 的输入；当前函数签名没有 Config option。

### 6.5 T1–T9 兼容 CLI

~~~matlab
summary = run_all_tests();
summary = run_all_tests(fullfile(root,'results','vlsi2024_xsr','legacy_t1_t9'));
~~~

T1–T9 是旧兼容命令行路径，覆盖 16 组眼图、损耗趋势、经验 bathtub、FFE/CTLE、码型注错、NRZ/PAM4、CDR 带宽和 x8 loopback。它们不属于 GUI paper actions；full regression 将它们隔离写到 legacy_t1_t9。

## 7. Simulink 生成、同步和安全验证

Simulink 是独立框图路径，MATLAB class/DSP 仍是算法源。顶层结构为 TX Bits → Raw PCS → TX PMA x8 → Die-to-Die Channel x8 → RX PMA x8 → BER_Results → RX Bits；各 lane 使用 Interpreted MATLAB Function 引用 src/dsp。

### 7.1 builder 选项

buildD2DSimulinkModel 的当前签名和 name/value：

~~~matlab
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
cfg = phyConfig('vlsi2024_xsr_typical');
tmp = buildD2DSimulinkModel('ModelName','stage_h_tmp', ...
    'ModelPath',fullfile(root,'simulink','stage_h_tmp.slx'), ...
    'Config',cfg,'Open',false,'Save',true,'Overwrite',false);
~~~

完成检查后由调用者清理临时 SLX；不要用临时模型名覆盖 tracked D2D_PHY_SI_Simulink.slx。Apply + Sync 才会写 shared MAT；Load from Simulink 只读。

### 7.4 同步流程

~~~matlab
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
10. 若需 Simulink 演示，使用显式 Config 和临时 ModelName/ModelPath，先更新模型，再 Load from Simulink 做 round-trip 检查。

## 10. 演示工况清单

以下每项都给出目的、设置、命令/GUI、预期趋势、查看位置和不能得出的结论。除明确写出 artifact 的项目外，debug_link 都是内存结果，不写正式结果。

| 演示 | 目的与设置 | 命令/GUI 步骤 | 预期趋势 | 查看 artifact/probe | 不能得出的结论 |
|---|---|---|---|---|---|
| Ideal vs Typical | 同一 paper schema 对比零损耗/零噪声与 nominal loss/noise/jitter | cfgI/cfgT 分别调用 debug_link；GUI 选择 VLSI Ideal/VLSI Typical 后 Run x8 Link | Ideal 波形、CTLE/AC/DAC impairment 更少；Typical 更能显示损耗和 jitter 影响；以 status/berValid 为准 | Debug.appliedCfg、performance.lane、RX CTLE output、TX DAC/pad、CDR lock | 不证明真实 PVT、silicon margin 或论文 BER |
| loss sweep | 28 GHz analytic IL 0.5/2/4/6/8/10 dB | run_vlsi2024_xsr('loss_sweep',2^14,'Config',cfg)；或 GUI 的 Static action | measured_loss 接近 requested；损耗变大通常提高 ISI 压力，但 BER 是否单调须看本次 rows | loss_sweep_metrics.csv、channel_il_at_28GHz.csv、channel_response.csv、Channel output | 不证明长度到 IL 的真实映射、反射或 MIMO 串扰 |
| 3 vs 6 tap | 观察 tap count 和 model-selected coefficients 的相对行为 | static_checkpoint；或 cfg 设 ffeMode='six_tap'、offsets/coeffs 后 debug_link | tapMeta offsets/coeffs 变化；6-tap 不保证优于 3-tap | ffe_3_vs_6.csv、trainedParameters、TX FFE output、tapMeta | 不声称系数来自论文，也不声称 6-tap 必然改善 |
| DAC on/off | 对比 Driver 量化和 swing calibration | cfg.txPma.lane.enableDacQuantization=true/false，分别 debug_link | on 时 TX pad 落在 targetSwing 的离散 step；off 时无 dacMeta 量化 | Debug.appliedCfg、model.txPma.lane(1).driver.dacMeta、TX DAC/pad | 不推导 SST 段权重、7.5-bit 电路、功耗或真实 swing |
| AC/DC 与 pre/post | 分离 terminationMode、AC pre 和 AC post 的影响 | 直接构造 cfgAc/cfgDc，分别 D2DPHY.configure/run；也可 GUI 改 AC/DC 与两个 enable | AC+enable 的 acPreOut/ acPostOut 不等于输入；DC 或关闭时相应路径旁路 | Afe.termOut、acPreOut、ctleRaw、acPostOut、ctleOut；static ac_ctle.csv | 不代表真实 transformer/leveling 电路频响 |
| CTLE grid/off-grid | 检查 0–6 dB、0.2 dB 网格和训练候选 | GUI 将 ctleBoost_dB 改为 4.13 后 Run x8 Link；static action 扫 grid | requested 4.13 会 applied 4.2；网格行 applied 与请求一致 | trainedParameters candidate_4.13、ctle_adaptation_trace.csv、CTLE output | 不把 4.13 当正式档位，也不声称零极点是论文值 |
| CDR on/off | 区分 formal BB-CDR 与 manual debug | c.model.debugStages.cdrEnabled/cdrOptions.enabled 设置四种合取组合后 debug_link；GUI 编辑两个开关 | 两者都 true 才 effectiveCdrEnabled=true；任一 false 为 debug_no_cdr，manual phase 生效 | Debug.status、effectiveCdrEnabled、fullLockTrace、PI code、CDR error、trainedParameters | no-CDR 结果不属于 formal paper BER，不能与 lock path 等价 |
| no-lock | 验证无锁不能伪造 BER | cfg.model.cdrOptions.lockWindow=100000 后 debug_link | status=invalid_no_lock、berValid=false、Result.ber/errCnt 为 NaN | Debug.laneLocked、laneLockUI、fullLockTrace、stageTrace | 不把 NaN 改成 0，也不把 pre-lock 波形当性能 |
| postLock | 检查 latest-lock 后等待量和统一起点 | 分别设置 debugStages.postLockWaitUI=0/32 后 debug_link | measurementStartUI 至少随 latestLock+postLockWaitUI 增大；所有 lane start 相同 | measurementStartUI/sample、berStartUIInFinalPass、totalWaitedUI、performance.lane | 不把 post-lock wait 当成物理 CDR settling time 的定量复现 |
| training toggles/manual retention | 检查五个独立 toggle 关闭后的手动值保留 | 逐个将 startupCalibration、clockTraining、samplerCalibration、ctleTraining、ffeTraining=false，并设 gain/phase/offset/CTLE/FFE 手动值后 debug_link | 对应 stage skipped_manual_value、consumedUI=0；trainedCfg 保留该 stage 所有请求值 | stageTrace、trainedParameters requested/trained/applied、trainedCfg | 不说明关闭训练后链路仍具备硅校准能力 |
| sampler offset | 检查 offset 进入 role probes 及校准归零 | 先 samplerCalibration=false、samplerOffsetCodes=0.25 debug；再打开 calibration 对照 | 关闭训练保留 0.25 code；开启训练目标为 0；level-shifted data/spare 可见变化 | Slicer levelShiftedSamples、dataDecisionInput、spareMonitorOutput、trainedParameters | 不估计真实 LOFF RDAC 分辨率、失调 sigma 或亚稳态 |
| jitter | 观察 RJ/SJ 行为与 CDR residual context | run_vlsi2024_regression('full',2^14)；或 baseline Config 修改 rjUI_rms/djUI_pp | jitter 改变 Pll/采样时序；BER/residual 需结合 seed 和 finite sample 比较，不要求无条件单调 | jitter_tolerance.csv、cdr_lock_trace.csv、residual_phase_histogram.csv、CDR trace | 不复现 CEI mask、194 fs 测量滤波或 PVT 曲线 |
| adaptation disturbance/recovery | 展示 startup/clock/equalization/mission 的受扰与恢复 | run_vlsi2024_xsr('adaptation',2^14,'Config',cfg)；GUI Calibration / Adaptation | RESET 后有 disturbed objective；MISSION_TRACK 的 recovered objective 应高于 disturbed objective；CTLE residual 在限制内 | adaptation_state_trace.csv、ctle_adaptation_trace.csv、Adaptation objective probe | 不把 objective recovery 写成 finite BER 优化或硅背景跟踪 |
| x8 与 final full | 观察 lane lock 差异、统一 post-lock、正式 artifact | GUI Run x8 Link 查看 8 lane；再 Full VLSI2024 Regression 或 CLI full | x8 输出 laneLockUI/metrics；full 输出 regression_summary 与全量 required artifacts | MetricsTable、Debug.performance、regression_summary.csv、legacy_t1_t9 | 不把保存的 pass 或有限结果升级为论文 silicon sign-off |

一个最小 custom debug 示例：

~~~matlab
cfg = phyConfig('vlsi2024_xsr_typical');
cfg.link.nBits = 4096;
cfg.model.debugStages.ctleTraining = false;
cfg.rxPma.lane.ctleBoost_dB = 5;
[out,~] = run_vlsi2024_xsr('debug_link',cfg.link.nBits,'Config',cfg);
row = out.trainedParameters(strcmp(string(out.trainedParameters.parameterPath), ...
    'rxPma.lane.ctleBoost_dB'),:);
disp(row);
~~~

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
| CTLE 请求 4.13 与 applied 不同 | 这是 paper_grid round 到 4.2；检查 candidate_4.13 行，不要改成连续档位 |
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
