function [ok,detail]=validate_vlsi2024_artifacts(root,varargin)
%VALIDATE_VLSI2024_ARTIFACTS Reopen and validate the paper evidence contract.
ok=false; detail='';
requireSummary=~(nargin>1&&strcmpi(char(varargin{1}),'ignore_summary'));
try
    required={"config.json","assumptions.md","baseline_metrics.csv","ffe_3_vs_6.csv","channel_il.csv",...
        "ctle_adaptation_trace.csv","cdr_lock_trace.csv","pi_code_trace.csv","residual_phase_histogram.csv",...
        "jitter_tolerance.csv","adaptation_state_trace.csv","paper_comparison.csv","paper_comparison.md",...
        "regression_summary.csv","baseline_probes.mat","plots/cdr_residual_phase.png","legacy_t1_t9/summary.csv"};
    for k=1:numel(required), assert(isfile(fullfile(root,required{k})),'Missing artifact: %s',required{k}); end
    cfg=jsondecode(fileread(fullfile(root,'config.json')));
    assert(isfield(cfg,'link')&&isfield(cfg.link,'nBits')&&cfg.link.nBits>0,'config link.nBits missing');
    assert(isfield(cfg,'model')&&isfield(cfg.model,'useReferenceAlign')&&~cfg.model.useReferenceAlign,...
        'formal config must disable reference alignment');
    assert(isfield(cfg.model,'trainingMode')&&strcmp(cfg.model.trainingMode,'decision_directed'),...
        'formal training mode is not decision_directed');
    assert(isfield(cfg.model,'cdrOptions')&&cfg.model.cdrOptions.nCodes==64,'PI code count missing');
    metrics=readtable(fullfile(root,'baseline_metrics.csv')); checkBer(metrics,{'errors','measured_bits','empirical_BER','seed','ber_upper_95'});
    assert(ismember('lane',metrics.Properties.VariableNames)&&all(metrics.lane>=1),'baseline lane schema');
    lock=readtable(fullfile(root,'cdr_lock_trace.csv')); requireVars(lock,{'sample','locked','transition','pi_raw_code',...
        'pi_wrapped_code','pi_applied_code','pi_mismatch_LSB','pi_wrap_count','data_phase_UI','edge_phase_UI','residual_phase_UI'});
    assert(height(lock)>0&&any(lock.locked),'formal CDR never locked'); assert(all(isfinite(lock.residual_phase_UI)),'nonfinite residual trace');
    pi=readtable(fullfile(root,'pi_code_trace.csv')); requireVars(pi,{'sample','pi_raw_code','pi_wrapped_code','pi_applied_code',...
        'pi_mismatch_LSB','pi_wrap_count','pi_trace_stride'}); assert(all(pi.pi_trace_stride>=1),'invalid PI stride');
    hist=readtable(fullfile(root,'residual_phase_histogram.csv')); requireVars(hist,{'count','sample_count'});
    assert(all(hist.count>=0)&&all(hist.sample_count==hist.sample_count(1))&&sum(hist.count)==hist.sample_count(1),...
        'residual histogram does not cover every sample');
    il=readtable(fullfile(root,'channel_il.csv')); requireVars(il,{'requested_loss_dB','measured_loss_dB','measured_bits','error_dB','tolerance_dB'});
    assert(all(il.measured_bits>0)&&all(isfinite(il.measured_loss_dB))&&all(abs(il.error_dB)<=il.tolerance_dB),...
        'channel IL schema/value invariant failed');
    ffe=readtable(fullfile(root,'ffe_3_vs_6.csv')); checkBer(ffe,{'errors','measured_bits','empirical_BER','seed','ber_upper_95'}); requireVars(ffe,{'tap_count','coefficients'});
    ac=readtable(fullfile(root,'ac_ctle.csv')); checkBer(ac,{'errors','measured_bits','empirical_BER','seed','ber_upper_95'}); requireVars(ac,{'ac_enabled','ctle_applied_dB'});
    jitter=readtable(fullfile(root,'jitter_tolerance.csv')); checkBer(jitter,{'errors','measured_bits','empirical_BER','seed','ber_upper_95'}); requireVars(jitter,{'sample_bits','mode','rate_context_Gbps','lane_context'});
    ctle=readtable(fullfile(root,'ctle_adaptation_trace.csv')); requireVars(ctle,{'objective','disturbed_objective','recovered_objective','control_changed'});
    adapt=readtable(fullfile(root,'adaptation_state_trace.csv')); requireVars(adapt,{'state','objective','disturbed_objective',...
        'recovered_objective','control_changed','rx_term_gain_applied','tx_gain_residual'});
    states=string(adapt.state); assert(isequal(states,["RESET";"STARTUP_IMPEDANCE_CAL";"CLOCK_CAL";"INITIAL_EQ_TRAIN";"MISSION_TRACK"]),...
        'adaptation states invalid'); mission=adapt(states=="MISSION_TRACK",:);
    assert(mission.disturbed_objective<mission.recovered_objective&&mission.control_changed,'adaptation did not recover');
    comparison=readtable(fullfile(root,'paper_comparison.csv')); requireVars(comparison,{'category','item','paper_value','model_value'});
    jsondecode(fileread(fullfile(root,'legacy_t1_t9','manifest.json'))); jsondecode(fileread(fullfile(root,'legacy_t1_t9','probes.json')));
    assert(~isempty(whos('-file',fullfile(root,'baseline_probes.mat'))));
    assert(strlength(string(fileread(fullfile(root,'assumptions.md'))))>0&&strlength(string(fileread(fullfile(root,'paper_comparison.md'))))>0);
    summary=readcell(fullfile(root,'regression_summary.csv'),'Delimiter',','); assert(size(summary,2)>=3&&strcmp(summary{1,1},'stage')&&strcmp(summary{1,2},'pass'),...
        'regression summary schema invalid'); if requireSummary, assert(all(cell2mat(summary(2:end,2))==1),'regression summary contains failure'); end
    legacy=readcell(fullfile(root,'legacy_t1_t9','summary.csv'),'Delimiter',','); assert(size(legacy,2)>=2&&strcmp(legacy{1,1},'test')&&strcmp(legacy{1,2},'pass')&&size(legacy,1)==10&&all(cell2mat(legacy(2:end,2))==1),...
        'legacy T1-T9 evidence invalid');
    assert(strlength(string(fileread(fullfile(root,'assumptions.md'))))>0&&~isempty(imfinfo(fullfile(root,'plots','cdr_residual_phase.png'))));
    ok=true; detail='OK';
catch ME
    detail=ME.message;
end
end

function requireVars(t,names)
for k=1:numel(names), assert(ismember(names{k},t.Properties.VariableNames),'Missing column: %s',names{k}); end
end

function checkBer(t,names)
requireVars(t,names); assert(all(t.errors>=0)&&all(t.measured_bits>0),'invalid BER counts');
assert(all(t.empirical_BER>=0&t.empirical_BER<=1)&&all(t.ber_upper_95>=t.empirical_BER-1e-12),...
    'invalid BER/upper-bound values'); z=t.errors==0; if any(z), assert(all(abs(t.ber_upper_95(z)-3./t.measured_bits(z))<1e-12),'zero-error bound invalid'); end
end
