function [samples, idx, residualUI] = dspSample(x, ph, delayUI, sps, jitterUI)
%DSPSAMPLE Sample once per UI with optional per-symbol timing offsets.
x = x(:); nSym = floor((numel(x)-ph-1)/sps)+1;
if nSym <= 0, samples=[]; idx=[]; residualUI=[]; return; end
if nargin < 5 || isempty(jitterUI), jitterUI = zeros(nSym,1); end
jitterUI = jitterUI(:);
if isscalar(jitterUI), jitterUI = repmat(jitterUI,nSym,1); end
nSym = min(nSym,numel(jitterUI)); residualUI = jitterUI(1:nSym);
idx = (0:nSym-1)'*sps + ph + 1 + delayUI*sps + round(sps*residualUI);
valid = idx>=1 & idx<=numel(x); idx=idx(valid); residualUI=residualUI(valid);
samples = x(idx);
end
