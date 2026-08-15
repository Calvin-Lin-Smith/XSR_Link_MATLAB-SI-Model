function measuredDb = verifyChannel(sps, lossDb, poles)
%VERIFYCHANNEL Measure channel loss at Nyquist using a sinusoid.
n=2^15; t=(0:n-1)'/sps; x=sin(2*pi*0.5*t);
y=dspChannel(x,sps,lossDb,poles); keep=floor(n/2):n;
measuredDb=-20*log10(rms(y(keep))/rms(x(keep)));
fprintf('Target %.3f dB, measured %.3f dB at Nyquist\n',lossDb,measuredDb);
end
