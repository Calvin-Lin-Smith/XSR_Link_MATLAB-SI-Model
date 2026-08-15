function summary = run_all_tests()
%RUN_ALL_TESTS Execute T1-T9 and write reproducible result artifacts.
root=fileparts(fileparts(mfilename('fullpath'))); addpath(genpath(fullfile(root,'src')),fullfile(root,'test'));
outDir=fullfile(root,'results'); if ~exist(outDir,'dir'), mkdir(outDir); end
names="T"+(1:9)'; passed=false(9,1); detail=strings(9,1);

% T1: eye metrics over rate/modulation/loss matrix.
mods={'NRZ','NRZ','PAM4','PAM4'}; bauds=[28 56 28 56]; losses=[0 4 8 10]; rows=[];
for m=1:4
    for L=losses
        c=quickCfg(); c.link.modulation=mods{m}; c.link.baud_Gbps=bauds(m); c.channel.lossNyq_dB=L;
        [r,p]=runPhy(c,1); eh=eyeHeight(p.rxPma.lane(1).afe.ctleOut,p.rxPma.lane(1).bestPhase,c.link.sps,c.link.modulation);
        rows=[rows; m bauds(m) L r.aggregateBer eh]; %#ok<AGROW>
        f=plotEye(p.rxPma.lane(1).afe.ctleOut,c.link.sps,fullfile(outDir,sprintf('T1_eye_%s_%gG_%gdB.png',mods{m},bauds(m),L))); close(f);
    end
end
T1=array2table(rows,'VariableNames',{'modeIndex','baudG','lossDb','ber','eyeHeight'}); writetable(T1,fullfile(outDir,'T1_eye_metrics.csv'));
passed(1)=all(isfinite(T1.eyeHeight)); detail(1)="16 configurations and eye PNG files";

% T2/T5/T8 use the statistically stable behavior operating points.
behavior=behavior_tests(); passed(2)=all(diff(behavior.loss.lossBer)>=-eps) && behavior.loss.lossBer(end)>behavior.loss.lossBer(1);
detail(2)="BER increases from 0 to 10 dB loss";

% T3: empirical bathtub at 8 dB with CTLE recovery.
c=quickCfg(); c.link.nBits=12000; c.channel.lossNyq_dB=8; c.rxPma.lane.ctleBoost_dB=8;
[~,p]=runPhy(c,1); wave=p.rxPma.lane(1).afe.ctleOut; d=p.rxPma.lane(1).delayUI; tx=p.rawPcs.referenceBits(:,1);
offset=(-floor(c.link.sps/2):ceil(c.link.sps/2))'; phase=zeros(size(offset)); delay=zeros(size(offset)); phaseBer=zeros(size(offset));
bps=1+strcmpi(c.link.modulation,'PAM4'); first=c.link.skipUI*bps+1;
for k=1:numel(offset)
    actual=p.rxPma.lane(1).bestPhase+offset(k); phase(k)=mod(actual,c.link.sps); delay(k)=d+floor(actual/c.link.sps);
    v=dspSample(wave,phase(k),delay(k),c.link.sps,0); rb=dspSlice(v,c.link.modulation);
    txFirst=first+delay(k)*bps; rxFirst=first; nAvail=min(numel(rb)-rxFirst+1,numel(tx)-txFirst+1);
    if nAvail<=0, phaseBer(k)=1; else, phaseBer(k)=sum(rb(rxFirst:rxFirst+nAvail-1)~=tx(txFirst:txFirst+nAvail-1))/nAvail; end
end
offsetUI=offset/c.link.sps; T3=table(offsetUI,phase,delay,phaseBer); writetable(T3,fullfile(outDir,'T3_bathtub.csv'));
f=figure('Visible','off'); semilogy(offsetUI,max(phaseBer,1/numel(tx)),'-o'); grid on; xlabel('Offset from aligned center (UI)'); ylabel('Empirical BER'); exportgraphics(f,fullfile(outDir,'T3_bathtub.png')); close(f);
center=find(offset==0); passed(3)=phaseBer(1)>phaseBer(center) && phaseBer(end)>phaseBer(center);
detail(3)="Empirical bathtub; no unsupported 1e-12 claim";

% T4: constrained FFE/CTLE sweep and P9 dB checks.
best=sweep_eq(); passed(4)=isfinite(best.ber) && isfinite(best.preEqDb) && isfinite(best.postEqDb); detail(4)="P9 formula and constrained tap scan";

% T5: CTLE BER and statistical eye improvement.
passed(5)=behavior.ctle.ctleBer(end)<behavior.ctle.ctleBer(1) && behavior.ctle.ctleEye(end)>behavior.ctle.ctleEye(1);
detail(5)="CTLE improves BER and eye opening";

% T6: supported patterns and exact unique-position error injection.
patterns={'PRBS7','PRBS15','PRBS31','PRQS10_SURROGATE'}; inj=[0 17]; t6rows=[];
for q=1:numel(patterns)
    for n=inj
        c=quickCfg(); c.rawPcs.pattern=patterns{q}; c.rawPcs.errInject=n; [r,~]=runPhy(c,1);
        t6rows=[t6rows; q n r.errCnt(1)]; %#ok<AGROW>
        assert(r.errCnt(1)==n,'T6 exact injection count failed.');
    end
