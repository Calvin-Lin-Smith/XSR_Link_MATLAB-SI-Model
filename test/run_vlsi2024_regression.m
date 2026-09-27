function out=run_vlsi2024_regression(mode,varargin)
%RUN_VLSI2024_REGRESSION Complete deterministic paper-profile evidence run.
if nargin<1 || isempty(mode), mode='full'; end
mode=lower(char(mode)); if ~strcmp(mode,'full'), error('run_vlsi2024_regression:Mode','Only full mode is supported.'); end
nBits=parseBits(varargin); root=fileparts(fileparts(mfilename('fullpath'))); resultRoot=fullfile(root,'results','vlsi2024_xsr'); ensureDir(resultRoot);
tic;
staticBits=min(nBits,2^14);
cfg0=phyConfig('vlsi2024_xsr'); cfg0.link.nBits=nBits; [selectedCfg,acSolution]=runAcSweep(cfg0,staticBits,resultRoot);
base=run_vlsi2024_xsr('baseline',nBits,'Config',selectedCfg); static=run_vlsi2024_xsr('static_checkpoint',staticBits,'Config',selectedCfg);
% static_checkpoint reuses the runner and overwrites baseline artifacts; restore full evidence.
base=run_vlsi2024_xsr('baseline',nBits,'Config',selectedCfg); adapt=run_vlsi2024_xsr('adaptation',nBits,'Config',selectedCfg);
adapt.cfg.model.staticSweepSampleBits=staticBits; writeJson(adapt.cfg,fullfile(resultRoot,'config.json'));
writeJitterTolerance(base.cfg,resultRoot,nBits);
writePaperComparison(base,static,adapt,resultRoot);
legacyRoot=fullfile(resultRoot,'legacy_t1_t9'); ensureDir(legacyRoot); legacy=run_all_tests(legacyRoot);
baselinePass=baselineRunPass(base,resultRoot); staticPass=staticRunPass(static,resultRoot); adaptationPass=adaptationRunPass(adapt); legacyPass=all(legacy.pass);
contractPass=pam4ContractPass(base.cfg); grayPass=grayAdjacencyPass(); dacPass=dacScalePass(base); levelsPass=fourLevelsPass(base); tailPass=tailLockPass(base);
alignmentPass=checkerAlignmentPass(base); berPass=berSanityPass(base); schemaPass=false;
stages=["pam4_contract_pass";"gray_adjacency_pass";"tx_dac_logical_scale_pass";"four_levels_valid";"tail_lock_pass";"checker_alignment_pass";"ber_sanity_pass";"artifact_schema_pass";"static_link";"adaptation";"legacy_t1_t9"];
passes=[contractPass;grayPass;dacPass;levelsPass;tailPass;alignmentPass;berPass;schemaPass;staticPass;adaptationPass;legacyPass];
details=["shared Gray PAM4 contract";"adjacent Gray codewords differ by one bit";"paper DAC remains in logical +/-3 units";"all lanes expose four valid levels";"all lanes currently locked in measurement tail";"bounded integer-UI checker alignment valid";"aggregate and lane BER below 0.25";"reopen and required labels";"reference-free static link and FFE/CTLE sweep";"bounded calibration/adaptation";"fresh T1-T9"];
summary=table(stages,passes,details,...
    'VariableNames',{'stage','pass','detail'});
writetable(summary,fullfile(resultRoot,'regression_summary.csv'));
[schemaPass,~]=validate_vlsi2024_artifacts(resultRoot,'ignore_summary'); summary.pass(strcmp(summary.stage,"artifact_schema_pass"))=schemaPass;
writetable(summary,fullfile(resultRoot,'regression_summary.csv'));
assert(all(summary.pass),'VLSI2024 regression failed.');
out=struct('mode',mode,'resultRoot',resultRoot,'summary',summary,'baseline',base,'static',static,...
    'adaptation',adapt,'legacy',legacy,'acSolution',acSolution,'runtime_s',toc);
end

