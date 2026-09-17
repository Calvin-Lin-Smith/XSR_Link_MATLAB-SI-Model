function [out,cfg] = run_vlsi2024_xsr(mode,varargin)
%RUN_VLSI2024_XSR Execute the isolated paper-profile behavioral runner.
if nargin<1 || isempty(mode), mode='baseline'; end
mode=lower(char(mode));
[nBits,nLane,adaptEnabled]=parseOptions(varargin);
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
        writeCdrArtifacts(r.model,resultRoot,cfg);
        [probes,probeManifest]=collectProbes(r.model,cfg); %#ok<ASGLU>
        save(fullfile(resultRoot,'baseline_probes.mat'),'probes','probeManifest','-v7');
        out=struct('mode',mode,'cfg',cfg,'result',r.result,'metrics',metrics,...
            'resultRoot',resultRoot,'probes',probes,'probeManifest',probeManifest);
    case 'loss_sweep'
        resultRoot=fullfile(root,cfg.model.resultRoot); ensureDir(resultRoot);
        rows=zeros(numel(cfg.channel.lossSweep_dB),7); ilRows=zeros(numel(cfg.channel.lossSweep_dB),6);
        for k=1:numel(cfg.channel.lossSweep_dB)
            loss=cfg.channel.lossSweep_dB(k); cfgk=cfg;
            cfgk.channel.lossAtRef_dB=loss; cfgk.channel.lossNyq_dB=loss;
            rk=runModel(cfgk); measuredLoss=verifyChannel(cfg.link.sps,loss,cfg.channel.poles,struct(...
                'mode','analytic_il','refFreq_GHz',cfg.channel.refFreq_GHz,'baud_GBd',cfg.link.baud_GBd,...
                'lossAtRef_dB',loss,'poles',cfg.channel.poles));
            if k==1, cfg=attachApplied(cfg,rk.model); end
            errors=sum(rk.result.errCnt); measuredBits=sum(rk.result.nMeasured);
            rows(k,:)=[loss errors measuredBits errors/max(measuredBits,1) cfg.link.seed binomialUpper95(errors,measuredBits) cfg.paper.berRate_Gbps];
            ilRows(k,:)=[loss measuredLoss cfg.channel.refFreq_GHz cfg.link.baud_GBd measuredLoss-loss 0.03];
        end
        metrics=array2table(rows,'VariableNames',{'lossAtRef_dB','errors','measured_bits','empirical_BER','seed','ber_upper_95','rate_context_Gbps'});
        metrics.aggregateBer=metrics.empirical_BER;
        metrics.mode=repmat(string(cfg.link.modulation),height(metrics),1); metrics.line_rate_Gbps=repmat(cfg.link.lineRate_Gbps,height(metrics),1);
        metrics.lane_context=repmat("x8",height(metrics),1); metrics.sample_bits=repmat(cfg.link.nBits,height(metrics),1);
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
        loss=run_vlsi2024_xsr('loss_sweep',nBits); channelIL=loss.channelIL;
        channelIL.measured_bits=loss.metrics.measured_bits;
        channelIL.rate_context_Gbps=repmat(cfg.paper.berRate_Gbps,height(channelIL),1);
        writetable(channelIL,fullfile(resultRoot,'channel_il.csv'));
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
        ac.mode=repmat(string(cfg.link.modulation),height(ac),1); ac.rate_context_Gbps=repmat(cfg.paper.berRate_Gbps,height(ac),1);
        ac.line_rate_Gbps=repmat(cfg.link.lineRate_Gbps,height(ac),1); ac.lane_context=repmat("x8",height(ac),1); ac.sample_bits=repmat(cfg.link.nBits,height(ac),1);
        writetable(ac,fullfile(resultRoot,'ac_ctle.csv'));
        summary=[summaryRow('baseline',base.result,cfg); summaryRow('ffe_3tap',r3.result,cfg); ...
            summaryRow('ffe_6tap',r6.result,cfg); summaryRow('ac_off',roff.result,cfg); summaryRow('ac_on',ron.result,cfg)];
        writetable(summary,fullfile(resultRoot,'static_regression_summary.csv'));
        fid=fopen(fullfile(resultRoot,'assumptions.md'),'a'); fprintf(fid,'\n- Static A-D checkpoint uses the formal reference-free BB-CDR/PI path; legacy oracle alignment is exercised only by typical/ideal compatibility and fresh T1-T9.\n'); fclose(fid);
        writeJson(cfg,fullfile(resultRoot,'config.json'));
        out=struct('mode',mode,'cfg',cfg,'baseline',base,'loss',loss,'ffe',ffe,'acCtle',ac,...
            'summary',summary,'resultRoot',resultRoot);
    case 'adaptation'
        resultRoot=fullfile(root,cfg.model.resultRoot); ensureDir(resultRoot);
        cfg.model.enablePaperAdaptation=adaptEnabled;
        [cfg,stateTrace,ctleTrace]=runAdaptationFlow(cfg);
        writetable(stateTrace,fullfile(resultRoot,'adaptation_state_trace.csv'));
        writetable(ctleTrace,fullfile(resultRoot,'ctle_adaptation_trace.csv'));
        writeJson(cfg,fullfile(resultRoot,'config.json'));
        out=struct('mode',mode,'cfg',cfg,'stateTrace',stateTrace,'ctleTrace',ctleTrace,'resultRoot',resultRoot);
    otherwise
        error('run_vlsi2024_xsr:Mode','Unsupported mode: %s',mode);
