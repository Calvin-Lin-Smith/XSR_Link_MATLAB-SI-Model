function test_channel_calibration()
%TEST_CHANNEL_CALIBRATION Frequency-aware analytic IL contract.
root=fileparts(fileparts(mfilename('fullpath'))); addpath(genpath(fullfile(root,'src')));
cfg=phyConfig('vlsi2024_xsr');
assert(strcmp(cfg.channel.mode,'analytic_il') && cfg.channel.refFreq_GHz==28);
assert(cfg.channel.lossAtRef_dB==8 && cfg.link.baud_GBd==56.25);

n=2^15; t=(0:n-1)'/cfg.link.sps; ref=cfg.channel.refFreq_GHz/cfg.link.baud_GBd;
for loss=cfg.channel.lossSweep_dB
    options=struct('mode','analytic_il','refFreq_GHz',28,'baud_GBd',56.25,...
        'lossAtRef_dB',loss,'poles',3);
    x=sin(2*pi*ref*t); y=dspChannel(x,cfg.link.sps,options);
    measured=-20*log10(rms(y(floor(n/2):end))/rms(x(floor(n/2):end)));
    assert(abs(measured-loss)<0.03);
end
assert(isequal(dspChannel((1:32)',16,struct('mode','analytic_il','refFreq_GHz',28,...
    'baud_GBd',56.25,'lossAtRef_dB',0,'poles',3)),(1:32)'));
assert(abs(28/56.25-0.5)>1e-4);
assert(abs(verifyChannel(32,8,3)-7.989)<0.15);

mustFail(@() dspChannel(ones(32,1),16,struct('mode','bad','refFreq_GHz',28,'baud_GBd',56.25,'lossAtRef_dB',8,'poles',3)));
mustFail(@() dspChannel(ones(32,1),16,struct('mode','analytic_il','refFreq_GHz',30,'baud_GBd',50,'lossAtRef_dB',8,'poles',3)));
mustFail(@() dspChannel(ones(32,1),16,struct('mode','analytic_il','refFreq_GHz',28,'baud_GBd',56.25,'lossAtRef_dB',-1,'poles',3)));
disp('Channel calibration tests OK');
end

function mustFail(f)
failed=false; try, f(); catch, failed=true; end
assert(failed);
end
