function test_stage_h()
%TEST_STAGE_H Paper-only GUI, edited-link, and temporary Simulink checks.
root=fileparts(fileparts(mfilename('fullpath')));
addpath(genpath(fullfile(root,'src'))); addpath(fullfile(root,'gui')); addpath(fullfile(root,'simulink'));

shared=fullfile(root,'simulink','d2d_shared_config.mat'); trackedSlx=fullfile(root,'simulink','D2D_PHY_SI_Simulink.slx');
sharedBefore=fileHash(shared); slxBefore=fileHash(trackedSlx);
app=D2DWorkbench(root); cleanup=onCleanup(@()closeGui(app));
texts=uiTextValues(app.Figure,'Text');
legacyExact=["ideal" "typical" "Reset Ideal" "Reset Typical" "Behavior Suite" "Standard T1-T9" ...
    "Loss Sweep" "CTLE Sweep" "RJ Sweep" "CDR Sweep" "FFE + CTLE Scan"];
assert(~any(ismember(lower(texts),lower(legacyExact))),'legacy GUI control/text remains visible');
assert(~isprop(app,'ProfileDropDown'),'generic profile selector remains');
assert(isprop(app,'PresetDropDown'),'paper preset selector missing');
assert(isequal(string(app.PresetDropDown.Items),["VLSI Typical" "VLSI Ideal"]));
assert(strcmp(app.PresetDropDown.Value,'VLSI Typical'));
assert(isfield(app.Cfg,'paper') && strcmp(app.Cfg.paper.preset,'VLSI Typical'));

actions=uiTextValues(app.Figure,'Text');
requiredActions=["Apply + Sync" "Load from Simulink" "Run x8 Link" "VLSI2024 Baseline" ...
    "Static A-D / FFE / IL / AC-CTLE" "BB-CDR / PI / Jitter Evidence" ...
    "Calibration / Adaptation" "Full VLSI2024 Regression"];
for k=1:numel(requiredActions), assert(any(strcmp(actions,requiredActions(k))),requiredActions(k)); end
probes=D2DWorkbench.probeItems();
requiredProbes=["TX FFE output" "TX DAC / pad" "Channel output" "RX AC pre" "RX AC post" ...
    "RX CTLE output" "RX level-shifted samples" "RX data samples" "RX edge samples" ...
    "RX spare samples" "PI code" "CDR error" "CDR lock" "Adaptation objective" "FFE tap trace"];
for k=1:numel(requiredProbes), assert(any(strcmp(probes,requiredProbes(k))),requiredProbes(k)); end
paths=D2DWorkbench.paperConfigPaths();
requiredPaths={'link.nBits','link.sps','link.seed','link.rjUI_rms','link.djUI_pp','model.resultRoot',...
    'txPma.lane.ffeMode','txPma.lane.ffeOffsets','txPma.lane.ffeCoeffs','txPma.lane.sixTapPreset.offsets',...
    'txPma.lane.enableDacQuantization','txPma.lane.dacLevels','channel.mode','channel.refFreq_GHz',...
    'channel.lossAtRef_dB','rxPma.lane.enableAcPre','rxPma.lane.enableAcPost','rxPma.lane.ctlePolicy',...
    'rxPma.lane.samplerRoles.samplerOffsetCodes','model.cdrOptions.nCodes','model.debugStages.startupCalibration',...
    'model.debugStages.ctleTraining','model.debugStages.ffeTraining','model.debugStages.samplerCalibration',...
    'model.debugStages.clockTraining','model.debugStages.cdrEnabled','model.debugStages.postLockWaitUI'};
for k=1:numel(requiredPaths), assert(any(strcmp(paths,requiredPaths{k})),requiredPaths{k}); end
assert(~any(contains(string(paths),["txEqMain" "txEqPre" "txEqPost" "lossNyq_dB" "clockMode"])),...
    'legacy flat aliases remain in paper table');

