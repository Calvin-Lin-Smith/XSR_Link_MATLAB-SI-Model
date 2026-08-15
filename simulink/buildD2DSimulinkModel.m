function model = buildD2DSimulinkModel(varargin)
%BUILDD2DSIMULINKMODEL Build a visual Simulink D2D PHY architecture.
%   model = buildD2DSimulinkModel() creates D2D_PHY_SI_Simulink.slx.
%   The existing MATLAB GUI and class model are not modified.
%
%   Name-value options:
%     'ModelName'  Simulink model name without .slx
%     'Open'       true/false, open the generated model
%     'Save'       true/false, save the generated model
root=fileparts(fileparts(mfilename('fullpath')));
modelName='D2D_PHY_SI_Simulink'; openModel=true; saveModel=true;
for k=1:2:numel(varargin)
    switch lower(varargin{k})
        case 'modelname', modelName=char(varargin{k+1});
        case 'open', openModel=logical(varargin{k+1});
        case 'save', saveModel=logical(varargin{k+1});
        otherwise, error('buildD2DSimulinkModel:Option','Unknown option %s.',varargin{k});
    end
end
if ~license('test','Simulink')
    error('buildD2DSimulinkModel:License','Simulink license is not available.');
end
addpath(genpath(fullfile(root,'src')));
cfg=loadD2DSharedConfig(modelName);
modelFile=fullfile(root,'simulink',[modelName '.slx']);
if bdIsLoaded(modelName), close_system(modelName,0); end
if isfile(modelFile), delete(modelFile); end
new_system(modelName); open_system(modelName);
assignin('base','d2dCfg',cfg);
assignin(get_param(modelName,'ModelWorkspace'),'d2dCfg',cfg);
set_param(modelName,'Location',[80 80 1500 850]);

% Top-level signal-flow architecture. Subsystems are intentionally separate
% so the generated diagram can be opened and refined block-by-block.
add_block('simulink/Ports & Subsystems/In1',[modelName '/TX Bits'],...
    'Position',[30 245 90 275],'Port','1');
add_block('simulink/Ports & Subsystems/Subsystem',[modelName '/Raw PCS'],...
    'Position',[130 205 290 315]);
add_block('simulink/Ports & Subsystems/Subsystem',[modelName '/TX PMA x8'],...
    'Position',[340 170 540 350]);
add_block('simulink/Ports & Subsystems/Subsystem',[modelName '/Die-to-Die Channel x8'],...
    'Position',[590 170 820 350]);
add_block('simulink/Ports & Subsystems/Subsystem',[modelName '/RX PMA x8'],...
    'Position',[870 170 1070 350]);
add_block('simulink/Ports & Subsystems/Subsystem',[modelName '/BER_Results'],...
    'Position',[1120 205 1280 315]);
add_block('simulink/Ports & Subsystems/Out1',[modelName '/RX Bits'],...
    'Position',[1320 245 1380 275],'Port','1');
add_line(modelName,'TX Bits/1','Raw PCS/1');
add_line(modelName,'Raw PCS/1','TX PMA x8/1');
add_line(modelName,'TX PMA x8/1','Die-to-Die Channel x8/1');
add_line(modelName,'Die-to-Die Channel x8/1','RX PMA x8/1');
add_line(modelName,'RX PMA x8/1','BER_Results/1');
add_line(modelName,'BER_Results/1','RX Bits/1');

% Annotate the model with the implementation contract.
ann=[sprintf('D2D PHY visual model\n') ...
    'Generated from existing src/dsp and src class model\n' ...
    'Open subsystems to inspect x8 lanes and white-box probe taps'];
add_block('built-in/Note',[modelName '/Architecture Note'],'Position',[450 30 920 85],'Name',ann);

