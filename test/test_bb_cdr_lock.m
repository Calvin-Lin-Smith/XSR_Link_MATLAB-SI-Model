function test_bb_cdr_lock()
%TEST_BB_CDR_LOCK Reference-free early/late lock from a known phase offset.
root=fileparts(fileparts(mfilename('fullpath'))); addpath(genpath(fullfile(root,'src')));
sps=16; bits=mod((0:511)',2); symbols=2*bits-1; x=repelem(symbols,sps);
opts=struct('initialPhaseUI',0.12,'nCodes',64,'loopGainCodes',2,'lockWindow',16,...
    'lockToleranceUI',0.08,'mismatchBoundLSB',0,'enabled',true);
[rx,trace]=dspBbCdr(x,'NRZ',sps,opts);
assert(trace.locked && trace.lockIndex>0);
assert(abs(trace.residualPhaseUI(end))<0.2 && numel(rx)==numel(bits));
opts.enabled=false; [rxOff,traceOff]=dspBbCdr(x,'NRZ',sps,opts);
assert(~traceOff.locked && traceOff.lockIndex==0);
assert(sum(rxOff~=bits)>=sum(rx~=bits));
disp('BB-CDR lock test OK');
end
