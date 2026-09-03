function test_tx_driver_quantization()
%TEST_TX_DRIVER_QUANTIZATION Driver compatibility and deterministic DAC path.
root=fileparts(fileparts(mfilename('fullpath'))); addpath(genpath(fullfile(root,'src')));
x=linspace(-1,1,1001)'; d=Driver('legacy'); d.configure(struct('amplitude',0.7));
assert(isequal(d.run(x),0.7*x));

c=struct('amplitude',1,'enableDacQuantization',true,'dacLevels',206,'targetSwing',1,...
    'gainError',0,'enableSwingCalibration',true);
d.configure(c); y=d.run(x); y2=d.run(x);
assert(isequal(y,y2) && numel(unique(y))<=206 && max(abs(y))<=1+eps);
assert(isfield(d.log,'quantization') && isfield(d.log.quantization,'appliedLevels'));

bad=c; bad.dacLevels=1; mustFail(@() d.configure(bad));
bad=c; bad.targetSwing=0; mustFail(@() d.configure(bad));
bad=c; bad.gainError=inf; mustFail(@() d.configure(bad));
disp('Driver quantization tests OK');
end

function mustFail(f)
failed=false; try, f(); catch, failed=true; end
assert(failed);
end
