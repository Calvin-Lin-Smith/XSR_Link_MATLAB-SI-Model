function test_fix_artifact_invariants()
%TEST_FIX_ARTIFACT_INVARIANTS Check PI, DLL2, channel IL, and histogram values.
root=fileparts(fileparts(mfilename('fullpath'))); addpath(genpath(fullfile(root,'src'))); addpath(fullfile(root,'test'));
cfg=phyConfig('vlsi2024_xsr'); [~,tr]=dspBbCdr(repelem(2*mod((0:127)',2)-1,cfg.link.sps),...
    'NRZ',cfg.link.sps,cfg.model.cdrOptions);
assert(abs(mod(tr.edgePhaseUI(1)-tr.dataPhaseUI(1),1)-0.125)<1e-12);
pi=readtable(fullfile(root,'results','vlsi2024_xsr','pi_code_trace.csv'));
for name={'pi_raw_code','pi_wrapped_code','pi_applied_code','pi_mismatch_LSB','pi_wrap_count'}
    assert(ismember(name{1},pi.Properties.VariableNames));
end
assert(any(abs(pi.pi_applied_code-pi.pi_wrapped_code)>0) || any(abs(pi.pi_mismatch_LSB)>0));
il=readtable(fullfile(root,'results','vlsi2024_xsr','channel_il.csv'));
for name={'requested_loss_dB','measured_loss_dB','measured_bits','error_dB'}
    assert(ismember(name{1},il.Properties.VariableNames));
end
assert(all(il.measured_bits>0) && all(abs(il.error_dB)<=il.tolerance_dB));
h=readtable(fullfile(root,'results','vlsi2024_xsr','residual_phase_histogram.csv'));
assert(sum(h.count)==h.sample_count(1));
disp('Fix artifact-invariant tests OK');
end