function nBits=parseBits(args)
nBits=2^18; if isempty(args), return; end
if numel(args)==1 && isnumeric(args{1}), nBits=args{1};
elseif mod(numel(args),2)==0
    for k=1:2:numel(args), if strcmpi(char(args{k}),'nbits'), nBits=args{k+1}; else, error('run_vlsi2024_regression:Option','Unsupported option.'); end, end
else, error('run_vlsi2024_regression:Option','Use nBits as a scalar override.'); end
validateattributes(nBits,{'numeric'},{'scalar','integer','positive'});
end

function pass=baselineRunPass(base,resultRoot)
measurement=getField(base.result,'measurement',struct()); locked=getField(measurement,'continuousTailLock',false);
pass=base.cfg.model.useReferenceAlign==false && all(base.result.nMeasured>0) && all(base.result.errCnt>=0) &&...
    all(isfinite(base.result.ber)) && locked && all(getField(measurement,'tailLockLosses',1)==0) &&...
    all(getField(measurement,'tailCycleSlips',1)==0) && base.result.aggregateBer<0.25;
end

function pass=pam4ContractPass(cfg)
c=dspPam4Contract(); bits=[0 0 0 1 1 1 1 0]'; pass=strcmp(cfg.link.pam4Mapping,'gray_00_01_11_10')&&...
    isequal(dspMap(bits,'PAM4'),c.levels')&&isequal(dspSlice(c.levels','PAM4'),bits)&&...
    isequal(cfg.link.pam4Levels,c.levels)&&isequal(cfg.link.pam4Thresholds,c.thresholds);
end

function pass=grayAdjacencyPass()
c=dspPam4Contract(); pass=all(sum(xor(c.bitPairs(1:3,:),c.bitPairs(2:4,:)),2)==1);
end

function pass=dacScalePass(base)
d=getField(base.cfg.model,'appliedDac',struct()); pass=getField(d,'enabled',false)&&...
    getField(d,'logicalOuterLevel',NaN)==3&&abs(getField(d,'logicalStep',NaN)-6/205)<1e-12&&...
    getField(d,'physicalTargetSwing',NaN)==base.cfg.txPma.lane.targetSwing;
end

function pass=fourLevelsPass(base)
pass=true; for k=1:base.model.nLane, pass=pass&&getField(base.model.rxPma.lane(k).levelingMeta,'levelsValid',false)&&getField(base.model.rxPma.lane(k).cdrTrace,'levelsValid',false); end
end

function pass=tailLockPass(base)
measurement=getField(base.result,'measurement',struct()); pass=getField(measurement,'continuousTailLock',false)&&...
    all(getField(measurement,'tailLockLosses',1)==0)&&all(getField(measurement,'tailCycleSlips',1)==0)&&all(getField(measurement,'tailLevelsValid',false));
end

function pass=checkerAlignmentPass(base)
pass=isfield(base.result,'checker')&&all(base.result.checker.alignmentValid)&&all(base.result.checker.framingValid)&&...
    all(isfinite(base.result.checker.checkerLagUI))&&getField(base.result.checker,'continuousTailLock',false)&&...
    isequaln(base.result.checker.measurementStartUI,base.result.measurement.measurementStartUI);
end

function pass=berSanityPass(base)
pass=isfinite(base.result.aggregateBer)&&base.result.aggregateBer<0.25&&all(base.result.ber<0.25)&&...
    getField(base.result.measurement,'continuousTailLock',false)&&all(base.result.nMeasured>0);
end

function pass=staticRunPass(static,resultRoot)
pass=isfield(static,'ffe') && height(static.ffe)==2 && all(static.ffe.measured_bits>0) &&...
    isfile(fullfile(resultRoot,'channel_il.csv')) && static.cfg.model.useReferenceAlign==false;
if pass, il=readtable(fullfile(resultRoot,'channel_il.csv')); pass=all(il.measured_bits>0)&&all(abs(il.error_dB)<=il.tolerance_dB); end
end

