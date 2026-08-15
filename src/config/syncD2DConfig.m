function cfg = syncD2DConfig(cfg, modelName, saveShared)
%SYNCD2DCONFIG Publish one PHY config to MATLAB and Simulink workspaces.
if nargin < 1 || isempty(cfg), cfg=phyConfig(); end
if nargin < 2 || isempty(modelName), modelName='D2D_PHY_SI_Simulink'; end
if nargin < 3, saveShared=true; end
validateattributes(cfg,{'struct'},{'scalar'});
required={'link','rawPcs','txPma','rxPma','channel'};
for k=1:numel(required)
    if ~isfield(cfg,required{k}), error('syncD2DConfig:Field','Missing cfg.%s.',required{k}); end
end
assignin('base','d2dCfg',cfg);
if saveShared
    root=fileparts(fileparts(fileparts(mfilename('fullpath'))));
    save(fullfile(root,'simulink','d2d_shared_config.mat'),'cfg');
end
if license('test','Simulink') && bdIsLoaded(modelName)
    ws=get_param(modelName,'ModelWorkspace');
    assignin(ws,'d2dCfg',cfg);
    try
        set_param(modelName,'SimulationCommand','update');
    catch ex
        warning('syncD2DConfig:ModelUpdate','Config synchronized; model update deferred: %s',ex.message);
    end
end
end
