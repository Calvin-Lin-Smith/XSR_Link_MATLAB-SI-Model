function [bits,trace]=dspPaperCdr(x,modulation,sps,options)
%DSPPAPERCDR Run the paper CDR with the shared PAM4 leveling validity gate.
if nargin<4 || isempty(options), options=struct(); end
modulation=char(modulation);
if strcmpi(modulation,'PAM4')
    levelingOptions=getField(options,'levelingOptions',struct());
    [logicalSamples,levelingMeta]=dspPam4Leveling(x,levelingOptions);
    cdrOptions=options; cdrOptions.levelingValid=levelingMeta.levelsValid;
    cdrOptions=removeField(cdrOptions,'levelingOptions');
    [bits,trace]=dspBbCdr(logicalSamples,modulation,sps,cdrOptions);
    trace.levelingMeta=levelingMeta;
    trace.levelingValid=levelingMeta.levelsValid;
    if ~levelingMeta.levelsValid
        bits(:)=NaN;
        trace.currentlyLocked=false;
        trace.continuousTailLock=false;
    end
else
    [bits,trace]=dspBbCdr(x,modulation,sps,options);
end
end

function value=getField(s,name,default)
if isstruct(s)&&isfield(s,name), value=s.(name); else, value=default; end
end

function s=removeField(s,name)
if isstruct(s)&&isfield(s,name), s=rmfield(s,name); end
end
