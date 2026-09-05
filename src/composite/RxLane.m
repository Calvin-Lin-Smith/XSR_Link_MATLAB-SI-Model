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
            else
                cdrOpts=obj.cdrOptions; cdrOpts.jitterUI=jitterUI;
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
