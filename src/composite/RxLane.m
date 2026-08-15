classdef RxLane < Blk
    properties
        afe
        slicer
        deserializer
        rxBits = []
        bestPhase = 0
        delayUI = 0
    end
    methods
        function obj=RxLane(name)
            if nargin<1,name='rx_lane';end, obj@Blk(name);
            obj.afe=Afe([name '.afe']); obj.slicer=Slicer([name '.slicer']); obj.deserializer=Deserializer([name '.deserializer']);
        end
        function configure(obj,c)
            configure@Blk(obj,c); obj.afe.configure(c);
            obj.slicer.configure(struct('modulation',c.modulation,'sps',c.sps,'phase',floor(c.sps/2),'delayUI',0,'jitterUI',0));
        end
        function bits=run(obj,x,txBits,jitterUI,skipUI)
            y=obj.afe.run(x);
            [~,d,ph,~,~]=dspAlign(y,txBits,obj.cfg.modulation,obj.cfg.sps,skipUI);
            obj.bestPhase=ph; obj.delayUI=d;
            obj.slicer.configure(struct('modulation',obj.cfg.modulation,'sps',obj.cfg.sps,'phase',ph,'delayUI',d,'jitterUI',jitterUI));
            bits=obj.deserializer.run(obj.slicer.run(y)); obj.rxBits=bits;
            obj.record('in',x(:)); obj.record('out',bits);
        end
        function dump(obj,indent)
            if nargin<2,indent='';end, dump@Blk(obj,indent);
            obj.afe.dump([indent '  ']); obj.slicer.dump([indent '  ']); obj.deserializer.dump([indent '  ']);
        end
    end
end
