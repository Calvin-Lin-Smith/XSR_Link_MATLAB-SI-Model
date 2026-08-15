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
    end

    methods
        function app=D2DWorkbench(root)
            app.Root=root; app.Cfg=phyConfig();
            app.buildUi(); app.populateModelTree(); app.populateConfigTable();
            app.log('D2D PHY Workbench ready. Edit parameters, then run a link or test.');
        end

        function buildUi(app)
            app.Figure=uifigure('Name','D2D 112G PHY Model Workbench','Position',[40 40 1720 960],...
                'Color',[0.95 0.96 0.98]);
            main=uigridlayout(app.Figure,[1 3]); main.ColumnWidth={340,520,'1x'};
            main.Padding=[12 12 12 12]; main.ColumnSpacing=12;

            left=uipanel(main,'Title','D2D IP Hierarchy','BackgroundColor',[1 1 1]); left.Layout.Column=1;
            lg=uigridlayout(left,[2 1]); lg.RowHeight={32,'1x'}; lg.Padding=[8 8 8 8]; lg.RowSpacing=6;
            uilabel(lg,'Text','Databook-aligned x8 structure','FontWeight','bold','FontColor',[0.18 0.23 0.32]);
            app.ModelTree=uitree(lg,'SelectionChangedFcn',@(s,e)app.onTreeSelection(e));

            center=uipanel(main,'Title','Configuration and Tests','BackgroundColor',[1 1 1]); center.Layout.Column=2;
            cg=uigridlayout(center,[3 1]); cg.RowHeight={'1x',260,140};
            cg.Padding=[8 8 8 8]; cg.RowSpacing=10;
            tabs=uitabgroup(cg); tabs.Layout.Row=1;
            cfgTab=uitab(tabs,'Title','Model Parameters');
            cfgGrid=uigridlayout(cfgTab,[2 1]); cfgGrid.RowHeight={'1x',44};
            cfgGrid.Padding=[8 8 8 8]; cfgGrid.RowSpacing=8;
            app.ConfigTable=uitable(cfgGrid,'ColumnName',{'Group','Parameter','Value'},...
                'ColumnWidth',{95,230,130},'ColumnEditable',[false false true],...
                'CellEditCallback',@(s,e)app.onConfigEdit(e));
            btnRow=uigridlayout(cfgGrid,[1 4]); btnRow.Layout.Row=2; btnRow.ColumnWidth={'1x','1x','1x','1x'};
            btnRow.Padding=[0 0 0 0]; btnRow.ColumnSpacing=8;
            uibutton(btnRow,'Text','Apply','FontWeight','bold','ButtonPushedFcn',@(s,e)app.applyConfigTable());
            uibutton(btnRow,'Text','Reset Ideal','ButtonPushedFcn',@(s,e)app.resetConfig());
            uibutton(btnRow,'Text','Reset Typical','ButtonPushedFcn',@(s,e)app.resetTypical());
            uibutton(btnRow,'Text','Run x8 Link','FontWeight','bold','BackgroundColor',[0.12 0.42 0.72],...
                'FontColor',[1 1 1],'ButtonPushedFcn',@(s,e)app.runLink());

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
            bg=uigridlayout(tests,[3 3]); bg.RowHeight={'1x','1x','1x'};
            bg.Padding=[8 8 8 8]; bg.RowSpacing=8; bg.ColumnSpacing=8;
            uibutton(bg,'Text','Loss Sweep','ButtonPushedFcn',@(s,e)app.runSweep('loss'));
            uibutton(bg,'Text','CTLE Sweep','ButtonPushedFcn',@(s,e)app.runSweep('ctle'));
            uibutton(bg,'Text','RJ Sweep','ButtonPushedFcn',@(s,e)app.runSweep('rj'));
            uibutton(bg,'Text','CDR Sweep','ButtonPushedFcn',@(s,e)app.runSweep('cdr'));
            uibutton(bg,'Text','FFE + CTLE Scan','ButtonPushedFcn',@(s,e)app.runEqScan());
            uibutton(bg,'Text','Behavior Suite','ButtonPushedFcn',@(s,e)app.runBehaviorSuite());
            uibutton(bg,'Text','Standard T1-T9','ButtonPushedFcn',@(s,e)app.runRegression());
            uibutton(bg,'Text','Open Results Folder','ButtonPushedFcn',@(s,e)winopen(fullfile(app.Root,'results')));
            uibutton(bg,'Text','Clear Log','ButtonPushedFcn',@(s,e)set(app.LogArea,'Value',''));

            statusPanel=uipanel(cg,'Title','Status'); statusPanel.Layout.Row=3;
            sg=uigridlayout(statusPanel,[2 1]); sg.RowHeight={26,'1x'};
            app.StatusLabel=uilabel(sg,'Text','Idle','FontWeight','bold');
            app.LogArea=uitextarea(sg,'Editable','off','Value','');

            right=uipanel(main,'Title','White-box Probes and Results','BackgroundColor',[1 1 1]); right.Layout.Column=3;
            rg=uigridlayout(right,[4 1]); rg.RowHeight={44,'2x',190,118};
            rg.Padding=[8 8 8 8]; rg.RowSpacing=10;
            probeRow=uigridlayout(rg,[1 2]); probeRow.ColumnWidth={70,'1x'}; probeRow.Padding=[0 0 0 0];
            uilabel(probeRow,'Text','Probe','FontWeight','bold');
            app.ProbeDropDown=uidropdown(probeRow,'Items',app.probeItems(),'Value','RX lane 1 CTLE output',...
                'ValueChangedFcn',@(s,e)app.plotSelectedProbe());
            app.Axes=uiaxes(rg); title(app.Axes,'Run the model to view an internal node'); grid(app.Axes,'on');
            app.Axes.Box='on'; app.Axes.FontSize=11;
            app.MetricsTable=uitable(rg,'ColumnName',{'Metric','Value'},'ColumnWidth',{190,'1x'});
            uitextarea(rg,'Editable','off','Value',{
                'WORKFLOW',...
                '1  Edit and apply model parameters',...
                '2  Run the x8 link',...
                '3  Select any white-box probe',...
                '4  Run sweeps or T1-T9; artifacts go to results/'});
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
            app.ConfigPaths={
                'link.modulation','link.baud_Gbps','link.sps','link.nBits','link.skipUI','link.snr_dB',...
                'link.rjUI_rms','link.djUI_pp','link.djFreq','link.cdrBw','link.seed',...
                'rawPcs.pattern','rawPcs.errInject',...
                'txPma.lane.txEqMain','txPma.lane.txEqPre','txPma.lane.txEqPost','txPma.lane.ffeNormalize','txPma.lane.amplitude',...
                'channel.lossNyq_dB','channel.poles',...
                'rxPma.lane.ctleBoost_dB','rxPma.lane.ctleFz','rxPma.lane.termGain','rxPma.lane.clockMode'};
            data=cell(numel(app.ConfigPaths),3);
            for k=1:numel(app.ConfigPaths)
                parts=strsplit(app.ConfigPaths{k},'.'); data{k,1}=parts{1}; data{k,2}=strjoin(parts(2:end),'.');
                data{k,3}=app.valueToText(app.getNested(app.Cfg,parts));
            end
            app.ConfigTable.Data=data;
        end

        function onConfigEdit(app,~), app.applyConfigTable(); end
        function applyConfigTable(app)
            data=app.ConfigTable.Data;
            for k=1:numel(app.ConfigPaths)
                parts=strsplit(app.ConfigPaths{k},'.'); old=app.getNested(app.Cfg,parts);
                value=app.parseValue(data{k,3},old); app.Cfg=app.setNested(app.Cfg,parts,value);
            end
            app.log('Configuration applied.');
        end

        function resetConfig(app)
            app.Cfg=phyConfig('ideal'); app.populateConfigTable(); app.log('Configuration reset to ideal verification baseline.');
        end

        function resetTypical(app)
            app.Cfg=phyConfig('typical'); app.populateConfigTable();
            app.log('Configuration reset to typical working non-ideal profile.');
        end

        function runLink(app)
            app.execute('x8 link',@doRun);
            function doRun()
                app.applyConfigTable(); app.Phy=D2DPHY(); app.Phy.configure(app.Cfg); app.Result=app.Phy.run();
                app.MetricsTable.Data={
                    'Aggregate BER',sprintf('%.3e',app.Result.aggregateBer);
                    'Errors',sprintf('%d',sum(app.Result.errCnt));
                    'Measured bits',sprintf('%d',sum(app.Result.nMeasured));
                    'Lane 1 phase',sprintf('%d',app.Phy.rxPma.lane(1).bestPhase);
                    'Lane 1 delay UI',sprintf('%d',app.Phy.rxPma.lane(1).delayUI);
                    'CTLE AGC gain',sprintf('%.4f',app.Phy.rxPma.lane(1).afe.agcGain)};
                app.plotSelectedProbe(); app.log(sprintf('x8 link complete: BER %.3e',app.Result.aggregateBer));
            end
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

        function onTreeSelection(app,event)
            if isempty(event.SelectedNodes), return; end
            data=event.SelectedNodes.NodeData; app.log(['Selected model block: ' char(data)]);
            if startsWith(data,'txPad'), app.ProbeDropDown.Value='TX lane 1 pad';
            elseif startsWith(data,'channel'), app.ProbeDropDown.Value='Channel 1 output';
            elseif startsWith(data,'ctle') || startsWith(data,'afe'), app.ProbeDropDown.Value='RX lane 1 CTLE output';
            elseif startsWith(data,'slicer'), app.ProbeDropDown.Value='RX lane 1 slicer samples';
            elseif startsWith(data,'rxPll'), app.ProbeDropDown.Value='RX PLL residual phase';
            end
            if ~isempty(app.Phy), app.plotSelectedProbe(); end
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

        function [x,isWave]=getProbe(app,label)
            isWave=true;
            switch label
                case 'TX lane 1 FFE output', x=app.Phy.txPma.lane(1).ffe.out; isWave=false;
                case 'TX lane 1 pad', x=app.Phy.txPma.lane(1).driver.txPad;
                case 'Channel 1 output', x=app.Phy.channel(1).out;
                case 'RX lane 1 TERM output', x=app.Phy.rxPma.lane(1).afe.termOut;
                case 'RX lane 1 CTLE raw', x=app.Phy.rxPma.lane(1).afe.ctleRaw;
                case 'RX lane 1 CTLE output', x=app.Phy.rxPma.lane(1).afe.ctleOut;
                case 'RX lane 1 slicer samples', x=app.Phy.rxPma.lane(1).slicer.samples; isWave=false;
                case 'RX PLL input phase', x=app.Phy.rxPma.support.pll.log.in; isWave=false;
                case 'RX PLL recovered phase', x=app.Phy.rxPma.support.pll.recoveredUI; isWave=false;
                case 'RX PLL residual phase', x=app.Phy.rxPma.support.pll.residualUI; isWave=false;
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
        function items=probeItems()
            items={'TX lane 1 FFE output','TX lane 1 pad','Channel 1 output','RX lane 1 TERM output',...
                'RX lane 1 CTLE raw','RX lane 1 CTLE output','RX lane 1 slicer samples',...
                'RX PLL input phase','RX PLL recovered phase','RX PLL residual phase'};
        end
        function text=valueToText(v)
            if ischar(v) || isstring(v), text=char(v); elseif islogical(v), text=mat2str(v); else, text=num2str(v,16); end
        end
        function value=parseValue(text,old)
            if iscell(text), text=text{1}; end
            if ischar(old) || isstring(old), value=char(text);
            elseif islogical(old), value=any(strcmpi(strtrim(char(text)),{'true','1','on'}));
            else, value=str2double(text); if isnan(value) && strcmpi(strtrim(char(text)),'inf'), value=inf; end
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
