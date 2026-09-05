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
nonzero=t.errors>0; assert(all(t.ber_upper_95(nonzero)>t.empirical_BER(nonzero)));
zero=t.errors==0; if any(zero), assert(all(abs(t.ber_upper_95(zero)-3./t.measured_bits(zero))<1e-12)); end
ffe=readtable(fullfile(o.resultRoot,'ffe_3_vs_6.csv')); ac=readtable(fullfile(o.resultRoot,'ac_ctle.csv'));
for k=1:numel(required), assert(ismember(required{k},ffe.Properties.VariableNames)); assert(ismember(required{k},ac.Properties.VariableNames)); end
ac0=ac.ac_enabled==0; ac1=ac.ac_enabled==1; assert(any(ac0)&&any(ac1));
assert(abs(ac.long_run_offset(find(ac0,1))-ac.long_run_offset(find(ac1,1)))>1e-6);
grid=o.cfg.rxPma.lane.ctleGrid_dB; applied=ac.ctle_applied_dB(~isnan(ac.ctle_applied_dB));
assert(min(applied)>=min(grid)-1e-12 && max(applied)<=max(grid)+1e-12);
assert(all(abs((applied/0.2)-round(applied/0.2))<1e-10));
assert(isfield(o.cfg.model,'appliedFfeSixTap') && numel(o.cfg.model.appliedFfeSixTap.appliedCoefficients)==6);
j=jsondecode(fileread(fullfile(o.resultRoot,'config.json')));
assert(isfield(j.model,'appliedFfeSixTap') && numel(j.model.appliedFfeSixTap.appliedCoefficients)==6);
disp('Static milestone tests OK');
end
