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
        function configure(obj,c,link,model)
            configure@Blk(obj,c); obj.link=link;
            pc=struct('mode',c.lane.clockMode,'rjRms',link.rjUI_rms,'djPp',link.djUI_pp,'djFreq',link.djFreq,'bandwidth',link.cdrBw,'seed',link.seed);
            obj.support.configure(pc); lc=c.lane; lc.sps=link.sps; lc.modulation=link.modulation;
            lc.useReferenceAlign=true;
            if nargin>=4 && isstruct(model)
                if isfield(model,'useReferenceAlign'), lc.useReferenceAlign=logical(model.useReferenceAlign); end
                if isfield(model,'cdrOptions'), lc.cdrOptions=model.cdrOptions; end
            end
            for j=1:obj.nLane, obj.lane(j).configure(lc); end
        end
        function bits=run(obj,waves,txBits)
            bps=1+strcmpi(obj.link.modulation,'PAM4'); nSym=floor(obj.link.nBits/bps);
            jitter=obj.support.run(nSym); bits=[];
            for j=1:obj.nLane
                ref=[]; if obj.lane(j).useReferenceAlign, ref=txBits(:,j); end
                bj=obj.lane(j).run(waves{j},ref,jitter,obj.link.skipUI);
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
