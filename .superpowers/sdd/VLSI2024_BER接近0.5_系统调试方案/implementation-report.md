# VLSI2024 BER≈0.5 实施报告

完整报告见同目录的 [task-1-5-report.md](task-1-5-report.md)。

- 根因：paper Driver 把 logical PAM4 `[-3,-1,1,3]` 按 physical `targetSwing=1` 裁剪，RX thresholds 仍在 logical units；二电平可假锁，checker 缺少 integer UI lag，wrapped PI code 会假失锁，training objective 未要求四电平。
- 修复：唯一 Gray contract `00→-3、01→-1、11→+1、10→+3`；blind RX leveling；2-bit/UI checker alignment；four-level/tail-lock CDR；unwrapped PI audit；AC 5×3 sweep 和独立 regression gates。
- Final fresh evidence：`run_all_tests()` 9/9；`run_vlsi2024_regression('full')` 11/11；artifact validator `ok=1 detail=OK`；aggregate BER `0.0444915254`，8/8 four-level/tail-lock，checker lag 全 `+1 UI`。
- 子仓 commits：`73d4bfb`、`75dc08a`、`3d7adf1`、`669a4ed`、`9f5b2c6`；父仓 commit：`2d2207b`。
- 子仓 push：`dd629c2..9f5b2c6 main -> main`；父仓 push：`8ae55b2..2d2207b main -> main`。
- concern：`simulink/d2d_shared_config.mat` 是用户既有未提交改动，未覆盖/未提交；BER/UCB 为有限样本行为模型证据，不是硅后 sign-off。
