function [bits,trace] = dspBbCdr(x,modulation,sps,options)
%DSPBBCDR Reference-free decision-directed early/late bang-bang CDR.
% The phase detector sees only the received samples and prior symbol decisions.
if nargin<4 || isempty(options), options=struct(); end
x=x(:); modulation=char(modulation);
validateattributes(sps,{'numeric'},{'scalar','integer','positive'});
nCodes=getField(options,'nCodes',64); enabled=logical(getField(options,'enabled',true));
initialPhaseUI=getField(options,'initialPhaseUI',0.5); targetPhaseUI=getField(options,'targetPhaseUI',0.5); loopGain=getField(options,'loopGainCodes',1);
lockWindow=getField(options,'lockWindow',32); lockTol=getField(options,'lockToleranceUI',0.08);
maxStep=getField(options,'maxStepCodes',max(1,ceil(abs(loopGain))));
updateCadence=getField(options,'updateCadence',1); bandwidthProxy=getField(options,'loopBandwidthProxy',loopGain/nCodes);
piOptions=struct('nCodes',nCodes,'mismatchBoundLSB',getField(options,'mismatchBoundLSB',0),...
    'mismatchSeed',getField(options,'mismatchSeed',0));
validateattributes(initialPhaseUI,{'numeric'},{'scalar','real','finite'});
validateattributes(targetPhaseUI,{'numeric'},{'scalar','real','finite'});
validateattributes(loopGain,{'numeric'},{'scalar','real','finite','nonnegative'});
validateattributes(lockWindow,{'numeric'},{'scalar','integer','positive'});
validateattributes(lockTol,{'numeric'},{'scalar','real','finite','positive'});
validateattributes(maxStep,{'numeric'},{'scalar','real','finite','positive'});
validateattributes(updateCadence,{'numeric'},{'scalar','integer','positive'});
rawCode=mod(initialPhaseUI*nCodes,nCodes); nSym=floor((numel(x)-1)/sps)+1;
jitterUI=getField(options,'jitterUI',zeros(nSym,1)); jitterUI=jitterUI(:);
if isscalar(jitterUI), jitterUI=repmat(jitterUI,nSym,1); end
if numel(jitterUI)<nSym, jitterUI(end+1:nSym,1)=0; end
bps=1+strcmpi(modulation,'PAM4'); bits=zeros(nSym*bps,1); samples=nan(nSym,1);
earlySamples=samples; lateSamples=samples; decisionTrace=nan(nSym,1); errorTrace=zeros(nSym,1);
piCodeTrace=zeros(nSym,1); appliedPhaseUI=zeros(nSym,1); dataPhaseUI=appliedPhaseUI;
edgePhaseUI=appliedPhaseUI; residualPhaseUI=appliedPhaseUI; lockTrace=false(nSym,1);
stable=0; lockIndex=0; prev=NaN;
for k=1:nSym
    [phase,piMeta]=dspPiClock(rawCode,sps,piOptions); %#ok<ASGLU>
    piCodeTrace(k)=piMeta.wrappedCode; appliedPhaseUI(k)=phase; dataPhaseUI(k)=phase;
    edgePhaseUI(k)=mod(phase+0.25,1); residualPhaseUI(k)=phase+jitterUI(k)-targetPhaseUI;
    effectivePhase=phase+jitterUI(k); idx=round((k-1)*sps+effectivePhase*sps)+1; eidx=idx-round(sps/4); lidx=idx+round(sps/4);
    if idx>=1 && idx<=numel(x)
        samples(k)=x(idx); decisionTrace(k)=decisionValue(samples(k),modulation);
        bits((k-1)*bps+(1:bps))=decisionBits(decisionTrace(k),modulation);
    end
    if eidx>=1 && lidx<=numel(x)
        earlySamples(k)=x(eidx); lateSamples(k)=x(lidx);
        if ~isnan(decisionTrace(k))
            ev=decisionValue(earlySamples(k),modulation); lv=decisionValue(lateSamples(k),modulation);
            e=sign(abs(ev-decisionTrace(k))-abs(lv-decisionTrace(k)));
            if e==0 && ~isnan(prev) && decisionTrace(k)~=prev, e=sign(targetPhaseUI-phase); end
            errorTrace(k)=e;
            if enabled && mod(k-1,updateCadence)==0 && ~isnan(prev) && decisionTrace(k)~=prev
                rawCode=mod(rawCode+max(-maxStep,min(maxStep,loopGain*e)),nCodes);
            end
        end
    end
    if enabled && k>=lockWindow
        recent=(k-lockWindow+1):k;
        if all(abs(residualPhaseUI(recent))<=lockTol) && all(abs(errorTrace(recent))<=1)
            stable=stable+1;
            if lockIndex==0, lockIndex=k; end
        else
            stable=0;
        end
    end
    lockTrace(k)=enabled && stable>0; prev=decisionTrace(k);
end
trace=struct('enabled',enabled,'nCodes',nCodes,'initialPhaseUI',initialPhaseUI,'targetPhaseUI',targetPhaseUI,...
    'loopGainCodes',loopGain,'loopBandwidthProxy',bandwidthProxy,'updateCadence',updateCadence,...
    'lockWindow',lockWindow,'lockToleranceUI',lockTol,...
    'lockIndex',lockIndex,'locked',lockIndex>0,'cdr_lock_trace',lockTrace,...
    'piCodeTrace',piCodeTrace,'rawCodeTrace',piCodeTrace,'errorTrace',errorTrace,...
    'earlyLateTrace',errorTrace,'dataPhaseUI',dataPhaseUI,'edgePhaseUI',edgePhaseUI,...
    'appliedPhaseUI',appliedPhaseUI,'residualPhaseUI',residualPhaseUI,...
    'samples',samples,'earlySamples',earlySamples,'lateSamples',lateSamples,...
    'decisionTrace',decisionTrace,'architecture',struct('dll1PhaseCount',8,...
        'dll2DataDegrees',[0 90 180 270],'dll2EdgeDegrees',[45 135 225 315],...
        'piFollows','DLL1','trainingMode','decision_directed'),...
    'jitterUI',jitterUI,'piOptions',piOptions);
end

function value=getField(s,name,default)
if isfield(s,name), value=s.(name); else, value=default; end
end

function v=decisionValue(x,modulation)
switch upper(modulation)
    case 'NRZ', v=2*double(x>=0)-1;
    case 'PAM4', v=-3; if x>=-2, v=-1; end; if x>=0, v=1; end; if x>=2, v=3; end
    otherwise, error('dspBbCdr:Modulation','Unsupported modulation: %s',modulation);
end
end

function b=decisionBits(v,modulation)
switch upper(modulation)
    case 'NRZ', b=double(v>0);
    case 'PAM4'
        lut=[0 0;0 1;1 0;1 1]; idx=round((v+3)/2)+1; b=reshape(lut(idx,:).',[],1);
end
end
