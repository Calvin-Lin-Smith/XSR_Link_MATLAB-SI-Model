classdef Afe < Blk
    properties
        term
        ctle
        termOut = []
        acPreOut = []
        ctleRaw = []
        acPostOut = []
        ctleOut = []
        levelShiftOut = []
        agcGain = 1
        appliedAgcGain = 1
        enableAcPre = false
        enableAcPost = false
        acPreCorner_UI = 0.01
        acPostCorner_UI = 0.01
        acInitialState = 'steady_state'
        enableAgc = true
        terminationMode = 'AC'
    end
    methods
        function obj=Afe(name)
            if nargin<1,name='afe';end, obj@Blk(name);
            obj.term=Term([name '.term']); obj.ctle=Ctle([name '.ctle']);
        end
        function configure(obj,c)
            configure@Blk(obj,c);
            obj.term.configure(struct('gain',c.termGain));
            obj.terminationMode='AC'; if isfield(c,'terminationMode'), obj.terminationMode=upper(char(c.terminationMode)); end
            if ~any(strcmp(obj.terminationMode,{'AC','DC'})), error('Afe:TerminationMode','terminationMode must be AC or DC.'); end
            obj.enableAcPre=false; obj.enableAcPost=false; obj.acInitialState='steady_state'; obj.enableAgc=true;
            if isfield(c,'enableAcPre'), obj.enableAcPre=logical(c.enableAcPre); end
            if isfield(c,'enableAcPost'), obj.enableAcPost=logical(c.enableAcPost); end
            if isfield(c,'acPreCorner_UI'), obj.acPreCorner_UI=c.acPreCorner_UI; end
            if isfield(c,'acPostCorner_UI'), obj.acPostCorner_UI=c.acPostCorner_UI; end
            if isfield(c,'acInitialState'), obj.acInitialState=char(c.acInitialState); end
            if isfield(c,'enableAgc'), obj.enableAgc=logical(c.enableAgc); end
            cc=struct('sps',c.sps,'boostDb',c.ctleBoost_dB,'fz',c.ctleFz);
            if isfield(c,'ctlePolicy'), cc.policy=c.ctlePolicy; end
            obj.ctle.configure(cc);
        end
        function y=run(obj,x)
            obj.termOut=obj.term.run(x); obj.acPreOut=obj.termOut;
            if obj.enableAcPre && strcmp(obj.terminationMode,'AC'), obj.acPreOut=dspAcCouple(obj.termOut,obj.cfg.sps,obj.acPreCorner_UI,obj.acInitialState); end
            raw=obj.ctle.run(obj.acPreOut); obj.ctleRaw=raw; obj.acPostOut=raw;
            if obj.enableAcPost && strcmp(obj.terminationMode,'AC'), obj.acPostOut=dspAcCouple(raw,obj.cfg.sps,obj.acPostCorner_UI,obj.acInitialState); end
            if obj.enableAgc
                den=max(rms(raw),eps); obj.agcGain=rms(obj.termOut)/den;
            else
                obj.agcGain=1;
            end
            obj.appliedAgcGain=obj.agcGain; y=obj.acPostOut*obj.agcGain; obj.ctleOut=y; obj.levelShiftOut=y;
            obj.record('in',x(:)); obj.record('termOut',obj.termOut); obj.record('acPreOut',obj.acPreOut);
            obj.record('ctleRaw',obj.ctleRaw); obj.record('acPostOut',obj.acPostOut); obj.record('out',y);
            obj.log.appliedAgcGain=obj.appliedAgcGain;
        end
        function dump(obj,indent)
            if nargin<2,indent='';end, dump@Blk(obj,indent);
            obj.term.dump([indent '  ']); obj.ctle.dump([indent '  ']);
        end
    end
end
