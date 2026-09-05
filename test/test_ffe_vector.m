function test_ffe_vector()
%TEST_FFE_VECTOR Signed arbitrary-offset FFE contract.
root=fileparts(fileparts(mfilename('fullpath'))); addpath(genpath(fullfile(root,'src')));
x=(1:7)';
[a,ma]=dspFfeVector(x,[-0.2 0.8 -0.1],[-1 0 1],struct('normalize',false));
assert(isequal(a,dspFfe(x,0.8,0.2,0.1,false)));
assert(isequal(ma.rawCoefficients,[-0.2 0.8 -0.1]) && isequal(ma.appliedOffsets,[-1 0 1]));
[b,mb]=dspFfeVector(x,[-2 8 -1],[-1 0 1],struct('normalize',true,'currentConstraint',1));
assert(isequal(b,dspFfe(x,8,2,1,true)) && abs(mb.appliedMagnitudeSum-1)<eps);

imp=zeros(7,1); imp(4)=1;
[h,mh]=dspFfeVector(imp,[1 2 3 4],[-2 0 1 3],struct('normalize',false));
expected=zeros(7,1); expected(2)=1; expected(4)=2; expected(5)=3; expected(7)=4;
assert(isequal(h,expected)); assert(numel(mh.impulseResponse)>0 && isequal(mh.pulseResponse,mh.impulseResponse));

[y,~]=dspFfeVector(x,[1 -2 0.5],[-3 0 2],struct('normalize',false));
want=[2;1;0.5;0;-8.5;-10;-11.5];
assert(isequal(y,want));

mustFail(@() dspFfeVector(x,[1 2],[0 0],struct()));
mustFail(@() dspFfeVector(x,[1 2],[-1 1],struct()));
mustFail(@() dspFfeVector(x,[1 2],[0 1],struct('normalize',true,'currentConstraint',0)));
mustFail(@() dspFfeVector(x,[1 2],[0 1],struct('normalize',false,'currentConstraint',1)));
disp('FFE vector tests OK');
end

function mustFail(f)
failed=false; try, f(); catch, failed=true; end
assert(failed);
end
