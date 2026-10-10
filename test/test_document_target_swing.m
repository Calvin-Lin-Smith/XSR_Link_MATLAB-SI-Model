function test_document_target_swing()
%TEST_DOCUMENT_TARGET_SWING README keeps physical swing separate from logical DAC units.
root=fileparts(fileparts(mfilename('fullpath'))); text=fileread(fullfile(root,'README.md'));
assert(contains(text,'`targetSwing` 只作为 physical swing metadata'));
assert(contains(text,'logicalOuterLevel'));
disp('targetSwing documentation tests OK');
end