buildRawPcs([modelName '/Raw PCS']);
buildTxPma([modelName '/TX PMA x8']);
buildChannel([modelName '/Die-to-Die Channel x8']);
buildRxPma([modelName '/RX PMA x8']);
buildResults([modelName '/BER_Results']);
set_param(modelName,'SimulationCommand','update');
if saveModel, save_system(modelName,modelFile); end
if ~openModel, close_system(modelName,0); end
model=modelName;
end

function setupSubsystem(path,nIn,nOut)
Simulink.SubSystem.deleteContents(path);
for k=1:nIn, add_block('simulink/Ports & Subsystems/In1',sprintf('%s/In%d',path,k),'Position',[25 50+70*k 55 70+70*k],'Port',num2str(k)); end
for k=1:nOut, add_block('simulink/Ports & Subsystems/Out1',sprintf('%s/Out%d',path,k),'Position',[650 50+70*k 680 70+70*k],'Port',num2str(k)); end
end

function buildRawPcs(path)
setupSubsystem(path,1,1);
add_block('simulink/User-Defined Functions/Interpreted MATLAB Function',[path '/dspPrbs_Pattern_Source'],...
    'Position',[95 90 260 150],'MATLABFcn','dspMap(u,d2dCfg.link.modulation)');
add_block('simulink/Signal Routing/Goto',[path '/rxBits_probe'],'Position',[350 95 450 125],'GotoTag','rawPcs_rxBits');
add_line(path,'In1/1','dspPrbs_Pattern_Source/1');
add_line(path,'dspPrbs_Pattern_Source/1','rxBits_probe/1');
add_line(path,'dspPrbs_Pattern_Source/1','Out1/1');
end

function buildTxPma(path)
setupSubsystem(path,1,1);
add_block('simulink/Signal Routing/Demux',[path '/Lane Demux'],'Position',[75 55 80 425],'Outputs','8');
add_block('simulink/Signal Routing/Mux',[path '/Lane Mux'],'Position',[500 55 505 425],'Inputs','8');
add_block('simulink/Signal Routing/Goto',[path '/TX pad probe'],'Position',[535 455 635 485],'GotoTag','txPad_lane1');
add_line(path,'In1/1','Lane Demux/1','autorouting','on');
for j=1:8
    y=35+(j-1)*48; name=sprintf('TX Lane %d',j);
    add_block('simulink/Ports & Subsystems/Subsystem',[path '/' name],'Position',[145 y 365 y+34]);
    buildLane([path '/' name],'tx',j);
    add_line(path,sprintf('Lane Demux/%d',j),sprintf('%s/1',name),'autorouting','on');
    add_line(path,sprintf('%s/1',name),sprintf('Lane Mux/%d',j),'autorouting','on');
end
add_line(path,'TX Lane 1/1','TX pad probe/1','autorouting','on');
add_line(path,'Lane Mux/1','Out1/1','autorouting','on');
end

function buildChannel(path)
setupSubsystem(path,1,1);
add_block('simulink/Signal Routing/Demux',[path '/Channel Demux'],'Position',[75 55 80 425],'Outputs','8');
add_block('simulink/Signal Routing/Mux',[path '/Channel Mux'],'Position',[500 55 505 425],'Inputs','8');
add_line(path,'In1/1','Channel Demux/1','autorouting','on');
for j=1:8
    y=35+(j-1)*48; name=sprintf('Channel %d',j);
    add_block('simulink/Ports & Subsystems/Subsystem',[path '/' name],'Position',[145 y 365 y+34]);
    setupSubsystem([path '/' name],1,1);
    add_block('simulink/User-Defined Functions/Interpreted MATLAB Function',[path '/' name '/dspChannel'],...
        'Position',[80 105 260 145],'MATLABFcn',['dspChannel(u,d2dCfg.link.sps,' ...
        'd2dCfg.channel.lossNyq_dB,d2dCfg.channel.poles)']);
    add_line([path '/' name],'In1/1','dspChannel/1'); add_line([path '/' name],'dspChannel/1','Out1/1');
    add_line(path,sprintf('Channel Demux/%d',j),sprintf('%s/1',name),'autorouting','on');
    add_line(path,sprintf('%s/1',name),sprintf('Channel Mux/%d',j),'autorouting','on');
