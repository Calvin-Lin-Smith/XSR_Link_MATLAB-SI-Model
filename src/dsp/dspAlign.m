function [ber, delayUI, phase, nErr, nBits] = dspAlign(x, txBits, modulation, sps, skipUI)
%DSPALIGN Exhaustively align a waveform to known transmitted bits.
x=x(:); txBits=txBits(:); bps=1+strcmpi(modulation,'PAM4'); best=[inf 0 0 0]; bestScore=inf;
for d=-12:12
    for ph=0:sps-1
        [v,~,~]=dspSample(x,ph,d,sps,0); rb=dspSlice(v,modulation);
        nb=min(numel(rb),numel(txBits)); first=skipUI*bps+1;
        if nb<first, continue; end
        ne=sum(rb(first:nb)~=txBits(first:nb)); measured=nb-first+1;
        score=ne+(numel(txBits)-first+1-measured);
        better = score<bestScore || (score==bestScore && abs(d)<abs(best(2))) || ...
            (score==bestScore && abs(d)==abs(best(2)) && abs(ph-floor(sps/2))<abs(best(3)-floor(sps/2)));
        if better, best=[ne d ph measured]; bestScore=score; end
    end
end
if isinf(best(1)), error('dspAlign:NoOverlap','No valid alignment found.'); end
nErr=best(1); delayUI=best(2); phase=best(3); nBits=best(4); ber=nErr/nBits;
end