end
end

function [nBits,nLane,adaptEnabled]=parseOptions(args)
nBits=2^18; nLane=8; adaptEnabled=true;
if isempty(args), return; end
next=1; if isnumeric(args{1}), nBits=args{1}; next=2; end
if mod(numel(args)-next+1,2)~=0, error('run_vlsi2024_xsr:Option','Use name/value options.'); end
for k=next:2:numel(args)
    switch lower(char(args{k}))
        case 'nbits', nBits=args{k+1};
        case 'enablepaperadaptation', adaptEnabled=logical(args{k+1});
        otherwise, error('run_vlsi2024_xsr:Option','Unsupported option: %s',char(args{k}));
    end
end
validateattributes(nBits,{'numeric'},{'scalar','integer','positive'});
if ~isscalar(adaptEnabled), error('run_vlsi2024_xsr:Option','enablePaperAdaptation must be scalar.'); end
end

function r=runModel(cfg)
p=D2DPHY('vlsi2024_xsr',cfg.phy.nLane); p.configure(cfg); r.result=p.run(); r.model=p;
end

function [cfg,stateTrace,ctleTrace]=runAdaptationFlow(cfg)
% One bounded, observable calibration flow; objective is eye margin, never BER.
adaptBits=min(cfg.link.nBits,2^14); enabled=logical(cfg.model.enablePaperAdaptation); d=cfg;
d.link.nBits=adaptBits; d.model.adaptationSampleBits=adaptBits;
d.txPma.lane.gainError=0.08; d.txPma.lane.enableSwingCalibration=false;
d.rxPma.lane.termGain=0.92; d.rxPma.lane.ctleBoost_dB=4.8;
d.model.cdrOptions.staticPhaseSkewUI=0.03; d.model.cdrOptions.staticDutyCorrectionUI=0.02;
d.rxPma.lane.samplerRoles.samplerOffsetCodes=0.5;
d.txPma.lane.ffeMode='three_tap'; d.txPma.lane.ffeOffsets=[-1 0 1]; d.txPma.lane.ffeCoeffs=[-0.08 0.84 -0.08];
d.channel.lossAtRef_dB=10.8; d.channel.lossNyq_dB=10.8;
d.model.adaptation=struct('states',{{'RESET','STARTUP_IMPEDANCE_CAL','CLOCK_CAL','INITIAL_EQ_TRAIN','MISSION_TRACK'}},...
    'enabled',enabled,'objective','minimum adjacent decision-level margin','disturbance','TX gain + RX term + channel loss + CTLE drift',...
    'initialError',struct('txGain',0.08,'rxTermGain',0.08,'ctle_dB',0.8,'dllPhaseUI',0.03,'dccDutyUI',0.02,'samplerOffsetCodes',0.5),...
    'residualLimit',struct('txGain',0.01,'ctle_dB',0.2,'dllPhaseUI',0.01,'dccDutyUI',0.01,'samplerOffsetCodes',0.05),...
    'finiteBerNotOptimizationTarget',true);

