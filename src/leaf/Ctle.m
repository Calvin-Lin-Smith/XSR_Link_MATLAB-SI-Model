classdef Ctle < Blk
    properties
        sps = 16
        boostDb = 0
        fz = 0.25
        ctleOut = []
    end
    methods
        function obj=Ctle(name), if nargin<1,name='ctle';end, obj@Blk(name); end
        function configure(obj,c)
            configure@Blk(obj,c); obj.sps=c.sps; obj.boostDb=c.boostDb; obj.fz=c.fz;
        end
        function y=run(obj,x)
            x=x(:); y=dspCtle(x,obj.sps,obj.boostDb,obj.fz); obj.ctleOut=y;
            obj.record('in',x); obj.record('out',y);
        end
    end
end
