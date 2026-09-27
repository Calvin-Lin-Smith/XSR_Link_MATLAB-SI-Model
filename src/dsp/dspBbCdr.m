function [bits,trace] = dspBbCdr(x,modulation,sps,options)
%DSPBBCDR Reference-free decision-directed early/late bang-bang CDR.
% The phase detector sees only received samples and prior symbol decisions.
if nargin<4 || isempty(options), options=struct(); end
x=x(:); modulation=char(modulation); isPam4=strcmpi(modulation,'PAM4');
validateattributes(sps,{'numeric'},{'scalar','integer','positive'});
nCodes=getField(options,'nCodes',64); enabled=logical(getField(options,'enabled',true));
initialPhaseUI=getField(options,'initialPhaseUI',0.5); loopGain=getField(options,'loopGainCodes',1);
lockWindow=getField(options,'lockWindow',32); lockTol=getField(options,'lockToleranceUI',0.08);
maxStep=getField(options,'maxStepCodes',max(1,ceil(abs(loopGain))));
updateCadence=getField(options,'updateCadence',1); bandwidthProxy=getField(options,'loopBandwidthProxy',loopGain/nCodes);
minTransitions=getField(options,'minTransitions',max(4,ceil(lockWindow/8))); maxCodeSpan=getField(options,'maxCodeSpanCodes',8);
staticPhaseSkewUI=getField(options,'staticPhaseSkewUI',0); staticDutyCorrectionUI=getField(options,'staticDutyCorrectionUI',0);
samplerOffsetCodes=getField(options,'samplerOffsetCodes',0); minOccupancy=getField(options,'minOccupancy',0.02);
minEyeMargin=getField(options,'minEyeMargin',0.08); levelingValid=logical(getField(options,'levelingValid',true));
holdoverOnLock=logical(getField(options,'holdoverOnLock',isPam4));
lockConfirmCount=getField(options,'lockConfirmCount',8); lossConfirmCount=getField(options,'lossConfirmCount',32);
levelValidationWindow=getField(options,'levelValidationWindow',512);
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
validateattributes(staticPhaseSkewUI,{'numeric'},{'scalar','real','finite'});
validateattributes(staticDutyCorrectionUI,{'numeric'},{'scalar','real','finite'});
validateattributes(samplerOffsetCodes,{'numeric'},{'scalar','real','finite'});
validateattributes(minOccupancy,{'numeric'},{'scalar','real','finite','>=',0,'<',0.25});
validateattributes(minEyeMargin,{'numeric'},{'scalar','real','finite','nonnegative'});
validateattributes(lockConfirmCount,{'numeric'},{'scalar','integer','positive'});
validateattributes(lossConfirmCount,{'numeric'},{'scalar','integer','positive'});
validateattributes(levelValidationWindow,{'numeric'},{'scalar','integer','positive'});
rawCode=initialPhaseUI*nCodes; nSym=floor((numel(x)-1)/sps)+1;
levelValidationWindow=min(levelValidationWindow,max(lockWindow,ceil(max(nSym,1)/2)));
jitterUI=getField(options,'jitterUI',zeros(max(nSym,0),1)); jitterUI=jitterUI(:);
if isscalar(jitterUI), jitterUI=repmat(jitterUI,max(nSym,1),1); end
if numel(jitterUI)<nSym, jitterUI(end+1:nSym,1)=0; end
bps=1+isPam4; bits=zeros(max(nSym,0)*bps,1); samples=nan(max(nSym,0),1);
earlySamples=samples; lateSamples=samples; decisionTrace=nan(max(nSym,0),1); decisionInputTrace=nan(max(nSym,0),1); errorTrace=zeros(max(nSym,0),1);
piCodeTrace=zeros(max(nSym,0),1); appliedPhaseUI=zeros(max(nSym,0),1); dataPhaseUI=appliedPhaseUI;
edgePhaseUI=appliedPhaseUI; residualPhaseUI=zeros(max(nSym,0),1); lockTrace=false(max(nSym,0),1);
earlyLateMetric=zeros(max(nSym,0),1); transitionTrace=false(max(nSym,0),1); transitionPhaseUI=nan(max(nSym,0),1);
piRawCodeTrace=zeros(max(nSym,0),1); piWrappedCodeTrace=zeros(max(nSym,0),1); piAppliedCodeTrace=zeros(max(nSym,0),1);
piMismatchTrace=zeros(max(nSym,0),1); piWrapCountTrace=zeros(max(nSym,0),1);
levelOccupancyTrace=nan(max(nSym,0),4); levelCentroidTrace=nan(max(nSym,0),4); levelSigmaTrace=nan(max(nSym,0),4);
logicalEyeMarginTrace=nan(max(nSym,0),1); levelsValidTrace=false(max(nSym,0),1);
lockStartTrace=false(max(nSym,0),1); lockLossTrace=false(max(nSym,0),1);
lockCandidateTrace=false(max(nSym,0),1); lockInvalidRunTrace=zeros(max(nSym,0),1);
stable=0; invalidStable=0; lockIndex=0; firstValidLockIndex=0; latestLockIndex=0; lockLossCount=0; currentlyLocked=false; prev=NaN; transitionHistory=[];
for k=1:nSym
    [phase,piMeta]=dspPiClock(rawCode,sps,piOptions);
    piRawCodeTrace(k)=piMeta.rawCode; piWrappedCodeTrace(k)=piMeta.wrappedCode;
    piAppliedCodeTrace(k)=piMeta.appliedCode; piMismatchTrace(k)=piMeta.mismatchLSB; piWrapCountTrace(k)=piMeta.wrapCount;
    dataPhase=mod(phase+staticPhaseSkewUI+0.5*staticDutyCorrectionUI,1);
    edgePhase=mod(phase+staticPhaseSkewUI+0.125-0.5*staticDutyCorrectionUI,1);
    piCodeTrace(k)=piMeta.wrappedCode; appliedPhaseUI(k)=dataPhase; dataPhaseUI(k)=dataPhase; edgePhaseUI(k)=edgePhase;
    effectivePhase=dataPhase+jitterUI(k); idx=round((k-1)*sps+effectivePhase*sps)+1;
    eidx=idx-round(sps/4); lidx=idx+round(sps/4);
    if idx>=1 && idx<=numel(x)
        samples(k)=x(idx); decisionInputTrace(k)=samples(k)+samplerOffsetCodes;
        decisionTrace(k)=decisionValue(decisionInputTrace(k),modulation);
        bits((k-1)*bps+(1:bps))=decisionBits(decisionTrace(k),modulation);
    end
    if eidx>=1 && lidx<=numel(x)
        earlySamples(k)=x(eidx); lateSamples(k)=x(lidx);
        if ~isnan(decisionTrace(k))
            ev=decisionValue(earlySamples(k)+samplerOffsetCodes,modulation); lv=decisionValue(lateSamples(k)+samplerOffsetCodes,modulation);
            earlyLateMetric(k)=abs(ev-decisionTrace(k))-abs(lv-decisionTrace(k)); errorTrace(k)=sign(earlyLateMetric(k));
            if ~isnan(prev) && decisionTrace(k)~=prev
                transitionTrace(k)=true; transitionPhaseUI(k)=dataPhase;
                if isempty(transitionHistory), residualPhaseUI(k)=0;
                else, residualPhaseUI(k)=wrapPhase(phase-median(transitionHistory(max(1,end-7):end))); end
                transitionHistory=[transitionHistory phase]; if numel(transitionHistory)>64, transitionHistory=transitionHistory(end-63:end); end %#ok<AGROW>
            end
            if enabled && mod(k-1,updateCadence)==0 && transitionTrace(k) && errorTrace(k)~=0 && ~(holdoverOnLock && currentlyLocked)
                rawCode=rawCode+max(-maxStep,min(maxStep,loopGain*errorTrace(k)));
            end
        end
    end
    levelValid=true; eyeMargin=NaN;
    if isPam4 && k>=levelValidationWindow
        recent=(k-levelValidationWindow+1):k;
        [levelValid,levelOccupancyTrace(k,:),levelCentroidTrace(k,:),levelSigmaTrace(k,:),eyeMargin]=...
            levelStats(decisionTrace(recent),samples(recent),minOccupancy);
        levelsValidTrace(k)=levelValid; logicalEyeMarginTrace(k)=eyeMargin;
    elseif ~isPam4
        levelsValidTrace(k)=true;
    end
    lockWindowReady=k>=lockWindow && (~isPam4 || k>=levelValidationWindow);
    if enabled && lockWindowReady
        recent=(k-lockWindow+1):k; transitionRecent=transitionTrace(recent); stableRecent=recent(floor(numel(recent)/2)+1:end);
        residualRecent=abs(residualPhaseUI(recent(transitionRecent))); phaseValues=piRawCodeTrace(stableRecent);
        if isempty(residualRecent), residualCriterion=0; else, sortedResidual=sort(residualRecent); residualCriterion=sortedResidual(max(1,ceil(0.9*numel(sortedResidual)))); end
        phaseSpan=max(phaseValues)-min(phaseValues);
        candidate=sum(transitionRecent)>=minTransitions && residualCriterion<=lockTol && phaseSpan<=maxCodeSpan;
        if isPam4, candidate=candidate && levelingValid && levelValid && eyeMargin>=minEyeMargin; end
        lockCandidateTrace(k)=candidate;
        wasLocked=currentlyLocked;
        if candidate
            stable=stable+1; invalidStable=0;
        else
            invalidStable=invalidStable+1;
            if ~currentlyLocked || invalidStable>=lossConfirmCount, stable=0; end
        end
        if ~currentlyLocked && stable>=lockConfirmCount, currentlyLocked=true; end
        if currentlyLocked && candidate, currentlyLocked=true; end
        if currentlyLocked && ~candidate && invalidStable>=lossConfirmCount, currentlyLocked=false; end
        if currentlyLocked, lockInvalidRunTrace(k)=invalidStable; end
        if ~wasLocked && currentlyLocked
            lockStartTrace(k)=true; latestLockIndex=k; if firstValidLockIndex==0, firstValidLockIndex=k; lockIndex=k; end
        elseif wasLocked && ~currentlyLocked
            lockLossCount=lockLossCount+1; lockLossTrace(k)=true;
        end
    end
    lockTrace(k)=enabled && currentlyLocked; prev=decisionTrace(k);
