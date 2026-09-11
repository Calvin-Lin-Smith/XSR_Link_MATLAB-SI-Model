function test_fix2_calibration_consumption()
%TEST_FIX2_CALIBRATION_CONSUMPTION Clock/sampler corrections must reach consumers.
root=fileparts(fileparts(mfilename('fullpath'))); addpath(genpath(fullfile(root,'src'))); addpath(fullfile(root,'test'));
cfg=phyConfig('vlsi2024_xsr'); cfg.link.nBits=512; cfg.phy.nLane=1;
a=cfg; a.model.cdrOptions.staticPhaseSkewUI=0; a.model.cdrOptions.staticDutyCorrectionUI=0; a.rxPma.lane.samplerRoles.samplerOffsetCodes=0;
b=cfg; b.model.cdrOptions.staticPhaseSkewUI=0.08; b.model.cdrOptions.staticDutyCorrectionUI=0.04; b.rxPma.lane.samplerRoles.samplerOffsetCodes=0.5;
pa=D2DPHY('fix2_a',1); pa.configure(a); pa.run(); pb=D2DPHY('fix2_b',1); pb.configure(b); pb.run();
assert(any(abs(pa.rxPma.lane(1).cdrTrace.dataPhaseUI-pb.rxPma.lane(1).cdrTrace.dataPhaseUI)>1e-12),...
    'clock skew/duty controls did not alter CDR phase');
assert(any(pa.rxPma.lane(1).cdrTrace.decisionInputTrace~=pb.rxPma.lane(1).cdrTrace.decisionInputTrace),...
    'sampler offset did not enter formal CDR decision input');
assert(any(pa.rxPma.lane(1).slicer.dataDecisionInput~=pb.rxPma.lane(1).slicer.dataDecisionInput),...
    'sampler offset did not alter Slicer decision input');
[o,~]=run_vlsi2024_xsr('adaptation',1024,'enablePaperAdaptation',true);
t=readtable(fullfile(o.resultRoot,'adaptation_state_trace.csv')); m=t(strcmp(string(t.state),'MISSION_TRACK'),:);
for name={'dll_phase_initial_UI','dll_phase_applied_UI','dll_phase_residual_UI','dcc_duty_initial_UI','dcc_duty_applied_UI',...
        'dcc_duty_residual_UI','sampler_offset_initial_codes','sampler_offset_applied_codes','sampler_offset_residual_codes','ctle_initial_error_dB','ctle_residual_dB'}
    assert(ismember(name{1},t.Properties.VariableNames));
end
assert(m.dll_phase_residual_UI<=0.01+1e-12 && m.dcc_duty_residual_UI<=0.01+1e-12 &&...
    m.sampler_offset_residual_codes<=0.05+1e-12 && m.ctle_residual_dB<=0.2+1e-12);
ct=readtable(fullfile(o.resultRoot,'ctle_adaptation_trace.csv')); off=abs(ct.requested_dB-ct.applied_dB);
assert(any(off>0) && all(abs(ct.residual_ctle_error_dB-off)<1e-12),'CTLE residual is not computed from quantization');
assert(all(ct.residual_ctle_error_dB<=0.2+1e-12),'off-grid CTLE residual exceeds limit');
[off,~]=run_vlsi2024_xsr('adaptation',1024,'enablePaperAdaptation',false); toff=readtable(fullfile(off.resultRoot,'adaptation_state_trace.csv'));
assert(all(toff.dll_phase_applied_UI~=0) && all(toff.sampler_offset_applied_codes~=0),'disabled path unexpectedly corrected controls');
disp('Fix Round 2 calibration-consumption tests OK');
end