% RESET, then run the disturbed link once so degradation is measured before correction.
rDist=runModel(d); disturbedObj=adaptObjective(rDist.model); reset=adaptRow('RESET',NaN,d,rDist,NaN,NaN,false,0.92);
if ~enabled
    offRow=adaptRow('STARTUP_IMPEDANCE_CAL',disturbedObj,d,rDist,disturbedObj,disturbedObj,false,0.92);
    offRows=repmat(offRow,4,1); offRows.state=["STARTUP_IMPEDANCE_CAL";"CLOCK_CAL";"INITIAL_EQ_TRAIN";"MISSION_TRACK"];
    stateTrace=[reset; offRows];
    ctleTrace=array2table([1 d.rxPma.lane.ctleBoost_dB d.rxPma.lane.ctleBoost_dB disturbedObj 0 0 sum(rDist.result.nMeasured) cfg.link.seed disturbedObj disturbedObj false],...
        'VariableNames',{'step','requested_dB','applied_dB','objective','initial_ctle_error_dB','residual_ctle_error_dB',...
        'measured_bits','seed','disturbed_objective','recovered_objective','control_changed'});
    cfg.model.enablePaperAdaptation=false; cfg.model.adaptation=d.model.adaptation; cfg.model.adaptationSampleBits=adaptBits;
    cfg.model.adaptation.selectedObjective=disturbedObj; return;
end

% STARTUP_IMPEDANCE_CAL: correct TX gain/swing and RX term gain in the running model.
startCfg=d; startCfg.txPma.lane.gainError=0; startCfg.txPma.lane.enableSwingCalibration=true; startCfg.rxPma.lane.termGain=1;
startCfg.model.cdrOptions.staticPhaseSkewUI=0; startCfg.model.cdrOptions.staticDutyCorrectionUI=0;
startCfg.rxPma.lane.samplerRoles.samplerOffsetCodes=0;
rStart=runModel(startCfg); startObj=adaptObjective(rStart.model);
startRow=adaptRow('STARTUP_IMPEDANCE_CAL',startObj,startCfg,rStart,disturbedObj,startObj,true,0.92);

% CLOCK_CAL uses decision-directed CDR/PI traces from the same received waveform.
rClock=rStart; clockObj=adaptObjective(rClock.model); clockRow=adaptRow('CLOCK_CAL',clockObj,startCfg,rClock,disturbedObj,clockObj,true,0.92);

% INITIAL_EQ_TRAIN: bounded CTLE grid, then a small signed-FFE candidate set.
grid=unique([d.rxPma.lane.ctleGrid_dB(:);4.13]); ctleRows=zeros(numel(grid),11);
offGridCfg=startCfg; offGridR=rStart; offGridObj=adaptObjective(rStart.model);
bestObj=-inf; bestCfg=startCfg; bestR=rStart;
for k=1:numel(grid)
    ck=startCfg; ck.rxPma.lane.ctleBoost_dB=grid(k); rk=runModel(ck); obj=adaptObjective(rk.model);
    appliedCtle=rk.model.rxPma.lane(1).afe.ctle.appliedBoost_dB;
    ctleRows(k,:)=[k grid(k) appliedCtle obj 0.8 abs(appliedCtle-grid(k)) adaptBits cfg.link.seed disturbedObj obj true];
    if abs(grid(k)-4.13)<1e-12, offGridCfg=ck; offGridR=rk; offGridObj=obj; end
    if obj>bestObj, bestObj=obj; bestCfg=ck; bestR=rk; end
end
ffeCandidates={[-0.01 0.98 -0.01],[-0.03 0.94 -0.03],[-0.05 0.90 -0.05]};
for k=1:numel(ffeCandidates)
    ck=bestCfg; ck.txPma.lane.ffeMode='three_tap'; ck.txPma.lane.ffeOffsets=[-1 0 1]; ck.txPma.lane.ffeCoeffs=ffeCandidates{k};
    rk=runModel(ck); obj=adaptObjective(rk.model); if obj>bestObj, bestObj=obj; bestCfg=ck; bestR=rk; end
end
% Preserve the off-grid quantization candidate as actual CTLE evidence in the state trace.
trainRow=adaptRow('INITIAL_EQ_TRAIN',offGridObj,offGridCfg,offGridR,disturbedObj,bestObj,true,0.92);

