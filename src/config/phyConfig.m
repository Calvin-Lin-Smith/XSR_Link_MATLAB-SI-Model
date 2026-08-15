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
    otherwise
        error('phyConfig:Profile','Unknown configuration profile: %s',profile);
end
end
