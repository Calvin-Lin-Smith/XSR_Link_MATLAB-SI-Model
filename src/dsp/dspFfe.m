function y = dspFfe(syms, main, pre, post, doNormalize)
%DSPFFE Apply one pre-cursor and one post-cursor at symbol rate.
x = syms(:);
validateattributes([main pre post], {'numeric'}, {'real','finite','nonnegative'});
if nargin < 5, doNormalize = true; end
den = main + pre + post;
if doNormalize
    if den <= 0, error('dspFfe:ZeroTaps','Tap magnitude sum must be positive.'); end
    main = main/den; pre = pre/den; post = post/den;
end
y = main*x - pre*[x(2:end);0] - post*[0;x(1:end-1)];
end