end
piWrapEventTrace=false(max(nSym,0),1); cycleSlipTrace=false(max(nSym,0),1);
if nSym>1
    piWrapEventTrace(2:end)=diff(piWrapCountTrace)~=0;
    cycleSlipTrace(2:end)=abs(diff(piRawCodeTrace))>nCodes/2;
end
tailLockLossCount=0; continuousTailLock=false;
if firstValidLockIndex>0
    tailLockLossCount=sum(lockLossTrace(firstValidLockIndex:end));
    continuousTailLock=currentlyLocked&&all(lockTrace(firstValidLockIndex:end));
end
trace=struct('enabled',enabled,'nCodes',nCodes,'initialPhaseUI',initialPhaseUI,...
    'loopGainCodes',loopGain,'loopBandwidthProxy',bandwidthProxy,'updateCadence',updateCadence,...
    'lockWindow',lockWindow,'lockToleranceUI',lockTol,'minTransitions',minTransitions,'maxCodeSpanCodes',maxCodeSpan,...
    'staticPhaseSkewUI',staticPhaseSkewUI,'staticDutyCorrectionUI',staticDutyCorrectionUI,'samplerOffsetCodes',samplerOffsetCodes,...
    'lockIndex',lockIndex,'firstValidLockIndex',firstValidLockIndex,'firstLockIndex',firstValidLockIndex,'latestLockIndex',latestLockIndex,...
    'locked',lockIndex>0,'everLocked',lockIndex>0,'currentlyLocked',enabled && currentlyLocked,'continuousTailLock',continuousTailLock,...
    'lockLossCount',lockLossCount,'tailLockLossCount',tailLockLossCount,'lockStartTrace',lockStartTrace,'lockLossTrace',lockLossTrace,...
    'lockCandidateTrace',lockCandidateTrace,'lockInvalidRunTrace',lockInvalidRunTrace,'lockConfirmCount',lockConfirmCount,'lossConfirmCount',lossConfirmCount,'levelValidationWindow',levelValidationWindow,...
    'cdr_lock_trace',lockTrace,'currentlyLockedTrace',lockTrace,...
    'piCodeTrace',piCodeTrace,'rawCodeTrace',piRawCodeTrace,'piRawCodeTrace',piRawCodeTrace,...
    'piWrappedCodeTrace',piWrappedCodeTrace,'piAppliedCodeTrace',piAppliedCodeTrace,'piMismatchTrace',piMismatchTrace,...
    'piWrapCountTrace',piWrapCountTrace,'piWrapEventTrace',piWrapEventTrace,'piUnwrappedCodeTrace',piRawCodeTrace,'piSampleTimeTrace',(1:nSym)',...
    'cycleSlipTrace',cycleSlipTrace,'cycleSlipCount',sum(cycleSlipTrace),...
    'errorTrace',errorTrace,'earlyLateTrace',earlyLateMetric,'transitionTrace',transitionTrace,'transitionPhaseUI',transitionPhaseUI,...
    'dataPhaseUI',dataPhaseUI,'edgePhaseUI',edgePhaseUI,'appliedPhaseUI',appliedPhaseUI,'residualPhaseUI',residualPhaseUI,...
    'samples',samples,'earlySamples',earlySamples,'lateSamples',lateSamples,'decisionTrace',decisionTrace,'decisionInputTrace',decisionInputTrace,...
    'architecture',struct('dll1PhaseCount',8,'dll2DataDegrees',[0 90 180 270],'dll2EdgeDegrees',[45 135 225 315],...
        'piFollows','DLL1','trainingMode','decision_directed'),...
    'jitterUI',jitterUI,'piOptions',piOptions,'levelOccupancyTrace',levelOccupancyTrace,'levelCentroidTrace',levelCentroidTrace,...
    'levelSigmaTrace',levelSigmaTrace,'logicalEyeMarginTrace',logicalEyeMarginTrace,'levelsValidTrace',levelsValidTrace,...
    'levelsValid',isPam4 && levelingValid && any(levelsValidTrace),'minOccupancy',minOccupancy,'minEyeMargin',minEyeMargin,...
    'levelingValid',levelingValid,'holdoverOnLock',holdoverOnLock,'residualDefinition','phase difference from recent received-transition decisions',...
    'lockCriterion','minimum RX transitions plus recent PI-code stability, PAM4 four-level validity, and transition-phase residual');
