function test_simulink_leveling_validity()
%TEST_SIMULINK_LEVELING_VALIDITY Invalid leveler output cannot lock in paper path.
root=fileparts(fileparts(mfilename('fullpath'))); addpath(genpath(fullfile(root,'src')),fullfile(root,'simulink'));
raw=repelem([-3;-1;1;5],128);
[~,levelMeta]=dspPam4Leveling(raw); assert(~levelMeta.levelsValid && levelMeta.fitResidual>0.15,'Non-affine leveler input was accepted.');
cfg=phyConfig('vlsi2024_xsr_typical');
if license('test','Simulink')
    name=matlab.lang.makeValidName(['validity_tmp_' char(java.util.UUID.randomUUID())]); path=fullfile(tempdir,[name '.slx']);
    cleanup=onCleanup(@()cleanupModel(name,path)); %#ok<NASGU>
    buildD2DSimulinkModel('ModelName',name,'ModelPath',path,'Config',cfg,'Open',false,'Save',true,'Overwrite',false); load_system(path);
    block=find_system(name,'LookUnderMasks','all','FollowLinks','on','RegExp','on','Name','BB.*CDR.*PI.*Adaptation');
    assert(~isempty(block) && contains(get_param(block{1},'MATLABFcn'),'dspPaperCdr'),'Simulink CDR validity wrapper is missing.');
end
[bits,trace]=dspPaperCdr(raw,'PAM4',cfg.link.sps,cfg.model.cdrOptions);
assert(~trace.levelingValid && ~trace.currentlyLocked && ~trace.continuousTailLock && all(isnan(bits)),...
    'Invalid leveling result reached a valid CDR output.');
disp('Simulink leveling-validity tests OK');
end

function cleanupModel(name,path)
if bdIsLoaded(name), close_system(name,0); end
if isfile(path), delete(path); end
end
