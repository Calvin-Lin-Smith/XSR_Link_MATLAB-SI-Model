function test_static_milestone()
%TEST_STATIC_MILESTONE Check the short isolated A-D artifact schema.
root=fileparts(fileparts(mfilename('fullpath'))); addpath(genpath(fullfile(root,'src'))); addpath(fullfile(root,'test'));
o=run_vlsi2024_xsr('static_checkpoint',128);
assert(o.cfg.phy.nLane==8 && strcmp(o.mode,'static_checkpoint'));
names={"ffe_3_vs_6.csv","channel_il.csv","channel_il_at_28GHz.csv","ac_ctle.csv","static_regression_summary.csv"};
for k=1:numel(names), assert(isfile(fullfile(o.resultRoot,names{k}))); end
t=readtable(fullfile(o.resultRoot,'static_regression_summary.csv'));
required={'errors','measured_bits','empirical_BER','seed','ber_upper_95'};
for k=1:numel(required), assert(ismember(required{k},t.Properties.VariableNames)); end
assert(all(isfinite(t.empirical_BER)) && all(isfinite(t.ber_upper_95)));
disp('Static milestone tests OK');
end
