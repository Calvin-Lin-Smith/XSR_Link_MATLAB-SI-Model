function app = launchD2DWorkbench()
%LAUNCHD2DWORKBENCH Open the structured D2D PHY model GUI.
root=fileparts(fileparts(mfilename('fullpath')));
addpath(genpath(fullfile(root,'src'))); addpath(genpath(fullfile(root,'test')));
app=D2DWorkbench(root);
end
