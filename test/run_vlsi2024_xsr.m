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
        cfg.model.appliedFfe=r.model.txPma.lane(1).ffe.tapMeta;
        cfg.model.appliedDac=r.model.txPma.lane(1).driver.dacMeta;
        resultRoot=fullfile(root,cfg.model.resultRoot); ensureDir(resultRoot);
        writeJson(cfg,fullfile(resultRoot,'config.json'));
        writeAssumptions(fullfile(resultRoot,'assumptions.md'));
        metrics=metricTable(r,cfg); writetable(metrics,fullfile(resultRoot,'baseline_metrics.csv'));
        [probes,probeManifest]=collectProbes(r.model,cfg); %#ok<ASGLU>
        save(fullfile(resultRoot,'baseline_probes.mat'),'probes','probeManifest','-v7');
        out=struct('mode',mode,'cfg',cfg,'result',r.result,'metrics',metrics,...
            'resultRoot',resultRoot,'probes',probes,'probeManifest',probeManifest);
    case 'loss_sweep'
        resultRoot=fullfile(root,cfg.model.resultRoot); ensureDir(resultRoot);
        rows=zeros(numel(cfg.channel.lossSweep_dB),3); ilRows=zeros(numel(cfg.channel.lossSweep_dB),6);
        for k=1:numel(cfg.channel.lossSweep_dB)
            loss=cfg.channel.lossSweep_dB(k); cfgk=cfg;
            cfgk.channel.lossAtRef_dB=loss; cfgk.channel.lossNyq_dB=loss;
            rk=runModel(cfgk); measured=verifyChannel(cfg.link.sps,loss,cfg.channel.poles,struct(...
                'mode','analytic_il','refFreq_GHz',cfg.channel.refFreq_GHz,'baud_GBd',cfg.link.baud_GBd,...
                'lossAtRef_dB',loss,'poles',cfg.channel.poles));
            if k==1, cfg=attachApplied(cfg,rk.model); end
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
    case {'static_checkpoint','static','milestone'}
        base=run_vlsi2024_xsr('baseline',nBits); cfg=base.cfg; resultRoot=base.resultRoot;
        loss=run_vlsi2024_xsr('loss_sweep',nBits); writetable(loss.channelIL,fullfile(resultRoot,'channel_il.csv'));
        cfg3=cfg; cfg3.txPma.lane.ffeMode='three_tap'; r3=runModel(cfg3);
        cfg6=cfg; cfg6.txPma.lane.ffeMode='six_tap'; cfg6.txPma.lane.ffeOffsets=cfg.txPma.lane.sixTapPreset.offsets;
        cfg6.txPma.lane.ffeCoeffs=cfg.txPma.lane.sixTapPreset.coeffs; r6=runModel(cfg6);
        cfg.model.appliedFfe=base.cfg.model.appliedFfe; cfg.model.appliedDac=base.cfg.model.appliedDac;
        cfg.model.appliedFfeThreeTap=r3.model.txPma.lane(1).ffe.tapMeta;
        cfg.model.appliedFfeSixTap=r6.model.txPma.lane(1).ffe.tapMeta;
        ffe=[metricVariant('three_tap',r3.result,cfg); metricVariant('six_tap',r6.result,cfg)];
        ffe.tap_count=[3;6]; ffe.coefficients=[string(mat2str(r3.model.txPma.lane(1).ffe.tapMeta.appliedCoefficients));...
            string(mat2str(r6.model.txPma.lane(1).ffe.tapMeta.appliedCoefficients))];
        ffe=movevars(ffe,{'tap_count','coefficients'},'Before',1);
        writetable(ffe,fullfile(resultRoot,'ffe_3_vs_6.csv'));
        cfgOff=cfg; cfgOff.rxPma.lane.enableAcPre=false; cfgOff.rxPma.lane.enableAcPost=false; roff=runModel(cfgOff);
        cfgOn=cfg; ron=runModel(cfgOn);
        grid=cfg.rxPma.lane.ctleGrid_dB(:); acRows=zeros(2+numel(grid),9);
        acRows(1,:)=acResultRow(0,cfgOff.rxPma.lane.ctleBoost_dB,roff,cfg);
        acRows(2,:)=acResultRow(1,cfgOn.rxPma.lane.ctleBoost_dB,ron,cfg);
        for k=1:numel(grid)
            cfgGrid=cfg; cfgGrid.rxPma.lane.ctleBoost_dB=grid(k); rg=runModel(cfgGrid);
            applied=rg.model.rxPma.lane(1).afe.ctle.appliedBoost_dB;
            assert(abs(applied-grid(k))<1e-12 && applied>=0 && applied<=6,'CTLE grid application failed.');
            acRows(k+2,:)=acResultRow(1,grid(k),rg,cfg,applied);
        end
        assert(abs(acRows(1,4)-acRows(2,4))>1e-6,'AC on/off response did not change.');
        assert(all(acRows(3:end,3)>=0 & acRows(3:end,3)<=6));
        ac=array2table(acRows,'VariableNames',{'ac_enabled','ctle_requested_dB','ctle_applied_dB',...
            'long_run_offset','errors','measured_bits','empirical_BER','seed','ber_upper_95'});
        writetable(ac,fullfile(resultRoot,'ac_ctle.csv'));
        summary=[summaryRow('baseline',base.result,cfg); summaryRow('ffe_3tap',r3.result,cfg); ...
            summaryRow('ffe_6tap',r6.result,cfg); summaryRow('ac_off',roff.result,cfg); summaryRow('ac_on',ron.result,cfg)];
        writetable(summary,fullfile(resultRoot,'static_regression_summary.csv'));
        fid=fopen(fullfile(resultRoot,'assumptions.md'),'a'); fprintf(fid,'\n- Static A-D checkpoint retains legacy oracle/reference-bit alignment; it is not the paper BB-CDR result.\n'); fclose(fid);
        writeJson(cfg,fullfile(resultRoot,'config.json'));
        out=struct('mode',mode,'cfg',cfg,'baseline',base,'loss',loss,'ffe',ffe,'acCtle',ac,...
            'summary',summary,'resultRoot',resultRoot);
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
upper=zeros(n,1); for k=1:n, upper(k)=binomialUpper95(r.result.errCnt(k),r.result.nMeasured(k)); end
metrics=table(lanes,r.result.errCnt(:),r.result.nMeasured(:),r.result.ber(:),repmat(cfg.link.seed,n,1),upper,...
    'VariableNames',{'lane','errors','measured_bits','empirical_BER','seed','ber_upper_95'});
