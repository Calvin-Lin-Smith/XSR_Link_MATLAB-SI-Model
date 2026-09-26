classdef D2DWorkbench < handle
    properties
        Root
        Cfg
        Phy
        Result
        Debug
        Figure
        ModelTree
        ConfigTable
        ProbeDropDown
        LaneDropDown
        Axes
        MetricsTable
        TrainedParametersTable
        LogArea
        StatusLabel
        PresetDropDown
        ConfigPaths
    end

    methods
        function app=D2DWorkbench(root)
            if nargin<1 || isempty(root), root=fileparts(fileparts(mfilename('fullpath'))); end
            app.Root=root; app.Cfg=phyConfig('vlsi2024_xsr_typical');
            app.buildUi(); app.populateModelTree(); app.populateConfigTable();
            app.log('VLSI2024 XSR paper workbench ready.');
        end

        function buildUi(app)
            app.Figure=uifigure('Name','VLSI2024 XSR PHY Workbench','Position',[40 40 1720 960],...
                'Color',[0.95 0.96 0.98]);
            main=uigridlayout(app.Figure,[1 3]); main.ColumnWidth={300,540,'1x'};
            main.Padding=[12 12 12 12]; main.ColumnSpacing=12;
            left=uipanel(main,'Title','VLSI2024 XSR hierarchy','BackgroundColor',[1 1 1]); left.Layout.Column=1;
            lg=uigridlayout(left,[3 1]); lg.RowHeight={32,'1x',280}; lg.Padding=[8 8 8 8]; lg.RowSpacing=8;
            uilabel(lg,'Text','Paper-aligned x8 structure','FontWeight','bold','FontColor',[0.18 0.23 0.32]);
            app.ModelTree=uitree(lg,'SelectionChangedFcn',@(s,e)app.onTreeSelection(e));
            statusPanel=uipanel(lg,'Title','Status','BackgroundColor',[0.98 0.99 1]);
            sg=uigridlayout(statusPanel,[2 1]); sg.RowHeight={26,'1x'}; sg.Padding=[6 6 6 6];
            app.StatusLabel=uilabel(sg,'Text','Idle','FontWeight','bold','FontColor',[0.15 0.35 0.22]);
            app.LogArea=uitextarea(sg,'Editable','off','Value','');

            center=uipanel(main,'Title','Paper configuration and evidence','BackgroundColor',[1 1 1]); center.Layout.Column=2;
            cg=uigridlayout(center,[2 1]); cg.RowHeight={'1x',260}; cg.Padding=[8 8 8 8]; cg.RowSpacing=10;
            tabs=uitabgroup(cg); tabs.Layout.Row=1; cfgTab=uitab(tabs,'Title','Paper controls');
            cfgGrid=uigridlayout(cfgTab,[3 1]); cfgGrid.RowHeight={34,'1x',82}; cfgGrid.Padding=[8 8 8 8]; cfgGrid.RowSpacing=8;
            presetRow=uigridlayout(cfgGrid,[1 3]); presetRow.Layout.Row=1; presetRow.ColumnWidth={100,'1x',140};
            presetRow.Padding=[0 0 0 0]; presetRow.ColumnSpacing=8;
            uilabel(presetRow,'Text','Paper preset','FontWeight','bold');
            app.PresetDropDown=uidropdown(presetRow,'Items',D2DWorkbench.presetNames(),'Value','VLSI Typical');
            uibutton(presetRow,'Text','Load Paper Preset','ButtonPushedFcn',@(s,e)app.loadPreset());
            app.ConfigTable=uitable(cfgGrid,'ColumnName',{'Group','Parameter','Value'},...
                'ColumnWidth',{95,280,130},'ColumnEditable',[false false true],...
                'CellEditCallback',@(s,e)app.onConfigEdit(e));
            buttonRow=uigridlayout(cfgGrid,[2 2]); buttonRow.Layout.Row=3;
            buttonRow.ColumnWidth={'1x','1x'}; buttonRow.RowHeight={'1x','1x'}; buttonRow.Padding=[0 0 0 0];
            buttonRow.ColumnSpacing=8; buttonRow.RowSpacing=6;
            uibutton(buttonRow,'Text','Apply + Sync','FontWeight','bold','ButtonPushedFcn',@(s,e)app.applyConfigTable(true));
            uibutton(buttonRow,'Text','Load from Simulink','ButtonPushedFcn',@(s,e)app.loadSharedConfig());
            uilabel(buttonRow,'Text','Requested paper cfg stays separate from trained/applied debug values',...
                'HorizontalAlignment','center','FontColor',[0.35 0.4 0.48]);
            uilabel(buttonRow,'Text','Post-lock metrics use one global mission window',...
                'HorizontalAlignment','center','FontColor',[0.35 0.4 0.48]);

            actions=uipanel(cg,'Title','Paper actions','BackgroundColor',[1 1 1]); actions.Layout.Row=2;
            bg=uigridlayout(actions,[3 3]); bg.RowHeight={'1x','1x','1x'}; bg.Padding=[8 8 8 8];
            bg.RowSpacing=8; bg.ColumnSpacing=8;
            uibutton(bg,'Text','Run x8 Link','FontWeight','bold','BackgroundColor',[0.12 0.42 0.72],...
                'FontColor',[1 1 1],'ButtonPushedFcn',@(s,e)app.runLink());
            uibutton(bg,'Text','VLSI2024 Baseline','ButtonPushedFcn',@(s,e)app.runPaperBaseline());
            uibutton(bg,'Text','Static A-D / FFE / IL / AC-CTLE','ButtonPushedFcn',@(s,e)app.runPaperStatic());
            uibutton(bg,'Text','BB-CDR / PI / Jitter Evidence','ButtonPushedFcn',@(s,e)app.runPaperEvidence());
            uibutton(bg,'Text','Calibration / Adaptation','ButtonPushedFcn',@(s,e)app.runPaperAdaptation());
            uibutton(bg,'Text','Full VLSI2024 Regression','ButtonPushedFcn',@(s,e)app.runPaperRegression());
            uibutton(bg,'Text','Open Paper Results','ButtonPushedFcn',@(s,e)winopen(fullfile(app.Root,'results','vlsi2024_xsr')));
            uibutton(bg,'Text','Clear Log','ButtonPushedFcn',@(s,e)set(app.LogArea,'Value',''));
            uilabel(bg,'Text','Debug link is in-memory only','HorizontalAlignment','center');

            right=uipanel(main,'Title','Paper probes and results','BackgroundColor',[1 1 1]); right.Layout.Column=3;
            rg=uigridlayout(right,[5 1]); rg.RowHeight={44,'2x',220,205,90}; rg.Padding=[8 8 8 8]; rg.RowSpacing=10;
            probeRow=uigridlayout(rg,[1 4]); probeRow.ColumnWidth={48,'1x',42,105}; probeRow.Padding=[0 0 0 0]; probeRow.ColumnSpacing=8;
            uilabel(probeRow,'Text','Probe','FontWeight','bold'); app.ProbeDropDown=uidropdown(probeRow,...
                'Items',D2DWorkbench.probeItems(),'Value','RX CTLE output');
            uilabel(probeRow,'Text','Lane','FontWeight','bold'); app.LaneDropDown=uidropdown(probeRow,...
                'Items',D2DWorkbench.laneItems(),'Value','Lane 1','ValueChangedFcn',@(s,e)app.plotSelectedProbeMulti());
            app.ProbeDropDown.ValueChangedFcn=@(s,e)app.plotSelectedProbeMulti();
            app.Axes=uiaxes(rg); title(app.Axes,'No paper link run yet'); grid(app.Axes,'on'); app.Axes.Box='on'; app.Axes.FontSize=11;
            app.MetricsTable=uitable(rg,'ColumnName',{'Lane','BER','Status','Lock','Lock UI','Training end UI','BER start UI',...
                'Waited UI','Measured bits','CTLE gain','Eye height'},...
                'ColumnWidth',{72,72,110,60,70,90,85,70,90,70,75});
            app.TrainedParametersTable=uitable(rg,'ColumnName',{'Stage','Parameter path','Enable','Status','Requested','Trained','Applied','Residual','Constraint','Unit'},...
                'ColumnWidth',{100,230,55,120,90,90,90,90,110,75});
            uitextarea(rg,'Editable','off','Value',{'PAPER WORKFLOW',...
                '1  Select VLSI Typical or VLSI Ideal and edit paper controls',...
                '2  Apply + Sync only when publishing paper cfg',...
                '3  Run x8 Link for trained in-memory debug',...
                '4  Inspect post-lock BER/eye/probes and trained parameters',...
                '5  Run paper evidence actions when artifact output is desired'});
        end

        function populateModelTree(app)
            delete(app.ModelTree.Children);
            root=uitreenode(app.ModelTree,'Text','VLSI2024 XSR | D2DPHY x8','NodeData','top');
            uitreenode(root,'Text','Paper raw bits / PRBS31','NodeData','rawPcs');
            tx=uitreenode(root,'Text','TX signed FFE + SST DAC x8','NodeData','txPma');
            supTx=uitreenode(tx,'Text','TX clock / DLL abstraction','NodeData','txSupport');
            uitreenode(supTx,'Text','DLL / PI phase map','NodeData','txPll');
            for j=1:8
                lane=uitreenode(tx,'Text',sprintf('TX lane %d | signed FFE + DAC',j),'NodeData',sprintf('txLane%d',j));
                uitreenode(lane,'Text','Signed 3/6-tap FFE','NodeData',sprintf('txFfe%d',j));
                uitreenode(lane,'Text','Serializer','NodeData',sprintf('serializer%d',j));
                uitreenode(lane,'Text','SST DAC / TX pad','NodeData',sprintf('txPad%d',j));
            end
            channels=uitreenode(root,'Text','Analytic IL channels x8','NodeData','channels');
            for j=1:8, uitreenode(channels,'Text',sprintf('Channel %d | IL@28GHz',j),'NodeData',sprintf('channel%d',j)); end
            rx=uitreenode(root,'Text','RX AC + CTLE + sampler x8','NodeData','rxPma');
            supRx=uitreenode(rx,'Text','RX BB-CDR / PI / lock','NodeData','rxSupport');
            uitreenode(supRx,'Text','DLL / DCC / PI clock path','NodeData','rxPll');
            for j=1:8
                lane=uitreenode(rx,'Text',sprintf('RX lane %d | paper sampler roles',j),'NodeData',sprintf('rxLane%d',j));
                afe=uitreenode(lane,'Text','AC termination + CTLE','NodeData',sprintf('afe%d',j));
                uitreenode(afe,'Text','AC termination','NodeData',sprintf('term%d',j));
                uitreenode(afe,'Text','CTLE / peaking','NodeData',sprintf('ctle%d',j));
                uitreenode(lane,'Text','Sampler roles / level shift','NodeData',sprintf('slicer%d',j));
                uitreenode(lane,'Text','Deserializer / BER view','NodeData',sprintf('deserializer%d',j));
            end
            expand(root);
        end

        function populateConfigTable(app)
            app.ConfigPaths=D2DWorkbench.paperConfigPaths(); data=cell(numel(app.ConfigPaths),3);
            for k=1:numel(app.ConfigPaths)
                parts=strsplit(app.ConfigPaths{k},'.'); data{k,1}=parts{1}; data{k,2}=strjoin(parts(2:end),'.');
                data{k,3}=app.valueToText(app.getNested(app.Cfg,parts));
            end
            app.ConfigTable.Data=data;
        end

        function onConfigEdit(app,~)
            try, app.applyConfigTable(false);
            catch ex
                app.populateConfigTable(); app.log(['Invalid paper control: ' ex.message]);
                if ~isempty(app.Figure) && isvalid(app.Figure), uialert(app.Figure,ex.message,'Invalid paper control'); end
            end
        end

        function loadPreset(app)
            app.Cfg=D2DWorkbench.presetConfig(app.PresetDropDown.Value); app.populateConfigTable();
            app.log(['Loaded ' app.PresetDropDown.Value ' paper preset for editing.']);
        end

        function applyConfigTable(app,publish)
            if nargin<2, publish=true; end
            candidate=app.Cfg; data=app.ConfigTable.Data;
            try
                for k=1:numel(app.ConfigPaths)
                    parts=strsplit(app.ConfigPaths{k},'.'); old=app.getNested(candidate,parts);
                    value=app.parseValue(data{k,3},old); app.validateValue(app.ConfigPaths{k},value,old);
                    candidate=app.setNested(candidate,parts,value);
                end
                app.validatePaperConfig(candidate);
            catch ex
                app.populateConfigTable(); rethrow(ex);
            end
            app.Cfg=candidate;
            if publish
                syncD2DConfig(app.Cfg); app.log('Paper configuration applied and synchronized to d2dCfg / Simulink.');
            else
                app.log('Paper configuration applied locally for the next debug link.');
            end
        end

        function loadSharedConfig(app)
            candidate=loadD2DSharedConfig();
            try, app.validatePaperConfig(candidate);
            catch ex
                app.log(['Shared config rejected: ' ex.message]);
                uialert(app.Figure,'Only a VLSI2024 XSR paper configuration can be loaded.','Paper config required'); return;
            end
            app.Cfg=candidate; app.populateConfigTable();
            if any(strcmp(D2DWorkbench.presetNames(),candidate.paper.preset)), app.PresetDropDown.Value=candidate.paper.preset; end
            app.log('VLSI2024 XSR paper configuration loaded from Simulink.');
        end

        function runLink(app)
            app.execute('trained VLSI2024 x8 link',@doRun);
            function doRun()
                app.applyConfigTable(false); requested=app.Cfg;
                out=run_vlsi2024_xsr('debug_link',requested.link.nBits,'Config',requested);
                app.Debug=out; app.Phy=out.model; app.Result=out.result;
                app.TrainedParametersTable.Data=out.trainedParameters;
                app.updateLaneMetrics(); app.plotSelectedProbeMulti();
                app.log(sprintf('x8 link %s: BER start %g UI, measured bits %d, CTLE %.3g dB.',...
                    out.status,out.berStartUIInFinalPass,sum(out.result.nMeasured),out.appliedCfg.rxPma.lane.ctleBoost_dB));
            end
        end

        function updateLaneMetrics(app)
            if isempty(app.Result) || isempty(app.Phy), return; end
            nLane=app.Phy.nLane; err=app.Result.errCnt(:); nBits=app.Result.nMeasured(:); ber=app.Result.ber(:);
            if isfield(app.Debug,'laneLocked'), locked=logical(app.Debug.laneLocked(:)); else, locked=false(nLane,1); end
            if isfield(app.Debug,'laneLockUI'), lockUI=app.Debug.laneLockUI(:); else, lockUI=nan(nLane,1); end
            if isfield(app.Debug,'performance') && isfield(app.Debug.performance,'lane')
                eye=arrayfun(@(x)x.eyeHeight,app.Debug.performance.lane(:));
            else, eye=nan(nLane,1); end
            gain=zeros(nLane,1); for k=1:nLane, gain(k)=app.Phy.rxPma.lane(k).afe.agcGain; end
            if isfield(app.Debug,'status'), status=string(app.Debug.status); else, status="debug"; end
            labels=["Aggregate"; "Lane "+string((1:nLane)')];
            totalErr=sum(err); totalBits=sum(nBits); totalBer=app.Result.aggregateBer;
            if isfield(app.Debug,'trainingEndUI'), tr=app.Debug.trainingEndUI; else, tr=NaN; end
            if isfield(app.Debug,'berStartUIInFinalPass'), bs=app.Debug.berStartUIInFinalPass; else, bs=NaN; end
            if isfield(app.Debug,'totalWaitedUI'), waited=app.Debug.totalWaitedUI; else, waited=NaN; end
            lockLabel=[string(all(locked)); string(locked)];
            statLabel=[status; repmat(status,nLane,1)];
            app.MetricsTable.Data=table(labels,[totalBer;ber],statLabel,lockLabel,[max(lockUI);lockUI],...
                repmat(tr,nLane+1,1),repmat(bs,nLane+1,1),repmat(waited,nLane+1,1),[totalBits;nBits],...
                [NaN;gain],[NaN;eye], 'VariableNames',{'Lane','BER','Status','Lock','LockUI','TrainingEndUI',...
                'BERStartUI','WaitedUI','MeasuredBits','CTLEGain','EyeHeight'});
            for k=1:nLane
                app.log(sprintf('Lane %d: lock=%d lockUI=%g, BER start=%g UI, bits=%d.',k,locked(k),lockUI(k),bs,nBits(k)));
            end
        end

        function runPaperBaseline(app)
            app.execute('VLSI2024 baseline',@doRun);
            function doRun(), app.applyConfigTable(false); o=run_vlsi2024_xsr('baseline',app.Cfg.link.nBits,'Config',app.Cfg); app.log(sprintf('Baseline complete: BER %.3e.',o.result.aggregateBer)); end
        end
        function runPaperStatic(app)
            app.execute('static A-D / FFE / IL / AC-CTLE',@doRun);
            function doRun(), app.applyConfigTable(false); run_vlsi2024_xsr('static_checkpoint',min(app.Cfg.link.nBits,2^14),'Config',app.Cfg); app.log('Static paper checkpoint complete.'); end
        end
        function runPaperEvidence(app)
            app.execute('BB-CDR / PI / Jitter evidence',@doRun);
            function doRun(), app.applyConfigTable(false); run_vlsi2024_regression('full',min(app.Cfg.link.nBits,2^14)); app.log('BB-CDR / PI / jitter evidence complete.'); end
        end
        function runPaperAdaptation(app)
            app.execute('paper calibration / adaptation',@doRun);
            function doRun(), app.applyConfigTable(false); run_vlsi2024_xsr('adaptation',min(app.Cfg.link.nBits,2^14),'Config',app.Cfg); app.log('Paper calibration/adaptation complete.'); end
        end
        function runPaperRegression(app)
            app.execute('full VLSI2024 regression',@doRun);
            function doRun(), app.applyConfigTable(false); o=run_vlsi2024_regression('full',app.Cfg.link.nBits); app.MetricsTable.Data=o.summary; app.log('Full VLSI2024 regression complete.'); end
        end

        function onTreeSelection(app,event)
            if isempty(event.SelectedNodes), return; end
            data=char(event.SelectedNodes.NodeData); app.log(['Selected paper block: ' data]);
            token=regexp(data,'(\d+)$','tokens','once'); if ~isempty(token), app.LaneDropDown.Value=['Lane ' token{1}]; end
            if startsWith(data,'txFfe'), app.ProbeDropDown.Value='TX FFE output';
            elseif startsWith(data,'txPad'), app.ProbeDropDown.Value='TX DAC / pad';
            elseif startsWith(data,'channel'), app.ProbeDropDown.Value='Channel output';
            elseif startsWith(data,'ctle'), app.ProbeDropDown.Value='RX CTLE output';
            elseif startsWith(data,'term'), app.ProbeDropDown.Value='RX AC pre';
            elseif startsWith(data,'slicer'), app.ProbeDropDown.Value='RX data samples';
            elseif startsWith(data,'rxPll'), app.ProbeDropDown.Value='CDR lock'; end
            if ~isempty(app.Phy), app.plotSelectedProbeMulti(); end
        end

        function plotSelectedProbeMulti(app)
            if isempty(app.Phy), title(app.Axes,'No paper link run yet'); return; end
            try
                label=app.ProbeDropDown.Value; allLanes=strcmp(app.LaneDropDown.Value,'All Lanes');
                if allLanes, lanes=1:app.Phy.nLane; else, lanes=str2double(extractAfter(app.LaneDropDown.Value,'Lane ')); end
                [~,isWave]=app.getProbeLane(label,lanes(1)); cla(app.Axes,'reset'); hold(app.Axes,'on');
                for k=lanes
                    [x,isWave]=app.getProbeLane(label,k); x=x(:); if isempty(x), continue; end
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
                if isWave, xlabel(app.Axes,'UI'); ylabel(app.Axes,'Amplitude'); else, xlabel(app.Axes,'Sample/UI'); ylabel(app.Axes,'Value'); end
                if allLanes, legend(app.Axes,'Lane 1','Lane 2','Lane 3','Lane 4','Lane 5','Lane 6','Lane 7','Lane 8','Location','eastoutside'); end
            catch ex, app.log(['Probe error: ' ex.message]); end
        end

        function [x,isWave]=getProbeLane(app,label,k)
            isWave=true; x=[]; if isempty(app.Phy), return; end
            switch char(label)
                case 'TX FFE output', x=app.Phy.txPma.lane(k).ffe.out; isWave=false;
                case 'TX DAC / pad', x=app.Phy.txPma.lane(k).driver.txPad;
                case 'Channel output', x=app.Phy.channel(k).out;
                case 'RX termination', x=app.Phy.rxPma.lane(k).afe.termOut;
                case 'RX AC pre', x=app.Phy.rxPma.lane(k).afe.acPreOut;
                case 'RX AC post', x=app.Phy.rxPma.lane(k).afe.acPostOut;
                case 'RX CTLE output', x=app.performanceProbe(k,'ctleOut');
                case 'RX level-shifted samples', x=app.performanceProbe(k,'levelShiftedSamples'); isWave=false;
                case 'RX data samples', x=app.performanceProbe(k,'dataSamples'); isWave=false;
                case 'RX edge samples', x=app.performanceProbe(k,'edgeSamples'); isWave=false;
                case 'RX edge detector', x=app.performanceProbe(k,'edgeDetectorOutput'); isWave=false;
                case 'RX spare samples', x=app.performanceProbe(k,'spareSamples'); isWave=false;
                case 'PI code', x=app.getTraceLane(k,'piCodeTrace'); isWave=false;
                case 'CDR error', x=app.getTraceLane(k,'errorTrace'); isWave=false;
                case 'CDR lock', x=app.getTraceLane(k,'cdr_lock_trace'); isWave=false;
                case 'Adaptation objective', x=app.getArtifactTrace('adaptation_state_trace.csv','objective'); isWave=false;
                case 'FFE tap trace', x=app.getArtifactTrace('adaptation_state_trace.csv','ffe_current'); isWave=false;
            end
            x=x(:);
        end

        function x=performanceProbe(app,k,name)
            x=[]; if ~isempty(app.Debug) && isfield(app.Debug,'performance') && isfield(app.Debug.performance,'lane')
                if k<=numel(app.Debug.performance.lane) && isfield(app.Debug.performance.lane(k),name), x=app.Debug.performance.lane(k).(name); return; end
            end
            lane=app.Phy.rxPma.lane(k); switch name
                case 'ctleOut', x=lane.afe.ctleOut;
                case 'levelShiftedSamples', x=lane.slicer.levelShiftedSamples;
                case 'dataSamples', x=lane.dataSamples;
                case 'edgeSamples', x=lane.edgeSamples;
                case 'edgeDetectorOutput', x=lane.edgeDetectorOutput;
                case 'spareSamples', x=lane.spareSamples;
            end
        end
        function x=getTraceLane(app,k,name)
            x=[]; if k<=numel(app.Phy.rxPma.lane), t=app.Phy.rxPma.lane(k).cdrTrace; if isstruct(t)&&isfield(t,name), x=t.(name); end, end
        end
        function x=getArtifactTrace(app,fileName,column)
            x=[]; f=fullfile(app.Root,'results','vlsi2024_xsr',fileName); if isfile(f), t=readtable(f); if ismember(column,t.Properties.VariableNames), x=t.(column); end, end
        end
        function execute(app,label,fn)
            app.StatusLabel.Text=['Running: ' label]; app.Figure.Pointer='watch'; drawnow;
            try, fn(); app.StatusLabel.Text=['Passed: ' label]; catch ex, app.StatusLabel.Text=['Failed: ' label]; app.log(getReport(ex,'basic','hyperlinks','off')); if isvalid(app.Figure), uialert(app.Figure,ex.message,[label ' failed']); end, end
            app.Figure.Pointer='arrow'; drawnow;
        end
        function log(app,msg)
            stamp=char(datetime('now','Format','HH:mm:ss')); old=app.LogArea.Value; if ischar(old), old={old}; end
            app.LogArea.Value=[old;{sprintf('[%s] %s',stamp,msg)}]; scroll(app.LogArea,'bottom');
        end
    end

    methods (Static)
        function names=presetNames(), names={'VLSI Typical','VLSI Ideal'}; end
        function cfg=presetConfig(name)
            switch char(name)
                case 'VLSI Typical', cfg=phyConfig('vlsi2024_xsr_typical');
                case 'VLSI Ideal', cfg=phyConfig('vlsi2024_xsr_ideal');
                otherwise, error('D2DWorkbench:Preset','Unknown paper preset: %s',char(name));
            end
        end
        function paths=paperConfigPaths()
            paths={
                'link.modulation','link.baud_Gbps','link.baud_GBd','link.lineRate_Gbps','link.sps','link.nBits','link.skipUI',...
                'link.snr_dB','link.rjUI_rms','link.djUI_pp','link.djFreq','link.cdrBw','link.seed',...
                'txPma.lane.ffeMode','txPma.lane.ffeOffsets','txPma.lane.ffeCoeffs','txPma.lane.ffeNormalize','txPma.lane.ffeCurrentConstraint',...
                'txPma.lane.sixTapPreset.offsets','txPma.lane.sixTapPreset.coeffs','txPma.lane.enableDacQuantization','txPma.lane.dacLevels',...
                'txPma.lane.targetSwing','txPma.lane.logicalOuterLevel','txPma.lane.gainError','txPma.lane.enableSwingCalibration',...
                'channel.mode','channel.refFreq_GHz','channel.baud_GBd','channel.lossAtRef_dB','channel.poles',...
                'rxPma.lane.terminationMode','rxPma.lane.termGain','rxPma.lane.enableAcPre','rxPma.lane.enableAcPost',...
                'rxPma.lane.acPreCorner_UI','rxPma.lane.acPostCorner_UI','rxPma.lane.acInitialState','rxPma.lane.acSelectedCorner_UI','rxPma.lane.acSelectedMode','rxPma.lane.ctlePolicy',...
                'rxPma.lane.ctleBoost_dB','rxPma.lane.ctleGrid_dB','rxPma.lane.ctleAppliedBoost_dB','rxPma.lane.enableAgc',...
                'rxPma.lane.samplerRoles.enabled','rxPma.lane.samplerRoles.quarterRateBranches',...
                'rxPma.lane.samplerRoles.roleCounts.data','rxPma.lane.samplerRoles.roleCounts.edge','rxPma.lane.samplerRoles.roleCounts.spare',...
                'rxPma.lane.samplerRoles.roleCounts.total','rxPma.lane.samplerRoles.levelShiftCodes.data',...
                'rxPma.lane.samplerRoles.levelShiftCodes.edge','rxPma.lane.samplerRoles.levelShiftCodes.spare',...
                'rxPma.lane.samplerRoles.samplerOffsetCodes','rxPma.lane.samplerRoles.thresholdAssumptions',...
                'model.resultRoot','model.enablePaperAdaptation','model.trainingMode','model.useManualPhase','model.manualPhaseUI','model.manualDelayUI','model.cdrOptions.nCodes',...
                'model.cdrOptions.initialPhaseUI','model.cdrOptions.loopGainCodes','model.cdrOptions.loopBandwidthProxy',...
                'model.cdrOptions.updateCadence','model.cdrOptions.lockWindow','model.cdrOptions.lockToleranceUI',...
                'model.cdrOptions.mismatchBoundLSB','model.cdrOptions.mismatchSeed','model.cdrOptions.enabled','model.cdrOptions.maxStepCodes',...
                'model.debugStages.startupCalibration','model.debugStages.ctleTraining','model.debugStages.ffeTraining',...
                'model.debugStages.samplerCalibration','model.debugStages.clockTraining','model.debugStages.cdrEnabled',...
                'model.debugStages.startupCalibrationBudgetUI','model.debugStages.ctleTrainingBudgetUI','model.debugStages.ffeTrainingBudgetUI',...
                'model.debugStages.samplerCalibrationBudgetUI','model.debugStages.clockTrainingBudgetUI','model.debugStages.postLockWaitUI'};
        end
        function items=probeItems()
            items={'TX FFE output','TX DAC / pad','Channel output','RX termination','RX AC pre','RX AC post','RX CTLE output',...
                'RX level-shifted samples','RX data samples','RX edge samples','RX edge detector','RX spare samples',...
                'PI code','CDR error','CDR lock','Adaptation objective','FFE tap trace'};
        end
        function items=laneItems(), items={'Lane 1','Lane 2','Lane 3','Lane 4','Lane 5','Lane 6','Lane 7','Lane 8','All Lanes'}; end
        function text=valueToText(v)
            if ischar(v)||isstring(v), text=char(v); elseif islogical(v), text=mat2str(v); elseif isnumeric(v), text=mat2str(v,16); else, text=char(string(v)); end
        end
        function value=parseValue(text,old)
            if iscell(text), text=text{1}; end; text=char(string(text));
            if ischar(old)||isstring(old), value=strtrim(text);
            elseif islogical(old)
                token=lower(strtrim(text));
                if any(strcmp(token,{'true','1','on'})), value=true;
                elseif any(strcmp(token,{'false','0','off'})), value=false;
                else, error('logical value must be true/false'); end
            else
                numericText=strtrim(text); wrapped=startsWith(numericText,'[')||endsWith(numericText,']');
                if wrapped
                    if ~(startsWith(numericText,'[')&&endsWith(numericText,']')), error('numeric vector brackets are incomplete'); end
                    numericText=strtrim(numericText(2:end-1));
                end
                if strcmpi(numericText,'inf'), value=inf;
                else
                    if isempty(numericText), error('numeric value required'); end
                    tokens=regexp(numericText,'[,\s]+','split');
                    value=zeros(1,numel(tokens)); pattern='^[+-]?(?:(?:\d+\.?\d*)|(?:\.\d+))(?:[eE][+-]?\d+)?$';
                    for j=1:numel(tokens)
                        if isempty(regexp(tokens{j},pattern,'once')), error('numeric value has invalid trailing text'); end
                        value(j)=str2double(tokens{j});
                    end
                end
                if isscalar(old)&&numel(value)==1, value=value(1); end
            end
        end
        function value=getNested(s,parts), value=s; for k=1:numel(parts), value=value.(parts{k}); end, end
        function s=setNested(s,parts,value)
            if numel(parts)==1, s.(parts{1})=value; else, child=s.(parts{1}); child=D2DWorkbench.setNested(child,parts(2:end),value); s.(parts{1})=child; end
        end
        function validateValue(path,value,old)
            if isnumeric(value)
                if isempty(value)||any(isnan(value(:)))||any(~isfinite(value(:)) & ~strcmp(path,'link.snr_dB')), error('numeric value is not finite'); end
                if any(contains(path,{'nBits','sps','nCodes','lockWindow','updateCadence','dacLevels','quarterRateBranches'})) && ...
                        (~isscalar(value)||value<=0||value~=fix(value)), error('integer value required'); end
                if strcmp(path,'link.skipUI') && (~isscalar(value)||value<0||value~=fix(value)), error('skipUI must be an integer >= 0'); end
                if contains(path,'Offsets') && any(value~=fix(value)), error('tap offsets must be signed integers'); end
                if contains(path,'ffeOffsets') && (numel(unique(value))~=numel(value) || ~any(value==0)), error('FFE offsets must be unique and include zero'); end
                if contains(path,'ctleBoost') && (value<0 || value>6), error('CTLE boost must be within 0 to 6 dB'); end
                if contains(path,'lossAtRef') && value<0, error('analytic IL must be nonnegative'); end
                if strcmp(path,'model.cdrOptions.initialPhaseUI') && (~isscalar(value)||value<0||value>1), error('manual/initial phase must be in [0,1] UI'); end
                if strcmp(path,'model.manualPhaseUI') && (~isscalar(value)||value<0||value>=1), error('manual phase must be in [0,1) UI'); end
                if strcmp(path,'model.manualDelayUI') && (~isscalar(value)||value~=fix(value)), error('manual delay must be an integer UI'); end
                if strcmp(path,'rxPma.lane.termGain') && (~isscalar(value)||value<=0), error('termination gain must be positive'); end
                if strcmp(path,'txPma.lane.ffeCurrentConstraint') && (~isscalar(value)||value<=0), error('FFE current constraint must be positive'); end
                if strcmp(path,'txPma.lane.gainError') && (~isscalar(value)||abs(value)>1), error('TX gain error must be within +/-1'); end
                if strcmp(path,'txPma.lane.logicalOuterLevel') && (~isscalar(value)||value~=3), error('paper PAM4 logical outer level must be 3'); end
                if strcmp(path,'model.cdrOptions.loopGainCodes') && (~isscalar(value)||value<0), error('CDR loop gain must be nonnegative'); end
                if contains(path,'BudgetUI') && (~isscalar(value)||value<0||value~=fix(value)), error('UI budget must be a nonnegative integer'); end
                if strcmp(path,'model.cdrOptions.nCodes') && (~isscalar(value)||value<2||value~=fix(value)), error('PI code count must be an integer >= 2'); end
                if contains(path,'thresholdAssumptions') && numel(value)~=3, error('PAM4 requires three thresholds'); end
                if contains(path,'mismatchBoundLSB') && (value<0||value>=0.5), error('PI mismatch bound must be in [0,0.5)'); end
                if contains(path,'postLockWaitUI') && (value<0||~isscalar(value)||value~=fix(value)), error('post-lock wait must be a nonnegative integer'); end
            end
            if islogical(value)&&~isscalar(value), error('logical control must be scalar'); end
            if contains(path,'ffeCoeffs') && numel(value)~=numel(old), error('FFE coefficients/offsets length mismatch'); end
            if strcmp(path,'rxPma.lane.terminationMode') && ~any(strcmp(value,{'AC','DC'})), error('terminationMode must be AC or DC'); end
            if strcmp(path,'txPma.lane.ffeMode') && ~any(strcmp(value,{'three_tap','six_tap','vector'})), error('ffeMode must be three_tap or six_tap'); end
            if strcmp(path,'rxPma.lane.ctlePolicy') && ~any(strcmp(value,{'paper_grid','continuous','quantized_grid'})), error('unsupported CTLE policy'); end
        end
        function validatePaperConfig(cfg)
            assert(isfield(cfg,'paper')&&strcmp(cfg.paper.id,'VLSI2024_XSR_3nm'),'VLSI2024 paper identity required');
            assert(isfield(cfg.paper,'preset')&&any(strcmp(cfg.paper.preset,{'VLSI Typical','VLSI Ideal'})),'paper preset required');
            assert(isfield(cfg,'model')&&isfield(cfg.model,'debugStages'),'debug stage controls missing');
            assert(isfield(cfg.link,'pam4Mapping')&&strcmp(cfg.link.pam4Mapping,'gray_00_01_11_10')&&...
                isequal(cfg.link.pam4Levels,[-3 -1 1 3])&&isequal(cfg.link.pam4Thresholds,[-2 0 2]),'Gray PAM4 contract required');
            assert(numel(cfg.txPma.lane.ffeOffsets)==numel(cfg.txPma.lane.ffeCoeffs) && ...
                numel(unique(cfg.txPma.lane.ffeOffsets))==numel(cfg.txPma.lane.ffeOffsets) && any(cfg.txPma.lane.ffeOffsets==0),...
                'signed FFE offsets must be unique and include zero');
            assert(numel(cfg.rxPma.lane.samplerRoles.thresholdAssumptions)==3,'PAM4 sampler thresholds required');
        end
    end
end
