classdef TxLane < Blk
    properties
        ffe
        serializer
        driver
        txPad = []
    end
    methods
        function obj=TxLane(name)
            if nargin<1,name='tx_lane';end, obj@Blk(name);
            obj.ffe=Ffe([name '.ffe']); obj.serializer=Serializer([name '.serializer']); obj.driver=Driver([name '.driver']);
        end
        function configure(obj,c)
            configure@Blk(obj,c);
            obj.ffe.configure(struct('main',c.txEqMain,'pre',c.txEqPre,'post',c.txEqPost,'normalize',c.ffeNormalize));
            obj.serializer.configure(struct('sps',c.sps)); obj.driver.configure(struct('amplitude',c.amplitude));
        end
        function y=run(obj,syms)
            eq=obj.ffe.run(syms); serial=obj.serializer.run(eq); y=obj.driver.run(serial); obj.txPad=y;
            obj.record('in',syms(:)); obj.record('out',y);
        end
        function dump(obj,indent)
            if nargin<2,indent='';end, dump@Blk(obj,indent);
            obj.ffe.dump([indent '  ']); obj.serializer.dump([indent '  ']); obj.driver.dump([indent '  ']);
        end
    end
end
