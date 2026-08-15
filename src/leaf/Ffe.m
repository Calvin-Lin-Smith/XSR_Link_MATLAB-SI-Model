classdef Ffe < Blk
    properties
        main = 1
        pre = 0
        post = 0
        normalize = true
        out = []
    end
    methods
        function obj=Ffe(name), if nargin<1,name='ffe';end, obj@Blk(name); end
        function configure(obj,c)
            configure@Blk(obj,c); obj.main=c.main; obj.pre=c.pre; obj.post=c.post;
            if isfield(c,'normalize'), obj.normalize=c.normalize; end
        end
        function y=run(obj,x)
            y=dspFfe(x,obj.main,obj.pre,obj.post,obj.normalize); obj.out=y;
            obj.record('in',x(:)); obj.record('out',y);
        end
    end
end
