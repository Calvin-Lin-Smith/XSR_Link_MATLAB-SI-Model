classdef Driver < Blk
    properties
        amplitude = 1
        txPad = []
    end
    methods
        function obj=Driver(name), if nargin<1,name='driver';end, obj@Blk(name); end
        function configure(obj,c), configure@Blk(obj,c); obj.amplitude=c.amplitude; end
        function y=run(obj,x)
            x=x(:); y=obj.amplitude*x; obj.txPad=y; obj.record('in',x); obj.record('out',y);
        end
    end
end
