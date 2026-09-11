function [ok,detail]=validate_vlsi2024_artifacts(root,varargin)
%VALIDATE_VLSI2024_ARTIFACTS Reopen and validate the paper evidence contract.
ok=false; detail='';
requireSummary=~(nargin>1&&strcmpi(char(varargin{1}),'ignore_summary'));
try
    required={"config.json","assumptions.md","baseline_metrics.csv","ffe_3_vs_6.csv","channel_il.csv",...
        "channel_response.csv","channel_il_at_28GHz.csv","loss_sweep_metrics.csv","static_regression_summary.csv","ac_ctle.csv",...
        "ctle_adaptation_trace.csv","cdr_lock_trace.csv","pi_code_trace.csv","residual_phase_histogram.csv",...
        "jitter_tolerance.csv","adaptation_state_trace.csv","paper_comparison.csv","paper_comparison.md",...
        "regression_summary.csv","baseline_probes.mat","plots/cdr_residual_phase.png",...
        "legacy_t1_t9/summary.csv","legacy_t1_t9/junit.xml","legacy_t1_t9/manifest.json","legacy_t1_t9/probes.json",...
        "legacy_t1_t9/T1_eye_metrics.csv","legacy_t1_t9/T3_bathtub.csv","legacy_t1_t9/T6_patterns.csv",...
        "legacy_t1_t9/T7_modulation.csv","legacy_t1_t9/T9_loopback.csv"};
    for k=1:numel(required), assert(isfile(fullfile(root,required{k})),'Missing artifact: %s',required{k}); end
    t1Names={"T1_eye_NRZ_28G_0dB.png","T1_eye_NRZ_28G_4dB.png","T1_eye_NRZ_28G_8dB.png","T1_eye_NRZ_28G_10dB.png",...
        "T1_eye_NRZ_56G_0dB.png","T1_eye_NRZ_56G_4dB.png","T1_eye_NRZ_56G_8dB.png","T1_eye_NRZ_56G_10dB.png",...
        "T1_eye_PAM4_28G_0dB.png","T1_eye_PAM4_28G_4dB.png","T1_eye_PAM4_28G_8dB.png","T1_eye_PAM4_28G_10dB.png",...
        "T1_eye_PAM4_56G_0dB.png","T1_eye_PAM4_56G_4dB.png","T1_eye_PAM4_56G_8dB.png","T1_eye_PAM4_56G_10dB.png"};
    for k=1:numel(t1Names), info=imfinfo(fullfile(root,'legacy_t1_t9',t1Names{k})); assert(info.Width>0&&info.Height>0,'invalid T1 PNG'); end
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
    il28=readtable(fullfile(root,'channel_il_at_28GHz.csv')); requireVars(il28,{'requested_loss_dB','measured_loss_dB','error_dB','tolerance_dB'});
    assert(all(abs((il28.measured_loss_dB-il28.requested_loss_dB)-il28.error_dB)<=1e-12)&&all(abs(il28.error_dB)<=il28.tolerance_dB),...
        'channel IL at 28 GHz invariant failed');
    response=readtable(fullfile(root,'channel_response.csv')); requireVars(response,{'frequency_GHz','baud_GBd','requested_loss_dB','measured_loss_dB','error_dB','tolerance_dB','mode','unmodeledCrosstalk'});
    assert(all(response.frequency_GHz>0)&&all(response.baud_GBd>0)&&...
        all(abs((response.measured_loss_dB-response.requested_loss_dB)-response.error_dB)<=1e-12)&&...
        all(abs(response.error_dB)<=response.tolerance_dB),...
        'channel response schema/value invariant failed');
    loss=readtable(fullfile(root,'loss_sweep_metrics.csv')); checkBer(loss,{'errors','measured_bits','empirical_BER','seed','ber_upper_95'}); requireVars(loss,{'lossAtRef_dB','rate_context_Gbps','mode','lane_context'});
    ffe=readtable(fullfile(root,'ffe_3_vs_6.csv')); checkBer(ffe,{'errors','measured_bits','empirical_BER','seed','ber_upper_95'}); requireVars(ffe,{'tap_count','coefficients'});
    ac=readtable(fullfile(root,'ac_ctle.csv')); checkBer(ac,{'errors','measured_bits','empirical_BER','seed','ber_upper_95'}); requireVars(ac,{'ac_enabled','ctle_applied_dB'});
    jitter=readtable(fullfile(root,'jitter_tolerance.csv')); checkBer(jitter,{'errors','measured_bits','empirical_BER','seed','ber_upper_95'}); requireVars(jitter,{'sample_bits','mode','rate_context_Gbps','lane_context'});
    static=readtable(fullfile(root,'static_regression_summary.csv')); checkBer(static,{'errors','measured_bits','empirical_BER','seed','ber_upper_95'}); requireVars(static,{'variant','mode','rate_context_Gbps','lane_context'});
    ctle=readtable(fullfile(root,'ctle_adaptation_trace.csv')); requireVars(ctle,{'objective','disturbed_objective','recovered_objective','control_changed','residual_ctle_error_dB'});
    assert(all(ctle.residual_ctle_error_dB<=0.2+1e-12),'CTLE residual exceeds limit');
    adapt=readtable(fullfile(root,'adaptation_state_trace.csv')); requireVars(adapt,{'state','objective','disturbed_objective',...
        'recovered_objective','control_changed','rx_term_gain_applied','tx_gain_residual','dll_phase_initial_UI',...
        'dll_phase_applied_UI','dll_phase_residual_UI','dcc_duty_initial_UI','dcc_duty_applied_UI','dcc_duty_residual_UI',...
        'sampler_offset_initial_codes','sampler_offset_applied_codes','sampler_offset_residual_codes','ctle_initial_error_dB','ctle_residual_dB'});
    states=string(adapt.state); assert(isequal(states,["RESET";"STARTUP_IMPEDANCE_CAL";"CLOCK_CAL";"INITIAL_EQ_TRAIN";"MISSION_TRACK"]),...
        'adaptation states invalid'); mission=adapt(states=="MISSION_TRACK",:);
    assert(mission.disturbed_objective<mission.recovered_objective&&mission.control_changed,'adaptation did not recover');
    assert(mission.dll_phase_residual_UI<=cfg.model.adaptation.residualLimit.dllPhaseUI+1e-12&&...
        mission.dcc_duty_residual_UI<=cfg.model.adaptation.residualLimit.dccDutyUI+1e-12&&...
        mission.sampler_offset_residual_codes<=cfg.model.adaptation.residualLimit.samplerOffsetCodes+1e-12&&...
        mission.ctle_residual_dB<=cfg.model.adaptation.residualLimit.ctle_dB+1e-12,'adaptation residual limit failed');
    comparison=readtable(fullfile(root,'paper_comparison.csv')); requireVars(comparison,{'category','item','paper_value','model_value'});
    manifest=jsondecode(fileread(fullfile(root,'legacy_t1_t9','manifest.json'))); probes=jsondecode(fileread(fullfile(root,'legacy_t1_t9','probes.json'))); %#ok<NASGU>
    assert(~isempty(whos('-file',fullfile(root,'baseline_probes.mat'))));
    legacyMat=whos('-file',fullfile(root,'legacy_t1_t9','regression.mat')); legacyNames={legacyMat.name};
    for name={'summary','T1','T3','T6','T7','T9'}, assert(ismember(name{1},legacyNames),'legacy MAT missing %s',name{1}); end
    assert(strlength(string(fileread(fullfile(root,'assumptions.md'))))>0&&strlength(string(fileread(fullfile(root,'paper_comparison.md'))))>0);
    summary=readcell(fullfile(root,'regression_summary.csv'),'Delimiter',','); assert(size(summary,2)>=3&&strcmp(summary{1,1},'stage')&&strcmp(summary{1,2},'pass'),...
        'regression summary schema invalid'); if requireSummary, assert(all(cell2mat(summary(2:end,2))==1),'regression summary contains failure'); end
    legacy=readcell(fullfile(root,'legacy_t1_t9','summary.csv'),'Delimiter',','); assert(size(legacy,2)>=2&&strcmp(legacy{1,1},'test')&&strcmp(legacy{1,2},'pass')&&size(legacy,1)==10&&all(cell2mat(legacy(2:end,2))==1),...
        'legacy T1-T9 evidence invalid');
    t1=readtable(fullfile(root,'legacy_t1_t9','T1_eye_metrics.csv')); requireVars(t1,{'modeIndex','baudG','lossDb','ber','eyeHeight'}); expectedT1=[repelem((1:4)',4) repmat([28;28;28;28;56;56;56;56],2,1) repmat([0;4;8;10],4,1)]; actualT1=sortrows(t1,{'modeIndex','baudG','lossDb'}); assert(height(t1)==16&&isequal(actualT1{:,1:3},expectedT1)&&all(t1.ber>=0&t1.ber<=1)&&all(isfinite(t1.eyeHeight)),'legacy T1 schema/value invalid');
    t3=readtable(fullfile(root,'legacy_t1_t9','T3_bathtub.csv')); requireVars(t3,{'offsetUI','phase','delay','phaseBer'}); center=find(abs(t3.offsetUI)<1e-12,1); assert(all(t3.phaseBer>=0&t3.phaseBer<=1)&&all(isfinite(t3.phaseBer))&&~isempty(center)&&t3.phaseBer(center)<=t3.phaseBer(1)&&t3.phaseBer(center)<=t3.phaseBer(end),'legacy T3 schema/value invalid');
    t6=readtable(fullfile(root,'legacy_t1_t9','T6_patterns.csv')); requireVars(t6,{'patternIndex','injected','detected'}); expectedT6=sortrows([repelem((1:4)',2) repmat([0;17],4,1)]); actualT6=sortrows(t6{:,1:2}); assert(isequal(actualT6,expectedT6)&&all(t6.injected==t6.detected),'legacy T6 mismatch');
    t7=readtable(fullfile(root,'legacy_t1_t9','T7_modulation.csv')); requireVars(t7,{'modulation','ber'}); assert(isequal(sort(string(t7.modulation)),sort(["NRZ";"PAM4"]))&&all(t7.ber>=0&t7.ber<=1)&&t7.ber(strcmp(string(t7.modulation),'PAM4'))>t7.ber(strcmp(string(t7.modulation),'NRZ')),'legacy T7 schema/value invalid');
    t9=readtable(fullfile(root,'legacy_t1_t9','T9_loopback.csv')); requireVars(t9,{'mode','pass'}); assert(isequal(sort(string(t9.mode)),sort(["shallow";"serial_lane";"die_to_die"]))&&height(t9)==3&&all(t9.pass),'legacy T9 failed');
    junit=fileread(fullfile(root,'legacy_t1_t9','junit.xml')); assert(contains(junit,'tests="9"')&&contains(junit,'failures="0"')&&count(junit,'<testcase')==9,'legacy JUnit invalid');
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
assert(all(t.errors<=t.measured_bits),'errors exceed measured bits');
assert(all(t.empirical_BER>=0&t.empirical_BER<=1)&&all(abs(t.empirical_BER-t.errors./t.measured_bits)<=1e-12),...
    'empirical BER ratio invalid');
assert(all(t.ber_upper_95>=t.empirical_BER-1e-12)&all(t.ber_upper_95<=1+1e-12),...
    'invalid BER/upper-bound values'); z=t.errors==0; if any(z), assert(all(abs(t.ber_upper_95(z)-3./t.measured_bits(z))<1e-12),'zero-error bound invalid'); end
if ismember('seed',t.Properties.VariableNames), assert(all(isfinite(t.seed)),'invalid seed context'); end
if ismember('rate_context_Gbps',t.Properties.VariableNames), assert(all(t.rate_context_Gbps>0),'invalid rate context'); end
if ismember('lane_context',t.Properties.VariableNames), assert(all(strlength(string(t.lane_context))>0),'invalid lane context'); end
if ismember('sample_bits',t.Properties.VariableNames), assert(all(t.sample_bits>0),'invalid sample context'); end
end
