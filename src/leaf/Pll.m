classdef Pll < Blk
    properties
        mode = 'forwarded'
        rjRms = 0
        djPp = 0
        djFreq = 1e-3
        bandwidth = 0.01
        seed = 42
        residualUI = []
        recoveredUI = []
    end
    methods
        function obj=Pll(name), if nargin<1,name='pll';end, obj@Blk(name); end
        function configure(obj,c)
            configure@Blk(obj,c);
            f={'mode','rjRms','djPp','djFreq','bandwidth','seed'};
            for k=1:numel(f), if isfield(c,f{k}), obj.(f{k})=c.(f{k}); end, end
        end
        function residual=run(obj,nSym)
            old=rng; rng(obj.seed,'twister'); n=(0:nSym-1)';
            input=obj.rjRms*randn(nSym,1)+(obj.djPp/2)*sin(2*pi*obj.djFreq*n);
            if strcmpi(obj.mode,'cdr')
                alpha=min(max(2*pi*obj.bandwidth,1e-6),0.95);
                recovered=filter(alpha,[1 -(1-alpha)],input);
                residual=input-recovered + 0.08*sqrt(obj.bandwidth)*randn(nSym,1);
            else
                recovered=zeros(nSym,1); residual=input;
            end
            rng(old); obj.residualUI=residual; obj.recoveredUI=recovered;
            obj.record('in',input); obj.record('recovered',recovered); obj.record('out',residual);
        end
    end
end