function pass=adaptationRunPass(adapt)
pass=isfield(adapt,'stateTrace')&&height(adapt.stateTrace)==5&&all(adapt.stateTrace.objective(3:end)>=0)&&...
    ismember('disturbed_objective',adapt.stateTrace.Properties.VariableNames);
if pass, m=adapt.stateTrace(strcmp(string(adapt.stateTrace.state),'MISSION_TRACK'),:); pass=~isempty(m)&&m.disturbed_objective<m.recovered_objective&&m.control_changed; end
end

function [selectedCfg,t]=runAcSweep(cfg,sweepBits,resultRoot)
corners=[1e-4 3e-4 1e-3 3e-3 1e-2]; modes={"pre-only","post-only","pre+post"}; rows=[];
for im=1:numel(modes)
    for ic=1:numel(corners)
        c=cfg; c.link.nBits=sweepBits; c.phy.nLane=1; c.rxPma.lane.acPreCorner_UI=corners(ic); c.rxPma.lane.acPostCorner_UI=corners(ic);
        c.rxPma.lane.enableAcPre=any(strcmp(modes{im},{'pre-only','pre+post'})); c.rxPma.lane.enableAcPost=any(strcmp(modes{im},{'post-only','pre+post'}));
        r=runLocal(c); lane=r.model.rxPma.lane(1); tr=lane.cdrTrace; margins=tr.logicalEyeMarginTrace(isfinite(tr.logicalEyeMarginTrace));
        if isempty(margins), eyeMargin=NaN; else, eyeMargin=margins(end); end
        measurement=getField(r.result,'measurement',struct()); valid=lane.levelingMeta.levelsValid&&getField(tr,'levelsValid',false);
        tail=getField(measurement,'continuousTailLock',false)&&all(getField(measurement,'tailLockLosses',1)==0)&&all(getField(measurement,'tailCycleSlips',1)==0);
        checker=getField(r.result,'checker',struct());
        if isfield(checker,'checkerLagUI'), lag=checker.checkerLagUI(1); else, lag=NaN; end
        errors=sum(r.result.errCnt); measured=sum(r.result.nMeasured); measuredValid=valid&&tail&&isfinite(eyeMargin)&&eyeMargin>0&&all(isfinite(r.result.ber));
        upper=binomialUpper95(errors,measured);
        firstUI=getField(measurement,'firstValidLockUI',NaN); if numel(firstUI)>1, firstUI=firstUI(1); end
        startUI=getField(measurement,'measurementStartUI',NaN); tailLoss=getField(measurement,'tailLockLosses',NaN); if numel(tailLoss)>1, tailLoss=tailLoss(1); end
        tailSlip=getField(measurement,'tailCycleSlips',NaN); if numel(tailSlip)>1, tailSlip=tailSlip(1); end
        tailLevel=getField(measurement,'tailLevelsValid',false); if numel(tailLevel)>1, tailLevel=tailLevel(1); end
        rows=[rows; corners(ic) im c.rxPma.lane.enableAcPre c.rxPma.lane.enableAcPost valid tail measuredValid eyeMargin errors measured r.result.aggregateBer upper lag getField(lane.levelingMeta,'levelingScale',NaN) firstUI startUI getField(measurement,'continuousTailLock',false) tailLoss tailSlip tailLevel]; %#ok<AGROW>
    end