trace.piMeta=struct('rawCode',piRawCodeTrace,'wrappedCode',piWrappedCodeTrace,'appliedCode',piAppliedCodeTrace,...
    'mismatchLSB',piMismatchTrace,'wrapCount',piWrapCountTrace,'phaseUI',appliedPhaseUI);
end

function value=wrapPhase(value)
value=mod(value+0.5,1)-0.5;
end

function value=getField(s,name,default)
if isstruct(s)&&isfield(s,name), value=s.(name); else, value=default; end
end

function v=decisionValue(x,modulation)
switch upper(modulation)
    case 'NRZ', v=2*double(x>=0)-1;
    case 'PAM4', c=dspPam4Contract(); v=c.levels(1+sum(x>=c.thresholds));
    otherwise, error('dspBbCdr:Modulation','Unsupported modulation: %s',modulation);
end
end

function b=decisionBits(v,modulation)
switch upper(modulation)
    case 'NRZ', b=double(v>0);
    case 'PAM4'
        c=dspPam4Contract(); idx=find(c.levels==v,1); if isempty(idx), error('dspBbCdr:Decision','Invalid PAM4 decision.'); end
        b=c.bitPairs(idx,:).';
end
end

function [valid,occupancy,centroids,sigma,eyeMargin]=levelStats(decisions,samples,minOccupancy)
c=dspPam4Contract(); finite=isfinite(decisions)&isfinite(samples); decisions=decisions(finite); samples=samples(finite); n=numel(decisions);
occupancy=zeros(1,4); centroids=nan(1,4); sigma=nan(1,4); valid=false; eyeMargin=-Inf;
if n==0, return; end
for k=1:4
    hit=decisions==c.levels(k); occupancy(k)=sum(hit)/n;
    if any(hit), v=samples(hit); centroids(k)=mean(v); if numel(v)>1, sigma(k)=std(v,0); else, sigma(k)=0; end, end
end
if all(isfinite(centroids)) && all(diff(centroids)>eps(max(1,max(abs(centroids)))))
    eyeMargin=min(diff(centroids))-2*max(sigma); valid=all(occupancy>=minOccupancy) && eyeMargin>=0;
end
end
