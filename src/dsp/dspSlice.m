function [bits, syms] = dspSlice(y, modulation)
%DSPSLICE Slice NRZ or Gray-coded PAM4 samples and decode to bits.
y = y(:);
switch upper(char(modulation))
    case 'PAM4'
        c=dspPam4Contract(); idx=1+sum(y>=c.thresholds,2); syms=c.levels(idx).';
        bits=reshape(c.bitPairs(idx,:).',[],1);
    case 'NRZ'
        bits = double(y>=0); syms = 2*bits-1;
    otherwise
        error('dspSlice:Modulation','Unsupported modulation: %s',char(modulation));
end
end
