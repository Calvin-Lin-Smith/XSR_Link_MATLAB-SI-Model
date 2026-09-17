classdef D2DWorkbench < handle
    properties
        Root
        Cfg
        Phy
        Result
        Figure
        ModelTree
        ConfigTable
        ProbeDropDown
        LaneDropDown
        Axes
        MetricsTable
        LogArea
        LossField
        BoostField
        RjField
        CdrField
        PreField
        PostField
        StatusLabel
        ConfigPaths
        ProfileDropDown
    end

    methods
        function app=D2DWorkbench(root)
            app.Root=root; app.Cfg=loadD2DSharedConfig();
            app.buildUi(); app.populateModelTree(); app.populateConfigTable();
            app.log('D2D PHY Workbench ready. Preview a profile, then Apply + Sync explicitly.');
        end

        function buildUi(app)
            app.Figure=uifigure('Name','D2D 112G PHY Model Workbench','Position',[40 40 1720 960],...
                'Color',[0.95 0.96 0.98]);
            main=uigridlayout(app.Figure,[1 3]); main.ColumnWidth={300,540,'1x'};
            main.Padding=[12 12 12 12]; main.ColumnSpacing=12;

            left=uipanel(main,'Title','D2D IP Hierarchy','BackgroundColor',[1 1 1]); left.Layout.Column=1;
            lg=uigridlayout(left,[3 1]); lg.RowHeight={32,'1x',280}; lg.Padding=[8 8 8 8]; lg.RowSpacing=8;
            uilabel(lg,'Text','Databook-aligned x8 structure','FontWeight','bold','FontColor',[0.18 0.23 0.32]);
            app.ModelTree=uitree(lg,'SelectionChangedFcn',@(s,e)app.onTreeSelection(e));
            statusPanel=uipanel(lg,'Title','Status','BackgroundColor',[0.98 0.99 1]);
            sg=uigridlayout(statusPanel,[2 1]); sg.RowHeight={26,'1x'}; sg.Padding=[6 6 6 6];
            app.StatusLabel=uilabel(sg,'Text','Idle','FontWeight','bold','FontColor',[0.15 0.35 0.22]);
            app.LogArea=uitextarea(sg,'Editable','off','Value','');

            center=uipanel(main,'Title','Configuration and Tests','BackgroundColor',[1 1 1]); center.Layout.Column=2;
            cg=uigridlayout(center,[2 1]); cg.RowHeight={'1x',260};
            cg.Padding=[8 8 8 8]; cg.RowSpacing=10;
            tabs=uitabgroup(cg); tabs.Layout.Row=1;
            cfgTab=uitab(tabs,'Title','Model Parameters');
            cfgGrid=uigridlayout(cfgTab,[3 1]); cfgGrid.RowHeight={34,'1x',82};
            cfgGrid.Padding=[8 8 8 8]; cfgGrid.RowSpacing=8;
            profileRow=uigridlayout(cfgGrid,[1 3]); profileRow.Layout.Row=1;
            profileRow.ColumnWidth={100,'1x',130}; profileRow.Padding=[0 0 0 0]; profileRow.ColumnSpacing=8;
            uilabel(profileRow,'Text','Paper profile','FontWeight','bold');
            app.ProfileDropDown=uidropdown(profileRow,'Items',D2DWorkbench.profileNames(),...
                'Value',D2DWorkbench.profileName(app.Cfg));
            uibutton(profileRow,'Text','Load / Preview','ButtonPushedFcn',@(s,e)app.loadProfile());
            app.ConfigTable=uitable(cfgGrid,'ColumnName',{'Group','Parameter','Value'},...
                'ColumnWidth',{95,230,130},'ColumnEditable',[false false true],...
                'CellEditCallback',@(s,e)app.onConfigEdit(e));
            btnRow=uigridlayout(cfgGrid,[2 3]); btnRow.Layout.Row=3;
            btnRow.ColumnWidth={'1x','1x','1x'}; btnRow.RowHeight={'1x','1x'};
            btnRow.Padding=[0 0 0 0]; btnRow.ColumnSpacing=8; btnRow.RowSpacing=6;
            uibutton(btnRow,'Text','Apply + Sync','FontWeight','bold','ButtonPushedFcn',@(s,e)app.applyConfigTable());
            uibutton(btnRow,'Text','Load from SLX','ButtonPushedFcn',@(s,e)app.loadSharedConfig());
            uibutton(btnRow,'Text','Run x8 Link','FontWeight','bold','BackgroundColor',[0.12 0.42 0.72],...
                'FontColor',[1 1 1],'ButtonPushedFcn',@(s,e)app.runLink());
            uibutton(btnRow,'Text','Reset Ideal','ButtonPushedFcn',@(s,e)app.resetConfig());
            uibutton(btnRow,'Text','Reset Typical','ButtonPushedFcn',@(s,e)app.resetTypical());
            uilabel(btnRow,'Text','Shared variable: d2dCfg','HorizontalAlignment','center','FontColor',[0.35 0.4 0.48]);

            testTab=uitab(tabs,'Title','Test Parameters');
            tg=uigridlayout(testTab,[7 2]); tg.ColumnWidth={135,'1x'};
            tg.Padding=[10 10 10 10]; tg.RowSpacing=7; tg.ColumnSpacing=10;
            uilabel(tg,'Text','Loss points (dB)'); app.LossField=uieditfield(tg,'text','Value','0 4 8 10');
            uilabel(tg,'Text','CTLE boost (dB)'); app.BoostField=uieditfield(tg,'text','Value','0 2 4 6 8');
            uilabel(tg,'Text','RJ RMS (UI)'); app.RjField=uieditfield(tg,'text','Value','0 .02 .05 .1 .2');
            uilabel(tg,'Text','CDR bandwidth'); app.CdrField=uieditfield(tg,'text','Value','.001 .003 .01 .03 .1 .3');
            uilabel(tg,'Text','FFE pre'); app.PreField=uieditfield(tg,'text','Value','0 .05 .1 .15');
            uilabel(tg,'Text','FFE post'); app.PostField=uieditfield(tg,'text','Value','0 .05 .1 .15');
            uilabel(tg,'Text','Note'); uilabel(tg,'Text','Sweep uses current model parameters and one lane.');

            tests=uipanel(cg,'Title','Test Actions','BackgroundColor',[1 1 1]); tests.Layout.Row=2;
            bg=uigridlayout(tests,[4 3]); bg.RowHeight={'1x','1x','1x','1x'};
            bg.Padding=[8 8 8 8]; bg.RowSpacing=8; bg.ColumnSpacing=8;
            uibutton(bg,'Text','Loss Sweep','ButtonPushedFcn',@(s,e)app.runSweep('loss'));
            uibutton(bg,'Text','CTLE Sweep','ButtonPushedFcn',@(s,e)app.runSweep('ctle'));
            uibutton(bg,'Text','RJ Sweep','ButtonPushedFcn',@(s,e)app.runSweep('rj'));
            uibutton(bg,'Text','CDR Sweep','ButtonPushedFcn',@(s,e)app.runSweep('cdr'));
            uibutton(bg,'Text','FFE + CTLE Scan','ButtonPushedFcn',@(s,e)app.runEqScan());
            uibutton(bg,'Text','Behavior Suite','ButtonPushedFcn',@(s,e)app.runBehaviorSuite());
            uibutton(bg,'Text','Standard T1-T9','ButtonPushedFcn',@(s,e)app.runRegression());
            uibutton(bg,'Text','Paper Baseline','ButtonPushedFcn',@(s,e)app.runPaperBaseline());
            uibutton(bg,'Text','Paper Full Regression','ButtonPushedFcn',@(s,e)app.runPaperRegression());
            uibutton(bg,'Text','Paper Adaptation','ButtonPushedFcn',@(s,e)app.runPaperAdaptation());
            uibutton(bg,'Text','Open Results Folder','ButtonPushedFcn',@(s,e)winopen(fullfile(app.Root,'results')));
            uibutton(bg,'Text','Clear Log','ButtonPushedFcn',@(s,e)set(app.LogArea,'Value',''));

            right=uipanel(main,'Title','White-box Probes and Results','BackgroundColor',[1 1 1]); right.Layout.Column=3;
            rg=uigridlayout(right,[4 1]); rg.RowHeight={44,'2x',230,118};
            rg.Padding=[8 8 8 8]; rg.RowSpacing=10;
            probeRow=uigridlayout(rg,[1 4]); probeRow.ColumnWidth={48,'1x',42,105}; probeRow.Padding=[0 0 0 0]; probeRow.ColumnSpacing=8;
            uilabel(probeRow,'Text','Probe','FontWeight','bold');
            app.ProbeDropDown=uidropdown(probeRow,'Items',app.probeItems(),'Value','RX CTLE output');
            uilabel(probeRow,'Text','Lane','FontWeight','bold');
            app.LaneDropDown=uidropdown(probeRow,'Items',app.laneItems(),'Value','Lane 1',...
                'ValueChangedFcn',@(s,e)app.plotSelectedProbeMulti());
            app.ProbeDropDown.ValueChangedFcn=@(s,e)app.plotSelectedProbeMulti();
            app.Axes=uiaxes(rg); title(app.Axes,'Run the model to view an internal node'); grid(app.Axes,'on');
            app.Axes.Box='on'; app.Axes.FontSize=11;
            app.MetricsTable=uitable(rg,'ColumnName',{'Lane','BER','Errors','Measured bits','Phase','Delay UI','CTLE gain','Eye height'},...
                'ColumnWidth',{85,82,62,88,52,62,76,76});
            uitextarea(rg,'Editable','off','Value',{
                'WORKFLOW',...
                '1  Edit and apply model parameters',...
                '2  Run the x8 link',...
                '3  Select a probe and Lane 1-8 / All Lanes',...
                '4  Inspect per-lane metrics and worst lane',...
                '5  Run sweeps or T1-T9; artifacts go to results/'});
        end

        function populateModelTree(app)
            delete(app.ModelTree.Children);
            root=uitreenode(app.ModelTree,'Text','D2DPHY  |  x8 Top','NodeData','top');
            uitreenode(root,'Text','RAW_PCS_RAW_PCS <RawPcs>','NodeData','rawPcs');
            tx=uitreenode(root,'Text','TX PMA <TxPma>','NodeData','txPma');
            supTx=uitreenode(tx,'Text','SUP_TX_SUP <TxSupport>','NodeData','txSupport');
            uitreenode(supTx,'Text','PLL <Pll>','NodeData','txPll');
            for j=1:8
                lane=uitreenode(tx,'Text',sprintf('TX_TX_%d <TxLane>',j),'NodeData',sprintf('txLane%d',j));
                uitreenode(lane,'Text','FFE <Ffe>','NodeData',sprintf('txFfe%d',j));
                uitreenode(lane,'Text','Serializer <Serializer>','NodeData',sprintf('serializer%d',j));
                uitreenode(lane,'Text','Driver / TX Pad <Driver>','NodeData',sprintf('txPad%d',j));
            end
            channels=uitreenode(root,'Text','Die-to-Die Channels x8','NodeData','channels');
            for j=1:8, uitreenode(channels,'Text',sprintf('Channel %d <Channel>',j),'NodeData',sprintf('channel%d',j)); end
            rx=uitreenode(root,'Text','RX PMA <RxPma>','NodeData','rxPma');
            supRx=uitreenode(rx,'Text','SUP_RX_SUP <RxSupport>','NodeData','rxSupport');
            uitreenode(supRx,'Text','PLL / CDR <Pll>','NodeData','rxPll');
            for j=1:8
                lane=uitreenode(rx,'Text',sprintf('RX_RX_%d <RxLane>',j),'NodeData',sprintf('rxLane%d',j));
                afe=uitreenode(lane,'Text','AFE <Afe>','NodeData',sprintf('afe%d',j));
                uitreenode(afe,'Text','TERM <Term>','NodeData',sprintf('term%d',j));
                uitreenode(afe,'Text','CTLE <Ctle>','NodeData',sprintf('ctle%d',j));
                uitreenode(lane,'Text','Slicer <Slicer>','NodeData',sprintf('slicer%d',j));
                uitreenode(lane,'Text','Deserializer <Deserializer>','NodeData',sprintf('deserializer%d',j));
            end
            expand(root);
        end

        function populateConfigTable(app)
            paths=unique([D2DWorkbench.baseConfigPaths(),D2DWorkbench.paperConfigPaths()],'stable');
            app.ConfigPaths=paths(cellfun(@(p)D2DWorkbench.hasNested(app.Cfg,strsplit(p,'.')),paths));
            data=cell(numel(app.ConfigPaths),3);
            for k=1:numel(app.ConfigPaths)
                parts=strsplit(app.ConfigPaths{k},'.'); data{k,1}=parts{1}; data{k,2}=strjoin(parts(2:end),'.');
                data{k,3}=app.valueToText(app.getNested(app.Cfg,parts));
            end
            app.ConfigTable.Data=data;
        end

        function onConfigEdit(app,~), app.applyConfigTable(); end

        function loadProfile(app)
            app.Cfg=phyConfig(app.ProfileDropDown.Value); app.populateConfigTable();
            app.log(['Loaded ' app.ProfileDropDown.Value ' for preview. Press Apply + Sync to publish it.']);
        end

        function applyConfigTable(app)
            data=app.ConfigTable.Data;
            for k=1:numel(app.ConfigPaths)
                parts=strsplit(app.ConfigPaths{k},'.'); old=app.getNested(app.Cfg,parts);
                value=app.parseValue(data{k,3},old); app.Cfg=app.setNested(app.Cfg,parts,value);
            end
            syncD2DConfig(app.Cfg);
            app.log('Configuration applied and synchronized to d2dCfg / Simulink.');
        end

        function resetConfig(app)
            app.Cfg=phyConfig('ideal'); app.populateConfigTable(); app.ProfileDropDown.Value='ideal'; syncD2DConfig(app.Cfg);
            app.log('Configuration reset to ideal baseline and synchronized.');
        end

        function resetTypical(app)
            app.Cfg=phyConfig('typical'); app.populateConfigTable(); app.ProfileDropDown.Value='typical'; syncD2DConfig(app.Cfg);
            app.log('Configuration reset to typical profile and synchronized.');
        end

        function loadSharedConfig(app)
            app.Cfg=loadD2DSharedConfig(); app.populateConfigTable();
            if ~isempty(app.ProfileDropDown), app.ProfileDropDown.Value=D2DWorkbench.profileName(app.Cfg); end
            app.log('Configuration loaded from the Simulink/shared d2dCfg workspace.');
        end

        function runLink(app)
            app.execute('x8 link',@doRun);
            function doRun()
                app.applyConfigTable(); app.Phy=D2DPHY(); app.Phy.configure(app.Cfg); app.Result=app.Phy.run();
                app.updateLaneMetrics();
                app.plotSelectedProbeMulti(); app.log(sprintf('x8 link complete: BER %.3e',app.Result.aggregateBer));
            end
        end

        function updateLaneMetrics(app)
            nLane=numel(app.Phy.rxPma.lane); err=app.Result.errCnt(:); nBits=app.Result.nMeasured(:);
            ber=err./max(nBits,1); phase=zeros(nLane,1); delay=zeros(nLane,1); gain=zeros(nLane,1); eye=zeros(nLane,1);
            for k=1:nLane
                phase(k)=app.Phy.rxPma.lane(k).bestPhase; delay(k)=app.Phy.rxPma.lane(k).delayUI;
                gain(k)=app.Phy.rxPma.lane(k).afe.agcGain;
                try
                    eye(k)=eyeHeight(app.Phy.rxPma.lane(k).afe.ctleOut,phase(k),app.Cfg.link.sps,app.Cfg.link.modulation);
                catch
                    eye(k)=NaN;
                end
            end
            labels=["Aggregate"; "Lane "+string((1:nLane)')];
            totalErr=sum(err); totalBits=sum(nBits); totalBer=totalErr/max(totalBits,1);
            app.MetricsTable.Data=table(labels,[totalBer;ber],[totalErr;err],[totalBits;nBits],...
                [NaN;phase],[NaN;delay],[NaN;gain],[NaN;eye],...
                'VariableNames',{'Lane','BER','Errors','MeasuredBits','Phase','DelayUI','CTLEGain','EyeHeight'});
            [worstBer,worst]=max(ber);
            app.log(sprintf('Worst lane: Lane %d, BER %.3e, eye height %.4f.',worst,worstBer,eye(worst)));
        end

        function runSweep(app,kind)
            app.execute([kind ' sweep'],@doSweep);
            function doSweep()
                app.applyConfigTable();
                switch kind
                    case 'loss', x=app.parseVector(app.LossField.Value); xLabel='Loss (dB)';
                    case 'ctle', x=app.parseVector(app.BoostField.Value); xLabel='CTLE boost (dB)';
                    case 'rj', x=app.parseVector(app.RjField.Value); xLabel='RJ RMS (UI)';
                    case 'cdr', x=app.parseVector(app.CdrField.Value); xLabel='CDR bandwidth';
                end
                ber=zeros(numel(x),1); residual=nan(numel(x),1);
                for k=1:numel(x)
                    c=app.Cfg; c.link.nBits=min(c.link.nBits,30000);
                    switch kind
                        case 'loss', c.channel.lossNyq_dB=x(k);
                        case 'ctle', c.rxPma.lane.ctleBoost_dB=x(k);
                        case 'rj', c.link.rjUI_rms=x(k);
                        case 'cdr', c.rxPma.lane.clockMode='cdr'; c.link.cdrBw=x(k);
                    end
                    p=D2DPHY('gui_sweep',1); p.configure(c); r=p.run(); ber(k)=r.aggregateBer;
                    if strcmp(kind,'cdr'), residual(k)=rms(p.rxPma.support.pll.residualUI); end
                    drawnow limitrate;
                end
                cla(app.Axes); semilogy(app.Axes,x,max(ber,1./max(app.Cfg.link.nBits,1)),'-o','LineWidth',1.5); grid(app.Axes,'on');
                xlabel(app.Axes,xLabel); ylabel(app.Axes,'Empirical BER'); title(app.Axes,[upper(kind) ' sweep']);
                app.MetricsTable.Data=table(x(:),ber,residual,'VariableNames',{'parameter','ber','residualRms'});
                writetable(app.MetricsTable.Data,fullfile(app.Root,'results',['gui_' kind '_sweep.csv']));
                app.log(sprintf('%s sweep complete (%d points).',kind,numel(x)));
            end
        end

        function runEqScan(app)
            app.execute('FFE + CTLE scan',@doScan);
            function doScan()
                app.applyConfigTable(); pre=app.parseVector(app.PreField.Value); post=app.parseVector(app.PostField.Value);
                boost=app.parseVector(app.BoostField.Value); rows=[]; bestBer=inf;
                for a=pre, for b=post
                    main=1-a-b; if main<=0, continue; end
                    for cBoost=boost
                        c=app.Cfg; c.link.nBits=min(c.link.nBits,15000); c.txPma.lane.txEqMain=main;
                        c.txPma.lane.txEqPre=a; c.txPma.lane.txEqPost=b; c.txPma.lane.ffeNormalize=false;
                        c.rxPma.lane.ctleBoost_dB=cBoost; p=D2DPHY('gui_eq',1); p.configure(c); r=p.run();
                        rows=[rows;a b main cBoost r.aggregateBer]; %#ok<AGROW>
                        bestBer=min(bestBer,r.aggregateBer); drawnow limitrate;
                    end
                end, end
                T=array2table(rows,'VariableNames',{'pre','post','main','boostDb','ber'}); app.MetricsTable.Data=T;
                writetable(T,fullfile(app.Root,'results','gui_eq_sweep.csv')); cla(app.Axes);
                scatter(app.Axes,T.boostDb,T.ber,35,T.pre+T.post,'filled'); set(app.Axes,'YScale','log'); grid(app.Axes,'on');
                xlabel(app.Axes,'CTLE boost (dB)'); ylabel(app.Axes,'BER'); title(app.Axes,'FFE + CTLE scan'); colorbar(app.Axes);
                app.log(sprintf('EQ scan complete: best BER %.3e.',bestBer));
            end
        end

        function runBehaviorSuite(app)
            app.execute('behavior suite',@doSuite);
            function doSuite()
                report=behavior_tests(); app.MetricsTable.Data=report.cdr; cla(app.Axes);
                semilogy(app.Axes,report.cdr.cdrBw,max(report.cdr.cdrBer,eps),'-o'); grid(app.Axes,'on');
                xlabel(app.Axes,'CDR bandwidth'); ylabel(app.Axes,'BER'); title(app.Axes,'Behavior suite: CDR');
                app.log(sprintf('Behavior suite passed; best CDR BW %.3g.',report.bestCdrBw));
            end
        end

        function runRegression(app)
            app.execute('T1-T9 regression',@doRegression);
            function doRegression()
                summary=run_all_tests(); app.MetricsTable.Data=summary; cla(app.Axes);
                bar(app.Axes,double(summary.pass)); ylim(app.Axes,[0 1.2]); xticks(app.Axes,1:9); xticklabels(app.Axes,summary.test);
                ylabel(app.Axes,'Pass'); title(app.Axes,'T1-T9 regression'); grid(app.Axes,'on');
                app.log('Standard T1-T9 regression passed.');
            end
        end

        function runPaperBaseline(app)
            app.execute('paper baseline',@doRun);
            function doRun()
                o=run_vlsi2024_xsr('baseline',min(app.Cfg.link.nBits,2^18));
                app.MetricsTable.Data=o.metrics; cla(app.Axes); app.log(sprintf('Paper baseline complete: BER %.3e.',o.result.aggregateBer));
            end
        end

        function runPaperRegression(app)
            app.execute('paper full regression',@doRun);
            function doRun()
                o=run_vlsi2024_regression('full',min(app.Cfg.link.nBits,2^18));
                app.MetricsTable.Data=o.summary; cla(app.Axes); bar(app.Axes,double(o.summary.pass));
                xticks(app.Axes,1:height(o.summary)); xticklabels(app.Axes,o.summary.stage); ylim(app.Axes,[0 1.2]);
                title(app.Axes,'VLSI2024 XSR full regression'); grid(app.Axes,'on'); app.log('Paper full regression passed.');
            end
        end

        function runPaperAdaptation(app)
            app.execute('paper adaptation',@doRun);
            function doRun()
                o=run_vlsi2024_xsr('adaptation',min(app.Cfg.link.nBits,2^18));
                app.MetricsTable.Data=o.stateTrace; cla(app.Axes); plot(app.Axes,o.stateTrace.objective,'-o');
                xlabel(app.Axes,'State'); ylabel(app.Axes,'Decision-level margin'); title(app.Axes,'Paper adaptation trace'); grid(app.Axes,'on');
                app.log('Paper adaptation trace complete.');
            end
        end

        function onTreeSelection(app,event)
            if isempty(event.SelectedNodes), return; end
            data=char(event.SelectedNodes.NodeData); app.log(['Selected model block: ' data]);
            token=regexp(data,'(\d+)$','tokens','once');
            if ~isempty(token) && str2double(token{1})<=8, app.LaneDropDown.Value=['Lane ' token{1}]; end
            if startsWith(data,'txFfe'), app.ProbeDropDown.Value='TX FFE output';
            elseif startsWith(data,'txPad'), app.ProbeDropDown.Value='TX pad';
            elseif startsWith(data,'channel'), app.ProbeDropDown.Value='Channel output';
            elseif startsWith(data,'ctle') || startsWith(data,'afe'), app.ProbeDropDown.Value='RX CTLE output';
            elseif startsWith(data,'slicer'), app.ProbeDropDown.Value='RX slicer samples';
            elseif startsWith(data,'rxPll'), app.ProbeDropDown.Value='RX PLL residual phase';
            end
            if ~isempty(app.Phy), app.plotSelectedProbeMulti(); end
        end

        function plotSelectedProbeMulti(app)
            if isempty(app.Phy), return; end
            try
                label=app.ProbeDropDown.Value; allLanes=strcmp(app.LaneDropDown.Value,'All Lanes');
                if allLanes, lanes=1:8; else, lanes=str2double(extractAfter(app.LaneDropDown.Value,'Lane ')); end
                [~,isWave]=app.getProbeLane(label,lanes(1)); cla(app.Axes,'reset'); hold(app.Axes,'on');
                app.Axes.XScale='linear'; app.Axes.YScale='linear'; app.Axes.Box='on'; app.Axes.FontSize=11;
                for k=lanes
                    [x,isWave]=app.getProbeLane(label,k); x=x(:);
                    if isWave
                        sps=app.Cfg.link.sps; n=floor(numel(x)/(2*sps)); n=min(n,1000);
                        if n>0
                            seg=reshape(x(1:n*2*sps),2*sps,n);
                            if allLanes, plot(app.Axes,(0:2*sps-1)'/sps,seg); else, plot(app.Axes,(0:2*sps-1)'/sps,seg,'Color',[0 .25 .7]); end
                        end
                    else
                        if allLanes, plot(app.Axes,x); else, plot(app.Axes,x,'LineWidth',1); end
                    end
                end
                hold(app.Axes,'off'); grid(app.Axes,'on'); title(app.Axes,[label ' | ' app.LaneDropDown.Value]);
                if isWave, xlabel(app.Axes,'UI'); ylabel(app.Axes,'Amplitude'); else, xlabel(app.Axes,'Symbol'); ylabel(app.Axes,'UI'); end
                if allLanes, legend(app.Axes,'Lane 1','Lane 2','Lane 3','Lane 4','Lane 5','Lane 6','Lane 7','Lane 8','Location','eastoutside'); end
            catch ex, app.log(['Probe error: ' ex.message]); end
        end

        function plotSelectedProbe(app)
            if isempty(app.Phy), return; end
            try
                [x,isWave]=app.getProbe(app.ProbeDropDown.Value); cla(app.Axes,'reset');
                app.Axes.XScale='linear'; app.Axes.YScale='linear'; app.Axes.Box='on'; app.Axes.FontSize=11;
                if isWave
                    sps=app.Cfg.link.sps; n=floor(numel(x)/(2*sps)); n=min(n,1000);
                    seg=reshape(x(1:n*2*sps),2*sps,n); plot(app.Axes,(0:2*sps-1)'/sps,seg,'Color',[0 .25 .7]);
                    xlabel(app.Axes,'UI'); ylabel(app.Axes,'Amplitude'); title(app.Axes,app.ProbeDropDown.Value); grid(app.Axes,'on');
                else
                    plot(app.Axes,x,'LineWidth',1); xlabel(app.Axes,'Symbol'); ylabel(app.Axes,'UI'); title(app.Axes,app.ProbeDropDown.Value); grid(app.Axes,'on');
                end
            catch ex, app.log(['Probe error: ' ex.message]); end
        end

        function [x,isWave]=getProbeLane(app,label,k)
            isWave=true;
            switch label
                case 'TX FFE output', x=app.Phy.txPma.lane(k).ffe.out; isWave=false;
                case 'TX pad', x=app.Phy.txPma.lane(k).driver.txPad;
                case 'Channel output', x=app.Phy.channel(k).out;
                case 'RX TERM output', x=app.Phy.rxPma.lane(k).afe.termOut;
                case 'RX AC pre', x=app.Phy.rxPma.lane(k).afe.acPreOut;
                case 'RX CTLE raw', x=app.Phy.rxPma.lane(k).afe.ctleRaw;
                case 'RX AC post', x=app.Phy.rxPma.lane(k).afe.acPostOut;
                case 'RX CTLE output', x=app.Phy.rxPma.lane(k).afe.ctleOut;
                case 'RX level-shifted samples', x=app.Phy.rxPma.lane(k).slicer.levelShiftedSamples; isWave=false;
                case 'RX slicer samples', x=app.Phy.rxPma.lane(k).slicer.samples; isWave=false;
                case 'RX data samples', x=app.Phy.rxPma.lane(k).dataSamples; isWave=false;
                case 'RX edge samples', x=app.Phy.rxPma.lane(k).edgeSamples; isWave=false;
                case 'RX edge detector', x=app.Phy.rxPma.lane(k).edgeDetectorOutput; isWave=false;
                case 'RX spare samples', x=app.Phy.rxPma.lane(k).spareSamples; isWave=false;
                case 'RX PLL input phase', x=app.Phy.rxPma.support.pll.log.in; isWave=false;
                case 'RX PLL recovered phase', x=app.Phy.rxPma.support.pll.recoveredUI; isWave=false;
                case 'RX PLL residual phase', x=app.Phy.rxPma.support.pll.residualUI; isWave=false;
                case 'PI code', x=app.getTraceLane(k,'piCodeTrace'); isWave=false;
                case 'CDR error', x=app.getTraceLane(k,'errorTrace'); isWave=false;
                case 'CDR lock', x=app.getTraceLane(k,'cdr_lock_trace'); isWave=false;
                case 'Adaptation objective', x=app.getArtifactTrace('adaptation_state_trace.csv','objective'); isWave=false;
                case 'FFE tap trace', x=app.getArtifactTrace('adaptation_state_trace.csv','ffe_current'); isWave=false;
            end
            x=x(:);
        end

        function x=getTraceLane(app,k,name)
            x=[];
            if k<=numel(app.Phy.rxPma.lane)
                trace=app.Phy.rxPma.lane(k).cdrTrace;
                if isstruct(trace) && isfield(trace,name), x=trace.(name); end
            end
        end

        function x=getArtifactTrace(app,fileName,column)
            x=[]; f=fullfile(app.Root,'results','vlsi2024_xsr',fileName);
            if isfile(f)
                t=readtable(f); if any(strcmp(t.Properties.VariableNames,column)), x=t.(column); end
            end
        end

        function [x,isWave]=getProbe(app,label)
            isWave=true;
            switch label
                case 'TX lane 1 FFE output', x=app.Phy.txPma.lane(1).ffe.out; isWave=false;
                case 'TX lane 1 pad', x=app.Phy.txPma.lane(1).driver.txPad;
                case 'Channel 1 output', x=app.Phy.channel(1).out;
                case 'RX lane 1 TERM output', x=app.Phy.rxPma.lane(1).afe.termOut;
                case 'RX AC pre', x=app.Phy.rxPma.lane(1).afe.acPreOut;
                case 'RX lane 1 CTLE raw', x=app.Phy.rxPma.lane(1).afe.ctleRaw;
                case 'RX AC post', x=app.Phy.rxPma.lane(1).afe.acPostOut;
                case 'RX lane 1 CTLE output', x=app.Phy.rxPma.lane(1).afe.ctleOut;
                case 'RX level-shifted samples', x=app.Phy.rxPma.lane(1).slicer.levelShiftedSamples; isWave=false;
                case 'RX lane 1 slicer samples', x=app.Phy.rxPma.lane(1).slicer.samples; isWave=false;
                case 'RX data samples', x=app.Phy.rxPma.lane(1).dataSamples; isWave=false;
                case 'RX edge samples', x=app.Phy.rxPma.lane(1).edgeSamples; isWave=false;
                case 'RX edge detector', x=app.Phy.rxPma.lane(1).edgeDetectorOutput; isWave=false;
                case 'RX spare samples', x=app.Phy.rxPma.lane(1).spareSamples; isWave=false;
                case 'RX PLL input phase', x=app.Phy.rxPma.support.pll.log.in; isWave=false;
                case 'RX PLL recovered phase', x=app.Phy.rxPma.support.pll.recoveredUI; isWave=false;
                case 'RX PLL residual phase', x=app.Phy.rxPma.support.pll.residualUI; isWave=false;
                case 'PI code', x=app.getTraceLane(1,'piCodeTrace'); isWave=false;
                case 'CDR error', x=app.getTraceLane(1,'errorTrace'); isWave=false;
                case 'CDR lock', x=app.getTraceLane(1,'cdr_lock_trace'); isWave=false;
                case 'Adaptation objective', x=app.getArtifactTrace('adaptation_state_trace.csv','objective'); isWave=false;
                case 'FFE tap trace', x=app.getArtifactTrace('adaptation_state_trace.csv','ffe_current'); isWave=false;
            end
            x=x(:);
        end

        function execute(app,label,fn)
            app.StatusLabel.Text=['Running: ' label]; app.Figure.Pointer='watch'; drawnow;
            try, fn(); app.StatusLabel.Text=['Passed: ' label];
            catch ex, app.StatusLabel.Text=['Failed: ' label]; app.log(getReport(ex,'basic','hyperlinks','off')); uialert(app.Figure,ex.message,[label ' failed']);
            end
            app.Figure.Pointer='arrow'; drawnow;
        end

        function log(app,msg)
            stamp=char(datetime('now','Format','HH:mm:ss')); old=app.LogArea.Value;
            if ischar(old), old={old}; end
            app.LogArea.Value=[old;{sprintf('[%s] %s',stamp,msg)}]; scroll(app.LogArea,'bottom');
        end
    end

    methods (Static)
        function names=profileNames()
            names={'ideal','typical','vlsi2024_xsr'};
        end
        function name=profileName(cfg)
            if isfield(cfg,'paper') && isfield(cfg.paper,'id'), name='vlsi2024_xsr';
            elseif isfield(cfg,'channel') && isfield(cfg.channel,'lossNyq_dB') && cfg.channel.lossNyq_dB==0, name='ideal';
            else, name='typical';
            end
        end
        function paths=baseConfigPaths()
            paths={
                'link.modulation','link.baud_Gbps','link.sps','link.nBits','link.skipUI','link.snr_dB',...
                'link.rjUI_rms','link.djUI_pp','link.djFreq','link.cdrBw','link.seed',...
                'rawPcs.pattern','rawPcs.errInject',...
                'txPma.lane.txEqMain','txPma.lane.txEqPre','txPma.lane.txEqPost','txPma.lane.ffeNormalize','txPma.lane.amplitude',...
                'channel.lossNyq_dB','channel.poles',...
                'rxPma.lane.ctleBoost_dB','rxPma.lane.ctleFz','rxPma.lane.termGain','rxPma.lane.clockMode'};
        end
        function paths=paperConfigPaths()
            paths={
                'txPma.lane.ffeMode','txPma.lane.ffeOffsets','txPma.lane.ffeCoeffs',...
                'txPma.lane.ffeNormalize','txPma.lane.ffeCurrentConstraint',...
                'txPma.lane.enableDacQuantization','txPma.lane.dacLevels','txPma.lane.targetSwing',...
                'txPma.lane.gainError','txPma.lane.enableSwingCalibration',...
                'channel.mode','channel.refFreq_GHz','channel.baud_GBd','channel.lossAtRef_dB',...
                'rxPma.lane.terminationMode','rxPma.lane.enableAcPre','rxPma.lane.enableAcPost',...
                'rxPma.lane.acPreCorner_UI','rxPma.lane.acPostCorner_UI','rxPma.lane.acInitialState',...
                'rxPma.lane.ctlePolicy','rxPma.lane.ctleBoost_dB','rxPma.lane.ctleGrid_dB','rxPma.lane.ctleAppliedBoost_dB',...
                'rxPma.lane.enableAgc','rxPma.lane.samplerRoles.enabled','rxPma.lane.samplerRoles.quarterRateBranches',...
                'rxPma.lane.samplerRoles.roleCounts.data','rxPma.lane.samplerRoles.roleCounts.edge',...
                'rxPma.lane.samplerRoles.roleCounts.spare','rxPma.lane.samplerRoles.roleCounts.total',...
                'rxPma.lane.samplerRoles.levelShiftCodes.data','rxPma.lane.samplerRoles.levelShiftCodes.edge',...
                'rxPma.lane.samplerRoles.levelShiftCodes.spare','rxPma.lane.samplerRoles.samplerOffsetCodes',...
                'rxPma.lane.samplerRoles.thresholdAssumptions',...
                'model.enablePaperAdaptation','model.trainingMode','model.cdrOptions.nCodes',...
                'model.cdrOptions.initialPhaseUI','model.cdrOptions.loopGainCodes','model.cdrOptions.loopBandwidthProxy',...
                'model.cdrOptions.updateCadence','model.cdrOptions.lockWindow','model.cdrOptions.lockToleranceUI',...
                'model.cdrOptions.mismatchBoundLSB','model.cdrOptions.mismatchSeed','model.cdrOptions.enabled',...
                'model.cdrOptions.maxStepCodes'};
        end
        function tf=hasNested(s,parts)
            tf=true; for k=1:numel(parts)
                if ~isstruct(s) || ~isfield(s,parts{k}), tf=false; return; end
                s=s.(parts{k});
            end
        end
        function items=probeItems()
            items={'TX FFE output','TX pad','Channel output','RX TERM output',...
                'RX AC pre','RX CTLE raw','RX AC post','RX CTLE output','RX level-shifted samples',...
                'RX slicer samples','RX data samples','RX edge samples','RX edge detector','RX spare samples',...
                'RX PLL input phase','RX PLL recovered phase','RX PLL residual phase',...
                'PI code','CDR error','CDR lock','Adaptation objective','FFE tap trace'};
        end
        function items=laneItems()
            items={'Lane 1','Lane 2','Lane 3','Lane 4','Lane 5','Lane 6','Lane 7','Lane 8','All Lanes'};
        end
        function text=valueToText(v)
            if ischar(v) || isstring(v), text=char(v); elseif islogical(v), text=mat2str(v); else, text=num2str(v,16); end
        end
        function value=parseValue(text,old)
            if iscell(text), text=text{1}; end
            if ischar(old) || isstring(old), value=char(text);
            elseif islogical(old), value=any(strcmpi(strtrim(char(text)),{'true','1','on'}));
            else
                value=sscanf(strrep(char(text),',',' '),'%f').';
                if isempty(value) && strcmpi(strtrim(char(text)),'inf'), value=inf; end
                if isempty(value), value=old; end
                if isscalar(old) && numel(value)==1, value=value(1); end
            end
        end
        function x=parseVector(text)
            x=sscanf(strrep(char(text),',',' '),'%f').'; if isempty(x), error('D2DWorkbench:Vector','Enter a numeric vector.'); end
        end
        function value=getNested(s,parts)
            value=s; for k=1:numel(parts), value=value.(parts{k}); end
        end
        function s=setNested(s,parts,value)
            if numel(parts)==1, s.(parts{1})=value;
            else, child=s.(parts{1}); child=D2DWorkbench.setNested(child,parts(2:end),value); s.(parts{1})=child;
            end
        end
    end
end
