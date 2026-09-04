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
    end
    methods
        function obj=RxLane(name)
            if nargin<1,name='rx_lane';end, obj@Blk(name);
            obj.afe=Afe([name '.afe']); obj.slicer=Slicer([name '.slicer']); obj.deserializer=Deserializer([name '.deserializer']);
        end
        function configure(obj,c)
            configure@Blk(obj,c); obj.afe.configure(c);
            sc=struct('modulation',c.modulation,'sps',c.sps,'phase',floor(c.sps/2),'delayUI',0,'jitterUI',0);
            if isfield(c,'samplerRoles'), sc.samplerRoles=c.samplerRoles; end
            obj.slicer.configure(sc);
        end
        function bits=run(obj,x,txBits,jitterUI,skipUI)
            y=obj.afe.run(x);
            [~,d,ph,~,~]=dspAlign(y,txBits,obj.cfg.modulation,obj.cfg.sps,skipUI);
            obj.bestPhase=ph; obj.delayUI=d;
            sc=struct('modulation',obj.cfg.modulation,'sps',obj.cfg.sps,'phase',ph,'delayUI',d,'jitterUI',jitterUI);
            if isfield(obj.cfg,'samplerRoles'), sc.samplerRoles=obj.cfg.samplerRoles; end
            obj.slicer.configure(sc);
            bits=obj.deserializer.run(obj.slicer.run(y)); obj.rxBits=bits;
            obj.dataSamples=obj.slicer.dataSamples; obj.dataDecisions=obj.slicer.dataDecisions;
            obj.edgeSamples=obj.slicer.edgeSamples; obj.edgeDetectorOutput=obj.slicer.edgeDetectorOutput;
            obj.spareSamples=obj.slicer.spareSamples; obj.spareMonitorOutput=obj.slicer.spareMonitorOutput;
            obj.record('in',x(:)); obj.record('out',bits);
        end
        function dump(obj,indent)
            if nargin<2,indent='';end, dump@Blk(obj,indent);
            obj.afe.dump([indent '  ']); obj.slicer.dump([indent '  ']); obj.deserializer.dump([indent '  ']);
        end
    end
end
