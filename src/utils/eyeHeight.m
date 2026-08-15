function height = eyeHeight(x, phase, sps, modulation)
%EYEHEIGHT Estimate minimum adjacent level separation at one phase.
s=x(phase+1:sps:end); nLvl=2+2*strcmpi(modulation,'PAM4');
if numel(s)<nLvl, height=NaN; return; end
[idx,c]=kmeans(s(:),nLvl,'Replicates',3); [c,order]=sort(c);
openings=zeros(nLvl-1,1);
for k=1:nLvl-1
    lo=s(idx==order(k)); hi=s(idx==order(k+1));
    openings(k)=prctile(hi,1)-prctile(lo,99);
end
height=min(openings);
end
