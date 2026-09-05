function test_vlsi2024_regression()
%TEST_VLSI2024_REGRESSION Complete paper artifact/schema smoke run.
root=fileparts(fileparts(mfilename('fullpath'))); addpath(genpath(fullfile(root,'src'))); addpath(fullfile(root,'test'));
o=run_vlsi2024_regression('full','nBits',4096);
assert(all(o.summary.pass));
required={"config.json","assumptions.md","baseline_metrics.csv","ffe_3_vs_6.csv","channel_il.csv",...
    "ctle_adaptation_trace.csv","cdr_lock_trace.csv","pi_code_trace.csv","residual_phase_histogram.csv",...
    "jitter_tolerance.csv","adaptation_state_trace.csv","paper_comparison.csv","paper_comparison.md",...
    "regression_summary.csv"};
for k=1:numel(required), assert(isfile(fullfile(o.resultRoot,required{k}))); end
assert(isfile(fullfile(o.resultRoot,'legacy_t1_t9','summary.csv')));
disp('VLSI2024 full regression test OK');
end
