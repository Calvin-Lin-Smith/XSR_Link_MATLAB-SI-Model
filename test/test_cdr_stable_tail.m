function test_cdr_stable_tail()
%TEST_CDR_STABLE_TAIL The first valid PAM4 lock must remain stable to the tail.
root=fileparts(fileparts(mfilename('fullpath'))); addpath(genpath(fullfile(root,'src')));
cfg=phyConfig('vlsi2024_xsr_typical'); cfg.link.nBits=2048; cfg.phy.nLane=1;
p=D2DPHY('stable_tail',1); p.configure(cfg); r=p.run(); %#ok<ASGLU>
t=p.rxPma.lane(1).cdrTrace;
assert(t.firstValidLockIndex>0 && t.currentlyLocked && t.tailLockLossCount==0 && t.cycleSlipCount==0);
assert(all(t.currentlyLockedTrace(t.firstValidLockIndex:end)));
assert(r.checker.alignmentValid && r.checker.measurementStartUI>=t.firstValidLockIndex+cfg.model.debugStages.postLockWaitUI);
disp('CDR stable-tail tests OK');
end
