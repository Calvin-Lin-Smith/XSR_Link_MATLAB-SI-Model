classdef D2DPHY < Blk
    properties
        rawPcs
        txPma
        rxPma
        channel
        nLane = 8
        link = struct()
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
            [err,nMeasured,ber]=obj.rawPcs.check(rx,obj.link.skipUI);
            res=struct('rxBits',rx,'errCnt',err,'nMeasured',nMeasured,'ber',ber,...
                'aggregateBer',sum(err)/max(sum(nMeasured),1));
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
