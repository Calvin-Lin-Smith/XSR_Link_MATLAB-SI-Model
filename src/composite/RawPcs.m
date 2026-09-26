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
        checkerOptions = struct()
        checkerMeta = struct()
    end
    methods
        function obj=RawPcs(name,nLane)
            if nargin<1,name='raw_pcs';end, if nargin<2,nLane=8;end, obj@Blk(name); obj.nLane=nLane;
        end
        function configure(obj,c,link)
            configure@Blk(obj,c); obj.pattern=c.pattern; obj.errInject=c.errInject;
            obj.nBits=link.nBits; obj.modulation=link.modulation; obj.seed=link.seed; obj.skipUI=link.skipUI; obj.checkerOptions=struct(); obj.checkerMeta=struct();
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
        function [err,nMeasured,ber,meta]=check(obj,rxBits,skipUI,varargin)
            options=struct(); if ~isempty(varargin), options=varargin{1}; end
            if ischar(options)||isstring(options), options=struct('paper',strcmpi(char(options),'paper')); end
            if isempty(fieldnames(options)) && ~isempty(fieldnames(obj.checkerOptions)), options=obj.checkerOptions; end
            if isfield(options,'paper') && logical(options.paper)
                [err,nMeasured,ber,meta]=paperCheck(obj,rxBits,skipUI,options); obj.checkerMeta=meta;
                obj.errCnt=err; obj.record('rxBits',rxBits); obj.record('errCnt',err); obj.record('checker',meta); return;
            end
            bps=1+strcmpi(obj.modulation,'PAM4'); first=skipUI*bps+1;
            err=zeros(1,obj.nLane); nMeasured=zeros(1,obj.nLane);
            for j=1:obj.nLane
                nb=min(size(rxBits,1),obj.nBits); if nb<first, continue; end
                nMeasured(j)=nb-first+1; err(j)=sum(rxBits(first:nb,j)~=obj.referenceBits(first:nb,j));
            end
            ber=err./max(nMeasured,1); meta=legacyCheckerMeta(obj,nMeasured,skipUI); obj.checkerMeta=meta;
            obj.errCnt=err; obj.record('rxBits',rxBits); obj.record('errCnt',err); obj.record('checker',meta);
        end
        function dump(obj,indent), if nargin<2,indent='';end, dump@Blk(obj,indent); end
    end
end

function meta=legacyCheckerMeta(obj,nMeasured,skipUI)
meta=struct('mode','legacy_skip_ui','checkerLagUI',zeros(1,obj.nLane),...
    'syncBits',zeros(1,obj.nLane),'measurementBits',nMeasured,'alignmentValid',true(1,obj.nLane),...
    'framingValid',true(1,obj.nLane),'measurementStartUI',skipUI);
end