% An edited table value must feed exactly one local x8 link; no sync or regression write occurs.
idx=find(strcmp(app.ConfigPaths,'link.nBits'),1); assert(~isempty(idx)); app.ConfigTable.Data{idx,3}='256';
app.runLink(); assert(~isempty(app.Result) && app.Cfg.link.nBits==256 && app.Phy.link.nBits==256);
assert(~isempty(app.MetricsTable.Data) && ~isempty(app.Phy.rxPma.lane(1).afe.ctleOut));
assert(~isempty(app.TrainedParametersTable.Data));
logs=string(app.LogArea.Value); assert(any(contains(logs,'x8 link trained'))); assert(~any(contains(lower(logs),'full regression')));
assert(strcmp(sharedBefore,fileHash(shared)) && strcmp(slxBefore,fileHash(trackedSlx)),'Run x8 Link changed tracked shared artifacts');
assert(isfield(app.Debug,'requestedCfg')&&isfield(app.Debug,'trainedCfg')&&isfield(app.Debug,'appliedCfg'));
assert(app.Debug.berStartUIInFinalPass>=max(app.Debug.laneLockUI)+app.Debug.postLockWaitUI);
assert(app.Debug.totalWaitedUI==app.Debug.totalTrainingBudgetUI+app.Debug.berStartUIInFinalPass);
assert(app.Debug.measurementStartSample==app.Debug.measurementStartUI*app.Cfg.link.sps+1);
assert(numel(app.Debug.fullLockTrace{1}.cdr_lock_trace)>=app.Debug.berStartUIInFinalPass);
wave=app.Debug.model.rxPma.lane(1).afe.ctleOut; start=app.Debug.measurementStartSample;
expected=wave(min(start,numel(wave)+1):end); assert(isequaln(app.Debug.performance.lane(1).ctleOut,expected));
assert(ismember('parameterPath',app.Debug.trainedParameters.Properties.VariableNames));
assert(all(ismember({'requested','trained','applied','residual','constraint','unit'},app.Debug.trainedParameters.Properties.VariableNames)));
assert(any(contains(string(app.Debug.trainedParameters.parameterPath),'candidate_4.13')));
starts=arrayfun(@(x)x.measurementStartSample,app.Debug.performance.lane(:)); assert(all(starts==app.Debug.measurementStartSample));
assert(numel(unique(app.Debug.laneLockUI))>1,'x8 debug did not expose unequal lane lock times');
assert(any(strcmp(string(app.Debug.trainedParameters.status),'executed')));

