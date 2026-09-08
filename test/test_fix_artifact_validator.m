function test_fix_artifact_validator()
%TEST_FIX_ARTIFACT_VALIDATOR Tampered/missing artifacts must fail concrete checks.
root=fileparts(fileparts(mfilename('fullpath'))); addpath(genpath(fullfile(root,'src'))); addpath(fullfile(root,'test'));
resultRoot=fullfile(root,'results','vlsi2024_xsr'); [ok,~]=validate_vlsi2024_artifacts(resultRoot); assert(ok);
tmp=tempname; mkdir(tmp); cleanup=onCleanup(@()rmdir(tmp,'s')); copyfile(resultRoot,tmp,'f');
t=readtable(fullfile(tmp,'baseline_metrics.csv')); t.ber_upper_95=[]; writetable(t,fullfile(tmp,'baseline_metrics.csv'));
[ok,~]=validate_vlsi2024_artifacts(tmp); assert(~ok,'missing BER bound was accepted');
copyfile(resultRoot,tmp,'f'); delete(fullfile(tmp,'cdr_lock_trace.csv')); [ok,~]=validate_vlsi2024_artifacts(tmp); assert(~ok,'missing CDR trace was accepted');
copyfile(resultRoot,tmp,'f'); t=readtable(fullfile(tmp,'cdr_lock_trace.csv')); t.locked(:)=false; writetable(t,fullfile(tmp,'cdr_lock_trace.csv'));
[ok,~]=validate_vlsi2024_artifacts(tmp); assert(~ok,'unlocked CDR trace was accepted');
disp('Fix artifact-validator tests OK');
end
