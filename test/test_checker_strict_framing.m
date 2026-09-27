function test_checker_strict_framing()
%TEST_CHECKER_STRICT_FRAMING Any odd-bit optimum or tie is invalid.
root=fileparts(fileparts(mfilename('fullpath'))); addpath(genpath(fullfile(root,'src')));
cfg=phyConfig('vlsi2024_xsr_ideal'); cfg.link.nBits=64; raw=RawPcs('framing',1); raw.configure(cfg.rawPcs,cfg.link); raw.run();
opt=struct('paper',true,'maxLagUI',2,'syncBits',8,'measurementStartBits',32);
ref=raw.referenceBits(:,1); oddPreferred=[0;ref(1:end-1)]; [~,~,~,m]=raw.check(oddPreferred,0,opt); assert(m.oddBitErrors<m.syncErrors && ~m.framingValid && ~m.alignmentValid);
ambiguous=ones(64,1); [~,~,~,m]=raw.check(ambiguous,0,opt); assert(m.oddBitErrors<=m.syncErrors && ~m.framingValid && ~m.alignmentValid);
disp('Checker strict framing tests OK');
end
