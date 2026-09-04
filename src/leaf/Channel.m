classdef Channel < Blk
    properties
        sps = 16
        lossNyq_dB = 0
        mode = 'legacy_nyquist'
        refFreq_GHz = 28
        lossAtRef_dB = 0
        baud_GBd = 56
        poles = 3
        in = []
        out = []
    end
    methods
        function obj=Channel(name), if nargin<1,name='channel';end, obj@Blk(name); end
        function configure(obj,c)
            configure@Blk(obj,c); obj.sps=c.sps; obj.lossNyq_dB=c.lossNyq_dB; obj.poles=c.poles;
            obj.mode='legacy_nyquist'; obj.refFreq_GHz=28; obj.lossAtRef_dB=obj.lossNyq_dB; obj.baud_GBd=56;
            if isfield(c,'mode'), obj.mode=char(c.mode); end
            if isfield(c,'refFreq_GHz'), obj.refFreq_GHz=c.refFreq_GHz; end
            if isfield(c,'lossAtRef_dB'), obj.lossAtRef_dB=c.lossAtRef_dB; end
            if isfield(c,'baud_GBd'), obj.baud_GBd=c.baud_GBd; end
        end
        function y=run(obj,x)
            x=x(:);
            if strcmpi(obj.mode,'analytic_il')
                y=dspChannel(x,obj.sps,struct('mode',obj.mode,'refFreq_GHz',obj.refFreq_GHz,...
                    'baud_GBd',obj.baud_GBd,'lossAtRef_dB',obj.lossAtRef_dB,'poles',obj.poles));
            elseif strcmpi(obj.mode,'legacy_nyquist')
                y=dspChannel(x,obj.sps,obj.lossNyq_dB,obj.poles);
            else
                error('Channel:Mode','Unsupported channel mode: %s',obj.mode);
            end
            obj.in=x; obj.out=y; obj.record('in',x); obj.record('out',y);
        end
    end
end
