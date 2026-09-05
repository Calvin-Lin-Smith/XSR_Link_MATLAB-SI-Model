function test_calibration_adaptation()
%TEST_CALIBRATION_ADAPTATION Deterministic bounded state/control recovery.
root=fileparts(fileparts(mfilename('fullpath'))); addpath(genpath(fullfile(root,'src'))); addpath(fullfile(root,'test'));
[o,~]=run_vlsi2024_xsr('adaptation',4096);
assert(isfile(fullfile(o.resultRoot,'adaptation_state_trace.csv')));
t=readtable(fullfile(o.resultRoot,'adaptation_state_trace.csv'));
assert(isequal(string(t.state(:)),["RESET";"STARTUP_IMPEDANCE_CAL";"CLOCK_CAL";"INITIAL_EQ_TRAIN";"MISSION_TRACK"]));
assert(all(t.objective(3:end)>=0 & isfinite(t.objective(3:end))));
assert(all(t.ctle_applied_dB>=0 & t.ctle_applied_dB<=6));
assert(all(abs(t.ffe_current)<=1+1e-12));
assert(t.objective(end)>=t.objective(4)-1e-12);
assert(isfile(fullfile(o.resultRoot,'ctle_adaptation_trace.csv')));
cfg=phyConfig('vlsi2024_xsr'); cfg.link.nBits=512; cfg.model.enablePaperAdaptation=false;
p1=D2DPHY('disabled_a',1); p1.configure(cfg); r1=p1.run();
p2=D2DPHY('disabled_b',1); p2.configure(cfg); r2=p2.run();
assert(isequal(r1.rxBits,r2.rxBits) && isequal(r1.errCnt,r2.errCnt));
disp('Calibration/adaptation test OK');
end
