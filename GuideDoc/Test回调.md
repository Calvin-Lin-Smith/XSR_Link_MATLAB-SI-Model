# Paper GUI callbacks

`D2DWorkbench.execute()` 统一更新 status、捕获异常并写入 log。GUI callback 只调用已有 paper runner/core model，不复制 DSP 算法。

| GUI action | Callback | Backend | Output |
|---|---|---|---|
| Run x8 Link | `runLink()` | `run_vlsi2024_xsr('debug_link',...)` | in-memory requested/trained/applied cfg, stage accounting, lock trace, post-lock BER/eye window |
| VLSI2024 Baseline | `runPaperBaseline()` | `run_vlsi2024_xsr('baseline',...)` | baseline paper artifacts |
| Static A-D / FFE / IL / AC-CTLE | `runPaperStatic()` | `run_vlsi2024_xsr('static_checkpoint',...)` | static checkpoint artifacts |
| BB-CDR / PI / Jitter Evidence | `runPaperEvidence()` | bounded `run_vlsi2024_regression('full',...)` | bounded evidence artifacts |
| Calibration / Adaptation | `runPaperAdaptation()` | `run_vlsi2024_xsr('adaptation',...)` | adaptation traces |
| Full VLSI2024 Regression | `runPaperRegression()` | `run_vlsi2024_regression('full',...)` | formal paper regression artifacts |

## Trained debug sequence

`Run x8 Link` consumes the edited VLSI2024 paper configuration and executes the enabled stages in fixed order: RESET, startup/swing, clock/DLL/PI, sampler, CTLE, FFE, final x8 CDR acquisition, lock/post-lock wait, and MISSION_TRACK. Disabled stages retain requested manual values and report `skipped_manual_value`; enabled stages report evaluation count and configured/consumed UI budget.

The final pass uses one global latest-lock window. `measurementStartSample` is one-based and equals `measurementStartUI*sps+1`; eye, eye-height, sampled-level, ISI/margin and BER data all begin there. Full acquisition traces remain available for diagnosis, but pre-lock samples are excluded from performance results.

Invalid edits are rejected at the existing table parser boundary. The last valid requested configuration remains intact. Opening/closing the GUI and running the in-memory debug action do not write the tracked Simulink snapshot or formal paper result set.
