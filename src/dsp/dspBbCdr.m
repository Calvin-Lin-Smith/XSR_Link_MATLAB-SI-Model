function [bits,trace] = dspBbCdr(x,modulation,sps,options)
%DSPBBCDR Reference-free decision-directed early/late bang-bang CDR.
% The phase detector sees only the received samples and prior symbol decisions.
if nargin<4 || isempty(options), options=struct(); end
x=x(:); modulation=char(modulation);
validateattributes(sps,{'numeric'},{'scalar','integer','positive'});
nCodes=getField(options,'nCodes',64); enabled=logical(getField(options,'enabled',true));
initialPhaseUI=getField(options,'initialPhaseUI',0.5); loopGain=getField(options,'loopGainCodes',1);
lockWindow=getField(options,'lockWindow',32); lockTol=getField(options,'lockToleranceUI',0.08);
maxStep=getField(options,'maxStepCodes',max(1,ceil(abs(loopGain))));
updateCadence=getField(options,'updateCadence',1); bandwidthProxy=getField(options,'loopBandwidthProxy',loopGain/nCodes);
minTransitions=getField(options,'minTransitions',max(4,ceil(lockWindow/8))); maxCodeSpan=getField(options,'maxCodeSpanCodes',8);
piOptions=struct('nCodes',nCodes,'mismatchBoundLSB',getField(options,'mismatchBoundLSB',0),...
    'mismatchSeed',getField(options,'mismatchSeed',0));
validateattributes(initialPhaseUI,{'numeric'},{'scalar','real','finite'});
validateattributes(loopGain,{'numeric'},{'scalar','real','finite','nonnegative'});
validateattributes(lockWindow,{'numeric'},{'scalar','integer','positive'});
validateattributes(lockTol,{'numeric'},{'scalar','real','finite','positive'});
validateattributes(maxStep,{'numeric'},{'scalar','real','finite','positive'});
validateattributes(updateCadence,{'numeric'},{'scalar','integer','positive'});
validateattributes(minTransitions,{'numeric'},{'scalar','integer','positive'});
validateattributes(maxCodeSpan,{'numeric'},{'scalar','real','finite','nonnegative'});
rawCode=initialPhaseUI*nCodes; nSym=floor((numel(x)-1)/sps)+1;
jitterUI=getField(options,'jitterUI',zeros(nSym,1)); jitterUI=jitterUI(:);
if isscalar(jitterUI), jitterUI=repmat(jitterUI,nSym,1); end
if numel(jitterUI)<nSym, jitterUI(end+1:nSym,1)=0; end
bps=1+strcmpi(modulation,'PAM4'); bits=zeros(nSym*bps,1); samples=nan(nSym,1);
earlySamples=samples; lateSamples=samples; decisionTrace=nan(nSym,1); errorTrace=zeros(nSym,1);
piCodeTrace=zeros(nSym,1); appliedPhaseUI=zeros(nSym,1); dataPhaseUI=appliedPhaseUI;
edgePhaseUI=appliedPhaseUI; residualPhaseUI=zeros(nSym,1); lockTrace=false(nSym,1);
earlyLateMetric=zeros(nSym,1); transitionTrace=false(nSym,1); transitionPhaseUI=nan(nSym,1);
piRawCodeTrace=zeros(nSym,1); piWrappedCodeTrace=zeros(nSym,1); piAppliedCodeTrace=zeros(nSym,1);
piMismatchTrace=zeros(nSym,1); piWrapCountTrace=zeros(nSym,1);
stable=0; lockIndex=0; prev=NaN; transitionHistory=[];
for k=1:nSym
    [phase,piMeta]=dspPiClock(rawCode,sps,piOptions);
    piRawCodeTrace(k)=piMeta.rawCode; piWrappedCodeTrace(k)=piMeta.wrappedCode;
    piAppliedCodeTrace(k)=piMeta.appliedCode; piMismatchTrace(k)=piMeta.mismatchLSB; piWrapCountTrace(k)=piMeta.wrapCount;
    piCodeTrace(k)=piMeta.wrappedCode; appliedPhaseUI(k)=phase; dataPhaseUI(k)=phase;
    edgePhaseUI(k)=mod(phase+0.125,1);
    effectivePhase=phase+jitterUI(k); idx=round((k-1)*sps+effectivePhase*sps)+1; eidx=idx-round(sps/4); lidx=idx+round(sps/4);
    if idx>=1 && idx<=numel(x)
        samples(k)=x(idx); decisionTrace(k)=decisionValue(samples(k),modulation);
        bits((k-1)*bps+(1:bps))=decisionBits(decisionTrace(k),modulation);
    end
    if eidx>=1 && lidx<=numel(x)
        earlySamples(k)=x(eidx); lateSamples(k)=x(lidx);
        if ~isnan(decisionTrace(k))
            ev=decisionValue(earlySamples(k),modulation); lv=decisionValue(lateSamples(k),modulation);
            earlyLateMetric(k)=abs(ev-decisionTrace(k))-abs(lv-decisionTrace(k));
            e=sign(earlyLateMetric(k));
            errorTrace(k)=e;
            if ~isnan(prev) && decisionTrace(k)~=prev
                transitionTrace(k)=true; transitionPhaseUI(k)=phase;
                if isempty(transitionHistory), residualPhaseUI(k)=0;
                else, residualPhaseUI(k)=wrapPhase(phase-median(transitionHistory(max(1,end-7):end))); end
                transitionHistory=[transitionHistory phase]; if numel(transitionHistory)>64, transitionHistory=transitionHistory(end-63:end); end %#ok<AGROW>
            end
            if enabled && mod(k-1,updateCadence)==0 && transitionTrace(k) && e~=0
                rawCode=rawCode+max(-maxStep,min(maxStep,loopGain*e));
            end
        end
    end
    if enabled && k>=lockWindow
        recent=(k-lockWindow+1):k;
        transitionRecent=transitionTrace(recent); stableRecent=recent(floor(numel(recent)/2)+1:end);
        residualRecent=abs(residualPhaseUI(recent(transitionRecent)));
        phaseValues=piWrappedCodeTrace(stableRecent); phaseSpan=max(phaseValues)-min(phaseValues);
        if sum(transitionRecent)>=minTransitions && (isempty(residualRecent) || max(residualRecent)<=lockTol) && phaseSpan<=maxCodeSpan
            stable=stable+1;
            if lockIndex==0, lockIndex=k; end
        else
            stable=0;
        end
    end
    lockTrace(k)=enabled && stable>0; prev=decisionTrace(k);
