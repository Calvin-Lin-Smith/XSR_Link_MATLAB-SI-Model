function [out,cfg] = run_vlsi2024_xsr(mode,varargin)
%RUN_VLSI2024_XSR Execute the isolated paper-profile behavioral runner.
if nargin<1 || isempty(mode), mode='baseline'; end
mode=lower(char(mode));
[nBits,nLane]=parseOptions(varargin);
root=fileparts(fileparts(mfilename('fullpath')));
if strcmp(mode,'debug_1lane'), nLane=1; end
cfg=phyConfig('vlsi2024_xsr'); cfg.link.nBits=nBits; cfg.phy.nLane=nLane;
switch mode
    case {'baseline','debug_1lane'}
        r=runModel(cfg);
        resultRoot=fullfile(root,cfg.model.resultRoot); ensureDir(resultRoot);
        writeJson(cfg,fullfile(resultRoot,'config.json'));
        writeAssumptions(fullfile(resultRoot,'assumptions.md'));
        metrics=metricTable(r,cfg); writetable(metrics,fullfile(resultRoot,'baseline_metrics.csv'));
        [probes,probeManifest]=collectProbes(r.model,cfg); %#ok<ASGLU>
        save(fullfile(resultRoot,'baseline_probes.mat'),'probes','probeManifest','-v7');
        out=struct('mode',mode,'cfg',cfg,'result',r.result,'metrics',metrics,...
            'resultRoot',resultRoot,'probes',probeManifest);
    case 'loss_sweep'
        resultRoot=fullfile(root,cfg.model.resultRoot); ensureDir(resultRoot);
        rows=zeros(numel(cfg.channel.lossSweep_dB),3); ilRows=zeros(numel(cfg.channel.lossSweep_dB),6);
        for k=1:numel(cfg.channel.lossSweep_dB)
            loss=cfg.channel.lossSweep_dB(k); cfgk=cfg;
            cfgk.channel.lossAtRef_dB=loss; cfgk.channel.lossNyq_dB=loss;
            rk=runModel(cfgk); measured=verifyChannel(cfg.link.sps,loss,cfg.channel.poles,struct(...
                'mode','analytic_il','refFreq_GHz',cfg.channel.refFreq_GHz,'baud_GBd',cfg.link.baud_GBd,...
                'lossAtRef_dB',loss,'poles',cfg.channel.poles));
            rows(k,:)=[loss rk.result.aggregateBer sum(rk.result.nMeasured)];
            ilRows(k,:)=[loss measured cfg.channel.refFreq_GHz cfg.link.baud_GBd measured-loss 0.03];
        end
        metrics=array2table(rows,'VariableNames',{'lossAtRef_dB','aggregateBer','measured_bits'});
        writetable(metrics,fullfile(resultRoot,'loss_sweep_metrics.csv'));
        il=array2table(ilRows,'VariableNames',{'requested_loss_dB','measured_loss_dB','referenceFrequency_GHz',...
            'baud_GBd','error_dB','tolerance_dB'});
        il.mode=repmat("analytic_il",height(il),1); il.unmodeledCrosstalk=repmat("true",height(il),1);
        writetable(il,fullfile(resultRoot,'channel_il_at_28GHz.csv'));
        response=il(:,{'referenceFrequency_GHz','baud_GBd','requested_loss_dB','measured_loss_dB','error_dB','tolerance_dB','mode','unmodeledCrosstalk'});
        response.Properties.VariableNames={'frequency_GHz','baud_GBd','requested_loss_dB','measured_loss_dB','error_dB','tolerance_dB','mode','unmodeledCrosstalk'};
        writetable(response,fullfile(resultRoot,'channel_response.csv'));
        writeJson(cfg,fullfile(resultRoot,'config.json'));
        out=struct('mode',mode,'cfg',cfg,'metrics',metrics,'channelIL',il,'resultRoot',resultRoot);
    otherwise
        error('run_vlsi2024_xsr:Mode','Unsupported mode: %s',mode);
end
end

function [nBits,nLane]=parseOptions(args)
nBits=2^18; nLane=8;
if isempty(args), return; end
if numel(args)==1 && isnumeric(args{1}), nBits=args{1};
elseif mod(numel(args),2)==0
    for k=1:2:numel(args)
        switch lower(char(args{k}))
            case 'nbits', nBits=args{k+1};
            otherwise, error('run_vlsi2024_xsr:Option','Unsupported option: %s',char(args{k}));
        end
    end
else
    error('run_vlsi2024_xsr:Option','Use an integer bit-count override.');
end
validateattributes(nBits,{'numeric'},{'scalar','integer','positive'});
end

function r=runModel(cfg)
p=D2DPHY('vlsi2024_xsr',cfg.phy.nLane); p.configure(cfg); r.result=p.run(); r.model=p;
end

function metrics=metricTable(r,cfg)
lanes=(1:numel(r.result.errCnt))'; n=numel(lanes);
metrics=table(lanes,r.result.errCnt(:),r.result.nMeasured(:),r.result.ber(:),repmat(cfg.link.seed,n,1),...
    'VariableNames',{'lane','errors','measured_bits','empirical_BER','seed'});
end

function [probes,manifest]=collectProbes(p,cfg)
limit=min(4096,cfg.link.nBits*cfg.link.sps);
probes=struct();
probes.txPad=p.txPma.lane(1).driver.txPad(1:min(limit,end));
probes.channelOut=p.channel(1).out(1:min(limit,end));
probes.ctleOut=p.rxPma.lane(1).afe.ctleOut(1:min(limit,end));
probes.slicerIn=p.rxPma.lane(1).slicer.in(1:min(limit,end));
probes.rxBits=p.rxPma.lane(1).deserializer.rxBits;
manifest=struct('nLane',p.nLane,'nBits',cfg.link.nBits,'sampleLimit',limit,...
    'txPad',size(p.txPma.lane(1).driver.txPad),'channelOut',size(p.channel(1).out),...
    'ctleOut',size(p.rxPma.lane(1).afe.ctleOut),'slicerIn',size(p.rxPma.lane(1).slicer.in),...
    'rxBits',size(p.rxPma.lane(1).deserializer.rxBits));
end

function writeJson(value,path)
fid=fopen(path,'w'); assert(fid>0,'Unable to write %s.',path);
fprintf(fid,'%s',jsonencode(value,'PrettyPrint',true)); fclose(fid);
end

function writeAssumptions(path)
fid=fopen(path,'w'); assert(fid>0,'Unable to write %s.',path);
fprintf(fid,['# VLSI2024 XSR Stage-A assumptions\n\n' ...
    '- This stage still executes the legacy oracle/reference-bit alignment internally; it is a static bootstrap result, not the paper BB-CDR result. The formal path becomes reference-free in Task/Stage E.\n' ...
    '- 112.5 Gb/s is the TX-eye baseline context, while the paper BER plot/text uses 112 Gb/s and headline/Table uses 113 Gb/s.\n' ...
    '- Finite simulation cannot prove the paper''s <1e-14/<1e-12 BER.\n' ...
    '- No real S-parameters, MIMO crosstalk, transistor circuits, or power prediction are present.\n']); fclose(fid);
end

function ensureDir(path)
if ~exist(path,'dir'), mkdir(path); end
end
