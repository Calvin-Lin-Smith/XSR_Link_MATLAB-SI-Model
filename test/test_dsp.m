function test_dsp()
root=fileparts(fileparts(mfilename('fullpath'))); addpath(genpath(fullfile(root,'src')));
x=sin((0:1000)'/32); y=dspChannel(x,32,0,3); assert(isequal(x,y));
s=dspMap([0 0 0 1 1 1 1 0]','PAM4'); assert(isequal(s,[-3;-1;1;3]));
v=[-3;-1;1;3]; assert(isequal(dspFfe(v,1,0,0,true),v));
b=dspPrbs([7 6],127); assert(numel(b)==127 && all(b==0|b==1));
assert(isequal(dspSlice(s,'PAM4'),[0;0;0;1;1;1;1;0]));
loss=verifyChannel(32,8,3); assert(abs(loss-8)<0.15);
disp('DSP tests OK');
end
