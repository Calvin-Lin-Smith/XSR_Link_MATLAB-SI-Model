function test_simulink_paper_parity()
%TEST_SIMULINK_PAPER_PARITY Generated paper lane uses shared executable DSP.
root=fileparts(fileparts(mfilename('fullpath'))); addpath(genpath(fullfile(root,'src')),fullfile(root,'simulink'));
assert(license('test','Simulink'),'Simulink license is required for parity gate');
cfg=phyConfig('vlsi2024_xsr_typical'); name=matlab.lang.makeValidName(['parity_tmp_' char(java.util.UUID.randomUUID())]); path=fullfile(tempdir,[name '.slx']);
cleanup=onCleanup(@()cleanupModel(name,path)); buildD2DSimulinkModel('ModelName',name,'ModelPath',path,'Config',cfg,'Open',false,'Save',true,'Overwrite',false);
load_system(path); tx=find_system(name,'LookUnderMasks','all','FollowLinks','on','RegExp','on','Name','DAC.*Driver');
level=find_system(name,'LookUnderMasks','all','FollowLinks','on','RegExp','on','Name','PAM4.*Leveling'); cdr=find_system(name,'LookUnderMasks','all','FollowLinks','on','RegExp','on','Name','BB.*CDR.*PI.*Adaptation');
assert(~isempty(tx)&&~isempty(level)&&~isempty(cdr)); assert(contains(get_param(tx{1},'MATLABFcn'),'dspPaperDriver'));
assert(contains(get_param(level{1},'MATLABFcn'),'dspPam4Leveling')); assert(contains(get_param(cdr{1},'MATLABFcn'),'dspBbCdr'));
disp('Simulink paper parity tests OK');
end

function cleanupModel(name,path)
if bdIsLoaded(name), close_system(name,0); end
if isfile(path), delete(path); end
end
