function test_pam4_leveling_invalid_inputs()
%TEST_PAM4_LEVELING_INVALID_INPUTS Reject nonfinite and non-affine clusters.
root=fileparts(fileparts(mfilename('fullpath'))); addpath(genpath(fullfile(root,'src')));
[~,sparseMeta]=dspPam4Leveling([repelem([-3;-1;1;3],32);nan(8,1)]);
assert(~sparseMeta.levelsValid && isfield(sparseMeta,'fitResidual'));
[~,nonAffineMeta]=dspPam4Leveling(repelem([0;1;2;20],128));
assert(~nonAffineMeta.levelsValid && isfinite(nonAffineMeta.fitResidual));
disp('PAM4 leveling invalid-input tests OK');
end
