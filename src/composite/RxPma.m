classdef RxPma < Blk
    properties
        lane
        support
        nLane = 8
        link = struct()
    end
    methods
        function obj=RxPma(name,nLane)
            if nargin<1,name='rx_pma';end, if nargin<2,nLane=8;end, obj@Blk(name); obj.nLane=nLane;
            obj.support=RxSupport([name '.support']); obj.lane=RxLane.empty(0,nLane);
            for j=1:nLane, obj.lane(j)=RxLane(sprintf('%s.lane%d',name,j)); end
        end
        function configure(obj,c,link)
            configure@Blk(obj,c); obj.link=link;
            pc=struct('mode',c.lane.clockMode,'rjRms',link.rjUI_rms,'djPp',link.djUI_pp,'djFreq',link.djFreq,'bandwidth',link.cdrBw,'seed',link.seed);
            obj.support.configure(pc); lc=c.lane; lc.sps=link.sps; lc.modulation=link.modulation;
            for j=1:obj.nLane, obj.lane(j).configure(lc); end
        end
        function bits=run(obj,waves,txBits)
            bps=1+strcmpi(obj.link.modulation,'PAM4'); nSym=floor(obj.link.nBits/bps);
            jitter=obj.support.run(nSym); bits=[];
            for j=1:obj.nLane
                bj=obj.lane(j).run(waves{j},txBits(:,j),jitter,obj.link.skipUI);
                if isempty(bits), bits=zeros(numel(bj),obj.nLane); end
                bits(1:numel(bj),j)=bj;
            end
            obj.record('in',waves); obj.record('out',bits);
        end
        function dump(obj,indent)
            if nargin<2,indent='';end, dump@Blk(obj,indent); obj.support.dump([indent '  ']);
            for j=1:obj.nLane, obj.lane(j).dump([indent '  ']); end
        end
    end
end