end
t=array2table(rows,'VariableNames',{'cornerRelNyq','modeIndex','ac_pre_enabled','ac_post_enabled','four_levels_valid','tail_lock','measurement_valid','eye_margin','errors','measured_bits','aggregate_BER','ber_upper_95','checker_lag_ui','leveling_scale','first_valid_lock_ui','measurement_start_ui','continuous_tail_lock','tail_lock_losses','tail_cycle_slips','tail_level_valid'});
t.mode=strings(height(t),1); for q=1:height(t), t.mode(q)=modes{t.modeIndex(q)}; end; t.modeIndex=[]; t.model_selected_assumption=repmat("AC corner/mode selected by bounded sweep; paper value undisclosed",height(t),1);
t=movevars(t,'mode','Before','cornerRelNyq'); writetable(t,fullfile(resultRoot,'ac_solution.csv'));
eligible=t.four_levels_valid&t.tail_lock&isfinite(t.eye_margin)&t.eye_margin>0;
assert(any(eligible),'AC sweep found no four-level tail-locked positive-eye candidate.'); candidates=t(eligible,:);
% Prefer the highest interpretable corner, then the lowest finite BER at that corner.
maxCorner=max(candidates.cornerRelNyq); same=candidates(candidates.cornerRelNyq==maxCorner,:); [~,pick]=min(same.aggregate_BER); selected=same(pick,:);
selectedCfg=cfg; selectedCfg.rxPma.lane.acPreCorner_UI=selected.cornerRelNyq; selectedCfg.rxPma.lane.acPostCorner_UI=selected.cornerRelNyq;
selectedCfg.rxPma.lane.enableAcPre=logical(selected.ac_pre_enabled); selectedCfg.rxPma.lane.enableAcPost=logical(selected.ac_post_enabled);
selectedCfg.rxPma.lane.acSelectedCorner_UI=selected.cornerRelNyq; selectedCfg.rxPma.lane.acSelectedMode='model-selected assumption';
selectedCfg.rxPma.lane.acSelectionBasis='bounded cornerRelNyq sweep; four levels, tail lock, positive eye margin';
end

function writeJitterTolerance(cfg,resultRoot,nBits)
values=[0 .005 .01 .02 .04 .08]; rows=zeros(numel(values),8); sweepBits=min(nBits,2^14);
for k=1:numel(values)
    c=cfg; c.link.nBits=sweepBits; c.link.rjUI_rms=values(k); c.link.djUI_pp=0; r=runLocal(c);
    errors=sum(r.result.errCnt); measured=sum(r.result.nMeasured); rows(k,:)=[values(k) errors measured errors/max(measured,1) c.link.seed binomialUpper95(errors,measured) sweepBits 1];
end
t=array2table(rows,'VariableNames',{'jitter_UI_rms','errors','measured_bits','empirical_BER','seed','ber_upper_95','sample_bits','sweep_context'});
t.sweep_context=repmat("bounded x8 tolerance sweep; no silicon claim",height(t),1);
t.mode=repmat(string(cfg.link.modulation),height(t),1); t.rate_context_Gbps=repmat(cfg.paper.berRate_Gbps,height(t),1);
t.line_rate_Gbps=repmat(cfg.link.lineRate_Gbps,height(t),1); t.lane_context=repmat("x8",height(t),1);
writetable(t,fullfile(resultRoot,'jitter_tolerance.csv'));
end

