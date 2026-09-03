function cfg = phyConfig(profile)
%PHYCONFIG Register-style D2D PHY configuration profiles.
%   phyConfig()          returns a typical working non-ideal D2D link.
%   phyConfig('ideal')   returns the zero-impairment verification baseline.
if nargin < 1 || isempty(profile), profile = 'typical'; end
profile = lower(char(profile));

% Link and simulation controls.
cfg.link.modulation='PAM4'; cfg.link.baud_Gbps=56; cfg.link.sps=16;
cfg.link.nBits=12000; cfg.link.skipUI=32; cfg.link.snr_dB=28;
cfg.link.rjUI_rms=0.005; cfg.link.djUI_pp=0.02; cfg.link.djFreq=1e-3;
cfg.link.cdrBw=0.1; cfg.link.seed=42;

% Raw PCS pattern and deliberate checker error injection.
cfg.rawPcs.pattern='PRBS31'; cfg.rawPcs.errInject=0;

% TX FFE effective taps are [-pre, main, -post], with total magnitude 1.
cfg.txPma.lane.txEqMain=0.98; cfg.txPma.lane.txEqPre=0.01; cfg.txPma.lane.txEqPost=0.01;
cfg.txPma.lane.ffeNormalize=false; cfg.txPma.lane.amplitude=1;

% RX termination, CTLE, and recovered-clock mode.
cfg.rxPma.lane.ctleBoost_dB=8; cfg.rxPma.lane.ctleFz=0.25;
cfg.rxPma.lane.termGain=1; cfg.rxPma.lane.clockMode='forwarded';

% Package/interposer channel loss at Nyquist and analytic filter order.
cfg.channel.lossNyq_dB=8; cfg.channel.poles=3;

switch profile
    case 'typical'
        % Keep the non-ideal but equalized defaults above.
    case 'ideal'
        cfg.link.snr_dB=inf; cfg.link.rjUI_rms=0; cfg.link.djUI_pp=0;
        cfg.link.cdrBw=0.01;
        cfg.txPma.lane.txEqMain=1; cfg.txPma.lane.txEqPre=0; cfg.txPma.lane.txEqPost=0;
        cfg.txPma.lane.ffeNormalize=true;
        cfg.rxPma.lane.ctleBoost_dB=0; cfg.rxPma.lane.clockMode='forwarded';
        cfg.channel.lossNyq_dB=0;
    case 'vlsi2024_xsr'
        cfg.paper.id='VLSI2024_XSR_3nm'; cfg.paper.mode='link_behavioral';
        cfg.paper.rateRange_Gbps=[9.8 113]; cfg.paper.txEyeRate_Gbps=112.5;
        cfg.paper.berRate_Gbps=112; cfg.paper.headlineRate_Gbps=113;
        cfg.link.modulation='PAM4'; cfg.link.sps=16; cfg.link.nBits=2^18;
        cfg.link.seed=202409; cfg.link.lineRate_Gbps=112.5;
        cfg.link.baud_GBd=56.25; cfg.link.baud_Gbps=56.25;
        cfg.rawPcs.pattern='PRBS31'; cfg.phy.nLane=8;
        cfg.txPma.lane.ffeMode='three_tap'; cfg.txPma.lane.ffeOffsets=[-1 0 1];
        cfg.txPma.lane.ffeCoeffs=[-0.01 0.98 -0.01]; cfg.txPma.lane.ffeNormalize=true;
        cfg.txPma.lane.ffeCurrentConstraint=1;
        cfg.txPma.lane.ffe=struct('mode','three_tap','offsets',[-1 0 1],...
            'coeffs',[-0.01 0.98 -0.01],'normalize',true,'currentConstraint',1);
        cfg.txPma.lane.sixTapPreset=struct('offsets',[-2 -1 0 1 2 3],...
            'coeffs',[-0.03 -0.05 0.88 -0.06 -0.04 -0.02],...
            'description','model-selected regression assumption; not paper-disclosed coefficients');
        cfg.txPma.lane.enableDacQuantization=true; cfg.txPma.lane.dacLevels=206;
        cfg.txPma.lane.targetSwing=1; cfg.txPma.lane.gainError=0;
        cfg.txPma.lane.enableSwingCalibration=true;
        cfg.channel.mode='legacy_nyquist'; cfg.channel.refFreq_GHz=28;
        cfg.channel.lossAtRef_dB=8; cfg.channel.lossNyq_dB=8;
        cfg.channel.lossSweep_dB=[0.5 2 4 6 8 10];
        cfg.model.useReferenceAlign=false; cfg.model.enablePaperAdaptation=false;
        cfg.model.resultRoot='results/vlsi2024_xsr';
        cfg.paper.facts.packageTopology='2D/2.5D CoWoS';
        cfg.paper.facts.channelLength_mm=[1 80];
        cfg.paper.facts.nextAt28GHz_dB=-40; cfg.paper.facts.fextAt28GHz_dB=-38;
        cfg.paper.facts.quotedEnergy_pJ_per_bit=0.9; cfg.paper.facts.dacLevels=206;
        cfg.paper.facts.ctleMaxBoost_dB=6; cfg.paper.facts.ctleMaxStep_dB=0.2;
        cfg.paper.facts.samplerRoleCounts=struct('data',12,'edge',4,'spare',4,'total',20);
        cfg.paper.facts.dllCount=2; cfg.paper.facts.piCount=1;
        cfg.paper.facts.piInlDnl='< +/-0.5 LSB';
        cfg.paper.facts.pllTxIntegratedJitter_fs=194;
        cfg.paper.facts.pllTxIntegratedJitterContext='PLL+TX integrated; filter/measurement context';
        cfg.paper.facts.table1LossAtRef_dB=10.8;
        cfg.paper.assumptions.channelModel='legacy Nyquist-normalized bootstrap until Stage C';
        cfg.paper.assumptions.quotedEnergyScope='quoted only; not a model prediction';
        cfg.paper.assumptions.crosstalk='NEXT/FEXT facts recorded; MIMO crosstalk unmodeled';
    otherwise
        error('phyConfig:Profile','Unknown configuration profile: %s',profile);
end
end
