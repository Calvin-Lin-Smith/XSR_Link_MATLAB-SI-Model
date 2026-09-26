function test_adaptation_requires_four_levels()
%TEST_ADAPTATION_REQUIRES_FOUR_LEVELS Training trace rejects a two-level score.
root=fileparts(fileparts(mfilename('fullpath'))); addpath(genpath(fullfile(root,'src'))); addpath(fullfile(root,'test'));
[o,~]=run_vlsi2024_xsr('adaptation',1024,'enablePaperAdaptation',true);
t=o.ctleTrace; assert(ismember('four_level_valid',t.Properties.VariableNames));
assert(ismember('objective_valid',t.Properties.VariableNames));
assert(all(~(t.objective_valid & ~t.four_level_valid)));
disp('Four-level adaptation objective tests OK');
end
