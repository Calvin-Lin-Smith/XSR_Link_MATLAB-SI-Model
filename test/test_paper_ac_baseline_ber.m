function test_paper_ac_baseline_ber()
%TEST_PAPER_AC_BASELINE_BER Reject AC baseline wander in the default paper link.
root=fileparts(fileparts(mfilename('fullpath'))); addpath(genpath(fullfile(root,'src')));
cfg=phyConfig('vlsi2024_xsr_typical'); cfg.link.nBits=16384;
assert(cfg.rxPma.lane.enableAcPre && ~cfg.model.useReferenceAlign && ~cfg.model.useManualPhase);
p=D2DPHY('ac_baseline_regression',1); p.configure(cfg); r=p.run();
fprintf('Default paper AC: errors=%g, bits=%g, BER=%.6g\n',r.errCnt,r.nMeasured,r.aggregateBer);
assert(r.continuousTailLock && all(r.checker.alignmentValid) && all(r.nMeasured>0));
assert(isfinite(r.aggregateBer) && r.aggregateBer<1e-4, ...
    'Default paper AC link has excessive baseline-wander errors.');
disp('Paper AC baseline BER test OK');
end
