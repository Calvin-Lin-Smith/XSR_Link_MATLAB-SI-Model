# D2D PHY Model Workbench

## Launch

Run from the project root in MATLAB R2024b:

```matlab
addpath('gui');
app = launchD2DWorkbench();
```

## Main areas

- **D2D IP Hierarchy**: complete x8 databook-aligned tree from `D2DPHY` through Raw PCS, TX/RX PMA, support, lanes, AFE, CTLE, slicer, serializer, driver, channels, and PLL/CDR.
- **Model Parameters**: editable `phyConfig` fields. **Apply + Sync** publishes the table to the shared `d2dCfg` variable and any loaded Simulink model. **Load from SLX** pulls Model Workspace changes back into the GUI. **Reset Typical** and **Reset Ideal** also synchronize immediately.
- **Paper profile**: **Load / Preview** selects `ideal`, `typical`, or `vlsi2024_xsr` without touching the shared snapshot; use **Apply + Sync** to publish it. Paper Baseline, Paper Full Regression, and Paper Adaptation call the existing paper runners.
- **Test Parameters**: editable vectors for channel loss, CTLE boost, RJ, CDR bandwidth, and FFE pre/post taps.
- **Test Actions**: x8 link, loss/CTLE/RJ/CDR sweeps, FFE+CTLE scan, behavior suite, and standard T1-T9 regression.
- **White-box Probe and Results**: select a node type plus `Lane 1`–`Lane 8` or `All Lanes`; view single-lane or overlaid waveforms. After a link run, Metrics shows aggregate plus per-lane BER, errors, measured bits, phase, delay, CTLE gain, eye height, and the worst lane.
- **Paper probes**: AC pre/post, level-shifted/data/edge/sampler-role outputs, PI code, CDR error/lock, and saved adaptation/FFE traces. Before a run, an empty probe is shown as not yet available.

GUI-generated sweep CSV files and the standard regression artifacts are written to `results/`.

## Simulink synchronization

Open `simulink/D2D_PHY_SI_Simulink.slx` in the same MATLAB session. GUI changes reach the model after **Apply + Sync**. To edit from Simulink, change the `d2dCfg` struct in Model Explorer's Model Workspace, then press **Load from SLX** in the GUI.
