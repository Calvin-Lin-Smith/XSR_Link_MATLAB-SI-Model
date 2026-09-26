function test_bb_cdr_pam4_valid_lock()
%TEST_BB_CDR_PAM4_VALID_LOCK Two-level data cannot satisfy a PAM4 lock.
root=fileparts(fileparts(mfilename('fullpath'))); addpath(genpath(fullfile(root,'src')));
sps=16; symbols=repmat([-3;-1;1;3],256,1); x=repelem(symbols,sps);
opts=struct('initialPhaseUI',0.12,'nCodes',64,'loopGainCodes',2,'lockWindow',32,...
    'lockToleranceUI',0.08,'mismatchBoundLSB',0,'enabled',true,'minOccupancy',0.02);
[~,good]=dspBbCdr(x,'PAM4',sps,opts);
assert(good.everLocked && good.currentlyLocked && good.lockLossCount==0);
two=repelem(repmat([-1;1],512,1),sps); [~,bad]=dspBbCdr(two,'PAM4',sps,opts);
assert(~bad.currentlyLocked && ~bad.everLocked);
collapse=[x(1:floor(end/2));two(1:floor(end/2))]; [~,lost]=dspBbCdr(collapse,'PAM4',sps,opts);
assert(lost.everLocked && ~lost.currentlyLocked && lost.lockLossCount>0);
assert(isfield(good,'piUnwrappedCodeTrace') && isfield(good,'cycleSlipTrace'));
disp('PAM4 valid-lock tests OK');
end
