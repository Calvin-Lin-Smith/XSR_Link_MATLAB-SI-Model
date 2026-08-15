# D2D PHY Model Workbench

## Launch

Run from the project root in MATLAB R2024b:

```matlab
addpath('gui');
app = launchD2DWorkbench();
```

## Main areas

- **D2D IP Hierarchy**: complete x8 databook-aligned tree from `D2DPHY` through Raw PCS, TX/RX PMA, support, lanes, AFE, CTLE, slicer, serializer, driver, channels, and PLL/CDR.
- **Model Parameters**: editable `phyConfig` fields. The GUI starts with the typical working non-ideal profile; press **Apply** before a test, or use **Reset Ideal** for the zero-impairment baseline.
- **Test Parameters**: editable vectors for channel loss, CTLE boost, RJ, CDR bandwidth, and FFE pre/post taps.
- **Test Actions**: x8 link, loss/CTLE/RJ/CDR sweeps, FFE+CTLE scan, behavior suite, and standard T1-T9 regression.
- **White-box Probe and Results**: eye diagrams, internal waveforms, PLL phase traces, BER tables, and test summaries.

GUI-generated sweep CSV files and the standard regression artifacts are written to `results/`.
