function y=dspAcCouple(x,sps,cornerUI,varargin)
%DSPACCOUPLE Causal first-order high-pass AC coupling in cycles/UI.
wasRow=isrow(x); x=x(:);
validateattributes(sps,{'numeric'},{'scalar','integer','positive'});
if nargin==3 && isstruct(cornerUI)
    options=cornerUI; cornerUI=getField(options,'cornerUI',[]);
else
    options=struct(); if ~isempty(varargin) && isstruct(varargin{1}), options=varargin{1};
    elseif ~isempty(varargin), options.initialState=varargin{1}; end
end
if isfield(options,'enabled') && ~logical(options.enabled)
    y=x; if wasRow, y=y.'; end; return;
end
validateattributes(cornerUI,{'numeric'},{'scalar','real','finite','positive'});
if cornerUI>=0.5, error('dspAcCouple:Nyquist','Corner must be below Nyquist.'); end
policy=getField(options,'initialState','steady_state'); policy=lower(char(policy));
if ~any(strcmp(policy,{'steady_state','zero'})), error('dspAcCouple:InitialState','Unsupported initial-state policy: %s',policy); end
a=exp(-2*pi*cornerUI/sps); state=0; if strcmp(policy,'steady_state') && ~isempty(x), state=x(1); end
y=zeros(size(x));
for k=1:numel(x)
    state=a*state+(1-a)*x(k); y(k)=x(k)-state;
end
if wasRow, y=y.'; end
end

function value=getField(s,name,default)
if isfield(s,name), value=s.(name); else, value=default; end
end
