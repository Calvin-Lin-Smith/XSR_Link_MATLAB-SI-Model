# VLSI2024 BER≈0.5 修复实施报告

## 范围与基线

- 子仓：`E:\Master_Record\D2D_matlab_model`，默认 `main`；初始 HEAD `dd629c2ba7a6a53b8bde6e1d4c700cc23a3f6b96`，远端同步。
- 父仓：`E:\Master_Record`，初始 HEAD `8ae55b2c74383900c6e48ebbc9bb81f72a1acdeb`；父仓 `node_modules` 修改未暂存、未修改、未提交。
- 初始用户改动：`simulink/d2d_shared_config.mat` 已修改；方案文档未跟踪。MAT 的语义未被本任务改写，方案文档已纳入 Task 1 提交；MAT 保持未提交。
- 初始复现命令：`matlab -batch "addpath(genpath(pwd)); [o,c]=run_vlsi2024_xsr('debug_1lane',8192); ..."`。
- 初始证据：1-lane 8192-bit `empirical_BER=0.4456200787`；Driver `targetSwing=1`、DAC peak=`1`；CDR `decisionTrace` 只有 `[-1,1]`，对应逻辑 outer level 丢失。

## 根因证据

1. TX paper DAC 原来以 `targetSwing=1` 作为 logical clipping bound，导致 canonical PAM4 `[-3,-1,1,3]` 被压到 `[-1,1]`。
2. RX Slicer/BB-CDR 仍用 logical thresholds `[-2,0,2]`，所以 outer decisions 消失；这解释了 BER 接近随机。
3. 原 CDR lock 只检查 transition/phase/PI span，二电平仍可 lock；原 checker 只按 skip UI 比较，未搜索 integer UI lag。
4. 原 PI span使用 wrapped code，`63→0` 会制造假失锁；原 adaptation objective 只计算现存 decision levels，不能拒绝二电平候选。
5. 修复后 baseline 的 fresh 2^18 x8 结果为 BER 0.0427087–0.0457879、8/8 four-level valid、8/8 tail lock、checker lag 全为 `+1 UI`，验证上述根因链已断开。

## Task 1 — `Fix PAM4 logical amplitude contract`

- RED：新增 `test/test_vlsi2024_pam4_contract.m` 后运行
  `matlab -batch "addpath(genpath(pwd)); test_vlsi2024_pam4_contract"`；失败：`dspPam4Contract` 无法识别。
- GREEN：实现 `src/dsp/dspPam4Contract.m`，mapper/slicer/CDR/Slicer 统一 Gray contract；paper Driver 在 logical `[-3,3]` 量化，physical target 仅 metadata，Simulink DAC 不再乘 `targetSwing`；同步 GUI、Simulink、README/GuideDoc、PAM4 expected vectors。
- GREEN 命令：`matlab -batch "addpath(genpath(pwd)); test_vlsi2024_pam4_contract; test_dsp; test_tx_driver_quantization; test_sampler_thresholds; test_vlsi2024_profile"`。
- 关键输出：`VLSI2024 PAM4 contract tests OK`、`DSP tests OK`、`Driver quantization tests OK`、`Sampler threshold tests OK`、`VLSI2024 profile and runner tests OK`。
- Commit：`73d4bfb Fix PAM4 logical amplitude contract`。

## Task 2 — `Add blind PAM4 RX leveling`

- RED：`matlab -batch "addpath(genpath(pwd)); test_pam4_leveling"`；失败：`dspPam4Leveling` 无法识别。
- GREEN：实现 RX-only deterministic four-cluster leveling，保存 raw/logical centroids、occupancy、offset、scale；二电平输入返回 `levelsValid=false`；RxLane/Slicer 保存 raw 与 logical probes。
- GREEN 命令：`matlab -batch "addpath(genpath(pwd)); test_pam4_leveling; test_sampler_thresholds; test_vlsi2024_pam4_contract"`。
- 关键输出：`PAM4 leveling tests OK`；2048-bit VLSI 1-lane trace 出现 `levels=-3 -1 1 3`，occupancy 四簇有效。
- Commit：`75dc08a Add blind PAM4 RX leveling`。

## Task 3 — `Align paper BER checker by integer UI`