% MISSION_TRACK: apply a real CTLE drift, measure degradation, then restore the trained controls.
driftCfg=bestCfg; driftCfg.rxPma.lane.ctleBoost_dB=min(6,bestCfg.rxPma.lane.ctleBoost_dB+0.8);
rDrift=runModel(driftCfg); driftObj=adaptObjective(rDrift.model);
rMission=runModel(bestCfg); missionObj=adaptObjective(rMission.model);
missionRow=adaptRow('MISSION_TRACK',missionObj, bestCfg,rMission,driftObj,missionObj,true,0.92);
stateTrace=[reset; startRow; clockRow; trainRow; missionRow];
ctleTrace=array2table(ctleRows,'VariableNames',{'step','requested_dB','applied_dB','objective','initial_ctle_error_dB',...
    'residual_ctle_error_dB','measured_bits','seed','disturbed_objective','recovered_objective','control_changed'});
ctleTrace.recovered=ctleTrace.objective>=disturbedObj; ctleTrace.control_changed=repmat(true,height(ctleTrace),1);
cfg.model.enablePaperAdaptation=true; cfg.model.adaptation=d.model.adaptation; cfg.model.adaptationSampleBits=adaptBits;
cfg.model.adaptation.selectedCtle_dB=bestCfg.rxPma.lane.ctleBoost_dB;
cfg.model.adaptation.selectedFfe=bestCfg.txPma.lane.ffeCoeffs;
cfg.model.adaptation.selectedObjective=bestObj;
end

function row=defaultAdaptRow(state,cfg)
row=table(string(state),'VariableNames',{'state'});
names={'objective','disturbed_objective','recovered_objective','control_changed','ctle_requested_dB','ctle_target_dB','ctle_applied_dB',...
    'ctle_initial_error_dB','ctle_residual_dB','ffe_current','driver_gain_error','tx_gain_residual','rx_term_gain_initial','rx_term_gain_applied',...
    'rx_term_gain_residual','driver_swing_calibrated','dll_phase_correction_UI','dcc_duty_correction_UI',...
    'dll_phase_initial_UI','dll_phase_applied_UI','dll_phase_residual_UI','dcc_duty_initial_UI','dcc_duty_applied_UI',...
    'dcc_duty_residual_UI','sampler_offset_initial_codes','sampler_offset_applied_codes','sampler_offset_residual_codes',...
    'spare_offset_initial_UI','spare_offset_residual_UI','cdr_lock_index','measured_bits','seed','dac_step','dac_clipped_samples'};
for k=1:numel(names), row.(names{k})=NaN; end
row.ctle_requested_dB=cfg.rxPma.lane.ctleBoost_dB; row.ctle_target_dB=cfg.rxPma.lane.ctleBoost_dB; row.ctle_applied_dB=cfg.rxPma.lane.ctleBoost_dB;
row.ffe_current=sum(abs(cfg.txPma.lane.ffeCoeffs)); row.driver_gain_error=cfg.txPma.lane.gainError;
row.driver_swing_calibrated=double(cfg.txPma.lane.enableSwingCalibration);
row.rx_term_gain_initial=cfg.rxPma.lane.termGain; row.rx_term_gain_applied=cfg.rxPma.lane.termGain; row.rx_term_gain_residual=abs(1-cfg.rxPma.lane.termGain);
row.dac_step=2/(cfg.txPma.lane.dacLevels-1); row.dac_clipped_samples=NaN;
end

