function test_ctle_quantized_steps()
%TEST_CTLE_QUANTIZED_STEPS Paper CTLE policy and legacy compatibility.
root=fileparts(fileparts(mfilename('fullpath'))); addpath(genpath(fullfile(root,'src')));
c=Ctle('paper_ctle'); c.configure(struct('sps',16,'boostDb',1.13,'fz',0.25,'policy','paper_grid'));
assert(abs(c.appliedBoost_dB-1.2)<1e-12 && abs(c.boostDb-1.2)<1e-12);
assert(isequal(c.boostGrid_dB,0:0.2:6));
c.run(randn(256,1)); assert(isfield(c.log,'appliedBoost_dB'));
mustFail(@() c.configure(struct('sps',16,'boostDb',6.1,'fz',0.25,'policy','paper_grid')));

c.configure(struct('sps',16,'boostDb',1.13,'fz',0.25));
assert(abs(c.appliedBoost_dB-1.13)<eps);
disp('CTLE quantized-step tests OK');
end

function mustFail(f)
failed=false; try, f(); catch, failed=true; end
assert(failed);
end