end
add_line(path,'Channel Mux/1','Out1/1','autorouting','on');
end

function buildRxPma(path)
setupSubsystem(path,1,1);
add_block('simulink/Signal Routing/Demux',[path '/Lane Demux'],'Position',[75 55 80 425],'Outputs','8');
add_block('simulink/Signal Routing/Mux',[path '/Lane Mux'],'Position',[500 55 505 425],'Inputs','8');
add_line(path,'In1/1','Lane Demux/1','autorouting','on');
for j=1:8
    y=35+(j-1)*48; name=sprintf('RX Lane %d',j);
    add_block('simulink/Ports & Subsystems/Subsystem',[path '/' name],'Position',[145 y 365 y+34]);
    buildLane([path '/' name],'rx',j);
    add_line(path,sprintf('Lane Demux/%d',j),sprintf('%s/1',name),'autorouting','on');
    add_line(path,sprintf('%s/1',name),sprintf('Lane Mux/%d',j),'autorouting','on');
end
add_line(path,'Lane Mux/1','Out1/1','autorouting','on');
end

function buildLane(path,direction,index)
setupSubsystem(path,1,1);
if strcmp(direction,'tx')
    blocks={'FFE','Serializer','Driver'};
    code={['dspFfe(u,d2dCfg.txPma.lane.txEqMain,d2dCfg.txPma.lane.txEqPre,' ...
        'd2dCfg.txPma.lane.txEqPost,d2dCfg.txPma.lane.ffeNormalize)'],...
        'repelem(u,d2dCfg.link.sps)',...
        'd2dCfg.txPma.lane.amplitude*u'};
else
    blocks={'AFE_TERM','CTLE','Sampler','Slicer','Deserializer'};
    code={'d2dCfg.rxPma.lane.termGain*u',...
        ['dspCtle(u,d2dCfg.link.sps,d2dCfg.rxPma.lane.ctleBoost_dB,' ...
        'd2dCfg.rxPma.lane.ctleFz)'],...
        'dspSample(u,floor(d2dCfg.link.sps/2),0,d2dCfg.link.sps,0)',...
        'dspSlice(u,d2dCfg.link.modulation)','u'};
end
last='In1/1';
for k=1:numel(blocks)
    b=blocks{k}; safe=matlab.lang.makeValidName(b); full=[path '/' safe];
    add_block('simulink/User-Defined Functions/Interpreted MATLAB Function',full,'Position',[80+(k-1)*125 45 180+(k-1)*125 80],...
        'MATLABFcn',code{k});
    add_line(path,last,[safe '/1'],'autorouting','on'); last=[safe '/1'];
end
add_line(path,last,'Out1/1','autorouting','on');
add_block('simulink/Signal Routing/Goto',[path '/white-box probe'],'Position',[80 105 180 135],...
    'GotoTag',sprintf('%sLane%d_probe',direction,index));
add_line(path,last,'white-box probe/1','autorouting','on');
end

function buildResults(path)
setupSubsystem(path,1,1);
add_block('simulink/User-Defined Functions/Interpreted MATLAB Function',[path '/BER calculator'],...
    'Position',[130 80 300 120],'MATLABFcn','mean(u~=0)');
add_block('simulink/Sinks/To Workspace',[path '/BER result'],'Position',[380 70 510 110],...
    'VariableName','simulinkBer','SaveFormat','Array');
add_line(path,'In1/1','BER calculator/1'); add_line(path,'BER calculator/1','BER result/1'); add_line(path,'BER calculator/1','Out1/1');
end

function setMATLABCode(block,code)
try
    set_param(block,'Script',sprintf(strrep(code,'\n','\n')));
catch
    % Script property differs between MATLAB releases; the block remains
    % visible and the referenced src function is documented in its label.
end
end
