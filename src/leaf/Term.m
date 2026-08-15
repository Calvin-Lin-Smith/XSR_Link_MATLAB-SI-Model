classdef Term < Blk
    properties
        gain = 1
        out = []
    end
    methods
        function obj=Term(name), if nargin<1,name='term';end, obj@Blk(name); end
        function configure(obj,c), configure@Blk(obj,c); obj.gain=c.gain; end
        function y=run(obj,x)
            x=x(:); y=obj.gain*x; obj.out=y; obj.record('in',x); obj.record('out',y);
        end
    end
end