cfgManual=phyConfig('vlsi2024_xsr_typical'); cfgManual.link.nBits=256; cfgManual.model.debugStages.ctleTraining=false;
cfgManual.rxPma.lane.ctleBoost_dB=5; [manual,~]=run_vlsi2024_xsr('debug_link',256,'Config',cfgManual);
row=manual.trainedParameters(strcmp(string(manual.trainedParameters.parameterPath),'rxPma.lane.ctleBoost_dB'),:);
assert(~isempty(row)&&strcmp(row.status,'skipped_manual_value')&&strcmp(row.trained,'5'));
assert(manual.trainedCfg.rxPma.lane.ctleBoost_dB==5);
ctleRow=strcmp(string(manual.stageTrace.stage),'ctle_training');
assert(strcmp(string(manual.stageTrace.status(ctleRow)),'skipped_manual_value'));
assert(manual.stageTrace.consumedUI(ctleRow)==0);
cfgRequested=phyConfig('vlsi2024_xsr_typical'); cfgRequested.link.nBits=256; cfgRequested.channel.lossAtRef_dB=2; cfgRequested.model.enablePaperAdaptation=false;
[requestedOut,~]=run_vlsi2024_xsr('debug_link',256,'Config',cfgRequested);
assert(requestedOut.requestedCfg.channel.lossAtRef_dB==2 && requestedOut.trainedCfg.channel.lossAtRef_dB==2 && requestedOut.appliedCfg.channel.lossAtRef_dB==2);
assert(~requestedOut.requestedCfg.model.enablePaperAdaptation && ~requestedOut.trainedCfg.model.enablePaperAdaptation && ~requestedOut.appliedCfg.model.enablePaperAdaptation);
assert(~requestedOut.trainedCfg.model.useReferenceAlign);
cfgSent=cfgRequested; cfgSent.model.debugOptions.preLockSentinel=1234;
[sentOut,~]=run_vlsi2024_xsr('debug_link',256,'Config',cfgSent);
assert(sentOut.preLockSentinelApplied && any(sentOut.model.rxPma.lane(1).afe.ctleOut==1234));
assert(~any(sentOut.performance.lane(1).ctleOut==1234),'pre-lock sentinel entered performance window');
assert(sentOut.result.berValid,'pre-lock sentinel invalidated post-lock BER');
cfgNoCdrRequested=cfgManual; cfgNoCdrRequested.model.debugStages.cdrEnabled=false;
[noCdrConfigured,~]=run_vlsi2024_xsr('debug_link',256,'Config',cfgNoCdrRequested);
assert(strcmp(noCdrConfigured.status,'debug_no_cdr') && ~noCdrConfigured.appliedCfg.model.useReferenceAlign);
assert(all(arrayfun(@(x)~isfield(x.cdrTrace,'trainingMode') || ~strcmp(x.cdrTrace.trainingMode,'legacy_reference_align'),noCdrConfigured.model.rxPma.lane)));
noCdrEnableRow=noCdrConfigured.trainedParameters(strcmp(string(noCdrConfigured.trainedParameters.parameterPath),'model.cdrOptions.enabled'),:);
assert(~isempty(noCdrEnableRow)&&strcmp(noCdrEnableRow.applied,'false'));
requiredTrainPaths={"rxPma.lane.terminationMode","rxPma.lane.termGain","txPma.lane.targetSwing","txPma.lane.enableDacQuantization",...
    "txPma.lane.dacLevels","txPma.lane.ffeMode","txPma.lane.ffeOffsets","txPma.lane.ffeCoeffs","txPma.lane.ffeCurrent",...
    "rxPma.lane.ctleBoost_dB","rxPma.lane.samplerRoles.samplerOffsetCodes","rxPma.lane.samplerRoles.thresholdAssumptions",...
    "model.cdrOptions.staticPhaseSkewUI","model.cdrOptions.staticDutyCorrectionUI","model.cdrOptions.nCodes",...
    "model.cdrOptions.initialPhaseUI","model.cdrOptions.loopGainCodes","model.cdrOptions.enabled","model.cdrOptions.maxStepCodes",...
    "model.cdrOptions.mismatchBoundLSB","model.cdrOptions.loopBandwidthProxy","model.cdrOptions.updateCadence",...
    "model.cdrOptions.lockToleranceUI","model.debugStages.postLockWaitUI"};
