# VLSI2024 XSR behavioral assumptions

- The formal paper profile uses `model.useReferenceAlign=false` and a decision-directed BB-CDR/PI path (reference-free in Task/Stage E). TX reference bits are passed only to the final BER checker.
- Static A-D checkpoint rows retain the legacy oracle/reference-bit alignment for compatibility; they are not the formal paper BB-CDR result.
- 112.5 Gb/s is the TX-eye baseline context, while the paper BER plot/text uses 112 Gb/s and headline/Table uses 113 Gb/s.
- The profile uses 2^18 bits by default; bounded static/adaptation/jitter sweeps may use fewer bits and record that sample count in each row.
- Finite simulation cannot prove the paper's <1e-14/<1e-12 BER; it reports empirical BER and a 95% finite-sample upper bound.
- PI uses 64 behavioral codes, DLL1/ DLL2 phase roles are metadata, and PI mismatch is deterministic and bounded below +/-0.5 LSB.
- BB-CDR lock means the residual phase stays within the configured tolerance for the configured consecutive lock window; loop bandwidth/update cadence are behavioral proxies.
- The approximately 194 fs value is retained as PLL+TX integrated jitter with measurement/filter context, not TX-only jitter.
- Calibration optimizes observable eye/decision margin, not finite BER.
- No real S-parameters/reflections, MIMO crosstalk, transistor/T-coil circuits, silicon calibration logic, or power breakdown are modeled.

- Static A-D checkpoint retains legacy oracle/reference-bit alignment; it is not the paper BB-CDR result.
