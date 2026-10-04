# VLSI2024 BER≈0.5 实施报告

完整报告见同目录的 [task-1-5-report.md](task-1-5-report.md)。

- 根因：paper Driver 把 logical PAM4 `[-3,-1,1,3]` 按 physical `targetSwing=1` 裁剪，RX thresholds 仍在 logical units；二电平可假锁，checker 缺少 integer UI lag，wrapped PI code 会假失锁，training objective 未要求四电平。
- 修复：唯一 Gray contract `00→-3、01→-1、11→+1、10→+3`；blind RX leveling；2-bit/UI checker alignment；four-level/tail-lock CDR；unwrapped PI audit；AC 5×3 sweep 和独立 regression gates。
- Final fresh evidence：`run_all_tests()` 9/9；`run_vlsi2024_regression('full')` 11/11；artifact validator `ok=1 detail=OK`；aggregate BER `0.0444915254`，8/8 four-level/tail-lock，checker lag 全 `+1 UI`。
- 子仓 commits：`73d4bfb`、`75dc08a`、`3d7adf1`、`669a4ed`、`9f5b2c6`；父仓 commit：`2d2207b`。
- 子仓 push：`dd629c2..9f5b2c6 main -> main`；父仓 push：`8ae55b2..2d2207b main -> main`。
- concern：`simulink/d2d_shared_config.mat` 是用户既有未提交改动，未覆盖/未提交；BER/UCB 为有限样本行为模型证据，不是硅后 sign-off。

## Final review fix wave（supersedes the earlier summary）

- P0 now uses the first-valid-lock-only global tail: x8 `first_valid_lock_ui=4103`,
  `measurement_start_ui=4119`, `continuous_tail_lock=1`, `tail_lock_losses=0`,
  `tail_cycle_slips=0`, `tail_level_valid=1`; no latest-lock/reacquisition window is used.
- Fresh final baseline: 8 lanes, 253904 measured bits/lane, BER `0.0173924003–0.0189677989`,
  UCB95 `0.0178252045–0.0194191388`, checker lag `+1 UI`; leveling scale
  `2.04557792–2.04646493`, fit residual `0.00887316–0.00940685`.
- Fresh final verification: `run_all_tests()` `9/9`; `run_vlsi2024_regression('full')`
  `11/11` (`1257.1 s`); `validate_vlsi2024_artifacts` `ok=1 detail=OK`; AC table `15/15`
  valid and model-selected `0.01/pre-only` row BER `0.0191552063`, UCB95 `0.0218466707`.
- Fix-wave child commits: `599cbd1`, `bdb09eb`, `cc87fa2`, `a797a50`, `09360b6`;
  child push `f360814..09360b6 main -> main`.
- Final fix-wave implementation pointer in the parent is `f3f0433`, pushed as
  `d3687d4..f3f0433 main -> main`; the full staged-diff/status evidence is in
  `task-1-5-report.md`. Historical parent entry `2d2207b` is superseded.