end

function row=summaryRow(label,result,cfg)
errors=sum(result.errCnt); measured=sum(result.nMeasured); ber=errors/max(measured,1);
row=table(string(label),errors,measured,ber,cfg.link.seed,binomialUpper95(errors,measured),...
    'VariableNames',{'variant','errors','measured_bits','empirical_BER','seed','ber_upper_95'});
end

function row=metricVariant(label,result,cfg)
errors=sum(result.errCnt); measured=sum(result.nMeasured); ber=errors/max(measured,1);
row=table(string(label),errors,measured,ber,cfg.link.seed,binomialUpper95(errors,measured),...
    'VariableNames',{'variant','errors','measured_bits','empirical_BER','seed','ber_upper_95'});
end

function row=acResultRow(enabled,requested,r,cfg,applied)
if nargin<5, applied=r.model.rxPma.lane(1).afe.ctle.appliedBoost_dB; end
errors=sum(r.result.errCnt); measured=sum(r.result.nMeasured); ber=errors/max(measured,1);
offset=mean(r.model.rxPma.lane(1).afe.acPostOut(end/2:end));
row=[enabled requested applied offset errors measured ber cfg.link.seed binomialUpper95(errors,measured)];
end

function cfg=attachApplied(cfg,p)
cfg.model.appliedFfe=p.txPma.lane(1).ffe.tapMeta;
cfg.model.appliedDac=p.txPma.lane(1).driver.dacMeta;
end

function upper=binomialUpper95(errors,measured)
if measured<=0, upper=NaN;
elseif errors<=0, upper=3/measured;
elseif errors>=measured, upper=1;
else, upper=betaincinv(0.95,errors+1,measured-errors);
end
end

function [probes,manifest]=collectProbes(p,cfg)
limit=min(4096,cfg.link.nBits*cfg.link.sps);
lane=p.rxPma.lane(1); slicer=lane.slicer;
probes=struct();
probes.txPad=takeProbe(p.txPma.lane(1).driver.txPad,limit);
probes.channelOut=takeProbe(p.channel(1).out,limit);
probes.ctleOut=takeProbe(lane.afe.ctleOut,limit);
probes.slicerIn=takeProbe(slicer.in,limit);
probes.rxBits=lane.deserializer.rxBits;
probes.dataSamples=takeProbe(slicer.dataSamples,limit); probes.dataDecisions=slicer.dataDecisions;
probes.edgeSamples=takeProbe(slicer.edgeSamples,limit); probes.edgeDetectorOutput=slicer.edgeDetectorOutput;
probes.spareSamples=takeProbe(slicer.spareSamples,limit); probes.spareMonitorOutput=slicer.spareMonitorOutput;
probes.levelShiftedSamples=takeProbe(slicer.levelShiftedSamples,limit);
probes.quarterRateSamples=cellfun(@(v)takeProbe(v,limit),slicer.quarterRateSamples,'UniformOutput',false);
probes.levelShiftCodes=slicer.levelShiftCodes; probes.comparatorThresholds=slicer.comparatorThresholds;
probes.samplerRoleCounts=slicer.samplerRoleCounts;
manifest=struct('nLane',p.nLane,'nBits',cfg.link.nBits,'sampleLimit',limit,...
    'txPad',size(p.txPma.lane(1).driver.txPad),'channelOut',size(p.channel(1).out),...
    'ctleOut',size(lane.afe.ctleOut),'slicerIn',size(slicer.in),'dataSamples',size(slicer.dataSamples),...
    'edgeSamples',size(slicer.edgeSamples),'spareSamples',size(slicer.spareSamples),...
    'levelShiftedSamples',size(slicer.levelShiftedSamples),'rxBits',size(lane.deserializer.rxBits));
end

function y=takeProbe(x,limit)
if isempty(x), y=x; else, y=x(1:min(limit,numel(x))); end
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
