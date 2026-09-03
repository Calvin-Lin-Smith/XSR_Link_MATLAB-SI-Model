function [y,meta] = dspFfeVector(symbols,tapCoeffs,tapOffsets,options)
%DSPFFEVECTOR Apply signed taps at arbitrary integer UI offsets.
if nargin<4 || isempty(options), options=struct(); end
validateattributes(symbols,{'numeric'},{'vector','real','finite'}); x=symbols(:);
validateattributes(tapCoeffs,{'numeric'},{'vector','real','finite'});
validateattributes(tapOffsets,{'numeric'},{'vector','real','finite'});
tapCoeffs=tapCoeffs(:).'; tapOffsets=tapOffsets(:).';
if numel(tapCoeffs)~=numel(tapOffsets), error('dspFfeVector:Length','Coefficients and offsets must have equal lengths.'); end
if any(tapOffsets~=fix(tapOffsets)) || numel(unique(tapOffsets))~=numel(tapOffsets)
    error('dspFfeVector:Offsets','Offsets must be unique integers.');
end
if sum(tapOffsets==0)~=1, error('dspFfeVector:Main','Exactly one main cursor at offset zero is required.'); end
normalize=true; if isfield(options,'normalize'), normalize=logical(options.normalize); end
hasConstraint=isfield(options,'currentConstraint');
if hasConstraint, currentConstraint=options.currentConstraint;
elseif normalize, currentConstraint=1;
else, currentConstraint=NaN;
end
if (hasConstraint || normalize) && (~isscalar(currentConstraint) || ~isreal(currentConstraint) || ~isfinite(currentConstraint) || currentConstraint<=0)
    error('dspFfeVector:Constraint','currentConstraint must be a positive finite scalar.');
end
raw=tapCoeffs; rawSum=sum(abs(raw));
if rawSum<=0, error('dspFfeVector:ZeroTaps','Tap magnitude sum must be positive.'); end
if normalize
    applied=raw*(currentConstraint/rawSum);
elseif hasConstraint && rawSum>currentConstraint
    error('dspFfeVector:Constraint','Unnormalized tap magnitude exceeds currentConstraint.');
else
    applied=raw;
end
y=applyTaps(x,applied,tapOffsets);
span=max(abs(tapOffsets)); impulse=zeros(2*span+1,1); impulse(span+1)=1;
meta=struct('rawCoefficients',raw,'appliedCoefficients',applied,'rawOffsets',tapOffsets,...
    'appliedOffsets',tapOffsets,'rawMagnitudeSum',rawSum,'appliedMagnitudeSum',sum(abs(applied)),...
    'currentConstraint',currentConstraint,'normalized',normalize,...
    'impulseResponse',applyTaps(impulse,applied,tapOffsets));
meta.pulseResponse=meta.impulseResponse;
end

function y=applyTaps(x,coeffs,offsets)
y=zeros(size(x)); n=numel(x); idx=(1:n)';
for k=1:numel(coeffs)
    source=idx-offsets(k); valid=source>=1 & source<=n;
    y(valid)=y(valid)+coeffs(k)*x(source(valid));
end
end
