function test_validator_ac_solution_values()
%TEST_VALIDATOR_AC_SOLUTION_VALUES AC evidence must retain consistent BER/UCB/fit values.
root=fileparts(fileparts(mfilename('fullpath'))); addpath(genpath(fullfile(root,'src')));
tmp=tempname; mkdir(tmp); cleanup=onCleanup(@()rmdir(tmp,'s')); copyfile(fullfile(root,'results','vlsi2024_xsr'),tmp,'f');
t=readtable(fullfile(tmp,'ac_solution.csv')); t.aggregate_BER(1)=0.9; t.ber_upper_95(1)=0.9; writetable(t,fullfile(tmp,'ac_solution.csv'));
[ok,~]=validate_vlsi2024_artifacts(tmp,'ignore_summary'); assert(~ok,'tampered AC BER/UCB accepted');
disp('AC validator value tests OK');
end
