classdef Ffe < Blk
    properties
        main = 1
        pre = 0
        post = 0
        normalize = true
        vectorMode = false
        tapOffsets = []
        tapCoeffs = []
        tapMeta = struct()
        out = []
    end
    methods
        function obj=Ffe(name), if nargin<1,name='ffe';end, obj@Blk(name); end
        function configure(obj,c)
            configure@Blk(obj,c); obj.vectorMode=false; obj.tapMeta=struct();
            if isfield(c,'mode') && any(strcmpi(char(c.mode),{'vector','three_tap','six_tap'}))
                obj.vectorMode=true; obj.tapOffsets=c.tapOffsets; obj.tapCoeffs=c.tapCoeffs;
                obj.normalize=true; if isfield(c,'normalize'), obj.normalize=c.normalize; end
            else
                obj.main=c.main; obj.pre=c.pre; obj.post=c.post;
                if isfield(c,'normalize'), obj.normalize=c.normalize; end
            end
        end
        function y=run(obj,x)
            if obj.vectorMode
                options=struct('normalize',obj.normalize);
                if isfield(obj.cfg,'currentConstraint'), options.currentConstraint=obj.cfg.currentConstraint; end
                [y,obj.tapMeta]=dspFfeVector(x,obj.tapCoeffs,obj.tapOffsets,options);
                obj.log.tapMeta=obj.tapMeta;
            else
                y=dspFfe(x,obj.main,obj.pre,obj.post,obj.normalize);
            end
            obj.out=y;
            obj.record('in',x(:)); obj.record('out',y);
        end
    end
end
