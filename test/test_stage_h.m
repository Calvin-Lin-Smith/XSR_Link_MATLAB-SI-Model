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
toggleFields={'startupCalibration','ctleTraining','ffeTraining','samplerCalibration','clockTraining'};
for k=1:numel(toggleFields)
    c=phyConfig('vlsi2024_xsr_typical'); c.link.nBits=128; c.model.debugStages.(toggleFields{k})=false;
    [o,~]=run_vlsi2024_xsr('debug_link',128,'Config',c); row=strcmp(string(o.stageTrace.stage),strrep(toggleFields{k},'Calibration','_calibration'));
    if strcmp(toggleFields{k},'ctleTraining'), row=strcmp(string(o.stageTrace.stage),'ctle_training'); end
    if strcmp(toggleFields{k},'ffeTraining'), row=strcmp(string(o.stageTrace.stage),'ffe_training'); end
    if strcmp(toggleFields{k},'samplerCalibration'), row=strcmp(string(o.stageTrace.stage),'sampler_calibration'); end
    if strcmp(toggleFields{k},'clockTraining'), row=strcmp(string(o.stageTrace.stage),'clock_training'); end
    assert(strcmp(string(o.stageTrace.status(row)),'skipped_manual_value')&&o.stageTrace.consumedUI(row)==0,toggleFields{k});
end
cfgNoLock=cfgManual; cfgNoLock.model.debugStages.ctleTraining=true; cfgNoLock.model.cdrOptions.lockWindow=100000;
[noLock,~]=run_vlsi2024_xsr('debug_link',256,'Config',cfgNoLock);
assert(~noLock.berValid&&strcmp(noLock.status,'invalid_no_lock')&&all(isnan(noLock.result.ber)));
cfgNoCdr=cfgManual; cfgNoCdr.model.debugStages.ctleTraining=true; cfgNoCdr.model.debugStages.cdrEnabled=false;
[noCdr,~]=run_vlsi2024_xsr('debug_link',256,'Config',cfgNoCdr);
assert(~noCdr.berValid&&strcmp(noCdr.status,'debug_no_cdr')&&all(isnan(noCdr.result.ber)));

bad=app.ConfigTable.Data{idx,3}; app.ConfigTable.Data{idx,3}='-1';
try, app.applyConfigTable(false); catch, end
assert(app.Cfg.link.nBits==256,'invalid edit changed requested cfg'); app.ConfigTable.Data{idx,3}=bad;

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
