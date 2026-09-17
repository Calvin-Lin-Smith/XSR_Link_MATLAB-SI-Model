function test_stage_h()
%TEST_STAGE_H Minimal Stage H GUI/config and temporary Simulink smoke checks.
root=fileparts(fileparts(mfilename('fullpath')));
addpath(genpath(fullfile(root,'src'))); addpath(fullfile(root,'gui')); addpath(fullfile(root,'simulink'));

profiles=D2DWorkbench.profileNames();
assert(isequal(profiles,{'ideal','typical','vlsi2024_xsr'}));
paths=D2DWorkbench.paperConfigPaths();
required={
    'txPma.lane.ffeMode','txPma.lane.ffeOffsets','txPma.lane.ffeCoeffs',...
    'txPma.lane.enableDacQuantization','txPma.lane.dacLevels','txPma.lane.targetSwing',...
    'channel.mode','channel.refFreq_GHz','channel.lossAtRef_dB',...
    'rxPma.lane.terminationMode','rxPma.lane.enableAcPre','rxPma.lane.enableAcPost',...
    'rxPma.lane.ctlePolicy','model.enablePaperAdaptation',...
    'rxPma.lane.samplerRoles.enabled','rxPma.lane.samplerRoles.roleCounts.data',...
    'rxPma.lane.samplerRoles.levelShiftCodes.data','rxPma.lane.samplerRoles.thresholdAssumptions',...
    'model.cdrOptions.nCodes','model.cdrOptions.loopGainCodes','model.cdrOptions.lockWindow'};
for k=1:numel(required), assert(any(strcmp(paths,required{k})),required{k}); end

cfg=phyConfig('vlsi2024_xsr');
app=D2DWorkbench(root); app.ProfileDropDown.Value='vlsi2024_xsr'; app.loadProfile(); guiCfg=app.Cfg; delete(app.Figure);
for k=1:numel(required)
    assertFieldEqual(cfg,guiCfg,required{k});
end
if ~license('test','Simulink'), disp('Stage H GUI/config checks OK (Simulink license unavailable).'); return; end

modelName=['stage_h_tmp_' char(java.util.UUID.randomUUID())];
modelName=matlab.lang.makeValidName(modelName);
modelFile=fullfile(root,'simulink',[modelName '.slx']);
cleanup=onCleanup(@()cleanupModel(modelName,modelFile));
mdl=buildD2DSimulinkModel('ModelName',modelName,'Config',cfg,'Open',false,'Save',true,'Overwrite',false);
assert(strcmp(mdl,modelName) && isfile(modelFile));
load_system(modelName);
ws=get_param(modelName,'ModelWorkspace'); modelCfg=evalin(ws,'d2dCfg');
for k=1:numel(required)
    assertFieldEqual(cfg,modelCfg,required{k});
end
blocks=find_system(modelName,'Type','Block','Name','BB-CDR PI Adaptation');
assert(~isempty(blocks),'stateful BB-CDR/PI/adaptation boundary missing');
disp('Stage H GUI/config and Simulink smoke checks OK');
end

function assertFieldEqual(a,b,path)
parts=strsplit(path,'.');
for k=1:numel(parts), a=a.(parts{k}); b=b.(parts{k}); end
assert(isequaln(a,b),['config mismatch: ' path]);
end

function cleanupModel(name,file)
% Simulink shutdown can block headless MATLAB; the isolated process owns this model.
if bdIsLoaded(name), set_param(name,'Dirty','off'); end
if isfile(file), try, delete(file); catch, end, end
end
