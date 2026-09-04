classdef Slicer < Blk
    properties
        modulation = 'PAM4'
        sps = 16
        phase = 8
        delayUI = 0
        jitterUI = 0
        in = []
        rxBits = []
        samples = []
        samplerRolesEnabled = false
        quarterRateBranches = 4
        samplerRoleCounts = struct('data',0,'edge',0,'spare',0)
        levelShiftCodes = struct('data',[],'edge',[],'spare',[])
        comparatorThresholds = []
        quarterRateSamples = {}
        dataSamples = []
        dataDecisions = []
        edgeSamples = []
        edgeDetectorOutput = []
        spareSamples = []
        spareMonitorOutput = []
    end
    methods
        function obj=Slicer(name), if nargin<1,name='slicer';end, obj@Blk(name); end
        function configure(obj,c)
            configure@Blk(obj,c); obj.modulation=c.modulation; obj.sps=c.sps; obj.samplerRolesEnabled=false;
            obj.samplerRoleCounts=struct('data',0,'edge',0,'spare',0); obj.levelShiftCodes=struct('data',[],'edge',[],'spare',[]);
            obj.comparatorThresholds=[]; obj.quarterRateBranches=4;
            if isfield(c,'samplerRoles')
                r=c.samplerRoles; if isfield(r,'enabled'), obj.samplerRolesEnabled=logical(r.enabled); end
                if isfield(r,'quarterRateBranches'), obj.quarterRateBranches=r.quarterRateBranches; end
                if isfield(r,'roleCounts'), obj.samplerRoleCounts=r.roleCounts; end
                if isfield(r,'levelShiftCodes'), obj.levelShiftCodes=r.levelShiftCodes; end
                if isfield(r,'thresholdAssumptions'), obj.comparatorThresholds=r.thresholdAssumptions; end
            end
            if isfield(c,'phase'), obj.phase=c.phase; else, obj.phase=floor(c.sps/2); end
            if isfield(c,'delayUI'), obj.delayUI=c.delayUI; end
            if isfield(c,'jitterUI'), obj.jitterUI=c.jitterUI; end
        end
        function bits=run(obj,x)
            x=x(:); [v,~,~]=dspSample(x,obj.phase,obj.delayUI,obj.sps,obj.jitterUI);
            bits=dspSlice(v,obj.modulation); obj.in=x; obj.samples=v; obj.rxBits=bits;
            obj.dataSamples=v; obj.dataDecisions=bits;
            if obj.samplerRolesEnabled
                obj.quarterRateSamples=cell(1,obj.quarterRateBranches);
                for k=1:obj.quarterRateBranches, obj.quarterRateSamples{k}=v(k:obj.quarterRateBranches:end); end
                obj.edgeSamples=[0;diff(v)]; obj.edgeDetectorOutput=double(obj.edgeSamples>=0);
                obj.spareSamples=v; obj.spareMonitorOutput=v-mean(v);
            else
                obj.quarterRateSamples={}; obj.edgeSamples=[]; obj.edgeDetectorOutput=[];
                obj.spareSamples=[]; obj.spareMonitorOutput=[];
            end
            obj.record('in',x); obj.record('samples',v); obj.record('out',bits);
            obj.log.dataSamples=obj.dataSamples; obj.log.dataDecisions=obj.dataDecisions;
            obj.log.edgeSamples=obj.edgeSamples; obj.log.edgeDetectorOutput=obj.edgeDetectorOutput;
            obj.log.spareSamples=obj.spareSamples; obj.log.spareMonitorOutput=obj.spareMonitorOutput;
        end
    end
end
