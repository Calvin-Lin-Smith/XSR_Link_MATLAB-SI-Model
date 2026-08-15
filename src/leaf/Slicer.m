classdef Slicer < Blk
    properties
        modulation = 'PAM4'
        sps = 16
        phase = 8
        delayUI = 0
        jitterUI = 0
        in = []
        rxBits = []
        samples = []
    end
    methods
        function obj=Slicer(name), if nargin<1,name='slicer';end, obj@Blk(name); end
        function configure(obj,c)
            configure@Blk(obj,c); obj.modulation=c.modulation; obj.sps=c.sps;
            if isfield(c,'phase'), obj.phase=c.phase; else, obj.phase=floor(c.sps/2); end
            if isfield(c,'delayUI'), obj.delayUI=c.delayUI; end
            if isfield(c,'jitterUI'), obj.jitterUI=c.jitterUI; end
        end
        function bits=run(obj,x)
            x=x(:); [v,~,~]=dspSample(x,obj.phase,obj.delayUI,obj.sps,obj.jitterUI);
            bits=dspSlice(v,obj.modulation); obj.in=x; obj.samples=v; obj.rxBits=bits;
            obj.record('in',x); obj.record('samples',v); obj.record('out',bits);
        end
    end
end
