function cfg = loadD2DSharedConfig(modelName)
%LOADD2DSHAREDCONFIG Read config from loaded model, base, file, or defaults.
if nargin < 1 || isempty(modelName), modelName='D2D_PHY_SI_Simulink'; end
if license('test','Simulink') && bdIsLoaded(modelName)
    try
        ws=get_param(modelName,'ModelWorkspace'); cfg=evalin(ws,'d2dCfg'); return;
    catch
    end
end
if evalin('base','exist(''d2dCfg'',''var'')')
    cfg=evalin('base','d2dCfg'); return;
end
root=fileparts(fileparts(fileparts(mfilename('fullpath'))));
f=fullfile(root,'simulink','d2d_shared_config.mat');
if isfile(f)
    s=load(f,'cfg'); cfg=s.cfg; return;
end
cfg=phyConfig();
end
