function y = dspCtle(x, sps, boostDb, fz)
%DSPCTLE First-order CTLE with unity high-frequency gain.
x = x(:);
validateattributes(boostDb, {'numeric'}, {'scalar','real','finite','nonnegative'});
if boostDb == 0, y = x; return; end
validateattributes(fz, {'numeric'}, {'scalar','real','finite','positive'});
wz = 2*pi*fz; wp = wz*10^(boostDb/20);
[num,den] = bilinear([1 wz],[1 wp],sps);
y = filter(num,den,x);
end
