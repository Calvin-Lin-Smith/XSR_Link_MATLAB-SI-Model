function test_vlsi2024_pam4_contract()
%TEST_VLSI2024_PAM4_CONTRACT Gray PAM4 mapping and paper TX logical units.
root=fileparts(fileparts(mfilename('fullpath'))); addpath(genpath(fullfile(root,'src')));
c=dspPam4Contract();
bits=[0 0 0 1 1 1 1 0]';
assert(isequal(dspMap(bits,'PAM4'),c.levels'));
assert(isequal(dspSlice(c.levels','PAM4'),bits));
assert(all(sum(xor(c.bitPairs(1:3,:),c.bitPairs(2:4,:)),2)==1));
cfg=phyConfig('vlsi2024_xsr_typical');
d=Driver('d'); d.configure(cfg.txPma.lane);
y=d.run(c.levels');
assert(max(abs(y))>2.9 && max(abs(y))<=3+eps);
assert(d.dacMeta.logicalOuterLevel==3 && d.dacMeta.physicalTargetSwing==cfg.txPma.lane.targetSwing);
cfg.txPma.lane.targetSwing=0.2; d.configure(cfg.txPma.lane); y=d.run(c.levels');
assert(max(abs(y))>2.9 && max(abs(y))<=3+eps);
disp('VLSI2024 PAM4 contract tests OK');
end
