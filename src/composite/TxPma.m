classdef TxPma < Blk
    properties
        lane
        support
        nLane = 8
    end
    methods
        function obj=TxPma(name,nLane)
            if nargin<1,name='tx_pma';end, if nargin<2,nLane=8;end, obj@Blk(name); obj.nLane=nLane;
            obj.support=TxSupport([name '.support']); obj.lane=TxLane.empty(0,nLane);
            for j=1:nLane, obj.lane(j)=TxLane(sprintf('%s.lane%d',name,j)); end
        end
        function configure(obj,c,link)
            configure@Blk(obj,c); pc=struct('mode','forwarded','rjRms',0,'djPp',0,'djFreq',1e-3,'bandwidth',link.cdrBw,'seed',link.seed);
            obj.support.configure(pc); lc=c.lane; lc.sps=link.sps;
            for j=1:obj.nLane, obj.lane(j).configure(lc); end
        end
        function out=run(obj,syms)
            out=cell(1,obj.nLane); for j=1:obj.nLane, out{j}=obj.lane(j).run(syms{j}); end
            obj.record('in',syms); obj.record('out',out);
        end
        function dump(obj,indent)
            if nargin<2,indent='';end, dump@Blk(obj,indent); obj.support.dump([indent '  ']);
            for j=1:obj.nLane, obj.lane(j).dump([indent '  ']); end
        end
    end
end