end
T6=array2table(t6rows,'VariableNames',{'patternIndex','injected','detected'}); writetable(T6,fullfile(outDir,'T6_patterns.csv'));
passed(6)=all(T6.injected==T6.detected); detail(6)="PRQS10 explicitly marked surrogate; exact injection counts";

% T7: PAM4 is more noise-sensitive than NRZ at equal baud in this model.
modBer=zeros(2,1); compareMods={'NRZ','PAM4'}; for k=1:2
    c=quickCfg(); c.link.nBits=20000; c.link.modulation=compareMods{k}; c.link.baud_Gbps=28;
    c.link.snr_dB=16; c.channel.lossNyq_dB=4; c.rxPma.lane.ctleBoost_dB=4; [r,~]=runPhy(c,1); modBer(k)=r.aggregateBer;
end
T7=table(["NRZ";"PAM4"],modBer,'VariableNames',{'modulation','ber'}); writetable(T7,fullfile(outDir,'T7_modulation.csv'));
passed(7)=modBer(2)>modBer(1); detail(7)="Equal baud comparison; PAM4 BER exceeds NRZ";

% T8: CDR optimum must be internal in the scanned bandwidth range.
[~,ib]=min(behavior.cdr.cdrBer); [~,ir]=min(behavior.cdr.residualRms);
passed(8)=ib>1 && ib<height(behavior.cdr) && ir>1 && ir<height(behavior.cdr); detail(8)="Interior BER and residual-phase optimum";

% T9: shallow, serial-lane, and two-endpoint die-to-die NRZ loopback.
c=quickCfg(); c.link.modulation='NRZ'; c.link.nBits=4096; c.link.snr_dB=inf; c.channel.lossNyq_dB=0;
a=D2DPHY('endpointA',8); b=D2DPHY('endpointB',8); a.configure(c); b.configure(c);
sa=a.rawPcs.run(); shallow=true;
for j=1:8, shallow=shallow && isequal(dspSlice(sa{j},'NRZ'),a.rawPcs.txBits(:,j)); end
serialRes=a.run(); serial=serialRes.aggregateBer==0;
sa=a.rawPcs.run(); txA=a.txPma.run(sa); ab=cell(1,8); for j=1:8, ab{j}=a.channel(j).run(txA{j}); end
rxB=b.rxPma.run(ab,a.rawPcs.referenceBits); sb=cell(1,8); for j=1:8, sb{j}=dspMap(rxB(:,j),'NRZ'); end
txB=b.txPma.run(sb); ba=cell(1,8); for j=1:8, ba{j}=b.channel(j).run(txB{j}); end
rxA=a.rxPma.run(ba,a.rawPcs.referenceBits); dieToDie=countErrors(rxA,a.rawPcs.referenceBits,c.link.skipUI)==0;
T9=table(["shallow";"serial_lane";"die_to_die"],[shallow;serial;dieToDie],'VariableNames',{'mode','pass'}); writetable(T9,fullfile(outDir,'T9_loopback.csv'));
passed(9)=all(T9.pass); detail(9)="x8 shallow, serial, and two-endpoint NRZ";
probeManifest=struct('txPad',size(a.txPma.lane(1).driver.txPad),...
    'channelOut',size(a.channel(1).out),'ctleOut',size(a.rxPma.lane(1).afe.ctleOut),...
    'slicerIn',size(a.rxPma.lane(1).slicer.in),'rxBits',size(a.rxPma.lane(1).deserializer.rxBits));
fid=fopen(fullfile(outDir,'probes.json'),'w'); fprintf(fid,'%s',jsonencode(probeManifest,'PrettyPrint',true)); fclose(fid);

summary=table(names,passed,detail,'VariableNames',{'test','pass','detail'}); writetable(summary,fullfile(outDir,'summary.csv'));
manifest=struct('matlab',version,'timestamp',char(datetime('now','Format','yyyy-MM-dd''T''HH:mm:ss')),...
    'seed',42,'note','Behavioral relative-trend model; PRQS10 is a documented surrogate; empirical BER only.');
fid=fopen(fullfile(outDir,'manifest.json'),'w'); fprintf(fid,'%s',jsonencode(manifest,'PrettyPrint',true)); fclose(fid);
fid=fopen(fullfile(outDir,'junit.xml'),'w'); fprintf(fid,'<testsuite tests="9" failures="%d">\n',sum(~passed));
for k=1:9, fprintf(fid,'  <testcase name="T%d">',k); if ~passed(k), fprintf(fid,'<failure>%s</failure>',detail(k)); end; fprintf(fid,'</testcase>\n'); end
fprintf(fid,'</testsuite>\n'); fclose(fid); save(fullfile(outDir,'regression.mat'),'summary','T1','T3','T6','T7','T9','behavior','best');
assert(all(passed),'One or more T1-T9 tests failed.'); disp(summary); disp('T1-T9 regression OK');
end

function c=quickCfg()
c=phyConfig('ideal'); c.link.nBits=6000; c.link.snr_dB=30; c.link.seed=42;
end
function [r,p]=runPhy(c,nLane)
p=D2DPHY('reg_phy',nLane); p.configure(c); r=p.run();
end
function n=countErrors(rx,ref,skipUI)
first=skipUI+1; nb=min(size(rx,1),size(ref,1)); n=sum(sum(rx(first:nb,:)~=ref(first:nb,:)));
end