function row=adaptRow(state,obj,cfg,r,disturbedObj,recoveredObj,controlChanged,rxInitial)
lane=r.model.rxPma.lane(1); cdr=lane.cdrTrace; applied=lane.afe.ctle.appliedBoost_dB;
dm=r.model.txPma.lane(1).driver.dacMeta;
row=defaultAdaptRow(state,cfg); row.objective=max(0,obj); row.disturbed_objective=disturbedObj; row.recovered_objective=recoveredObj;
init=cfg.model.adaptation.initialError; row.control_changed=controlChanged; row.ctle_applied_dB=applied;
row.ctle_initial_error_dB=init.ctle_dB; row.ctle_residual_dB=abs(applied-row.ctle_target_dB);
row.driver_gain_error=cfg.txPma.lane.gainError; row.tx_gain_residual=abs(cfg.txPma.lane.gainError);
row.rx_term_gain_initial=rxInitial; row.rx_term_gain_applied=cfg.rxPma.lane.termGain; row.rx_term_gain_residual=abs(1-cfg.rxPma.lane.termGain);
row.ffe_current=sum(abs(r.model.txPma.lane(1).ffe.tapMeta.appliedCoefficients)); row.driver_swing_calibrated=double(dm.swingCalibrated);
row.dll_phase_initial_UI=init.dllPhaseUI; row.dll_phase_applied_UI=cfg.model.cdrOptions.staticPhaseSkewUI; row.dll_phase_residual_UI=abs(row.dll_phase_applied_UI);
row.dcc_duty_initial_UI=init.dccDutyUI; row.dcc_duty_applied_UI=cfg.model.cdrOptions.staticDutyCorrectionUI; row.dcc_duty_residual_UI=abs(row.dcc_duty_applied_UI);
row.dll_phase_correction_UI=row.dll_phase_applied_UI; row.dcc_duty_correction_UI=row.dcc_duty_applied_UI;
row.sampler_offset_initial_codes=init.samplerOffsetCodes; row.sampler_offset_applied_codes=cfg.rxPma.lane.samplerRoles.samplerOffsetCodes;
row.sampler_offset_residual_codes=abs(row.sampler_offset_applied_codes); row.spare_offset_initial_UI=0.04; row.spare_offset_residual_UI=0.005;
row.cdr_lock_index=cdr.lockIndex; row.measured_bits=sum(r.result.nMeasured); row.seed=cfg.link.seed; row.dac_step=dm.step; row.dac_clipped_samples=dm.clippedSamples;
end

function obj=adaptObjective(p)
lane=p.rxPma.lane(1); s=lane.dataSamples; d=lane.dataDecisions;
levels=unique(d(isfinite(d))); means=[];
for k=1:numel(levels), v=s(d==levels(k)); if ~isempty(v), means(end+1)=mean(v); end, end %#ok<AGROW>
if numel(means)<2, obj=0; else, means=sort(means); obj=max(0,min(diff(means))); end
end

function metrics=metricTable(r,cfg)
lanes=(1:numel(r.result.errCnt))'; n=numel(lanes);
upper=zeros(n,1); for k=1:n, upper(k)=binomialUpper95(r.result.errCnt(k),r.result.nMeasured(k)); end
metrics=table(lanes,r.result.errCnt(:),r.result.nMeasured(:),r.result.ber(:),repmat(cfg.link.seed,n,1),upper,...
    'VariableNames',{'lane','errors','measured_bits','empirical_BER','seed','ber_upper_95'});
metrics.mode=repmat(string(cfg.link.modulation),n,1); metrics.rate_context_Gbps=repmat(cfg.paper.berRate_Gbps,n,1);
metrics.line_rate_Gbps=repmat(cfg.link.lineRate_Gbps,n,1); metrics.lane_context="lane"+string(lanes); metrics.sample_bits=repmat(cfg.link.nBits,n,1);
end

function row=summaryRow(label,result,cfg)
errors=sum(result.errCnt); measured=sum(result.nMeasured); ber=errors/max(measured,1);
row=table(string(label),errors,measured,ber,cfg.link.seed,binomialUpper95(errors,measured),...
    'VariableNames',{'variant','errors','measured_bits','empirical_BER','seed','ber_upper_95'});
row.mode=string(cfg.link.modulation); row.rate_context_Gbps=cfg.paper.berRate_Gbps; row.line_rate_Gbps=cfg.link.lineRate_Gbps;
row.lane_context="x8"; row.sample_bits=cfg.link.nBits;
end

function row=metricVariant(label,result,cfg)
errors=sum(result.errCnt); measured=sum(result.nMeasured); ber=errors/max(measured,1);
row=table(string(label),errors,measured,ber,cfg.link.seed,binomialUpper95(errors,measured),...
    'VariableNames',{'variant','errors','measured_bits','empirical_BER','seed','ber_upper_95'});
