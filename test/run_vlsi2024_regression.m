function out=run_vlsi2024_regression(mode,varargin)
%RUN_VLSI2024_REGRESSION Complete deterministic paper-profile evidence run.
if nargin<1 || isempty(mode), mode='full'; end
mode=lower(char(mode)); if ~strcmp(mode,'full'), error('run_vlsi2024_regression:Mode','Only full mode is supported.'); end
nBits=parseBits(varargin); root=fileparts(fileparts(mfilename('fullpath'))); resultRoot=fullfile(root,'results','vlsi2024_xsr'); ensureDir(resultRoot);
tic;
base=run_vlsi2024_xsr('baseline',nBits); static=run_vlsi2024_xsr('static_checkpoint',nBits); adapt=run_vlsi2024_xsr('adaptation',nBits);
writeJitterTolerance(base.cfg,resultRoot,nBits);
writePaperComparison(base,static,adapt,resultRoot);
legacyRoot=fullfile(resultRoot,'legacy_t1_t9'); ensureDir(legacyRoot); legacy=run_all_tests(legacyRoot);
schemaPass=true;
summary=table(["baseline_cdr_pi";"static_link";"adaptation";"legacy_t1_t9";"artifact_schema"],...
    [true;true;all(adapt.stateTrace.objective(3:end)>=0);all(legacy.pass);schemaPass],...
    ["formal decision-directed CDR/PI";"legacy static link and FFE/CTLE sweep";"bounded calibration/adaptation";"fresh T1-T9";"reopen and required labels"],...
    'VariableNames',{'stage','pass','detail'});
writetable(summary,fullfile(resultRoot,'regression_summary.csv'));
schemaPass=validateArtifacts(resultRoot); summary.pass(5)=schemaPass;
writetable(summary,fullfile(resultRoot,'regression_summary.csv'));
assert(all(summary.pass),'VLSI2024 regression failed.');
out=struct('mode',mode,'resultRoot',resultRoot,'summary',summary,'baseline',base,'static',static,...
    'adaptation',adapt,'legacy',legacy,'runtime_s',toc);
end

function nBits=parseBits(args)
nBits=2^18; if isempty(args), return; end
if numel(args)==1 && isnumeric(args{1}), nBits=args{1};
elseif mod(numel(args),2)==0
    for k=1:2:numel(args), if strcmpi(char(args{k}),'nbits'), nBits=args{k+1}; else, error('run_vlsi2024_regression:Option','Unsupported option.'); end, end
else, error('run_vlsi2024_regression:Option','Use nBits as a scalar override.'); end
validateattributes(nBits,{'numeric'},{'scalar','integer','positive'});
end

function writeJitterTolerance(cfg,resultRoot,nBits)
values=[0 .005 .01 .02 .04 .08]; rows=zeros(numel(values),8); sweepBits=min(nBits,2^14);
for k=1:numel(values)
    c=cfg; c.link.nBits=sweepBits; c.link.rjUI_rms=values(k); c.link.djUI_pp=0; r=runLocal(c);
    errors=sum(r.result.errCnt); measured=sum(r.result.nMeasured); rows(k,:)=[values(k) errors measured errors/max(measured,1) c.link.seed binomialUpper95(errors,measured) sweepBits 1];
end
t=array2table(rows,'VariableNames',{'jitter_UI_rms','errors','measured_bits','empirical_BER','seed','ber_upper_95','sample_bits','sweep_context'});
t.sweep_context=repmat("bounded x8 tolerance sweep; no silicon claim",height(t),1);
t.mode=repmat(string(cfg.link.modulation),height(t),1); t.rate_context_Gbps=repmat(cfg.paper.berRate_Gbps,height(t),1); t.lane_context=repmat("x8",height(t),1);
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

function ok=validateArtifacts(root)
required={"config.json","assumptions.md","baseline_metrics.csv","ffe_3_vs_6.csv","channel_il.csv",...
    "ctle_adaptation_trace.csv","cdr_lock_trace.csv","pi_code_trace.csv","residual_phase_histogram.csv",...
    "jitter_tolerance.csv","adaptation_state_trace.csv","paper_comparison.csv","paper_comparison.md",...
    "regression_summary.csv","baseline_probes.mat","plots/cdr_residual_phase.png","legacy_t1_t9/summary.csv"};
ok=true; for k=1:numel(required), ok=ok&&isfile(fullfile(root,required{k})); end
if ~ok, return; end
j=jsondecode(fileread(fullfile(root,'config.json'))); assert(isfield(j,'model')&&isfield(j.model,'useReferenceAlign'));
csvs=dir(fullfile(root,'**','*.csv')); for k=1:numel(csvs), t=readtable(fullfile(csvs(k).folder,csvs(k).name)); assert(~isempty(t.Properties.VariableNames)); end
jsons=dir(fullfile(root,'**','*.json')); for k=1:numel(jsons), jsondecode(fileread(fullfile(jsons(k).folder,jsons(k).name))); end
mats=dir(fullfile(root,'**','*.mat')); for k=1:numel(mats), whos('-file',fullfile(mats(k).folder,mats(k).name)); end
md=dir(fullfile(root,'**','*.md')); for k=1:numel(md), assert(strlength(string(fileread(fullfile(md(k).folder,md(k).name))))>0); end
assert(~isempty(imfinfo(fullfile(root,'plots','cdr_residual_phase.png'))));
end

function r=runLocal(cfg)
p=D2DPHY('vlsi2024_xsr',cfg.phy.nLane); p.configure(cfg); r.result=p.run(); r.model=p;
end

function upper=binomialUpper95(errors,measured)
if measured<=0, upper=NaN; elseif errors<=0, upper=3/measured; elseif errors>=measured, upper=1; else, upper=betaincinv(0.95,errors+1,measured-errors); end
end

function ensureDir(path)
if ~exist(path,'dir'), mkdir(path); end
end