- RED：`matlab -batch "addpath(genpath(pwd)); test_checker_ui_alignment"`；失败：旧 checker `Too many output arguments`。
- GREEN：保留 `check(rxBits,skipUI)`，增加可选 paper path；以 2-bit/UI bounded lag 搜索，odd-bit framing 标 invalid；sync 与 measurement 独立；CDR 不接收 reference bits。
- GREEN 命令：`matlab -batch "addpath(genpath(pwd)); test_checker_ui_alignment; test_cdr_no_reference_bits"`。
- 关键输出：`Checker integer UI alignment tests OK`、`CDR no-reference-bits test OK`；已知 +1 UI shift 得 `checkerLagUI=1`、zero errors，odd-bit 被拒绝。
- Commit：`3d7adf1 Align paper BER checker by integer UI`。

## Task 4 — `Require valid PAM4 levels for CDR and training`

- RED：`matlab -batch "addpath(genpath(pwd)); test_bb_cdr_pam4_valid_lock"`；失败：trace 缺少 `everLocked`。
- GREEN：CDR 区分 `everLocked/currentlyLocked/lockLossCount`，加入 rolling four-level occupancy/eye margin；two-level/constant/collapse 不得 current-lock；记录 unwrapped PI/sample time/cycle slip；adaptation objective 加入 four-level validity、separation、within-cluster noise。
- 额外根因修复：lock span 改用 unwrapped PI code，避免 wrapped `63→0` 假失锁。
- GREEN 命令：`matlab -batch "addpath(genpath(pwd)); test_bb_cdr_pam4_valid_lock; test_adaptation_requires_four_levels; test_fix_adaptation_disturbance"`。
- 关键输出：`PAM4 valid-lock tests OK`、`Four-level adaptation objective tests OK`、`Fix adaptation disturbance tests OK`。
- Commit：`669a4ed Require valid PAM4 levels for CDR and training`。

## Task 5 — `Close VLSI2024 PAM4 link regression`

- RED：`test_vlsi2024_ac_solution` 首先因缺少 AC selection metadata 失败；random BER 负测在保持 errors/bits/ratio 自洽时暴露旧 validator 可接受随机 BER。
- GREEN：运行规定的 `cornerRelNyq=[1e-4,3e-4,1e-3,3e-3,1e-2] × {pre-only,post-only,pre+post}`；选择最高可解释 corner（0.01/pre-only），加入独立 regression gates、checker/leveling/CDR/physical-vs-logical metadata validator；修正 CTLE=6 时 drift 被上限截断而不退化的 adaptation 根因。
- GREEN 命令：`matlab -batch "addpath(genpath(pwd)); test_vlsi2024_ac_solution; test_regression_rejects_random_ber; test_fix_adaptation_disturbance"`。
- 关键输出：AC selection test、random-BER rejection、adaptation disturbance 均通过。
- Final fresh `run_all_tests()` 命令：`matlab -batch "addpath(genpath(pwd)); summary=run_all_tests();"`。
- Final fresh T1–T9：`results/summary.csv` 为 `T1..T9 pass=1`，JUnit `tests="9" failures="0"`。
- Final canonical 命令：`matlab -batch "addpath(genpath(pwd)); o=run_vlsi2024_regression('full');"`。
- Final canonical fresh evidence：`regression_summary.csv` 11/11 PASS；validator `validate_vlsi2024_artifacts(results/vlsi2024_xsr)` 返回 `ok=1 detail=OK`。

## Final key metrics

| lane | errors | measured bits | BER | UCB95 | four levels | tail lock | lock losses | checker lag UI |
|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| 1 | 12000 | 262078 | 0.0457879 | 0.0464651 | 1 | 1 | 1210 | 1 |
| 2 | 11193 | 262078 | 0.0427087 | 0.0433640 | 1 | 1 | 1178 | 1 |
| 3 | 11806 | 262078 | 0.0450477 | 0.0457197 | 1 | 1 | 1203 | 1 |
| 4 | 11424 | 262078 | 0.0435901 | 0.0442518 | 1 | 1 | 1176 | 1 |
| 5 | 11653 | 262078 | 0.0444639 | 0.0451318 | 1 | 1 | 1214 | 1 |
| 6 | 11735 | 262078 | 0.0447767 | 0.0454469 | 1 | 1 | 1221 | 1 |
| 7 | 11671 | 262078 | 0.0445325 | 0.0452009 | 1 | 1 | 1169 | 1 |
| 8 | 11800 | 262078 | 0.0450248 | 0.0456966 | 1 | 1 | 1245 | 1 |

