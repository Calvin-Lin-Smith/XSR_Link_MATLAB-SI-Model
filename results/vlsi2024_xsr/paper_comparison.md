# VLSI2024 XSR comparison

Paper facts are recorded separately from model-selected assumptions and outputs. The formal profile uses reference-free decision-directed BB-CDR/PI; TX reference bits enter only the final BER checker.

- Paper facts: 8 lanes + PLL; 9.8-113 Gb/s PAM4/NRZ; 3/optional 6-tap FFE; 7.5-bit/206-level SST DAC; 1-80 mm 2D/2.5D CoWoS; text 0.5-10 dB and Table-1 10.8 dB insertion loss at 28 GHz; NEXT/FEXT -40/-38 dB; AC leveling; CTLE 0-6 dB in 0.2 dB steps; sampler roles; 2 DLL + PI/BB-CDR; PI mismatch below +/-0.5 LSB; PRBS31; 194 fs PLL+TX integrated-jitter context; 2.5 dB COM at 1e-6; quoted BER, 0.9 pJ/b, 0.65 V, and area facts.
- Model outputs: empirical BER rows include errors, measured bits, seed, and a 95% finite-sample upper bound. They are behavioral finite-sample observations, not proof of the paper BER claims.
- Limitations: no S-parameters/reflections, MIMO crosstalk, transistor/T-coil circuits, exact disclosed FFE coefficients, true DLL/PI transfer, silicon calibration logic, or power breakdown.
