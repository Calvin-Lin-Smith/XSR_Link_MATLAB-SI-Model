function y = dspChannel(x, sps, lossDb, poles, varargin)
%DSPCHANNEL Legacy Nyquist or calibrated analytic insertion-loss channel.
x = x(:);
validateattributes(sps, {'numeric'}, {'scalar','integer','positive'});
if (nargin == 3 && isstruct(lossDb)) || (nargin >= 5 && isstruct(varargin{1}))
    if nargin == 3, options=lossDb; else, options=varargin{1}; end
    if nargin >= 5
        if ~isfield(options,'lossAtRef_dB'), options.lossAtRef_dB=lossDb; end
        if ~isfield(options,'poles'), options.poles=poles; end
    end
    mode=getField(options,'mode','analytic_il');
    if ~strcmpi(char(mode),'analytic_il'), error('dspChannel:Mode','Unsupported channel mode: %s',char(mode)); end
    refFreq=getField(options,'refFreq_GHz',[]); baud=getField(options,'baud_GBd',[]);
    lossDb=getField(options,'lossAtRef_dB',[]); poles=getField(options,'poles',3);
    validateattributes(refFreq,{'numeric'},{'scalar','real','finite','positive'});
    validateattributes(baud,{'numeric'},{'scalar','real','finite','positive'});
    validateattributes(lossDb, {'numeric'}, {'scalar','real','finite','nonnegative'});
    validateattributes(poles, {'numeric'}, {'scalar','integer','positive'});
    fUI=refFreq/baud;
    if fUI<=0 || fUI>=0.5, error('dspChannel:Nyquist','Reference frequency must be below Nyquist.'); end
    if lossDb==0, y=x; return; end
    g=10^(-lossDb/(20*poles)); c=cos(2*pi*fUI/sps);
    A=1-g^2; B=2*(g^2*c-1); disc=max(B^2-4*A^2,0);
    roots=[(-B-sqrt(disc))/(2*A),(-B+sqrt(disc))/(2*A)];
    a=roots(find(roots>0 & roots<1,1,'first'));
    if isempty(a), error('dspChannel:Calibration','Unable to calibrate analytic channel pole.'); end
    y=x; for k=1:poles, y=filter(1-a,[1 -a],y); end
    return;
end
if nargin < 4, error('dspChannel:Arguments','Legacy mode requires lossDb and poles.'); end
validateattributes(lossDb, {'numeric'}, {'scalar','real','finite','nonnegative'});
validateattributes(poles, {'numeric'}, {'scalar','integer','positive'});
if lossDb == 0, y = x; return; end
linPower = 10^(lossDb/10);
fp = 0.5/sqrt(linPower^(1/poles)-1);
a = exp(-2*pi*fp/sps); y = x;
for k = 1:poles, y = filter(1-a,[1 -a],y); end
end

function value=getField(s,name,default)
if isfield(s,name), value=s.(name); else, value=default; end
end
