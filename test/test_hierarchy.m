function test_hierarchy()
root=fileparts(fileparts(mfilename('fullpath'))); addpath(genpath(fullfile(root,'src')));
cfg=phyConfig('ideal'); phy=D2DPHY(); phy.configure(cfg); res=phy.run();
assert(all(res.errCnt==0)); assert(res.aggregateBer==0); assert(all(res.nMeasured>0));
assert(numel(phy.txPma.lane(1).driver.txPad)>0);
assert(numel(phy.channel(1).out)>0);
assert(numel(phy.rxPma.lane(1).afe.ctleOut)>0);
assert(numel(phy.rxPma.lane(1).slicer.in)>0);
assert(numel(phy.rxPma.lane(1).deserializer.rxBits)>0);
assert(isequal(phy.txPma.lane(1).driver.txPad,phy.channel(1).in));
assert(isequal(phy.channel(1).out,phy.rxPma.lane(1).afe.log.in));
phy.dump(); fprintf('Baseline BER = %.3e\n',res.aggregateBer); disp('Hierarchy tests OK');
end