- Aggregate BER：`0.0444915254`；all 8 lanes four-level valid/tail locked/checker aligned。
- Leveling scale：约 `2.04558–2.04646`；logical outer level `3`；physical target swing `1`；logical DAC step `6/205`。
- AC matrix：15/15 rows valid；最高 valid corner `0.01`，selected mode `pre-only`，model-selected assumption（论文未公开该值）。0.01 rows 的 eye margin 为约 `0.503–0.659`；pre-only selected row aggregate BER `0.0862851`（sweep sample context）。
- Gates：`pam4_contract_pass`、`gray_adjacency_pass`、`tx_dac_logical_scale_pass`、`four_levels_valid`、`tail_lock_pass`、`checker_alignment_pass`、`ber_sanity_pass`、`artifact_schema_pass`、`static_link`、`adaptation`、`legacy_t1_t9` 全部 PASS。

## 变更与提交

- Task 1：contract/mapper/slicer/CDR/Driver/config/GUI/Simulink/docs/tests。
- Task 2：`dspPam4Leveling`、Slicer/RxLane integration、leveling test。
- Task 3：RawPcs/D2DPHY paper checker、xsr runner、alignment test。
- Task 4：CDR validity/PI audit/adaptation objective、xsr runner、two negative tests。
- Task 5：AC sweep/config、regression gates、artifact validator、AC/random-BER tests，以及 fresh `results/` artifacts。
- 子仓最终 commits：`73d4bfb`、`75dc08a`、`3d7adf1`、`669a4ed`、`9f5b2c6`。

## Push 与状态

- 子仓 push：
  `To https://github.com/Calvin-Lin-Smith/D2D_matlab_model.git`
  `dd629c2..9f5b2c6  main -> main`
- 父仓仅执行 `git add -- D2D_matlab_model`；staged diff 只有 gitlink `dd629c2 → 9f5b2c6`，dirty 子仓的 shared MAT 未被纳入 staged diff。
- 父仓 commit：`2d2207b Update D2D MATLAB model submodule`。
- 父仓 push：
  `To https://github.com/Calvin-Lin-Smith/Master_Record.git`
  `8ae55b2..2d2207b  main -> main`
- 子仓最终工作树（报告创建前）仅保留用户既有：`M simulink/d2d_shared_config.mat`；父仓 node_modules 修改均未暂存/提交。

## 自审与 concerns

- BER 是有限样本 empirical BER/UCB，不是论文极低 BER 的 silicon/sign-off 复现。
- 当前 lock loss count 较高，但最终 measurement tail 的 `currentlyLocked=true`；这是按方案要求同时保留 ever/current/loss 证据，而不是用历史 lockIndex 代替 tail lock。
- AC 0.01/pre-only 是本模型 bounded sweep 的选择，不是论文公开参数；真实 S 参数、MIMO 串扰、晶体管级 DAC/CDR、功耗未建模。
- shared MAT 是用户现有未提交改动，按要求未覆盖、未纳入本次提交。

## Final review fix wave（2026-09-08）

本节追加记录 final-review.md 的 8 项 finding。此前报告中的 1210 次失锁和
`measurement_start_ui=32` 是修复前证据；本节及新生成的 `results/` 是最终证据。

### P0：首次有效锁后的连续测量尾与 CDR 根因

- RED 复现/边界证据：对旧 `cdr_lock_trace.csv`、`checker_alignment.csv` 做只读关联，关键输出为
  `first lock=232 UI, last reacquire=131060 UI, lock losses=1210, checker measurement_start_ui=32`；
  旧窗口同时包含 pre-lock 和 lock-loss 区间，证明只检查最终 `currentlyLocked` 不足。
- 根因假设：PAM4 的短 level-validation window 在 acquisition 后仍会把瞬态/不完整四簇判为无效，
  触发 CDR 的反复失锁；应延长验证窗口，并在已经确认的 PAM4 lock 上使用 holdover，保留真实
  transition/phase/PI 证据。该假设先由稳定尾测试验证，未通过移动窗口掩盖失锁。
- GREEN 命令：
  `matlab -batch "addpath(genpath(pwd)); test_cdr_stable_tail; test_measurement_start_metadata"`。
  输出：`CDR stable-tail tests OK`、`Measurement first-lock metadata tests OK`。
  相关实现为 `levelValidationWindow=4096`（按模型长度裁剪）、PAM4 lock holdover、首次有效
  lock/lock loss/cycle-slip/PI trace 持久化，以及全局
  `measurement_start_ui=max(firstValidLockUI)+postLockWaitUI`；不使用 latest/reacquisition 起点。
