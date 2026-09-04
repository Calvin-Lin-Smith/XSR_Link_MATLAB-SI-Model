function [measuredDb,info] = verifyChannel(sps, lossDb, poles, varargin)
%VERIFYCHANNEL Measure legacy Nyquist or frequency-aware channel loss.
n=2^15; t=(0:n-1)'/sps; x=sin(2*pi*0.5*t);
if isempty(varargin)
    y=dspChannel(x,sps,lossDb,poles); refFreq=NaN; baud=NaN; mode='legacy_nyquist';
else
    if numel(varargin)==1 && isstruct(varargin{1})
        options=varargin{1};
    elseif numel(varargin)>=2
        options=struct('mode','analytic_il','refFreq_GHz',varargin{1},'baud_GBd',varargin{2},...
            'lossAtRef_dB',lossDb,'poles',poles);
    else
        error('verifyChannel:Arguments','Frequency-aware mode requires reference frequency and baud.');
    end
    if ~isfield(options,'mode'), options.mode='analytic_il'; end
    if ~isfield(options,'lossAtRef_dB'), options.lossAtRef_dB=lossDb; end
    if ~isfield(options,'poles'), options.poles=poles; end
    refFreq=options.refFreq_GHz; baud=options.baud_GBd; mode=char(options.mode);
    x=sin(2*pi*(refFreq/baud)*t); y=dspChannel(x,sps,options);
end
keep=floor(n/2):n;
measuredDb=-20*log10(rms(y(keep))/rms(x(keep)));
if isnan(refFreq), fprintf('Target %.3f dB, measured %.3f dB at Nyquist\n',lossDb,measuredDb);
else, fprintf('Target %.3f dB, measured %.3f dB at %.3f GHz\n',lossDb,measuredDb,refFreq); end
info=struct('mode',mode,'requestedLoss_dB',lossDb,'measuredLoss_dB',measuredDb,...
    'referenceFrequency_GHz',refFreq,'baud_GBd',baud);
end
