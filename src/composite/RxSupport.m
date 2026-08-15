classdef RxSupport < Blk
    properties
        pll
    end
    methods
        function obj=RxSupport(name), if nargin<1,name='rx_support';end, obj@Blk(name); obj.pll=Pll([name '.pll']); end
        function configure(obj,c), configure@Blk(obj,c); obj.pll.configure(c); end
        function y=run(obj,n), y=obj.pll.run(n); obj.record('in',n); obj.record('out',y); end
        function dump(obj,indent), if nargin<2,indent='';end, dump@Blk(obj,indent); obj.pll.dump([indent '  ']); end
    end
end
