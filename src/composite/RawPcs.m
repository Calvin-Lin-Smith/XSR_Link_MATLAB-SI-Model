classdef RawPcs < Blk
    properties
        nLane = 8
        nBits = 4096
        modulation = 'PAM4'
        pattern = 'PRBS31'
        errInject = 0
        skipUI = 32
        seed = 42
        txBits = []
        referenceBits = []
        errCnt = []
    end
    methods
        function obj=RawPcs(name,nLane)
            if nargin<1,name='raw_pcs';end, if nargin<2,nLane=8;end, obj@Blk(name); obj.nLane=nLane;
        end
        function configure(obj,c,link)
            configure@Blk(obj,c); obj.pattern=c.pattern; obj.errInject=c.errInject;
            obj.nBits=link.nBits; obj.modulation=link.modulation; obj.seed=link.seed; obj.skipUI=link.skipUI;
        end
        function syms=run(obj)
            switch upper(obj.pattern)
                case 'PRBS7', taps=[7 6];
                case 'PRBS15', taps=[15 14];
                case 'PRBS31', taps=[31 28];
                case 'PRQS10_SURROGATE', taps=[10 7];
                otherwise, error('RawPcs:Pattern','Unsupported pattern: %s',obj.pattern);
            end
            base=dspPrbs(taps,obj.nBits); obj.referenceBits=repmat(base,1,obj.nLane); obj.txBits=obj.referenceBits;
            old=rng; rng(obj.seed,'twister');
            if obj.errInject>0
                first=obj.skipUI*(1+strcmpi(obj.modulation,'PAM4'))+1;
                candidates=first:obj.nBits;
                if obj.errInject>numel(candidates), error('RawPcs:InjectCount','Too many injected errors.'); end
                for j=1:obj.nLane
                    pick=randperm(numel(candidates),obj.errInject); pos=candidates(pick);
                    obj.txBits(pos,j)=1-obj.txBits(pos,j);
                end
            end
            rng(old); syms=cell(1,obj.nLane);
            for j=1:obj.nLane, syms{j}=dspMap(obj.txBits(:,j),obj.modulation); end
            obj.record('in',obj.referenceBits); obj.record('out',syms);
        end
        function [err,nMeasured,ber]=check(obj,rxBits,skipUI)
            bps=1+strcmpi(obj.modulation,'PAM4'); first=skipUI*bps+1;
            err=zeros(1,obj.nLane); nMeasured=zeros(1,obj.nLane);
            for j=1:obj.nLane
                nb=min(size(rxBits,1),obj.nBits); if nb<first, continue; end
                nMeasured(j)=nb-first+1; err(j)=sum(rxBits(first:nb,j)~=obj.referenceBits(first:nb,j));
            end
            ber=err./max(nMeasured,1); obj.errCnt=err; obj.record('rxBits',rxBits); obj.record('errCnt',err);
        end
        function dump(obj,indent), if nargin<2,indent='';end, dump@Blk(obj,indent); end
    end
end