actualTrainPaths=cellstr(string(app.Debug.trainedParameters.parameterPath)); requiredTrainPaths=cellstr(requiredTrainPaths);
for k=1:numel(requiredTrainPaths), assert(any(strcmp(actualTrainPaths,requiredTrainPaths{k}))); end
ffeModeRow=app.Debug.trainedParameters(strcmp(string(app.Debug.trainedParameters.parameterPath),'txPma.lane.ffeMode'),:);
assert(~isempty(ffeModeRow)&&~strcmp(ffeModeRow.applied,'[-1 0 1]'),'FFE mode applied value is mis-mapped');
cfgSix=phyConfig('vlsi2024_xsr_typical'); cfgSix.link.nBits=256; cfgSix.txPma.lane.ffeMode='six_tap';
cfgSix.txPma.lane.ffeOffsets=cfgSix.txPma.lane.sixTapPreset.offsets; cfgSix.txPma.lane.ffeCoeffs=cfgSix.txPma.lane.sixTapPreset.coeffs;
[sixOut,~]=run_vlsi2024_xsr('debug_link',256,'Config',cfgSix);
assert(strcmp(sixOut.trainedCfg.txPma.lane.ffeMode,'six_tap')&&numel(sixOut.trainedCfg.txPma.lane.ffeOffsets)==6);
assert(isequal(sixOut.appliedCfg.txPma.lane.ffeCoeffs,sixOut.model.txPma.lane(1).ffe.tapMeta.appliedCoefficients));
assert(isequal(sixOut.appliedCfg.txPma.lane.ffeOffsets,sixOut.model.txPma.lane(1).ffe.tapMeta.appliedOffsets));
cfgAc=phyConfig('vlsi2024_xsr_typical'); cfgAc.link.nBits=128; cfgAc.rxPma.lane.enableAcPre=true; cfgAc.rxPma.lane.terminationMode='AC';
cfgDc=cfgAc; cfgDc.rxPma.lane.terminationMode='DC';
pAc=D2DPHY('ac_mode',1); pAc.configure(cfgAc); pAc.run(); pDc=D2DPHY('dc_mode',1); pDc.configure(cfgDc); pDc.run();
assert(norm(pAc.rxPma.lane(1).afe.acPreOut-pAc.rxPma.lane(1).afe.termOut)>0);
assert(isequaln(pDc.rxPma.lane(1).afe.acPreOut,pDc.rxPma.lane(1).afe.termOut));
toggleFields={'startupCalibration','ctleTraining','ffeTraining','samplerCalibration','clockTraining'};
for k=1:numel(toggleFields)
    c=phyConfig('vlsi2024_xsr_typical'); c.link.nBits=128; c.model.debugStages.(toggleFields{k})=false;
    c.txPma.lane.gainError=0.11; c.rxPma.lane.termGain=0.88; c.model.cdrOptions.staticPhaseSkewUI=0.07;
    c.model.cdrOptions.staticDutyCorrectionUI=0.03; c.rxPma.lane.samplerRoles.samplerOffsetCodes=0.25; c.rxPma.lane.ctleBoost_dB=5;
    c.txPma.lane.ffeCoeffs=[-0.02 0.96 -0.02];
    [o,~]=run_vlsi2024_xsr('debug_link',128,'Config',c); row=strcmp(string(o.stageTrace.stage),strrep(toggleFields{k},'Calibration','_calibration'));
    if strcmp(toggleFields{k},'ctleTraining'), row=strcmp(string(o.stageTrace.stage),'ctle_training'); end
    if strcmp(toggleFields{k},'ffeTraining'), row=strcmp(string(o.stageTrace.stage),'ffe_training'); end
    if strcmp(toggleFields{k},'samplerCalibration'), row=strcmp(string(o.stageTrace.stage),'sampler_calibration'); end
    if strcmp(toggleFields{k},'clockTraining'), row=strcmp(string(o.stageTrace.stage),'clock_training'); end
    assert(strcmp(string(o.stageTrace.status(row)),'skipped_manual_value')&&o.stageTrace.consumedUI(row)==0,toggleFields{k});
    switch toggleFields{k}
        case 'startupCalibration', assert(o.trainedCfg.txPma.lane.gainError==c.txPma.lane.gainError&&o.trainedCfg.rxPma.lane.termGain==c.rxPma.lane.termGain);
        case 'clockTraining', assert(o.trainedCfg.model.cdrOptions.staticPhaseSkewUI==c.model.cdrOptions.staticPhaseSkewUI);
        case 'samplerCalibration', assert(o.trainedCfg.rxPma.lane.samplerRoles.samplerOffsetCodes==c.rxPma.lane.samplerRoles.samplerOffsetCodes);
        case 'ctleTraining', assert(o.trainedCfg.rxPma.lane.ctleBoost_dB==c.rxPma.lane.ctleBoost_dB);
        case 'ffeTraining', assert(isequal(o.trainedCfg.txPma.lane.ffeCoeffs,c.txPma.lane.ffeCoeffs));
    end
end
cfgNoLock=cfgManual; cfgNoLock.model.debugStages.ctleTraining=true; cfgNoLock.model.cdrOptions.lockWindow=100000;
[noLock,~]=run_vlsi2024_xsr('debug_link',256,'Config',cfgNoLock);
assert(~noLock.berValid&&strcmp(noLock.status,'invalid_no_lock')&&all(isnan(noLock.result.ber)));
cfgNoCdr=cfgManual; cfgNoCdr.model.debugStages.ctleTraining=true; cfgNoCdr.model.debugStages.cdrEnabled=false;
[noCdr,~]=run_vlsi2024_xsr('debug_link',256,'Config',cfgNoCdr);
assert(~noCdr.berValid&&strcmp(noCdr.status,'debug_no_cdr')&&all(isnan(noCdr.result.ber)));
assert(noCdr.model.rxPma.lane(1).bestPhase==round(0.5*cfgNoCdr.link.sps)&&noCdr.model.rxPma.lane(1).delayUI==cfgNoCdr.model.manualDelayUI);

