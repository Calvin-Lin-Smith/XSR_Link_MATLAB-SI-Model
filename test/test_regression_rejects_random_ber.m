function test_regression_rejects_random_ber()
%TEST_REGRESSION_REJECTS_RANDOM_BER A random-looking BER cannot pass gates.
root=fileparts(fileparts(mfilename('fullpath'))); addpath(genpath(fullfile(root,'src')));
source=fullfile(root,'results','vlsi2024_xsr'); tmp=tempname; mkdir(tmp); cleanup=onCleanup(@()rmdir(tmp,'s')); copyfile(source,tmp,'f');
t=readtable(fullfile(tmp,'baseline_metrics.csv')); t.errors=round(0.5*t.measured_bits); t.empirical_BER=t.errors./t.measured_bits; t.ber_upper_95(:)=0.51; writetable(t,fullfile(tmp,'baseline_metrics.csv'));
[ok,~]=validate_vlsi2024_artifacts(tmp,'ignore_summary'); assert(~ok);
disp('Regression random-BER rejection test OK');
end
