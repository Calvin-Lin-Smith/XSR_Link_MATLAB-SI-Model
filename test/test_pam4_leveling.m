function test_pam4_leveling()
%TEST_PAM4_LEVELING Blindly recover logical Gray PAM4 units from RX samples.
root=fileparts(fileparts(mfilename('fullpath'))); addpath(genpath(fullfile(root,'src')));
levels=repelem([-3;-1;1;3],128);
raw=0.35*levels+0.17;
[logical,meta]=dspPam4Leveling(raw);
assert(meta.levelsValid);
assert(max(abs(meta.logicalCentroids-[-3 -1 1 3]))<0.15);
assert(all(ismember([-3 -1 1 3],unique(meta.decisions)')));
assert(max(abs(logical-meta.logicalSamples))<eps);
twoLevel=repelem([-1;1],256);
[~,twoMeta]=dspPam4Leveling(twoLevel);
assert(~twoMeta.levelsValid);
disp('PAM4 leveling tests OK');
end
