function test_regression_rejects_random_ber()
%TEST_REGRESSION_REJECTS_RANDOM_BER Reject random and percent-level baseline BER.
root=fileparts(fileparts(mfilename('fullpath'))); addpath(genpath(fullfile(root,'src')));
source=fullfile(root,'results','vlsi2024_xsr'); tmp=tempname; mkdir(tmp); cleanup=onCleanup(@()rmdir(tmp,'s')); copyfile(source,tmp,'f');
[ok,detail]=validate_vlsi2024_artifacts(tmp,'ignore_summary'); assert(ok,detail);
for badBer=[0.02 0.5]
    t=readtable(fullfile(tmp,'baseline_metrics.csv')); t.errors=round(badBer*t.measured_bits); t.empirical_BER=t.errors./t.measured_bits; t.ber_upper_95(:)=badBer+0.01; writetable(t,fullfile(tmp,'baseline_metrics.csv'));
    [ok,detail]=validate_vlsi2024_artifacts(tmp,'ignore_summary');
    assert(~ok && contains(detail,'baseline PAM4/BER gates failed'));
end
disp('Regression random-BER rejection test OK');
end
