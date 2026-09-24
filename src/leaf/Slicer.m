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
        levelShiftedSamples = []
        dataDecisionInput = []
        edgeLevelShiftedSamples = []
        spareLevelShiftedSamples = []
        quarterRateSamples = {}
        dataSamples = []
        dataDecisions = []
        edgeSamples = []
        edgeDetectorOutput = []
        spareSamples = []
        spareMonitorOutput = []
        samplerOffsetCodes = 0
    end
    methods
        function obj=Slicer(name), if nargin<1,name='slicer';end, obj@Blk(name); end
        function configure(obj,c)
            configure@Blk(obj,c); obj.modulation=c.modulation; obj.sps=c.sps; obj.samplerRolesEnabled=false;
            obj.samplerRoleCounts=struct('data',0,'edge',0,'spare',0); obj.levelShiftCodes=struct('data',[],'edge',[],'spare',[]);
            obj.comparatorThresholds=[]; obj.quarterRateBranches=4;
            if strcmpi(char(c.modulation),'PAM4'), obj.comparatorThresholds=dspPam4Contract().thresholds; end
            obj.samplerOffsetCodes=0;
            if isfield(c,'samplerRoles')
                r=c.samplerRoles; if isfield(r,'enabled'), obj.samplerRolesEnabled=logical(r.enabled); end
                if isfield(r,'quarterRateBranches'), obj.quarterRateBranches=r.quarterRateBranches; end
                if isfield(r,'roleCounts'), obj.samplerRoleCounts=r.roleCounts; end
                if isfield(r,'levelShiftCodes'), obj.levelShiftCodes=r.levelShiftCodes; end
                if isfield(r,'thresholdAssumptions'), obj.comparatorThresholds=r.thresholdAssumptions; end
                if isfield(r,'samplerOffsetCodes'), obj.samplerOffsetCodes=r.samplerOffsetCodes; end
            end
            if isfield(c,'phase'), obj.phase=c.phase; else, obj.phase=floor(c.sps/2); end
            if isfield(c,'delayUI'), obj.delayUI=c.delayUI; end
            if isfield(c,'jitterUI'), obj.jitterUI=c.jitterUI; end
            validateattributes(obj.samplerOffsetCodes,{'numeric'},{'scalar','real','finite'});
        end
        function bits=run(obj,x)
            x=x(:); [v,~,~]=dspSample(x,obj.phase,obj.delayUI,obj.sps,obj.jitterUI);
            if obj.samplerRolesEnabled
                dataCodes=obj.levelShiftCodes.data(:).'; if isempty(dataCodes), dataCodes=0; end
                obj.levelShiftedSamples=v+dataCodes+obj.samplerOffsetCodes;
                center=find(dataCodes==0,1); if isempty(center), center=ceil(numel(dataCodes)/2); end
                obj.dataDecisionInput=obj.levelShiftedSamples(:,center);
                bits=sliceWithThresholds(obj.dataDecisionInput,obj.modulation,obj.comparatorThresholds);
            else
                obj.levelShiftedSamples=[]; obj.dataDecisionInput=v; bits=dspSlice(v,obj.modulation);
            end
            obj.in=x; obj.samples=v; obj.rxBits=bits; obj.dataSamples=v; obj.dataDecisions=bits;
            if obj.samplerRolesEnabled
                obj.quarterRateSamples=cell(1,obj.quarterRateBranches);
                for k=1:obj.quarterRateBranches, obj.quarterRateSamples{k}=v(k:obj.quarterRateBranches:end); end
                obj.edgeSamples=[0;diff(v)]; edgeCode=obj.levelShiftCodes.edge;
                obj.edgeLevelShiftedSamples=obj.edgeSamples+edgeCode;
                obj.edgeDetectorOutput=double(obj.edgeLevelShiftedSamples>=0);
                obj.spareSamples=v; spareCodes=obj.levelShiftCodes.spare(:).'; if isempty(spareCodes), spareCodes=0; end
                obj.spareLevelShiftedSamples=v+spareCodes+obj.samplerOffsetCodes;
                obj.spareMonitorOutput=mean(obj.spareLevelShiftedSamples,2)-mean(obj.comparatorThresholds);
            else
                obj.quarterRateSamples={}; obj.edgeSamples=[]; obj.edgeDetectorOutput=[]; obj.spareSamples=[]; obj.spareMonitorOutput=[];
                obj.edgeLevelShiftedSamples=[]; obj.spareLevelShiftedSamples=[];
            end
            obj.record('in',x); obj.record('samples',v); obj.record('out',bits);
            obj.log.dataSamples=obj.dataSamples; obj.log.dataDecisions=obj.dataDecisions;
            obj.log.edgeSamples=obj.edgeSamples; obj.log.edgeDetectorOutput=obj.edgeDetectorOutput;
            obj.log.spareSamples=obj.spareSamples; obj.log.spareMonitorOutput=obj.spareMonitorOutput;
            obj.log.levelShiftedSamples=obj.levelShiftedSamples; obj.log.dataDecisionInput=obj.dataDecisionInput;
            obj.log.edgeLevelShiftedSamples=obj.edgeLevelShiftedSamples; obj.log.spareLevelShiftedSamples=obj.spareLevelShiftedSamples;
        end
    end
end

function bits=sliceWithThresholds(y,modulation,thresholds)
if isempty(thresholds), bits=dspSlice(y,modulation); return; end
switch upper(char(modulation))
    case 'PAM4'
        if numel(thresholds)~=3, error('Slicer:Thresholds','PAM4 requires three comparator thresholds.'); end
        c=dspPam4Contract(); idx=1+sum(y(:)>=thresholds(:).',2); bits=reshape(c.bitPairs(idx,:).',[],1);
    case 'NRZ'
        bits=double(y>=thresholds(1));
    otherwise
        error('Slicer:Modulation','Unsupported modulation: %s',char(modulation));
end
end
