function test_ac_coupling()
%TEST_AC_COUPLING AC coupling primitive contract.
root=fileparts(fileparts(mfilename('fullpath'))); addpath(genpath(fullfile(root,'src')));
x=ones(4096,1); ys=dspAcCouple(x,16,0.01,'steady_state'); yz=dspAcCouple(x,16,0.01,'zero');
assert(abs(mean(ys(end/2:end)))<1e-6 && abs(ys(1))<1e-6);
assert(abs(yz(1))>1e-3 && abs(mean(yz(end/2:end)))<1e-3);
off=dspAcCouple(x,16,0.01,struct('enabled',false,'initialState','zero'));
assert(isequal(off,x));
assert(isequal(size(dspAcCouple(x,16,0.01,'zero')),size(x)));
mustFail(@() dspAcCouple(x,16,0.5,'zero'));
mustFail(@() dspAcCouple(x,16,-0.01,'zero'));
mustFail(@() dspAcCouple(x,16,0.5,struct('enabled',false,'initialState','zero')));
disp('AC coupling tests OK');
end

function mustFail(f)
failed=false; try, f(); catch, failed=true; end
assert(failed);
end
