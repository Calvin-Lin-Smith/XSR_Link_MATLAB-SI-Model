classdef Channel < Blk
    properties
        sps = 16
        lossNyq_dB = 0
        poles = 3
        in = []
        out = []
    end
    methods
        function obj=Channel(name), if nargin<1,name='channel';end, obj@Blk(name); end
        function configure(obj,c)
            configure@Blk(obj,c); obj.sps=c.sps; obj.lossNyq_dB=c.lossNyq_dB; obj.poles=c.poles;
        end
        function y=run(obj,x)
            x=x(:); y=dspChannel(x,obj.sps,obj.lossNyq_dB,obj.poles);
            obj.in=x; obj.out=y; obj.record('in',x); obj.record('out',y);
        end
    end
end
