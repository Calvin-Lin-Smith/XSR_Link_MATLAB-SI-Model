function test_fix_cdr_reference_free()
%TEST_FIX_CDR_REFERENCE_FREE CDR cannot use an externally supplied target phase.
root=fileparts(fileparts(mfilename('fullpath'))); addpath(genpath(fullfile(root,'src')));
sps=16; bits=mod((0:1023)',2); x=dspChannel(repelem(2*bits-1,sps),sps,8,3);
base=struct('initialPhaseUI',0.12,'nCodes',64,'loopGainCodes',2,'lockWindow',32,...
    'lockToleranceUI',0.08,'enabled',true,'maxStepCodes',2);
a=base; a.targetPhaseUI=0.2; b=base; b.targetPhaseUI=0.8;
[ra,ta]=dspBbCdr(x,'NRZ',sps,a); [rb,tb]=dspBbCdr(x,'NRZ',sps,b);
assert(isequal(ra,rb) && isequal(ta.piCodeTrace,tb.piCodeTrace) && isequal(ta.cdr_lock_trace,tb.cdr_lock_trace));
for initial=[0.12 0.32 0.68 0.88]
    o=base; o.initialPhaseUI=initial; [~,t]=dspBbCdr(x,'NRZ',sps,o); assert(t.locked,'initial phase did not converge');
end
flat=ones(512*sps,1); [~,tf]=dspBbCdr(flat,'NRZ',sps,base); assert(~tf.locked,'no-transition waveform falsely locked');
o=base; o.initialPhaseUI=0.12; o.enabled=true; [~,tGood]=dspBbCdr(x,'NRZ',sps,o);
o.enabled=false; [~,tOff]=dspBbCdr(x,'NRZ',sps,o);
assert(tGood.locked && ~tOff.locked && sum(tGood.cdr_lock_trace)>0,...
    'disabled CDR has no observable acquisition degradation');
disp('Fix CDR reference-free tests OK');
end
