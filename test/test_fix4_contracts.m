function test_fix4_contracts()
%TEST_FIX4_CONTRACTS Round 4 contracts reject concrete artifact tampering.
root=fileparts(fileparts(mfilename('fullpath'))); addpath(genpath(fullfile(root,'src'))); addpath(fullfile(root,'test'));
resultRoot=fullfile(root,'results','vlsi2024_xsr'); [ok,~]=validate_vlsi2024_artifacts(resultRoot); assert(ok);
tmp=tempname; mkdir(tmp); cleanup=onCleanup(@()rmdir(tmp,'s')); copyfile(resultRoot,tmp,'f');

delete(fullfile(tmp,'legacy_t1_t9','T3_bathtub.png'));
[ok,~]=validate_vlsi2024_artifacts(tmp); assert(~ok,'missing T3 PNG accepted');

copyfile(resultRoot,tmp,'f');
s=load(fullfile(tmp,'baseline_probes.mat')); s.probes=rmfield(s.probes,'txPad');
save(fullfile(tmp,'baseline_probes.mat'),'-struct','s');
[ok,~]=validate_vlsi2024_artifacts(tmp); assert(~ok,'baseline MAT missing core probe accepted');

copyfile(resultRoot,tmp,'f');
t=readtable(fullfile(tmp,'baseline_metrics.csv'));
t.sample_bits=repmat(262144,height(t),1); t.line_rate_Gbps=repmat(112.5,height(t),1);
writetable(t,fullfile(tmp,'baseline_metrics.csv'));
t.sample_bits=[]; writetable(t,fullfile(tmp,'baseline_metrics.csv'));
[ok,~]=validate_vlsi2024_artifacts(tmp); assert(~ok,'missing BER mandatory context accepted');

copyfile(resultRoot,tmp,'f');
t=readtable(fullfile(tmp,'baseline_metrics.csv')); t.empirical_BER(1)=t.empirical_BER(1)+1e-3;
writetable(t,fullfile(tmp,'baseline_metrics.csv')); [ok,~]=validate_vlsi2024_artifacts(tmp); assert(~ok,'tampered BER ratio accepted');

copyfile(resultRoot,tmp,'f');
t=readtable(fullfile(tmp,'baseline_metrics.csv')); t.ber_upper_95(1)=t.empirical_BER(1)-1e-3;
writetable(t,fullfile(tmp,'baseline_metrics.csv')); [ok,~]=validate_vlsi2024_artifacts(tmp); assert(~ok,'tampered BER upper bound accepted');

copyfile(resultRoot,tmp,'f');
t=readtable(fullfile(tmp,'channel_il.csv')); t.error_dB=t.measured_loss_dB-t.requested_loss_dB+0.01;
writetable(t,fullfile(tmp,'channel_il.csv')); [ok,~]=validate_vlsi2024_artifacts(tmp); assert(~ok,'tampered channel IL formula accepted');

copyfile(resultRoot,tmp,'f');
t=readtable(fullfile(tmp,'adaptation_state_trace.csv')); t.ctle_target_dB=t.ctle_requested_dB; t.ctle_residual_dB(:)=0.1;
writetable(t,fullfile(tmp,'adaptation_state_trace.csv')); [ok,~]=validate_vlsi2024_artifacts(tmp); assert(~ok,'tampered CTLE residual accepted');

copyfile(resultRoot,tmp,'f');
t=readtable(fullfile(tmp,'adaptation_state_trace.csv')); t.ctle_target_dB=t.ctle_requested_dB;
t.ctle_applied_dB(4)=t.ctle_applied_dB(4)+0.1; t.ctle_residual_dB(4)=abs(t.ctle_applied_dB(4)-t.ctle_target_dB(4));
writetable(t,fullfile(tmp,'adaptation_state_trace.csv')); [ok,~]=validate_vlsi2024_artifacts(tmp); assert(~ok,'tampered CTLE applied/target relation accepted');

disp('Fix Round 4 contract tests RED/GREEN target OK');
end
