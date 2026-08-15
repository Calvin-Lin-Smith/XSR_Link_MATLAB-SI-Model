function best = sweep_eq()
%SWEEP_EQ Scan FFE pre/post and CTLE boost under total-current constraint.
root=fileparts(fileparts(mfilename('fullpath'))); addpath(genpath(fullfile(root,'src')));
outDir=fullfile(root,'results'); if ~exist(outDir,'dir'), mkdir(outDir); end
preList=[0 .05 .1 .15]; postList=[0 .05 .1 .15]; boostList=[0 2 4 6 8];
rows=[]; baselineBer=NaN;
for pre=preList
    for post=postList
        main=1-pre-post;
        if main<=0, continue; end
        [preDb,postDb]=ffeEqDb(main,pre,post);
        cm1=-pre; cp1=-post; top=main-cm1-cp1;
        preCheck=20*log10(top/(main+cm1-cp1)); postCheck=20*log10(top/(main-cm1+cp1));
        assert(abs(preDb-preCheck)<1e-12 && abs(postDb-postCheck)<1e-12,'FFE dB formula mismatch.');
        for boost=boostList
            c=phyConfig('ideal'); c.link.nBits=12000; c.link.snr_dB=30; c.link.seed=43;
            c.channel.lossNyq_dB=8; c.txPma.lane.txEqMain=main;
            c.txPma.lane.txEqPre=pre; c.txPma.lane.txEqPost=post; c.txPma.lane.ffeNormalize=false;
            c.rxPma.lane.ctleBoost_dB=boost;
            p=D2DPHY('eq_phy',1); p.configure(c); r=p.run();
            eh=eyeHeight(p.rxPma.lane(1).afe.ctleOut,p.rxPma.lane(1).bestPhase,c.link.sps,c.link.modulation);
            rows=[rows; pre post main boost preDb postDb r.aggregateBer eh]; %#ok<AGROW>
            if pre==0 && post==0 && boost==0, baselineBer=r.aggregateBer; end
        end
    end
end
T=array2table(rows,'VariableNames',{'pre','post','main','boostDb','preEqDb','postEqDb','ber','eyeHeight'});
score=T.ber-1e-9*T.eyeHeight; [~,idx]=min(score); best=table2struct(T(idx,:));
assert(best.ber<baselineBer,'Equalization scan did not beat the baseline BER.');
writetable(T,fullfile(outDir,'eq_sweep.csv')); save(fullfile(outDir,'eq_best.mat'),'best','baselineBer','T');
fprintf('EQ sweep OK: pre=%.2f post=%.2f main=%.2f boost=%.0f dB BER=%.3e (baseline %.3e)\n',...
    best.pre,best.post,best.main,best.boostDb,best.ber,baselineBer);
end
