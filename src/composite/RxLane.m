classdef RxLane < Blk
    properties
        afe
        slicer
        deserializer
        rxBits = []
        bestPhase = 0
        delayUI = 0
        dataSamples = []
        dataDecisions = []
        edgeSamples = []
        edgeDetectorOutput = []
        spareSamples = []
        spareMonitorOutput = []
        useReferenceAlign = true
        useManualPhase = false
        manualPhaseUI = 0.5
        manualDelayUI = 0
        cdrOptions = struct()
        cdrTrace = struct()
    end
    methods
        function obj=RxLane(name)
            if nargin<1,name='rx_lane';end, obj@Blk(name);
            obj.afe=Afe([name '.afe']); obj.slicer=Slicer([name '.slicer']); obj.deserializer=Deserializer([name '.deserializer']);
        end
        function configure(obj,c)
            configure@Blk(obj,c); obj.afe.configure(c);
            obj.useReferenceAlign=true; if isfield(c,'useReferenceAlign'), obj.useReferenceAlign=logical(c.useReferenceAlign); end
            obj.useManualPhase=false; if isfield(c,'useManualPhase'), obj.useManualPhase=logical(c.useManualPhase); end
            if isfield(c,'manualPhaseUI'), obj.manualPhaseUI=c.manualPhaseUI; end
            if isfield(c,'manualDelayUI'), obj.manualDelayUI=c.manualDelayUI; end
            obj.cdrOptions=struct(); if isfield(c,'cdrOptions'), obj.cdrOptions=c.cdrOptions; end
            sc=struct('modulation',c.modulation,'sps',c.sps,'phase',floor(c.sps/2),'delayUI',0,'jitterUI',0);
            if isfield(c,'samplerRoles'), sc.samplerRoles=c.samplerRoles; end
            obj.slicer.configure(sc);
        end
        function bits=run(obj,x,txBits,jitterUI,skipUI)
            y=obj.afe.run(x);
            if obj.useReferenceAlign
                [~,d,ph,~,~]=dspAlign(y,txBits,obj.cfg.modulation,obj.cfg.sps,skipUI);
                obj.bestPhase=ph; obj.delayUI=d;
                sc=struct('modulation',obj.cfg.modulation,'sps',obj.cfg.sps,'phase',ph,'delayUI',d,'jitterUI',jitterUI);
                if isfield(obj.cfg,'samplerRoles'), sc.samplerRoles=obj.cfg.samplerRoles; end
                obj.slicer.configure(sc); bits=obj.deserializer.run(obj.slicer.run(y));
                obj.cdrTrace=struct('enabled',false,'trainingMode','legacy_reference_align');
            elseif obj.useManualPhase
                phase=round(obj.manualPhaseUI*obj.cfg.sps); sc=struct('modulation',obj.cfg.modulation,'sps',obj.cfg.sps,...
                    'phase',phase,'delayUI',obj.manualDelayUI,'jitterUI',jitterUI);
                if isfield(obj.cfg,'samplerRoles'), sc.samplerRoles=obj.cfg.samplerRoles; end
                obj.slicer.configure(sc); bits=obj.deserializer.run(obj.slicer.run(y)); obj.bestPhase=mod(phase,obj.cfg.sps); obj.delayUI=obj.manualDelayUI;
                obj.cdrTrace=struct('enabled',false,'trainingMode','fixed_manual_phase','manualPhaseUI',obj.manualPhaseUI,...
                    'manualDelayUI',obj.manualDelayUI,'lockIndex',NaN,'cdr_lock_trace',false(size(obj.slicer.dataSamples)));
            else
                cdrOpts=obj.cdrOptions; cdrOpts.jitterUI=jitterUI; cdrOpts.samplerOffsetCodes=0;
                if isfield(obj.cfg,'samplerRoles') && isfield(obj.cfg.samplerRoles,'samplerOffsetCodes')
                    cdrOpts.samplerOffsetCodes=obj.cfg.samplerRoles.samplerOffsetCodes;
                end
                [cdrBits,obj.cdrTrace]=dspBbCdr(y,obj.cfg.modulation,obj.cfg.sps,cdrOpts);
                obj.bestPhase=mod(round(obj.cdrTrace.dataPhaseUI(end)*obj.cfg.sps),obj.cfg.sps); obj.delayUI=0;
                sc=struct('modulation',obj.cfg.modulation,'sps',obj.cfg.sps,'phase',obj.bestPhase,'delayUI',0,'jitterUI',jitterUI);
                if isfield(obj.cfg,'samplerRoles'), sc.samplerRoles=obj.cfg.samplerRoles; end
                obj.slicer.configure(sc); obj.slicer.run(y);
                obj.slicer.dataSamples=obj.cdrTrace.samples; obj.slicer.dataDecisions=obj.cdrTrace.decisionTrace;
                obj.slicer.edgeSamples=obj.cdrTrace.earlySamples; obj.slicer.edgeDetectorOutput=obj.cdrTrace.errorTrace;
                obj.slicer.spareSamples=obj.cdrTrace.lateSamples; obj.slicer.spareMonitorOutput=obj.cdrTrace.residualPhaseUI;
                bits=obj.deserializer.run(cdrBits);
            end
            obj.rxBits=bits;
            obj.dataSamples=obj.slicer.dataSamples; obj.dataDecisions=obj.slicer.dataDecisions;
            obj.edgeSamples=obj.slicer.edgeSamples; obj.edgeDetectorOutput=obj.slicer.edgeDetectorOutput;
            obj.spareSamples=obj.slicer.spareSamples; obj.spareMonitorOutput=obj.slicer.spareMonitorOutput;
            obj.record('in',x(:)); obj.record('out',bits);
            if ~obj.useReferenceAlign, obj.record('cdr',obj.cdrTrace); end
        end
        function dump(obj,indent)
            if nargin<2,indent='';end, dump@Blk(obj,indent);
            obj.afe.dump([indent '  ']); obj.slicer.dump([indent '  ']); obj.deserializer.dump([indent '  ']);
        end
    end
end