function writePaperComparison(base,static,adapt,resultRoot) %#ok<INUSD>
category=[repmat("paper fact",15,1);"model output";"model assumption";repmat("model limitation",5,1)];
item=["lanes and PLL";"rate/modulation range";"TX FFE";"SST DAC";"package/channel length";"insertion loss";"NEXT/FEXT";"AC leveling";"CTLE";"sampler roles";"DLL/PI/BB-CDR";"PI mismatch";"pattern";"integrated jitter";"COM";"baseline empirical BER";"channel";"S-parameters/reflections";"MIMO crosstalk";"transistor/T-coil";"exact FFE coefficients";"power/area/silicon calibration"];
paper=["8 lanes + PLL";"9.8-113 Gb/s PAM4/NRZ";"3/optional 6 taps";"7.5-bit/206-level SST DAC";"1-80 mm 2D/2.5D CoWoS";"text 0.5-10 dB; Table-1 10.8 dB IL at 28 GHz";"-40/-38 dB at 28 GHz";"AC leveling";"single-stage max 6 dB, max 0.2 dB step";"12 data, 4 edge, 4 spare";"2 DLL + PI/BB-CDR";"< +/-0.5 LSB";"PRBS31";"194 fs PLL+TX integrated, filtered/measurement context";"2.5 dB COM at 1e-6";"paper BER claims";"not selected";"not modeled";"not modeled";"not modeled";"model-selected only";"not modeled/quoted facts only"];
model=["cfg.phy.nLane=8; RxSupport PLL";"cfg rate contexts 112.5/112/113";"three-tap formal + six-tap comparison";"cfg.txPma.lane.dacLevels=206";"metadata only; analytic channel";"8 dB model point; 10.8 dB fact retained";"metadata only";"enabled in AFE";"grid 0:0.2:6 dB";"Slicer role metadata";"decision-directed 64-code PI";"deterministic bound 0.49 LSB";"cfg.rawPcs.pattern";"metadata only";"not estimated";sprintf('aggregate BER %.6g over %d bits',base.result.aggregateBer,sum(base.result.nMeasured));"calibrated analytic IL at 28 GHz";"absent";"absent";"absent";"preset coefficients";"absent"];
status=[repmat("recorded",15,1);"measured behavioral output";"selected assumption";repmat("explicit limitation",5,1)];
scope=[repmat("source fact retained; not inferred from model",15,1);"finite empirical result with 95% upper bounds";"architecture/trend reproduction";repmat("outside milestone scope",5,1)];
t=table(category,item,paper,model,status,scope,'VariableNames',{'category','item','paper_value','model_value','status','scope'}); writetable(t,fullfile(resultRoot,'paper_comparison.csv'));
fid=fopen(fullfile(resultRoot,'paper_comparison.md'),'w'); assert(fid>0,'Unable to write comparison.');
fprintf(fid,['# VLSI2024 XSR comparison\n\n' ...
    'Paper facts are recorded separately from model-selected assumptions and outputs. The formal profile uses reference-free decision-directed BB-CDR/PI; TX reference bits enter only the final BER checker.\n\n' ...
    '- Paper facts: 8 lanes + PLL; 9.8-113 Gb/s PAM4/NRZ; 3/optional 6-tap FFE; 7.5-bit/206-level SST DAC; 1-80 mm 2D/2.5D CoWoS; text 0.5-10 dB and Table-1 10.8 dB insertion loss at 28 GHz; NEXT/FEXT -40/-38 dB; AC leveling; CTLE 0-6 dB in 0.2 dB steps; sampler roles; 2 DLL + PI/BB-CDR; PI mismatch below +/-0.5 LSB; PRBS31; 194 fs PLL+TX integrated-jitter context; 2.5 dB COM at 1e-6; quoted BER, 0.9 pJ/b, 0.65 V, and area facts.\n' ...
    '- Model outputs: empirical BER rows include errors, measured bits, seed, and a 95%% finite-sample upper bound. They are behavioral finite-sample observations, not proof of the paper BER claims.\n' ...
    '- Limitations: no S-parameters/reflections, MIMO crosstalk, transistor/T-coil circuits, exact disclosed FFE coefficients, true DLL/PI transfer, silicon calibration logic, or power breakdown.\n']); fclose(fid);
end

function r=runLocal(cfg)
p=D2DPHY('vlsi2024_xsr',cfg.phy.nLane); p.configure(cfg); r.result=p.run(); r.model=p;
end

function upper=binomialUpper95(errors,measured)
if ~isfinite(errors)||~isfinite(measured)||measured<=0, upper=NaN; elseif errors<=0, upper=3/measured; elseif errors>=measured, upper=1; else, upper=betaincinv(0.95,errors+1,measured-errors); end
end

function ensureDir(path)
if ~exist(path,'dir'), mkdir(path); end
end

function writeJson(value,path)
fid=fopen(path,'w'); assert(fid>0,'Unable to write %s.',path); fprintf(fid,'%s',jsonencode(value,'PrettyPrint',true)); fclose(fid);
end

function value=getField(s,name,default)
if isstruct(s)&&isfield(s,name), value=s.(name); else, value=default; end
end
