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
