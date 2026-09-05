function [phaseUI,meta] = dspPiClock(rawCode,sps,options)
%DSPPICLOCK Deterministic behavioral PI code-to-phase mapping.
if nargin<3 || isempty(options), options=struct(); end
validateattributes(rawCode,{'numeric'},{'real','finite'});
validateattributes(sps,{'numeric'},{'scalar','real','finite','positive'});
nCodes=getField(options,'nCodes',64);
bound=getField(options,'mismatchBoundLSB',0);
seed=getField(options,'mismatchSeed',0);
validateattributes(nCodes,{'numeric'},{'scalar','integer','>=',2});
validateattributes(bound,{'numeric'},{'scalar','real','finite','nonnegative','<',0.5});
wrappedCode=mod(round(rawCode),nCodes);
mismatchLSB=0.98*bound*sin(2*pi*(double(wrappedCode)+1+double(seed))/nCodes);
appliedCode=double(wrappedCode)+mismatchLSB;
phaseUI=mod(appliedCode/nCodes,1);
meta=struct('nCodes',nCodes,'rawCode',rawCode,'wrappedCode',wrappedCode,...
    'appliedCode',appliedCode,'mismatchLSB',mismatchLSB,'phaseUI',phaseUI,...
    'phaseSamples',phaseUI*sps,'wrapCount',floor(double(rawCode)/nCodes),...
    'wrapBehavior','modulo','mismatchBoundLSB',bound,'mismatchSeed',seed);
meta.appliedPhase=phaseUI; meta.mismatch=mismatchLSB; meta.wrap=wrappedCode;
end

function value=getField(s,name,default)
if isfield(s,name), value=s.(name); else, value=default; end
end
