# VLSI2024 XSR PHY Model Workbench

## Launch

Run from the project root in MATLAB R2024b:

```matlab
addpath('gui');
app = launchD2DWorkbench();
```

## Main areas

- **VLSI2024 XSR hierarchy**: paper-aligned x8 tree from `D2DPHY` through signed FFE/DAC, analytic IL, AC/CTLE/sampler roles, and BB-CDR/PI.
- **Paper controls**: the editable table exposes the VLSI2024 XSR rate/sample/seed, signed FFE, DAC, analytic IL, AC termination/coupling, CTLE, sampler roles, BB-CDR/PI, training toggles and post-lock wait. **Apply + Sync** publishes a valid paper configuration; **Load from Simulink** accepts paper schema only.
- Training toggles run in fixed order: startup/swing, clock/DLL/PI, sampler, CTLE, FFE; each reports executed/skipped status, evaluation count, and offline UI budget. CDR enable is an explicit debug control.
- **Paper presets**: **VLSI Typical** is the nominal paper behavioral setup. **VLSI Ideal** keeps the same paper identity/schema while disabling loss, noise, jitter, quantization and PI mismatch for debug reference. Selecting a preset repopulates the initial table; later edits remain local until explicitly applied or run.
- **Paper actions**: **Run x8 Link** performs an in-memory trained debug link and reports requested/trained/applied controls, per-lane lock timing and one global post-lock BER/eye window. Other buttons call the existing VLSI2024 baseline, static A-D, BB-CDR/PI/jitter, adaptation, or full-regression runners.
- **Paper probes/results**: select `Lane 1`–`Lane 8` or `All Lanes` for TX FFE/DAC, channel, AC pre/post, CTLE, level-shift/data/edge/spare samples, PI/CDR/lock and adaptation/tap traces. Before a run, probes remain empty and are labeled as unavailable.

Paper evidence actions may write their documented artifacts to `results/vlsi2024_xsr/`; **Run x8 Link** is in-memory debug only.

## Simulink synchronization

Open `simulink/D2D_PHY_SI_Simulink.slx` in the same MATLAB session. GUI changes reach the model after **Apply + Sync**. To edit from Simulink, change the paper `d2dCfg` struct in Model Explorer's Model Workspace, then press **Load from Simulink** in the GUI.
