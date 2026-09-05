function test_sampler_thresholds()
%TEST_SAMPLER_THRESHOLDS Behavioral sampler role outputs and legacy bits.
root=fileparts(fileparts(mfilename('fullpath'))); addpath(genpath(fullfile(root,'src')));
s=Slicer('paper_slicer'); s.configure(struct('modulation','PAM4','sps',4,'phase',2,...
    'samplerRoles',struct('enabled',true,'quarterRateBranches',4,'roleCounts',struct('data',12,'edge',4,'spare',4),...
    'levelShiftCodes',struct('data',[2 0 -2],'edge',0,'spare',[3 1 -1 -3]),...
    'thresholdAssumptions',[-2 0 2])));
x=repelem([-3;-1;1;3],4); bits=s.run(x);
assert(s.samplerRoleCounts.data==12 && s.samplerRoleCounts.edge==4 && s.samplerRoleCounts.spare==4);
assert(isequal(s.levelShiftCodes.data,[2 0 -2]) && s.levelShiftCodes.edge==0);
assert(isequal(s.comparatorThresholds,[-2 0 2]));
assert(~isempty(s.dataSamples) && ~isempty(s.dataDecisions));
assert(~isempty(s.edgeSamples) && ~isempty(s.edgeDetectorOutput));
assert(~isempty(s.spareSamples) && ~isempty(s.spareMonitorOutput));
assert(~isempty(s.levelShiftedSamples) && any(any(s.levelShiftedSamples~=repmat(s.dataSamples,1,3))));
assert(isequal(bits,dspSlice(s.dataSamples,'PAM4')));
sc=s.cfg; sc.samplerRoles.levelShiftCodes.data=[2 1 -2]; s.configure(sc); s.run(x);
assert(any(s.dataDecisionInput~=s.dataSamples));
disp('Sampler threshold tests OK');
end
