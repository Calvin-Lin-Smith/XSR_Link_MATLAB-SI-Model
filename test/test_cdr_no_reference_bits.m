function test_cdr_no_reference_bits()
%TEST_CDR_NO_REFERENCE_BITS TX reference perturbation cannot change CDR traces.
root=fileparts(fileparts(mfilename('fullpath'))); addpath(genpath(fullfile(root,'src')));
cfg=phyConfig('vlsi2024_xsr'); lane=RxLane('no_ref_lane'); laneCfg=cfg.rxPma.lane;
laneCfg.sps=cfg.link.sps; laneCfg.modulation=cfg.link.modulation; laneCfg.useReferenceAlign=false;
bits=mod((0:1023)',2); x=repelem(2*bits-1,cfg.link.sps);
lane.configure(laneCfg); lane.run(x,zeros(numel(bits),1),zeros(numel(bits),1),cfg.link.skipUI);
t1=lane.cdrTrace;
lane.run(x,ones(numel(bits),1),zeros(numel(bits),1),cfg.link.skipUI); t2=lane.cdrTrace;
assert(isequal(t1.piCodeTrace,t2.piCodeTrace));
assert(isequal(t1.errorTrace,t2.errorTrace));
assert(isequal(t1.residualPhaseUI,t2.residualPhaseUI));
disp('CDR no-reference-bits test OK');
end
