function report = behavior_tests()
%BEHAVIOR_TESTS Verify channel, CTLE, jitter, and CDR trends.
root=fileparts(fileparts(mfilename('fullpath'))); addpath(genpath(fullfile(root,'src')));
outDir=fullfile(root,'results'); if ~exist(outDir,'dir'), mkdir(outDir); end

lossDb=[0 4 8 10]'; lossBer=zeros(size(lossDb));
for k=1:numel(lossDb)
    c=baseCfg(); c.channel.lossNyq_dB=lossDb(k); [r,~]=runOne(c); lossBer(k)=r.aggregateBer;
end
assert(all(diff(lossBer)>=-eps) && lossBer(end)>lossBer(1),'Channel-loss BER trend failed.');
lossTable=table(lossDb,lossBer); writetable(lossTable,fullfile(outDir,'behavior_loss.csv'));

boostDb=[0 2 4 6 8]'; ctleBer=zeros(size(boostDb)); ctleEye=zeros(size(boostDb));
for k=1:numel(boostDb)
    c=baseCfg(); c.channel.lossNyq_dB=8; c.rxPma.lane.ctleBoost_dB=boostDb(k);
    [r,p]=runOne(c); ctleBer(k)=r.aggregateBer;
    ctleEye(k)=eyeHeight(p.rxPma.lane(1).afe.ctleOut,p.rxPma.lane(1).bestPhase,c.link.sps,c.link.modulation);
end
assert(ctleBer(end)<ctleBer(1),'CTLE did not improve BER.');
assert(ctleEye(end)>ctleEye(1),'CTLE did not improve eye opening.');
ctleTable=table(boostDb,ctleBer,ctleEye); writetable(ctleTable,fullfile(outDir,'behavior_ctle.csv'));

rjUI=[0 .02 .05 .1 .2]'; rjBer=zeros(size(rjUI));
for k=1:numel(rjUI)
    c=baseCfg(); c.channel.lossNyq_dB=4; c.rxPma.lane.ctleBoost_dB=4; c.link.rjUI_rms=rjUI(k);
    [r,~]=runOne(c); rjBer(k)=r.aggregateBer;
end
assert(all(diff(rjBer)>=-eps) && rjBer(end)>rjBer(1),'RJ BER trend failed.');
rjTable=table(rjUI,rjBer); writetable(rjTable,fullfile(outDir,'behavior_rj.csv'));

cdrBw=[.001 .003 .01 .03 .1 .3]'; cdrBer=zeros(size(cdrBw)); residualRms=zeros(size(cdrBw));
for k=1:numel(cdrBw)
    c=baseCfg(); c.channel.lossNyq_dB=4; c.rxPma.lane.ctleBoost_dB=4;
    c.link.rjUI_rms=.03; c.link.djUI_pp=.15; c.rxPma.lane.clockMode='cdr'; c.link.cdrBw=cdrBw(k);
    [r,p]=runOne(c); cdrBer(k)=r.aggregateBer; residualRms(k)=rms(p.rxPma.support.pll.residualUI);
end
[~,ib]=min(cdrBer); [~,ir]=min(residualRms);
assert(ib>1 && ib<numel(cdrBw),'CDR BER optimum is not interior.');
assert(ir>1 && ir<numel(cdrBw),'CDR residual-phase optimum is not interior.');
cdrTable=table(cdrBw,cdrBer,residualRms); writetable(cdrTable,fullfile(outDir,'behavior_cdr.csv'));

report=struct('loss',lossTable,'ctle',ctleTable,'rj',rjTable,'cdr',cdrTable,...
    'bestCdrBw',cdrBw(ib)); save(fullfile(outDir,'behavior_results.mat'),'report');
fprintf('Behavior tests OK; best CDR BW = %.3g\n',cdrBw(ib));
end

function c=baseCfg()
c=phyConfig('ideal'); c.link.nBits=30000; c.link.snr_dB=30; c.link.seed=42;
end
function [r,p]=runOne(c)
p=D2DPHY('behavior_phy',1); p.configure(c); r=p.run();
end
