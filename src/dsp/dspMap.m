function [syms, bps] = dspMap(bits, modulation)
%DSPMAP Map bits to NRZ or databook PAM4 levels.
bits = bits(:);
if any(bits ~= 0 & bits ~= 1), error('dspMap:InvalidBits','Bits must be zero or one.'); end
switch upper(char(modulation))
    case 'PAM4'
        if mod(numel(bits),2), error('dspMap:OddBitCount','PAM4 requires an even bit count.'); end
        bps = 2; pairs = reshape(bits,2,[]);
        syms = (2*(2*pairs(1,:) + pairs(2,:)) - 3).';
    case 'NRZ'
        bps = 1; syms = 2*bits - 1;
    otherwise
        error('dspMap:Modulation','Unsupported modulation: %s',char(modulation));
end
end
