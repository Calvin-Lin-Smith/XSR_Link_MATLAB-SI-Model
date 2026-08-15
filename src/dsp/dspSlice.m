function [bits, syms] = dspSlice(y, modulation)
%DSPSLICE Slice NRZ or PAM4 samples and decode to bits.
y = y(:);
switch upper(char(modulation))
    case 'PAM4'
        syms = -3*ones(size(y)); syms(y>=-2)=-1; syms(y>=0)=1; syms(y>=2)=3;
        idx = (syms+3)/2; lut = [0 0;0 1;1 0;1 1];
        pairs = lut(idx+1,:); bits = reshape(pairs.',[],1);
    case 'NRZ'
        bits = double(y>=0); syms = 2*bits-1;
    otherwise
        error('dspSlice:Modulation','Unsupported modulation: %s',char(modulation));
end
end
