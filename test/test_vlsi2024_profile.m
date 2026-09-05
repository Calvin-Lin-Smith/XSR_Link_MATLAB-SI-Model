function test_vlsi2024_profile()
%TEST_VLSI2024_PROFILE Contract for the isolated Stage-A paper runner.
root=fileparts(fileparts(mfilename('fullpath'))); addpath(genpath(fullfile(root,'src')));
addpath(fullfile(root,'test'));

cfg=phyConfig('vlsi2024_xsr');
assert(strcmp(cfg.paper.id,'VLSI2024_XSR_3nm'));
assert(strcmp(cfg.paper.mode,'link_behavioral'));
assert(isequal(cfg.paper.rateRange_Gbps,[9.8 113]));
assert(cfg.paper.txEyeRate_Gbps==112.5 && cfg.paper.berRate_Gbps==112 && cfg.paper.headlineRate_Gbps==113);
assert(strcmp(cfg.link.modulation,'PAM4') && cfg.link.sps==16 && cfg.link.nBits==2^18);
assert(cfg.link.lineRate_Gbps==112.5 && cfg.link.baud_GBd==56.25 && cfg.link.baud_Gbps==56.25);
assert(cfg.link.seed==202409 && strcmp(cfg.rawPcs.pattern,'PRBS31') && cfg.phy.nLane==8);
assert(cfg.channel.refFreq_GHz==28 && cfg.channel.lossAtRef_dB==8);
assert(isequal(cfg.channel.lossSweep_dB,[0.5 2 4 6 8 10]));
assert(cfg.paper.facts.table1LossAtRef_dB==10.8);
assert(~cfg.model.useReferenceAlign && ~cfg.model.enablePaperAdaptation);
assert(strcmp(cfg.model.resultRoot,'results/vlsi2024_xsr'));
assert(strcmp(cfg.paper.facts.packageTopology,'2D/2.5D CoWoS'));
assert(isequal(cfg.paper.facts.channelLength_mm,[1 80]));
assert(cfg.paper.facts.nextAt28GHz_dB==-40 && cfg.paper.facts.fextAt28GHz_dB==-38);
assert(cfg.paper.facts.quotedEnergy_pJ_per_bit==0.9 && cfg.paper.facts.dacLevels==206);
assert(cfg.paper.facts.ctleMaxBoost_dB==6 && cfg.paper.facts.ctleMaxStep_dB==0.2);
assert(cfg.paper.facts.samplerRoleCounts.data==12 && cfg.paper.facts.samplerRoleCounts.edge==4 && cfg.paper.facts.samplerRoleCounts.spare==4);
assert(cfg.paper.facts.dllCount==2 && cfg.paper.facts.piCount==1);
assert(strcmp(cfg.paper.facts.piInlDnl,'< +/-0.5 LSB'));
assert(cfg.paper.facts.pllTxIntegratedJitter_fs==194);

typical=phyConfig('typical'); ideal=phyConfig('ideal');
assert(strcmp(typical.link.modulation,'PAM4') && typical.link.baud_Gbps==56 && typical.link.nBits==12000);
assert(typical.link.seed==42 && typical.channel.lossNyq_dB==8 && typical.rxPma.lane.ctleBoost_dB==8);
assert(ideal.link.snr_dB==inf && ideal.link.rjUI_rms==0 && ideal.channel.lossNyq_dB==0);

[a,cfgA]=run_vlsi2024_xsr('baseline',256);
assert(strcmp(a.mode,'baseline') && strcmp(a.resultRoot,fullfile(root,'results','vlsi2024_xsr')));
assert(cfgA.link.nBits==256 && cfgA.phy.nLane==8);
assert(numel(a.result.errCnt)==8 && all(isfinite(a.metrics.empirical_BER)));
assert(isfield(cfgA.model,'appliedFfe') && isfield(cfgA.model,'appliedDac'));
assert(isfield(a.probes,'dataSamples') && isfield(a.probes,'edgeSamples') && isfield(a.probes,'spareSamples'));
assert(isfield(a.probes,'levelShiftCodes') && isfield(a.probes,'comparatorThresholds'));
assert(isfield(a.probes,'levelShiftedSamples') && isfield(a.probes,'quarterRateSamples'));
load(fullfile(a.resultRoot,'baseline_probes.mat'),'probes');
assert(isfield(probes,'dataSamples') && isfield(probes,'edgeSamples') && isfield(probes,'spareSamples'));
assert(all(a.metrics.measured_bits>0) && all(isfinite(a.metrics.errors)));
required={"config.json","assumptions.md","baseline_metrics.csv","baseline_probes.mat"};
for k=1:numel(required), assert(isfile(fullfile(a.resultRoot,required{k}))); end
assert(isfile(fullfile(root,'results','summary.csv')));
text=fileread(fullfile(a.resultRoot,'assumptions.md'));
assert(contains(text,'legacy oracle/reference-bit alignment'));
assert(contains(text,'reference-free in Task/Stage E'));
assert(contains(text,'112.5 Gb/s') && contains(text,'112 Gb/s') && contains(text,'113 Gb/s'));
assert(contains(text,'Finite simulation cannot prove'));
assert(contains(text,'No real S-parameters'));

[b,~]=run_vlsi2024_xsr('debug_1lane',256);
assert(numel(b.result.errCnt)==1 && b.cfg.phy.nLane==1);
[a2,~]=run_vlsi2024_xsr('baseline',256);
assert(isequal(a.metrics.errors,a2.metrics.errors) && isequal(a.metrics.measured_bits,a2.metrics.measured_bits));
assert(isequal(a.metrics.empirical_BER,a2.metrics.empirical_BER));
disp('VLSI2024 profile and runner tests OK');
end
