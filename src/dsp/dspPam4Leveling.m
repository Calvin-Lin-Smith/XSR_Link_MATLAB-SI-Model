function [logicalSamples,meta]=dspPam4Leveling(raw,varargin)
%DSPPAM4LEVELING Blindly normalize four received PAM4 clusters.
%   No transmitted bits are used; invalid/degenerate inputs retain their
%   samples and return levelsValid=false rather than inventing outer levels.
wasRow=isrow(raw); rawSamples=raw(:);
options=struct();
if ~isempty(varargin)
    if isstruct(varargin{1}), options=varargin{1}; else, options.minOccupancy=varargin{1}; end
end
minOccupancy=getField(options,'minOccupancy',0.02);
maxIterations=getField(options,'maxIterations',32);
validateattributes(minOccupancy,{'numeric'},{'scalar','real','finite','>=',0,'<',0.25});
validateattributes(maxIterations,{'numeric'},{'scalar','integer','positive'});
c=dspPam4Contract(); finiteMask=isfinite(rawSamples); values=rawSamples(finiteMask); n=numel(values);
rawCentroids=nan(1,4); occupancyCount=zeros(1,4); occupancy=zeros(1,4); assignments=zeros(n,1);
levelsValid=false; levelingOffset=NaN; levelingScale=NaN; logicalCentroids=nan(1,4);
if n>=4
    sorted=sort(values); seedIndex=max(1,min(n,round([0.125 0.375 0.625 0.875]*(n-1)+1)));
    centroids=sorted(seedIndex).';
    for iter=1:maxIterations
        [~,assignments]=min(abs(values-centroids),[],2);
        next=centroids;
        for k=1:4
            if any(assignments==k), next(k)=mean(values(assignments==k)); end
        end
        next=sort(next);
        if max(abs(next-centroids))<=eps(max(abs(centroids))+1), centroids=next; break; end
        centroids=next;
    end
    [~,assignments]=min(abs(values-centroids),[],2);
    for k=1:4
        occupancyCount(k)=sum(assignments==k); occupancy(k)=occupancyCount(k)/n;
        if occupancyCount(k)>0, rawCentroids(k)=mean(values(assignments==k)); end
    end
    separation=diff(rawCentroids); scaleFloor=eps(max(1,max(abs(rawCentroids))));
    levelsValid=all(isfinite(rawCentroids)) && all(separation>scaleFloor) && all(occupancy>=minOccupancy);
    if levelsValid
        target=c.levels; center=mean(rawCentroids);
        levelingScale=(target*(rawCentroids-center).')/sum((rawCentroids-center).^2);
        levelingOffset=center;
        levelsValid=isfinite(levelingScale) && levelingScale>0;
    end
end
logicalSamples=rawSamples;
if levelsValid
    logicalSamples=(rawSamples-levelingOffset)*levelingScale;
    logicalCentroids=(rawCentroids-levelingOffset)*levelingScale;
end
decisions=nan(size(logicalSamples));
if levelsValid
    decisionIndex=1+sum(logicalSamples>=c.thresholds,2); decisions=c.levels(decisionIndex).';
end
withinClusterSigma=nan(1,4);
if levelsValid
    for k=1:4
        cluster=logicalSamples(finiteMask); cluster=cluster(assignments==k);
        if numel(cluster)>1, withinClusterSigma(k)=std(cluster,0); else, withinClusterSigma(k)=0; end
    end
end
meta=struct('levelsValid',levelsValid,'rawSamples',rawSamples,'logicalSamples',logicalSamples,...
    'rawCentroids',rawCentroids,'logicalCentroids',logicalCentroids,'occupancy',occupancy,...
    'occupancyCount',occupancyCount,'minOccupancy',minOccupancy,'levelingOffset',levelingOffset,...
    'levelingScale',levelingScale,'offset',levelingOffset,'scale',levelingScale,...
    'withinClusterSigma',withinClusterSigma,'decisions',decisions,'thresholds',c.thresholds,...
    'levels',c.levels,'contract',c);
if wasRow, logicalSamples=logicalSamples.'; meta.logicalSamples=meta.logicalSamples.'; meta.decisions=meta.decisions.'; end
end

function value=getField(s,name,default)
if isfield(s,name), value=s.(name); else, value=default; end
end
