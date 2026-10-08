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
saved=jsondecode(fileread(fullfile(root,'results','vlsi2024_xsr','config.json')));
eligible=t.measurement_valid & t.four_levels_valid & t.tail_lock & isfinite(t.eye_margin) & t.eye_margin>0;
selected=t.cornerRelNyq==saved.rxPma.lane.acSelectedCorner_UI & ...
    t.ac_pre_enabled==saved.rxPma.lane.enableAcPre & t.ac_post_enabled==saved.rxPma.lane.enableAcPost;
assert(any(selected & eligible) && max(t.eye_margin(selected))>=max(t.eye_margin(eligible))-1e-12, ...
    'AC selector must maximize received eye margin, not the high-pass corner.');
for name={'measurement_valid','errors','measured_bits','first_valid_lock_ui','measurement_start_ui','continuous_tail_lock','tail_lock_losses','tail_cycle_slips','tail_level_valid'}, assert(ismember(name{1},t.Properties.VariableNames),name{1}); end
disp('VLSI2024 AC solution tests OK');
end