bps=1+strcmpi(sentOut.requestedCfg.link.modulation,'PAM4'); first=sentOut.measurementStartUI*bps+1; last=min(size(sentOut.rawResult.rxBits,1),size(sentOut.model.rawPcs.referenceBits,1));
postErrors=zeros(1,sentOut.model.nLane); for k=1:sentOut.model.nLane, postErrors(k)=sum(sentOut.rawResult.rxBits(first:last,k)~=sentOut.model.rawPcs.referenceBits(first:last,k)); end
assert(isequaln(postErrors,sentOut.result.errCnt),'rawResult/result BER accounting diverged');
[rawErrors,~,~]=sentOut.model.rawPcs.check(sentOut.rawResult.rxBits,0); assert(any(rawErrors>sentOut.result.errCnt),'pre-lock sentinel was not visible to full raw checker');
for k=1:sentOut.model.nLane
    assert(sentOut.performance.lane(k).measurementStartSample==sentOut.measurementStartSample);
    assert(~any(sentOut.performance.lane(k).ctleOut==sentOut.preLockSentinel));
    assert(~any(sentOut.performance.lane(k).dataSamples==sentOut.preLockSentinel));
    assert(~any(sentOut.performance.lane(k).edgeSamples==sentOut.preLockSentinel));
    assert(~any(sentOut.performance.lane(k).edgeDetectorOutput==sentOut.preLockSentinel));
    assert(~any(sentOut.performance.lane(k).spareSamples==sentOut.preLockSentinel));
    assert(~any(sentOut.performance.lane(k).levelShiftedSamples(:)==sentOut.preLockSentinel));
    assert(~any(sentOut.performance.lane(k).sampleLevelDistribution==sentOut.preLockSentinel));
    assert(numel(sentOut.performance.lane(k).dataSamples)==max(0,numel(sentOut.model.rxPma.lane(k).dataSamples)-sentOut.measurementStartUI));
end

bad=app.ConfigTable.Data{idx,3}; app.ConfigTable.Data{idx,3}='-1';
try, app.applyConfigTable(false); catch, end
assert(app.Cfg.link.nBits==256,'invalid edit changed requested cfg'); app.ConfigTable.Data{idx,3}=bad;
for badValue={'abc','-1','1.5'}
    app.ConfigTable.Data{idx,3}=badValue{1}; try, app.applyConfigTable(false); catch, end
    assert(app.Cfg.link.nBits==256,'invalid numeric edit changed requested cfg');
end
logicalIdx=find(strcmp(app.ConfigPaths,'model.debugStages.cdrEnabled'),1); oldLogical=app.ConfigTable.Data{logicalIdx,3};
app.ConfigTable.Data{logicalIdx,3}='abc'; try, app.applyConfigTable(false); catch, end
assert(app.Cfg.model.debugStages.cdrEnabled==true,'invalid logical edit changed requested cfg'); app.ConfigTable.Data{logicalIdx,3}=oldLogical;
modeIdx=find(strcmp(app.ConfigPaths,'rxPma.lane.terminationMode'),1); oldMode=app.ConfigTable.Data{modeIdx,3};
app.ConfigTable.Data{modeIdx,3}='xyz'; try, app.applyConfigTable(false); catch, end
assert(strcmp(app.Cfg.rxPma.lane.terminationMode,'AC'),'invalid enum edit changed requested cfg'); app.ConfigTable.Data{modeIdx,3}=oldMode;
rejectEdit(app,'link.skipUI','1abc',32); rejectEdit(app,'link.skipUI','1.5',32);
rejectEdit(app,'model.debugStages.postLockWaitUI','-1',app.Cfg.model.debugStages.postLockWaitUI);
rejectEdit(app,'model.debugStages.startupCalibrationBudgetUI','1.5',app.Cfg.model.debugStages.startupCalibrationBudgetUI);
rejectEdit(app,'model.cdrOptions.nCodes','1',app.Cfg.model.cdrOptions.nCodes);
rejectEdit(app,'model.cdrOptions.initialPhaseUI','1.2',app.Cfg.model.cdrOptions.initialPhaseUI);
rejectEdit(app,'channel.lossAtRef_dB','-1',app.Cfg.channel.lossAtRef_dB);
rejectEdit(app,'rxPma.lane.ctleBoost_dB','7',app.Cfg.rxPma.lane.ctleBoost_dB);
rejectEdit(app,'txPma.lane.ffeCoeffs','-0.1 0.9 abc',app.Cfg.txPma.lane.ffeCoeffs);

