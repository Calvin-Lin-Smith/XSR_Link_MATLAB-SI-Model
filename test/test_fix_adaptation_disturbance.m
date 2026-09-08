function test_fix_adaptation_disturbance()
%TEST_FIX_ADAPTATION_DISTURBANCE Disturbance must degrade, then correction recover.
root=fileparts(fileparts(mfilename('fullpath'))); addpath(genpath(fullfile(root,'src'))); addpath(fullfile(root,'test'));
[on,~]=run_vlsi2024_xsr('adaptation',2048,'enablePaperAdaptation',true);
t=readtable(fullfile(on.resultRoot,'adaptation_state_trace.csv'));
required={'disturbed_objective','recovered_objective','control_changed','rx_term_gain_applied','tx_gain_residual'};
for k=1:numel(required), assert(ismember(required{k},t.Properties.VariableNames)); end
mission=t(strcmp(string(t.state),'MISSION_TRACK'),:); train=t(strcmp(string(t.state),'INITIAL_EQ_TRAIN'),:);
assert(mission.disturbed_objective<mission.recovered_objective && mission.recovered_objective>=train.objective);
assert(mission.control_changed && mission.rx_term_gain_applied~=1 || mission.tx_gain_residual<0.08);
[off,~]=run_vlsi2024_xsr('adaptation',2048,'enablePaperAdaptation',false);
toff=readtable(fullfile(off.resultRoot,'adaptation_state_trace.csv'));
assert(~off.cfg.model.enablePaperAdaptation && ~any(toff.control_changed));
assert(toff.objective(end)<mission.recovered_objective);
disp('Fix adaptation disturbance tests OK');
end
