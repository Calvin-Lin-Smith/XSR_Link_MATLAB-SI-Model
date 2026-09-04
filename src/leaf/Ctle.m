classdef Ctle < Blk
    properties
        sps = 16
        boostDb = 0
        appliedBoost_dB = 0
        policy = 'continuous'
        boostGrid_dB = 0:0.2:6
        fz = 0.25
        ctleOut = []
    end
    methods
        function obj=Ctle(name), if nargin<1,name='ctle';end, obj@Blk(name); end
        function configure(obj,c)
            configure@Blk(obj,c); obj.sps=c.sps; obj.fz=c.fz; obj.policy='continuous'; obj.boostGrid_dB=0:0.2:6;
            obj.boostDb=c.boostDb; obj.appliedBoost_dB=obj.boostDb;
            if isfield(c,'policy'), obj.policy=lower(char(c.policy)); end
            if any(strcmp(obj.policy,{'paper_grid','quantized_grid'}))
                if obj.boostDb<0 || obj.boostDb>6, error('Ctle:Policy','Paper CTLE boost must be within 0 to 6 dB.'); end
                obj.appliedBoost_dB=round(obj.boostDb/0.2)*0.2; obj.boostGrid_dB=0:0.2:6;
            elseif ~strcmp(obj.policy,'continuous')
                error('Ctle:Policy','Unsupported CTLE policy: %s',obj.policy);
            end
            validateattributes(obj.appliedBoost_dB,{'numeric'},{'scalar','real','finite','nonnegative'});
            obj.boostDb=obj.appliedBoost_dB;
        end
        function y=run(obj,x)
            x=x(:); y=dspCtle(x,obj.sps,obj.appliedBoost_dB,obj.fz); obj.ctleOut=y;
            obj.log.appliedBoost_dB=obj.appliedBoost_dB; obj.log.policy=obj.policy;
            obj.record('in',x); obj.record('out',y);
        end
    end
end
