function test_pam4_slicer_contract_thresholds()
%TEST_PAM4_SLICER_CONTRACT_THRESHOLDS Sampler thresholds cannot override PAM4 contract.
root=fileparts(fileparts(mfilename('fullpath'))); addpath(genpath(fullfile(root,'src')));
c=dspPam4Contract(); x=repelem(c.levels(:),4);
s=Slicer('contract_thresholds'); rejected=false;
try, s.configure(struct('modulation','PAM4','sps',4,'phase',2,...
    'samplerRoles',struct('enabled',true,'levelShiftCodes',struct('data',[2 0 -2],'edge',0,'spare',c.levels),...
    'thresholdAssumptions',[-0.4 0 0.4])));
catch, rejected=true;
end
assert(rejected || isequal(s.comparatorThresholds,c.thresholds));
if ~rejected, assert(isequal(s.run(x),dspSlice(x(2:4:end),'PAM4'))); end
disp('PAM4 Slicer contract threshold tests OK');
end
