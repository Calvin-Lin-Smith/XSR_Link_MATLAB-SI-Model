classdef D2DPHY < Blk
    properties
        rawPcs
        txPma
        rxPma
        channel
        nLane = 8
        link = struct()
        checkerOptions = struct()
        measurementMeta = struct()
    end
    methods
        function obj=D2DPHY(name,nLane)
            if nargin<1,name='dwc_d2d_sr112_phy_tsmc12ffc_x8ns';end
            if nargin<2,nLane=8;end
            obj@Blk(name); obj.nLane=nLane; obj.rawPcs=RawPcs([name '.raw_pcs'],nLane);
            obj.txPma=TxPma([name '.tx_pma'],nLane); obj.rxPma=RxPma([name '.rx_pma'],nLane);
            obj.channel=Channel.empty(0,nLane);
            for j=1:nLane, obj.channel(j)=Channel(sprintf('%s.channel%d',name,j)); end
        end
        function configure(obj,cfg)
            configure@Blk(obj,cfg); obj.link=cfg.link; obj.rawPcs.configure(cfg.rawPcs,cfg.link);
            obj.txPma.configure(cfg.txPma,cfg.link);
            obj.checkerOptions=struct(); if isfield(cfg,'model') && isfield(cfg.model,'checker'), obj.checkerOptions=cfg.model.checker; end
            obj.measurementMeta=struct();
            if isfield(cfg,'model'), obj.rxPma.configure(cfg.rxPma,cfg.link,cfg.model); else, obj.rxPma.configure(cfg.rxPma,cfg.link); end
            cc=cfg.channel; cc.sps=cfg.link.sps;
            for j=1:obj.nLane, obj.channel(j).configure(cc); end
        end
        function res=run(obj)
            syms=obj.rawPcs.run(); tx=obj.txPma.run(syms); ch=cell(1,obj.nLane);
            old=rng; rng(obj.link.seed,'twister');
            for j=1:obj.nLane
                ch{j}=obj.channel(j).run(tx{j});
                if isfinite(obj.link.snr_dB)
                    sigma=rms(ch{j})*10^(-obj.link.snr_dB/20); ch{j}=ch{j}+sigma*randn(size(ch{j}));
                end
            end
            rng(old); rx=obj.rxPma.run(ch,obj.rawPcs.referenceBits);
            checkerOptions=obj.checkerOptions; measurementStartUI=obj.link.skipUI;
            if isfield(checkerOptions,'paper') && checkerOptions.paper
                [measurementStartUI,obj.measurementMeta]=paperMeasurementWindow(obj,checkerOptions);
                checkerOptions.measurementStartUI=measurementStartUI; checkerOptions.tailValid=obj.measurementMeta.continuousTailLock;
                checkerOptions.firstValidLockUI=obj.measurementMeta.firstValidLockUI; checkerOptions.measurementEndUI=obj.measurementMeta.measurementEndUI;
                checkerOptions.tailLockLosses=obj.measurementMeta.tailLockLosses; checkerOptions.tailCycleSlips=obj.measurementMeta.tailCycleSlips;
                checkerOptions.tailLevelsValid=obj.measurementMeta.tailLevelsValid;
            end
            checkSkipUI=measurementStartUI; if ~isfinite(checkSkipUI), checkSkipUI=obj.link.skipUI; end
            [err,nMeasured,ber,checker]=obj.rawPcs.check(rx,checkSkipUI,checkerOptions);
            if isfield(checker,'measurementStartUI'), obj.measurementMeta.measurementStartUI=checker.measurementStartUI; end
            res=struct('rxBits',rx,'errCnt',err,'nMeasured',nMeasured,'ber',ber,...
                'aggregateBer',sum(err)/max(sum(nMeasured),1),'checker',checker,'measurement',obj.measurementMeta,...
                'firstValidLockUI',obj.measurementMeta.firstValidLockUI,'measurementStartUI',obj.measurementMeta.measurementStartUI,...
                'continuousTailLock',obj.measurementMeta.continuousTailLock,'tailLockLosses',obj.measurementMeta.tailLockLosses,...
                'tailCycleSlips',obj.measurementMeta.tailCycleSlips,'tailLevelsValid',obj.measurementMeta.tailLevelsValid);
            obj.record('txPad',tx); obj.record('channelOut',ch); obj.record('rxBits',rx); obj.record('out',res);
        end
        function dump(obj,indent)
            if nargin<2,indent='';end, dump@Blk(obj,indent); obj.rawPcs.dump([indent '  ']);
            obj.txPma.dump([indent '  ']);
            for j=1:obj.nLane, obj.channel(j).dump([indent '  ']); end
            obj.rxPma.dump([indent '  ']);
        end
    end
end

function [measurementStartUI,meta]=paperMeasurementWindow(obj,options)
postLockWaitUI=getField(options,'postLockWaitUI',16); minTailUI=getField(options,'minTailUI',64);
first=zeros(1,obj.nLane); tailValid=false(1,obj.nLane); tailLosses=zeros(1,obj.nLane); tailSlips=zeros(1,obj.nLane); tailLevels=false(1,obj.nLane);
for k=1:obj.nLane
    first(k)=getField(obj.rxPma.lane(k).cdrTrace,'firstValidLockIndex',0);
end
if any(first==0), measurementStartUI=NaN; else, measurementStartUI=max([obj.link.skipUI max(first)+postLockWaitUI]); end
measurementEndUI=inf; if ~isempty(obj.rxPma.lane(1).cdrTrace), measurementEndUI=numel(obj.rxPma.lane(1).cdrTrace.currentlyLockedTrace); end
if isfinite(measurementStartUI)
    for k=1:obj.nLane
        t=obj.rxPma.lane(k).cdrTrace; measurementEndUI=min(measurementEndUI,numel(t.currentlyLockedTrace)); idx=measurementStartUI+1;
        levelsTrace=getField(t,'levelsValidTrace',false(size(t.currentlyLockedTrace))); lockLossTrace=getField(t,'lockLossTrace',false(size(t.currentlyLockedTrace)));
        slipTrace=getField(t,'cycleSlipTrace',false(size(t.currentlyLockedTrace)));
        if idx<=numel(t.currentlyLockedTrace)
            tailLosses(k)=sum(lockLossTrace(idx:end)); tailSlips(k)=sum(slipTrace(idx:end)); tailLevels(k)=all(levelsTrace(idx:end));
            tailValid(k)=getField(t,'currentlyLocked',false)&&all(t.currentlyLockedTrace(idx:end))&&tailLosses(k)==0&&tailLevels(k)&&tailSlips(k)==0;
        end
    end
    if measurementEndUI-measurementStartUI<minTailUI, tailValid(:)=false; end
end
meta=struct('firstValidLockUI',first,'postLockWaitUI',postLockWaitUI,'measurementStartUI',measurementStartUI,...
    'measurementEndUI',measurementEndUI,'continuousTailLock',all(tailValid),'tailLockLosses',tailLosses,...
    'tailCycleSlips',tailSlips,'tailLevelsValid',tailLevels,'minTailUI',minTailUI);
end

function value=getField(s,name,default)
if isstruct(s)&&isfield(s,name), value=s.(name); else, value=default; end
end