app.PresetDropDown.Value='VLSI Ideal'; app.loadPreset();
assert(strcmp(app.Cfg.paper.preset,'VLSI Ideal') && app.Cfg.channel.lossAtRef_dB==0 && isinf(app.Cfg.link.snr_dB));
assert(strcmp(app.ConfigTable.Data{idx,3},app.valueToText(app.Cfg.link.nBits)),'preset did not repopulate editable table');

if license('test','Simulink')
    cfg=phyConfig('vlsi2024_xsr');
    modelName=matlab.lang.makeValidName(['stage_h_tmp_' char(java.util.UUID.randomUUID())]);
    modelFile=fullfile(root,'simulink',[modelName '.slx']);
    tempCleanup=onCleanup(@()cleanupModel(modelName,modelFile));
    mdl=buildD2DSimulinkModel('ModelName',modelName,'Config',cfg,'Open',false,'Save',true,'Overwrite',false);
    assert(strcmp(mdl,modelName) && isfile(modelFile)); load_system(modelName);
    modelCfg=evalin(get_param(modelName,'ModelWorkspace'),'d2dCfg');
    for k=1:numel(requiredPaths), assertFieldEqual(cfg,modelCfg,requiredPaths{k}); end
    assert(~isempty(find_system(modelName,'Type','Block','Name','BB-CDR PI Adaptation')));
    acPreBlock=find_system(modelName,'Type','Block','Name','ACPre'); acPostBlock=find_system(modelName,'Type','Block','Name','ACPost');
    assert(~isempty(acPreBlock)&&~isempty(acPostBlock));
    assert(contains(get_param(acPreBlock{1},'MATLABFcn'),'terminationMode')&&contains(get_param(acPreBlock{1},'MATLABFcn'),'enableAcPre'));
    assert(contains(get_param(acPostBlock{1},'MATLABFcn'),'terminationMode')&&contains(get_param(acPostBlock{1},'MATLABFcn'),'enableAcPost'));
end
assert(strcmp(sharedBefore,fileHash(shared)) && strcmp(slxBefore,fileHash(trackedSlx)),'GUI changed tracked shared artifacts');
disp('Stage H paper-only GUI and Simulink smoke checks OK');
end

function assertFieldEqual(a,b,path)
parts=strsplit(path,'.'); for k=1:numel(parts), a=a.(parts{k}); b=b.(parts{k}); end
assert(isequaln(a,b),['config mismatch: ' path]);
end

function values=uiTextValues(parent,property)
h=findall(parent,'-property',property); values=strings(0,1);
for k=1:numel(h)
    try
        v=get(h(k),property); if ischar(v) || isstring(v), values(end+1,1)=string(v); end %#ok<AGROW>
    catch
    end
end
end

function value=fileHash(path)
[status,out]=system(['certutil -hashfile "' path '" SHA256']); assert(status==0,['hash failed: ' path]);
value=regexp(char(out),'(?m)^[0-9A-Fa-f]{64}$','match','once');
assert(~isempty(value),['hash missing: ' path]);
end

function closeGui(app)
if isvalid(app) && ~isempty(app.Figure) && isvalid(app.Figure), delete(app.Figure); end
end

function cleanupModel(name,file)
if bdIsLoaded(name), set_param(name,'Dirty','off'); end
if isfile(file), try, delete(file); catch, end, end
end

function rejectEdit(app,path,value,expected)
idx=find(strcmp(app.ConfigPaths,path),1); assert(~isempty(idx),path); app.ConfigTable.Data{idx,3}=value; rejected=false;
try, app.applyConfigTable(false); catch, rejected=true; end
assert(rejected && isequaln(app.getNested(app.Cfg,strsplit(path,'.')),expected),['invalid edit accepted: ' path]);
app.ConfigTable.Data{idx,3}=app.valueToText(expected);
end
