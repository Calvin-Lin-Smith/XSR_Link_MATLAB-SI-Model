function test_fix2_validator_contracts()
%TEST_FIX2_VALIDATOR_CONTRACTS Every formal artifact contract must reject tampering.
root=fileparts(fileparts(mfilename('fullpath'))); addpath(genpath(fullfile(root,'src'))); addpath(fullfile(root,'test'));
resultRoot=fullfile(root,'results','vlsi2024_xsr'); [ok,~]=validate_vlsi2024_artifacts(resultRoot); assert(ok);
tmp=tempname; mkdir(tmp); cleanup=onCleanup(@()rmdir(tmp,'s')); copyfile(resultRoot,tmp,'f');
delete(fullfile(tmp,'channel_response.csv')); [ok,~]=validate_vlsi2024_artifacts(tmp); assert(~ok,'missing channel response accepted');
copyfile(resultRoot,tmp,'f'); t=readtable(fullfile(tmp,'baseline_metrics.csv')); t.errors(1)=t.measured_bits(1)+1; writetable(t,fullfile(tmp,'baseline_metrics.csv'));
[ok,~]=validate_vlsi2024_artifacts(tmp); assert(~ok,'errors greater than measured bits accepted');
copyfile(resultRoot,tmp,'f'); t=readtable(fullfile(tmp,'channel_response.csv')); t.measured_loss_dB(1)=t.requested_loss_dB(1)+1; writetable(t,fullfile(tmp,'channel_response.csv'));
[ok,~]=validate_vlsi2024_artifacts(tmp); assert(~ok,'IL out-of-tolerance row accepted');
copyfile(resultRoot,tmp,'f'); t=readtable(fullfile(tmp,'legacy_t1_t9','T3_bathtub.csv')); t.phaseBer=[]; writetable(t,fullfile(tmp,'legacy_t1_t9','T3_bathtub.csv'));
[ok,~]=validate_vlsi2024_artifacts(tmp); assert(~ok,'legacy T3 schema tamper accepted');
disp('Fix Round 2 validator-contract tests OK');
end
