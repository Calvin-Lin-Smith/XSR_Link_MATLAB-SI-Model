function test_vlsi2024_ac_solution()
%TEST_VLSI2024_AC_SOLUTION The paper regression records its bounded AC choice.
root=fileparts(fileparts(mfilename('fullpath'))); addpath(genpath(fullfile(root,'src')));
cfg=phyConfig('vlsi2024_xsr');
assert(isfield(cfg.rxPma.lane,'acSelectedCorner_UI') && cfg.rxPma.lane.acSelectedCorner_UI>0);
assert(isfield(cfg.rxPma.lane,'acSelectedMode') && strcmp(cfg.rxPma.lane.acSelectedMode,'model-selected assumption'));
path=fullfile(root,'results','vlsi2024_xsr','ac_solution.csv'); assert(isfile(path));
t=readtable(path); assert(height(t)==15);
assert(isequal(sort(unique(t.cornerRelNyq))',[1e-4 3e-4 1e-3 3e-3 1e-2]));
assert(isequal(sort(unique(string(t.mode))),sort(["pre-only";"post-only";"pre+post"])));
assert(any(t.four_levels_valid & t.tail_lock & t.eye_margin>0));
disp('VLSI2024 AC solution tests OK');
end
