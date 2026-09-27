function test_measurement_start_metadata()
%TEST_MEASUREMENT_START_METADATA BER uses first-lock global post-lock tail.
root=fileparts(fileparts(mfilename('fullpath'))); addpath(genpath(fullfile(root,'src')),fullfile(root,'test'));
[o,~]=run_vlsi2024_xsr('baseline',8192); m=o.metrics;
required={'first_valid_lock_ui','measurement_start_ui','continuous_tail_lock','tail_lock_losses','tail_cycle_slips','tail_level_valid'};
for k=1:numel(required), assert(ismember(required{k},m.Properties.VariableNames),required{k}); end
assert(all(m.continuous_tail_lock)&&all(m.tail_lock_losses==0)&&all(m.tail_cycle_slips==0)&&all(m.tail_level_valid));
assert(all(m.measurement_start_ui>=m.first_valid_lock_ui+o.cfg.model.debugStages.postLockWaitUI));
assert(all(m.measured_bits>0));
disp('Measurement first-lock metadata tests OK');
end