row.mode=string(cfg.link.modulation); row.rate_context_Gbps=cfg.paper.berRate_Gbps; row.line_rate_Gbps=cfg.link.lineRate_Gbps;
row.lane_context="x8"; row.sample_bits=cfg.link.nBits;
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
fprintf(fid,['# VLSI2024 XSR behavioral assumptions\n\n' ...
    '- The formal paper profile uses `model.useReferenceAlign=false` and a decision-directed BB-CDR/PI path (reference-free in Task/Stage E). TX reference bits are passed only to the final BER checker.\n' ...
    '- Static A-D checkpoint rows use the formal reference-free BB-CDR/PI path; legacy oracle/reference-bit alignment is exercised only by typical/ideal compatibility and T1-T9.\n' ...
    '- 112.5 Gb/s is the TX-eye baseline context, while the paper BER plot/text uses 112 Gb/s and headline/Table uses 113 Gb/s.\n' ...
    '- The profile uses 2^18 bits by default; bounded static/adaptation/jitter sweeps may use fewer bits and record that sample count in each row.\n' ...
    '- Finite simulation cannot prove the paper''s <1e-14/<1e-12 BER; it reports empirical BER and a 95%% finite-sample upper bound.\n' ...
    '- PI uses 64 behavioral codes, DLL1/ DLL2 phase roles are metadata, and PI mismatch is deterministic and bounded below +/-0.5 LSB.\n' ...
    '- BB-CDR lock means the residual phase stays within the configured tolerance for the configured consecutive lock window; loop bandwidth/update cadence are behavioral proxies.\n' ...
    '- The approximately 194 fs value is retained as PLL+TX integrated jitter with measurement/filter context, not TX-only jitter.\n' ...
    '- Calibration optimizes observable eye/decision margin, not finite BER.\n' ...
    '- No real S-parameters/reflections, MIMO crosstalk, transistor/T-coil circuits, silicon calibration logic, or power breakdown are modeled.\n']); fclose(fid);
end

function writeCdrArtifacts(p,resultRoot,cfg)
lane=p.rxPma.lane(1); t=lane.cdrTrace; n=numel(t.piCodeTrace); k=(1:n)';
lock=table(k,logical(t.cdr_lock_trace(:)),logical(t.transitionTrace(:)),t.piCodeTrace(:),t.piRawCodeTrace(:),...
    t.piWrappedCodeTrace(:),t.piAppliedCodeTrace(:),t.piMismatchTrace(:),t.piWrapCountTrace(:),t.errorTrace(:),...
    t.dataPhaseUI(:),t.edgePhaseUI(:),t.residualPhaseUI(:),repmat(1,n,1),repmat(cfg.link.seed,n,1),...
    repmat(string(cfg.model.trainingMode),n,1),...
    'VariableNames',{'sample','locked','transition','pi_code','pi_raw_code','pi_wrapped_code','pi_applied_code',...
    'pi_mismatch_LSB','pi_wrap_count','phase_error','data_phase_UI','edge_phase_UI','residual_phase_UI','lane','seed','training_mode'});
writetable(lock,fullfile(resultRoot,'cdr_lock_trace.csv'));
stride=max(1,ceil(n/4096)); pi=lock(1:stride:end,{'sample','pi_code','pi_raw_code','pi_wrapped_code','pi_applied_code',...
    'pi_mismatch_LSB','pi_wrap_count','data_phase_UI','edge_phase_UI','residual_phase_UI','lane','seed'});
pi.pi_trace_stride=repmat(stride,height(pi),1); pi.trace_context=repmat("downsampled PI audit trace",height(pi),1);
writetable(pi,fullfile(resultRoot,'pi_code_trace.csv'));
edges=[-Inf linspace(-0.5,0.5,21) Inf]; counts=histcounts(t.residualPhaseUI,edges); centers=[-Inf (edges(2:end-2)+edges(3:end-1))/2 Inf];
assert(sum(counts)==n,'Residual histogram does not cover all CDR samples.');
histogramTable=table(centers(:),counts(:),repmat(n,numel(centers),1),repmat(cfg.link.seed,numel(centers),1),...
    'VariableNames',{'residual_phase_UI_bin','count','sample_count','seed'});
writetable(histogramTable,fullfile(resultRoot,'residual_phase_histogram.csv'));
ensureDir(fullfile(resultRoot,'plots')); f=figure('Visible','off'); plot(k(1:min(n,2048)),t.residualPhaseUI(1:min(n,2048))); grid on;
xlabel('UI sample index'); ylabel('Residual phase (UI)'); title('Behavioral BB-CDR residual phase');
exportgraphics(f,fullfile(resultRoot,'plots','cdr_residual_phase.png')); close(f);
end

function ensureDir(path)
if ~exist(path,'dir'), mkdir(path); end
end
