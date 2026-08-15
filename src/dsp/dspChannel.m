function y = dspChannel(x, sps, lossDb, poles)
%DSPCHANNEL Cascaded one-pole channel with lossDb at 0.5 cycles/UI.
x = x(:);
validateattributes(sps, {'numeric'}, {'scalar','integer','positive'});
validateattributes(lossDb, {'numeric'}, {'scalar','real','finite','nonnegative'});
validateattributes(poles, {'numeric'}, {'scalar','integer','positive'});
if lossDb == 0, y = x; return; end
linPower = 10^(lossDb/10);
fp = 0.5/sqrt(linPower^(1/poles)-1);
a = exp(-2*pi*fp/sps); y = x;
for k = 1:poles, y = filter(1-a,[1 -a],y); end
end
