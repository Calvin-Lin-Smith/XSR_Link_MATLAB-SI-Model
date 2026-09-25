function test_checker_ui_alignment()
%TEST_CHECKER_UI_ALIGNMENT Paper checker searches only integer PAM4 UI lags.
root=fileparts(fileparts(mfilename('fullpath'))); addpath(genpath(fullfile(root,'src')));
cfg=phyConfig('vlsi2024_xsr_ideal'); cfg.link.nBits=4096; raw=RawPcs('checker',1); raw.configure(cfg.rawPcs,cfg.link); raw.run();
ref=raw.referenceBits(:,1); rx=[zeros(2,1);ref(1:end-2)];
opt=struct('paper',true,'maxLagUI',2,'syncBits',256,'measurementStartBits',512);
[err,n,ber,meta]=raw.check(rx,0,opt);
assert(meta.checkerLagUI==1 && meta.alignmentValid && err==0 && n>0 && ber==0);
odd=[0;ref(1:end-1)]; [~,~,~,oddMeta]=raw.check(odd,0,opt);
assert(~oddMeta.alignmentValid && ~oddMeta.framingValid);
disp('Checker integer UI alignment tests OK');
end
