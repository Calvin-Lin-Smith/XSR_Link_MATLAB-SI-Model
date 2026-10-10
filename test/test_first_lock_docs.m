function test_first_lock_docs()
%TEST_FIRST_LOCK_DOCS Active docs use the accepted first-lock-only measurement contract.
root=fileparts(fileparts(mfilename('fullpath')));
paths={fullfile(root,'README.md'),fullfile(root,'gui','README.md'),...
    fullfile(root,'simulink','README.md')};
allText='';
for k=1:numel(paths), allText=[allText lower(fileread(paths{k}))]; %#ok<AGROW>
end
assert(~contains(allText,'latestlock') && ~contains(allText,'latest-lock') && ~contains(allText,'latest lock'),...
    'Active docs still describe latest-lock/reacquisition measurement.');
assert(contains(allText,'firstvalidlockui') && contains(allText,'postlockwaitui') && contains(allText,'continuous'),...
    'Active docs omit first-lock guard/tail invalidation semantics.');
disp('First-lock documentation tests OK');
end
