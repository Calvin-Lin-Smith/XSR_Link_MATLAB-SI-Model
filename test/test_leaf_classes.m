function test_leaf_classes()
root=fileparts(fileparts(mfilename('fullpath'))); addpath(genpath(fullfile(root,'src')));
x=randn(128,1); syms=[-3;-1;1;3;-1;1];
blocks={};
s=Serializer('ser'); s.configure(struct('sps',8)); s.run(syms); blocks{end+1}=s;
f=Ffe('ffe'); f.configure(struct('main',1,'pre',0.1,'post',0.1,'normalize',true)); f.run(syms); blocks{end+1}=f;
d=Driver('drv'); d.configure(struct('amplitude',0.8)); d.run(x); blocks{end+1}=d;
t=Term('term'); t.configure(struct('gain',0.95)); t.run(x); blocks{end+1}=t;
c=Ctle('ctle'); c.configure(struct('sps',8,'boostDb',4,'fz',0.25)); c.run(x); blocks{end+1}=c;
sl=Slicer('slicer'); sl.configure(struct('modulation','PAM4','sps',8,'phase',4,'jitterUI',0)); sl.run(repelem(syms,8)); blocks{end+1}=sl;
de=Deserializer('des'); de.run([1;0;1]); blocks{end+1}=de;
ch=Channel('ch'); ch.configure(struct('sps',8,'lossNyq_dB',4,'poles',3)); ch.run(x); blocks{end+1}=ch;
p=Pll('pll'); p.configure(struct('mode','cdr','rjRms',0.02,'djPp',0.1,'djFreq',1e-3,'bandwidth',0.01,'seed',1)); p.run(128); blocks{end+1}=p;
for k=1:numel(blocks)
    b=blocks{k}; assert(isfield(b.log,'in') && isfield(b.log,'out')); assert(~isempty(b.log.in)); assert(~isempty(b.log.out)); b.dump();
end
assert(numel(s.out)==numel(syms)*8); assert(numel(ch.out)==numel(x)); assert(isfield(p.log,'recovered'));
disp('Leaf class tests OK');
end
