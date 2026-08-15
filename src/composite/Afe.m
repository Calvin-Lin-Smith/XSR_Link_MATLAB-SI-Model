classdef Afe < Blk
    properties
        term
        ctle
        termOut = []
        ctleRaw = []
        ctleOut = []
        agcGain = 1
    end
    methods
        function obj=Afe(name)
            if nargin<1,name='afe';end, obj@Blk(name);
            obj.term=Term([name '.term']); obj.ctle=Ctle([name '.ctle']);
        end
        function configure(obj,c)
            configure@Blk(obj,c);
            obj.term.configure(struct('gain',c.termGain));
            obj.ctle.configure(struct('sps',c.sps,'boostDb',c.ctleBoost_dB,'fz',c.ctleFz));
        end
        function y=run(obj,x)
            obj.termOut=obj.term.run(x); raw=obj.ctle.run(obj.termOut); obj.ctleRaw=raw;
            den=max(rms(raw),eps); obj.agcGain=rms(obj.termOut)/den; y=raw*obj.agcGain; obj.ctleOut=y;
            obj.record('in',x(:)); obj.record('termOut',obj.termOut); obj.record('ctleRaw',raw); obj.record('out',y);
        end
        function dump(obj,indent)
            if nargin<2,indent='';end, dump@Blk(obj,indent);
            obj.term.dump([indent '  ']); obj.ctle.dump([indent '  ']);
        end
    end
end
