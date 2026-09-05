function test_pi_quantization()
%TEST_PI_QUANTIZATION Deterministic bounded PI code-to-phase mapping.
root=fileparts(fileparts(mfilename('fullpath'))); addpath(genpath(fullfile(root,'src')));
[phase,meta]=dspPiClock([-1;0;63;64],16,struct('nCodes',64,'mismatchBoundLSB',0));
assert(meta.nCodes==64 && numel(phase)==4);
assert(meta.wrappedCode(1)==63 && meta.wrappedCode(4)==0);
assert(abs(phase(2)-0)<1e-12 && abs(phase(3)-phase(1))<1e-12);
assert(all(abs(meta.mismatchLSB)<0.5));
[~,meta2]=dspPiClock((0:63)',16,struct('nCodes',64,'mismatchBoundLSB',0.49,'mismatchSeed',7));
[~,meta3]=dspPiClock((0:63)',16,struct('nCodes',64,'mismatchBoundLSB',0.49,'mismatchSeed',7));
assert(isequal(meta2.mismatchLSB,meta3.mismatchLSB));
disp('PI quantization test OK');
end