end
trace=struct('enabled',enabled,'nCodes',nCodes,'initialPhaseUI',initialPhaseUI,...
    'loopGainCodes',loopGain,'loopBandwidthProxy',bandwidthProxy,'updateCadence',updateCadence,...
    'lockWindow',lockWindow,'lockToleranceUI',lockTol,'minTransitions',minTransitions,'maxCodeSpanCodes',maxCodeSpan,...
    'lockIndex',lockIndex,'locked',lockIndex>0,'cdr_lock_trace',lockTrace,...
    'piCodeTrace',piCodeTrace,'rawCodeTrace',piRawCodeTrace,'piRawCodeTrace',piRawCodeTrace,...
    'piWrappedCodeTrace',piWrappedCodeTrace,'piAppliedCodeTrace',piAppliedCodeTrace,...
    'piMismatchTrace',piMismatchTrace,'piWrapCountTrace',piWrapCountTrace,...
    'errorTrace',errorTrace,'earlyLateTrace',earlyLateMetric,'transitionTrace',transitionTrace,...
    'transitionPhaseUI',transitionPhaseUI,'dataPhaseUI',dataPhaseUI,'edgePhaseUI',edgePhaseUI,...
    'appliedPhaseUI',appliedPhaseUI,'residualPhaseUI',residualPhaseUI,...
    'samples',samples,'earlySamples',earlySamples,'lateSamples',lateSamples,...
    'decisionTrace',decisionTrace,'architecture',struct('dll1PhaseCount',8,...
        'dll2DataDegrees',[0 90 180 270],'dll2EdgeDegrees',[45 135 225 315],...
        'piFollows','DLL1','trainingMode','decision_directed'),...
    'jitterUI',jitterUI,'piOptions',piOptions,'residualDefinition',...
    'phase difference from recent received-transition decisions','lockCriterion',...
    'minimum RX transitions plus recent PI-code stability and transition-phase residual');
trace.piMeta=struct('rawCode',piRawCodeTrace,'wrappedCode',piWrappedCodeTrace,'appliedCode',piAppliedCodeTrace,...
    'mismatchLSB',piMismatchTrace,'wrapCount',piWrapCountTrace,'phaseUI',appliedPhaseUI);
end

function value=wrapPhase(value)
value=mod(value+0.5,1)-0.5;
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