- 最终边界证据：x8 baseline 的 8 行均 `first_valid_lock_ui=4103`、
  `measurement_start_ui=4119`、`continuous_tail_lock=1`、`tail_lock_losses=0`、
  `tail_cycle_slips=0`、`tail_level_valid=1`；fresh trace 的 tail 中
  `unlock rows=0, invalid-level rows=0, lock-loss events=0, cycle-slip events=0,
  pi-wrap events=0`。acquisition 边界保留 `4102` 个未锁样本、`4095` 个无效 level 样本和
  `53` 个 PI wrap events，均在测量起点之前；tail PI residual 为 `[0,0] UI`，未解释的
  cycle slip/wrap 不进入 BER。baseline lane BER 为 `0.0173924003–0.0189677989`，
  UCB95 为 `0.0178252045–0.0194191388`，每 lane `253904` measured bits。

### P1：严格 framing、统一 slicer contract、leveling validity、Simulink parity

1. **Odd-bit candidate**
   - RED：原审查向量输出 `oddBitErrors=1 < syncErrors=2` 但
     `framingValid=1, alignmentValid=1`，证明“优势阈值”会接受 odd framing。
   - GREEN：`matlab -batch "addpath(genpath(pwd)); test_checker_strict_framing"`；输出
     `Checker strict framing tests OK`。现在 odd candidate 只要严格优于 even 即 invalid，
     even/odd tie 也 invalid，并有 deterministic test 覆盖。
2. **Slicer/GUI threshold contract**
   - RED：向 `thresholdAssumptions=[-0.4 0 0.4]` 注入后旧 Slicer 产生与
     `dspSlice` 不同的 bits；证明存在第二套 PAM4 thresholds。
   - GREEN：`matlab -batch "addpath(genpath(pwd)); test_pam4_slicer_contract_thresholds"`；输出
     `PAM4 Slicer threshold-contract tests OK`。PAM4 只接受精确 `dspPam4Contract().thresholds`
     （否则报错），`levelShiftCodes` 仍是独立 metadata/control。
3. **Blind leveling validity**
   - RED：旧 helper 对 `[-3;-1;1;3;nan(1000,1)]` 和非仿射
     `repelem([0;1;2;20],128)` 都曾返回 `levelsValid=1`。
   - GREEN：`matlab -batch "addpath(genpath(pwd)); test_pam4_leveling_invalid_inputs"`；输出
     `PAM4 leveling invalid-input tests OK`。现在 nonfinite/sparse 输入直接 invalid，
     四簇必须通过 canonical `[-3 -1 1 3]` affine fit residual（persisted as `fitResidual`）
     才 valid。
4. **Simulink executable parity**
   - RED：旧生成模型审查为 TX `MATLABFcn=u`、无 leveling，`BB-CDR PI Adaptation` 仅 Unit Delay。
   - GREEN：`matlab -batch "addpath(genpath(pwd)); test_simulink_paper_parity"`；输出
     `Simulink paper parity tests OK`。paper executable path 现在调用共享
     `dspPaperDriver`、`dspPam4Leveling`、`dspBbCdr`；测试检查生成模型中三者实际接入，
     不以 visual-only 说明绕过 parity gate。

### P2：GUI 证据、AC validator、文档语义

1. **GUI read-only probes**
   - RED：旧 paper controls/probes 没有 Gray mapping、raw/logical samples、centroids、occupancy、scale。
   - GREEN：`matlab -batch "addpath(genpath(pwd)); test_gui_gray_leveling_visibility"`；输出
     `GUI Gray/leveling visibility tests OK`。GUI 仅显示只读 Gray contract banner 和 raw/logical
     leveling probes/meta，没有 mapping switch。
2. **AC artifact validator**
   - RED：tamper `ac_solution.csv.aggregate_BER/ber_upper_95` 后旧 validator 仍接受。
   - GREEN：`matlab -batch "addpath(genpath(pwd)); test_validator_ac_solution_values"`；输出
     `AC validator value tests OK`。AC valid rows 现在要求 BER/UCB/scale/eye finite、范围和
     UCB 关系正确，并以 `errors/measured_bits` 重算 aggregate BER。
3. **targetSwing documentation**
   - RED：旧指南把 `targetSwing` 写成 Driver clipping bound。
   - GREEN：`matlab -batch "addpath(genpath(pwd)); test_document_target_swing"`；输出
     `Document targetSwing tests OK`。指南改为 logicalOuterLevel 负责 logical PAM4
     clipping/quantization，targetSwing 仅为 physical metadata。

### Fix-wave focused RED/GREEN 汇总

除上述单项 focused tests 外，GREEN 汇总命令为：
`matlab -batch "addpath(genpath(pwd)); test_cdr_stable_tail; test_measurement_start_metadata; test_checker_strict_framing; test_pam4_slicer_contract_thresholds; test_pam4_leveling_invalid_inputs; test_simulink_paper_parity; test_gui_gray_leveling_visibility; test_validator_ac_solution_values; test_document_target_swing; test_vlsi2024_profile"`。
各项均通过；`test_vlsi2024_profile` 对短窗口保留 invalid/insufficient evidence 语义。

