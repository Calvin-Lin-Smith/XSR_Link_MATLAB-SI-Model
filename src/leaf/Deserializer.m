classdef Deserializer < Blk
    properties
        rxBits = []
    end
    methods
        function obj=Deserializer(name), if nargin<1,name='deserializer';end, obj@Blk(name); end
        function bits=run(obj,in)
            bits=in(:); obj.rxBits=bits; obj.record('in',bits); obj.record('out',bits);
        end
    end
end
