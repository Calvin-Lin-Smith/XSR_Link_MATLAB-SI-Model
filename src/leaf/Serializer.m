classdef Serializer < Blk
    properties
        sps = 16
        out = []
    end
    methods
        function obj=Serializer(name), if nargin<1,name='serializer';end, obj@Blk(name); end
        function configure(obj,c), configure@Blk(obj,c); obj.sps=c.sps; end
        function y=run(obj,x)
            x=x(:); y=repelem(x,obj.sps); obj.out=y; obj.record('in',x); obj.record('out',y);
        end
    end
end
