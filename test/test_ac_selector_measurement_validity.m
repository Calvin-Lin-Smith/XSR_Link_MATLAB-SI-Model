function test_ac_selector_measurement_validity()
%TEST_AC_SELECTOR_MEASUREMENT_VALIDITY Invalid AC rows cannot be hidden/selected.
root=fileparts(fileparts(mfilename('fullpath'))); addpath(genpath(fullfile(root,'src')));
source=lower(fileread(fullfile(root,'test','run_vlsi2024_regression.m')));
assert(contains(source,'eligible=t.measurement_valid&'),'AC selector does not gate eligibility on measurement_valid.');
tmp=tempname; mkdir(tmp); cleanup=onCleanup(@()rmdir(tmp,'s')); %#ok<NASGU>
copyfile(fullfile(root,'results','vlsi2024_xsr'),tmp,'f'); path=fullfile(tmp,'ac_solution.csv'); t=readtable(path); t.measurement_valid(1)=false; writetable(t,path);
[ok,~]=validate_vlsi2024_artifacts(tmp,'ignore_summary'); assert(~ok,'Hidden invalid AC row was accepted.');
disp('AC selector measurement-validity tests OK');
end
