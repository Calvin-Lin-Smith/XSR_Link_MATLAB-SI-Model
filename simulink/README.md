# Simulink D2D PHY implementation

This is a separate block-diagram implementation path. It remains independent from the GUI layout, while both implementations share the same `d2dCfg` parameter structure.

## Generate the visual model

From the project root in MATLAB:

```matlab
addpath('simulink');
mdl = buildD2DSimulinkModel();
```

The generator creates and opens:

```text
simulink/D2D_PHY_SI_Simulink.slx
```

The top-level diagram is:

```text
TX Bits -> Raw PCS -> TX PMA x8 -> Die-to-Die Channel x8 -> RX PMA x8 -> BER / Results -> RX Bits
```

Each subsystem can be opened to inspect the TX/RX lanes, eight channel blocks, CTLE, sampler, slicer, serializer, driver, and white-box probe tags. The generated channel and lane blocks reference the existing DSP functions from `src/dsp` through Interpreted MATLAB Function blocks, so the Simulink path uses the same algorithms rather than a second copied implementation.

## Shared parameters with the GUI

Both implementations use the `d2dCfg` structure. In the GUI:

- **Apply + Sync** writes a validated VLSI2024 XSR paper table to the MATLAB base workspace, the loaded model's Model Workspace, and `simulink/d2d_shared_config.mat`.
- **VLSI Typical** and **VLSI Ideal** are the two paper presets; selecting one only repopulates GUI initial values.
- **Load from Simulink** reads and validates paper-schema `d2dCfg` from the loaded model and refreshes the GUI table.

Simulink blocks read fields such as `d2dCfg.link.sps`, TX FFE taps, channel loss/poles, termination mode/gain, CTLE boost/zero, and modulation directly. To change parameters from Simulink, edit paper `d2dCfg` in Model Explorer under the model workspace and then use **Load from Simulink** in the GUI.

Options:

```matlab
buildD2DSimulinkModel('Open',false);
buildD2DSimulinkModel('ModelName','MyD2DModel');
```

For an isolated release-candidate smoke build, pass the same paper config and a temporary model name/path:

```matlab
cfg = phyConfig('vlsi2024_xsr');
mdl = buildD2DSimulinkModel('ModelName','stage_h_tmp', ...
    'Config',cfg,'Open',false,'Save',true,'Overwrite',false);
```

The builder preserves the existing default model name, but only overwrites an existing `.slx` when `Overwrite` is true. The generated TX path uses vector FFE/DAC fields when present; the channel uses the calibrated analytic IL fields; RX exposes AC pre/post, CTLE, sampler-role and a stateful BB-CDR/PI/adaptation boundary. MATLAB remains the algorithm source of truth.

Requirements: MATLAB Simulink license. The generated `.slx` is an additional artifact; it does not replace `D2DPHY`, `D2DWorkbench`, or the T1-T9 regression. All BER values remain finite-sample behavioral measurements with the profile's recorded assumptions and do not constitute silicon or paper BER sign-off.
