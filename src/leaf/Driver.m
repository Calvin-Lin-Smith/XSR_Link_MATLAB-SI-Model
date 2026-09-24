classdef Driver < Blk
    properties
        amplitude = 1
        enableDacQuantization = false
        dacLevels = 206
        targetSwing = 1
        logicalOuterLevel = 1
        gainError = 0
        enableSwingCalibration = true
        dacMeta = struct()
        txPad = []
    end
    methods
        function obj=Driver(name), if nargin<1,name='driver';end, obj@Blk(name); end
        function configure(obj,c)
            configure@Blk(obj,c); obj.amplitude=c.amplitude;
            obj.enableDacQuantization=false; obj.dacLevels=206; obj.targetSwing=1; obj.logicalOuterLevel=1;
            obj.gainError=0; obj.enableSwingCalibration=true; obj.dacMeta=struct();
            if isfield(c,'enableDacQuantization'), obj.enableDacQuantization=logical(c.enableDacQuantization); end
            if isfield(c,'dacLevels'), obj.dacLevels=c.dacLevels; end
            if isfield(c,'targetSwing'), obj.targetSwing=c.targetSwing; end
            if isfield(c,'logicalOuterLevel'), obj.logicalOuterLevel=c.logicalOuterLevel; end
            if isfield(c,'gainError'), obj.gainError=c.gainError; end
            if isfield(c,'enableSwingCalibration'), obj.enableSwingCalibration=logical(c.enableSwingCalibration); end
            if ~isscalar(obj.enableDacQuantization), error('Driver:Quantization','enableDacQuantization must be scalar.'); end
            validateattributes(obj.dacLevels,{'numeric'},{'scalar','real','finite','integer','>=',2});
            validateattributes(obj.targetSwing,{'numeric'},{'scalar','real','finite','positive'});
            validateattributes(obj.logicalOuterLevel,{'numeric'},{'scalar','real','finite','positive'});
            validateattributes(obj.gainError,{'numeric'},{'scalar','real','finite'});
            if ~isscalar(obj.enableSwingCalibration), error('Driver:Quantization','enableSwingCalibration must be scalar.'); end
        end
        function y=run(obj,x)
            x=x(:); y=obj.amplitude*x;
            if obj.enableDacQuantization
                y=y*(1+obj.gainError);
                logicalOuterLevel=obj.logicalOuterLevel; peakBeforeClip=max(abs(y)); clippedSamples=sum(abs(y)>logicalOuterLevel);
                if obj.enableSwingCalibration
                    peak=peakBeforeClip; if peak>0, y=y*(logicalOuterLevel/peak); end
                end
                y=max(min(y,logicalOuterLevel),-logicalOuterLevel);
                step=2*logicalOuterLevel/(obj.dacLevels-1);
                y=round((y+logicalOuterLevel)/step)*step-logicalOuterLevel;
                obj.dacMeta=struct('enabled',true,'appliedLevels',obj.dacLevels,...
                    'targetSwing',obj.targetSwing,'gainError',obj.gainError,...
                    'swingCalibrated',obj.enableSwingCalibration,'step',step,...
                    'peakBeforeClip',peakBeforeClip,'clippedSamples',clippedSamples,...
                    'logicalOuterLevel',logicalOuterLevel,'logicalStep',step,...
                    'physicalTargetSwing',obj.targetSwing,'gainResidual',max(abs(y))/logicalOuterLevel-1,...
                    'unit','logical_amplitude');
                obj.log.quantization=obj.dacMeta;
            else
                obj.dacMeta=struct('enabled',false,'appliedLevels',0,'logicalOuterLevel',obj.logicalOuterLevel,...
                    'logicalStep',NaN,'physicalTargetSwing',obj.targetSwing,'gainResidual',0,'unit','logical_amplitude');
                obj.log.quantization=obj.dacMeta;
            end
            obj.txPad=y; obj.record('in',x); obj.record('out',y);
        end
    end
end