function [err,nMeasured,ber,meta]=paperCheck(obj,rxBits,skipUI,options)
bps=1+strcmpi(obj.modulation,'PAM4'); maxLagUI=getField(options,'maxLagUI',4);
syncLength=getField(options,'syncBits',128); explicitStart=getField(options,'measurementStartBits',[]);
validateattributes(maxLagUI,{'numeric'},{'scalar','integer','nonnegative'});
validateattributes(syncLength,{'numeric'},{'scalar','integer','nonnegative'});
if ~isempty(explicitStart), validateattributes(explicitStart,{'numeric'},{'scalar','integer','nonnegative'}); end
if isvector(rxBits), rxBits=rxBits(:); end
rxBits=double(rxBits); ref=double(obj.referenceBits); lanes=min([obj.nLane size(rxBits,2) size(ref,2)]);
err=nan(1,obj.nLane); nMeasured=zeros(1,obj.nLane); ber=nan(1,obj.nLane);
lagUI=nan(1,obj.nLane); syncBits=zeros(1,obj.nLane); measurementBits=zeros(1,obj.nLane); alignmentValid=false(1,obj.nLane); framingValid=false(1,obj.nLane);
syncErrors=nan(1,obj.nLane); oddErrors=nan(1,obj.nLane); measurementStartBit=nan(1,obj.nLane);
for lane=1:lanes
    nRef=min(size(ref,1),obj.nBits); nRx=size(rxBits,1);
    baseStart=skipUI*bps+1;
    if isempty(explicitStart)
        if baseStart>1 && baseStart-1>=syncLength, syncEnd=min([nRef nRx baseStart-1]); syncStart=max(1,syncEnd-syncLength+1); measureStart=max(baseStart,syncEnd+1);
        elseif baseStart>1, syncStart=baseStart; syncEnd=min([nRef nRx baseStart+syncLength-1]); measureStart=syncEnd+1;
        else, syncStart=1; syncEnd=min([nRef nRx syncLength]); measureStart=syncEnd+1; end
    else
        measureStart=explicitStart+1; syncEnd=min([nRef nRx max(0,measureStart-1)]); syncStart=max(1,syncEnd-syncLength+1);
    end
    if syncEnd<syncStart, syncStart=1; syncEnd=0; end
    evenUI=-maxLagUI:maxLagUI; evenBits=evenUI*bps; evenErr=inf(size(evenBits)); evenCount=zeros(size(evenBits));
    for k=1:numel(evenBits), [evenErr(k),evenCount(k)]=windowErrors(rxBits(:,lane),ref(:,lane),syncStart,syncEnd,evenBits(k)); end
    bestErr=min(evenErr); bestIndex=find(evenErr==bestErr,1,'last'); bestLagBits=evenBits(bestIndex);
    oddCandidates=(-maxLagUI*bps):(maxLagUI*bps); oddCandidates=oddCandidates(mod(oddCandidates,bps)~=0); oddErr=inf(size(oddCandidates));
    for k=1:numel(oddCandidates), [oddErr(k),~]=windowErrors(rxBits(:,lane),ref(:,lane),syncStart,syncEnd,oddCandidates(k)); end
    bestOdd=min(oddErr); oddAdvantage=max(2,ceil(0.1*max(syncEnd-syncStart+1,1)));
    framingValid(lane)=isempty(oddErr) || ~(bestOdd<bestErr-oddAdvantage);
    if isfinite(bestErr) && framingValid(lane)
        [measureErr,measureCount]=windowErrors(rxBits(:,lane),ref(:,lane),measureStart,min(nRef,nRx),bestLagBits);
        if measureCount>0
            lagUI(lane)=bestLagBits/bps; syncBits(lane)=max(0,syncEnd-syncStart+1); measurementBits(lane)=measureCount;
            err(lane)=measureErr; nMeasured(lane)=measureCount; ber(lane)=measureErr/measureCount; alignmentValid(lane)=true;
            syncErrors(lane)=bestErr; oddErrors(lane)=bestOdd; measurementStartBit(lane)=measureStart;
        end
    end
end
meta=struct('mode','paper_integer_ui','checkerLagUI',lagUI,'syncBits',syncBits,'measurementBits',measurementBits,...
    'alignmentValid',alignmentValid,'framingValid',framingValid,'syncErrors',syncErrors,'oddBitErrors',oddErrors,...
    'measurementStartBit',measurementStartBit,'measurementStartUI',(measurementStartBit-1)/bps,...
    'maxLagUI',maxLagUI,'bitsPerUI',bps,'referenceSource','RawPcs.referenceBits');
end

function [errors,count]=windowErrors(rx,ref,startIndex,endIndex,lagBits)
if endIndex<startIndex, errors=inf; count=0; return; end
rxStart=startIndex+max(lagBits,0); refStart=startIndex+max(-lagBits,0);
count=min([endIndex-startIndex+1 numel(rx)-rxStart+1 numel(ref)-refStart+1]);
if count<=0, errors=inf; count=0; else, errors=sum(rx(rxStart:rxStart+count-1)~=ref(refStart:refStart+count-1)); end
end

function value=getField(s,name,default)
if isstruct(s)&&isfield(s,name), value=s.(name); else, value=default; end
end
