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
    case {'vlsi2024_xsr','vlsi2024_xsr_typical','vlsi2024_xsr_ideal'}
        cfg.paper.id='VLSI2024_XSR_3nm'; cfg.paper.preset='VLSI Typical'; cfg.paper.mode='link_behavioral';
        cfg.paper.rateRange_Gbps=[9.8 113]; cfg.paper.txEyeRate_Gbps=112.5;
        cfg.paper.berRate_Gbps=112; cfg.paper.headlineRate_Gbps=113;
        cfg.paper.rateContext=struct('range_Gbps',[9.8 113],'txEye_Gbps',112.5,...
            'ber_Gbps',112,'headlineTable_Gbps',113);
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
        cfg.channel.mode='analytic_il'; cfg.channel.refFreq_GHz=28; cfg.channel.baud_GBd=56.25;
        cfg.channel.lossAtRef_dB=8; cfg.channel.lossNyq_dB=8;
        cfg.channel.lossSweep_dB=[0.5 2 4 6 8 10];
        cfg.rxPma.lane.terminationMode='AC'; cfg.rxPma.lane.enableAcPre=true; cfg.rxPma.lane.enableAcPost=true;
        cfg.rxPma.lane.acPreCorner_UI=0.01; cfg.rxPma.lane.acPostCorner_UI=0.01;
        cfg.rxPma.lane.acInitialState='steady_state'; cfg.rxPma.lane.enableAgc=false;
        cfg.rxPma.lane.ctlePolicy='paper_grid'; cfg.rxPma.lane.ctleBoost_dB=4;
        cfg.rxPma.lane.ctleGrid_dB=0:0.2:6; cfg.rxPma.lane.ctleAppliedBoost_dB=4;
        cfg.rxPma.lane.samplerRoles=struct('enabled',true,'quarterRateBranches',4,...
            'roleCounts',struct('data',12,'edge',4,'spare',4,'total',20),...
            'levelShiftCodes',struct('data',[2 0 -2],'edge',0,'spare',[3 1 -1 -3]),...
            'samplerOffsetCodes',0,...
            'thresholdAssumptions',[-2 0 2],...
            'offsetCalibrationPlaceholder','not implemented in Stage D');
        cfg.model.useReferenceAlign=false; cfg.model.enablePaperAdaptation=false;
        cfg.model.trainingMode='decision_directed';
        cfg.model.cdrOptions=struct('nCodes',64,'initialPhaseUI',0.5,'loopGainCodes',1,...
            'loopBandwidthProxy',1/64,'updateCadence',1,'lockWindow',32,'lockToleranceUI',0.08,...
            'mismatchBoundLSB',0.49,'mismatchSeed',202409,...
            'enabled',true,'maxStepCodes',2);
        cfg.model.debugStages=struct('startupCalibration',true,'ctleTraining',true,'ffeTraining',true,...
            'samplerCalibration',true,'clockTraining',true,'cdrEnabled',true,...
            'startupCalibrationBudgetUI',64,'ctleTrainingBudgetUI',128,'ffeTrainingBudgetUI',128,...
            'samplerCalibrationBudgetUI',64,'clockTrainingBudgetUI',64,'postLockWaitUI',16);
        cfg.model.debugOptions=struct('postLockWaitUI',16);
        cfg.model.resultRoot='results/vlsi2024_xsr';
        cfg.paper.facts.packageTopology='2D/2.5D CoWoS';
        cfg.paper.facts.channelLength_mm=[1 80];
        cfg.paper.facts.nextAt28GHz_dB=-40; cfg.paper.facts.fextAt28GHz_dB=-38;
        cfg.paper.facts.next_dB=-40; cfg.paper.facts.fext_dB=-38;
        cfg.paper.facts.quotedEnergy_pJ_per_bit=0.9; cfg.paper.facts.dacLevels=206;
        cfg.paper.facts.energy_pJ_per_bit=0.9;
        cfg.paper.facts.ctleMaxBoost_dB=6; cfg.paper.facts.ctleMaxStep_dB=0.2;
        cfg.paper.facts.samplerRoleCounts=struct('data',12,'edge',4,'spare',4,'total',20);
        cfg.paper.facts.dllCount=2; cfg.paper.facts.piCount=1;
        cfg.paper.facts.piInlDnl='< +/-0.5 LSB';
        cfg.paper.facts.piInlDnl_LSB='< +/-0.5 LSB';
        cfg.paper.facts.pllTxIntegratedJitter_fs=194;
        cfg.paper.facts.pllTxIntegratedJitter_UI=194e-15/(1/(cfg.link.baud_GBd*1e9));
        cfg.paper.facts.pllTxIntegratedJitterContext='PLL+TX integrated; filter/measurement context';
        cfg.paper.facts.table1LossAtRef_dB=10.8;
        cfg.paper.facts.table1Loss_dB=10.8; cfg.paper.facts.table1_IL_dB=10.8;
        cfg.paper.assumptions.channelModel='calibrated analytic_il at 28 GHz; no real S-parameters';
        cfg.paper.assumptions.quotedEnergyScope='quoted only; not a model prediction';
        cfg.paper.assumptions.crosstalk='NEXT/FEXT facts recorded; MIMO crosstalk unmodeled';
        if strcmp(profile,'vlsi2024_xsr_ideal')
            cfg.paper.preset='VLSI Ideal';
            cfg.link.snr_dB=inf; cfg.link.rjUI_rms=0; cfg.link.djUI_pp=0;
            cfg.channel.lossAtRef_dB=0; cfg.channel.lossNyq_dB=0;
            cfg.channel.lossSweep_dB=0;
            cfg.txPma.lane.ffeCoeffs=[0 1 0]; cfg.txPma.lane.ffeNormalize=true;
            cfg.txPma.lane.sixTapPreset.coeffs=[0 0 1 0 0 0];
            cfg.txPma.lane.enableDacQuantization=false; cfg.txPma.lane.gainError=0;
            cfg.txPma.lane.enableSwingCalibration=true;
            cfg.rxPma.lane.enableAcPre=false; cfg.rxPma.lane.enableAcPost=false;
            cfg.rxPma.lane.ctleBoost_dB=0; cfg.rxPma.lane.ctleGrid_dB=0; cfg.rxPma.lane.ctleAppliedBoost_dB=0;
            cfg.model.cdrOptions.mismatchBoundLSB=0; cfg.model.cdrOptions.mismatchSeed=0;
            cfg.model.cdrOptions.staticPhaseSkewUI=0; cfg.model.cdrOptions.staticDutyCorrectionUI=0;
            cfg.model.enablePaperAdaptation=false;
        end
    otherwise
        error('phyConfig:Profile','Unknown configuration profile: %s',profile);
end
end