### Final fresh verification（focused tests 之后）

- 全量 legacy suite（fresh，未使用历史 `summary.csv`）：
  `matlab -batch "addpath(genpath(pwd)); summary=run_all_tests();"`；输出
  `RUN_ALL_FINAL_WAVE_DONE pass=9/9`。
- canonical：
  `matlab -batch "addpath(genpath(pwd)); try, o=run_vlsi2024_regression('full'); fprintf('CANONICAL_FINAL_WAVE_DONE rows=%d pass=%d runtime=%.1fs\\n',height(o.summary),sum(o.summary.pass),o.runtime_s); catch ME, fprintf(2,'%s\\n',getReport(ME,'extended','hyperlinks','off')); exit(1); end"`；
  输出 `T1-T9 regression OK`、`CANONICAL_FINAL_WAVE_DONE rows=11 pass=11 runtime=1257.1s`。
- artifact validator 与负向校验：
  `matlab -batch "addpath(genpath(pwd)); [ok,detail]=validate_vlsi2024_artifacts(fullfile(pwd,'results','vlsi2024_xsr')); fprintf('ARTIFACT_VALIDATOR ok=%d detail=%s\\n',ok,detail); assert(ok); test_validator_ac_solution_values; test_fix_artifact_validator"`；
  输出 `ARTIFACT_VALIDATOR ok=1 detail=OK`、`AC validator value tests OK`、
  `Fix artifact-validator tests OK`。
- Final AC table：`15/15` rows measurement-valid；at `cornerRelNyq=0.01` the model-selected
  minimum-BER row is `pre-only`, `aggregate_BER=0.0191552063`, `UCB95=0.0218466707`,
  `eye_margin=0.989641146`; all valid rows satisfy first-lock/tail fields and validator recomputation.
- Regression gates：11/11 pass；all 8 lanes share first/start `[4103,4119]`, tail losses/slips `0/0`,
  checker lag `+1 UI`; leveling scale `2.04557792–2.04646493`, fit residual
  `0.00887316–0.00940685`.

### Fix-wave commits, artifacts, push/status

- Fix commits（均为新 commit，未 amend 已推送历史）：
  `599cbd1 Fix VLSI2024 review gates and stable tail`；
  `bdb09eb Enforce first-lock BER tail and contract parity`；
  `cc87fa2 Stabilize PAM4 lock validation window`；
  `a797a50 Validate first-lock tails and invalid sweep rows`。
- 本节报告、fresh `results/` artifacts 和必要测试将随最终 fix commit 纳入 child `main`；
  `simulink/d2d_shared_config.mat` 仍保持用户既有 dirty，未暂存。
- 父仓之前的 `d3687d4` 仅指向上一轮 child 报告提交；本轮 child push 后，父仓只暂存
  `D2D_matlab_model` gitlink 并产生新的最终 parent commit。最终 push 输出与 commit SHA
  在本节末尾追加，避免把父仓 `node_modules` 修改混入。

### 自审与 concerns（fix wave）

- 首次有效锁之前允许 acquisition 未锁；从全局 first-lock guard 起点到 measurement end 不丢弃
  中间区间，任何 unlock/level-invalid/cycle-slip 都会令整次 measurement invalid，而不是改选 latest lock。
- BER/UCB 是有限样本 behavioral evidence，不是论文极低 BER 或 silicon/package sign-off；AC 参数是
  bounded model-selected assumption，真实 S 参数/MIMO/晶体管级实现仍未建模。
- Simulink parity focused gate 检查生成 paper model 的共享函数接线；完整 canonical 数值证据仍来自
  MATLAB paper path。shared MAT 和父仓无关 dirty 保留。

### Delivery push addendum

- Child push：`To https://github.com/Calvin-Lin-Smith/D2D_matlab_model.git`，
  `f360814..09360b6  main -> main`。
- Parent pre-addendum pointer commit：`f3f0433 Update D2D MATLAB model submodule`；
  staged name-status 仅为 `M D2D_matlab_model`，submodule diff 为
  `f360814 -> 09360b6`，父仓无关 `node_modules` 和 child shared MAT 未暂存。
- Parent push：`To https://github.com/Calvin-Lin-Smith/Master_Record.git`，
  `d3687d4..f3f0433  main -> main`。
- 本次 addendum 只补写 push 证据；其 child commit 后的父仓 gitlink pointer-sync
  是独立的 docs-only 提交，`f3f0433` 仍是本 fix wave implementation pointer。
