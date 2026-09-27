function test_gui_gray_leveling_visibility()
%TEST_GUI_GRAY_LEVELING_VISIBILITY GUI exposes read-only contract and leveling evidence.
root=fileparts(fileparts(mfilename('fullpath'))); addpath(genpath(fullfile(root,'src')),fullfile(root,'gui'));
app=D2DWorkbench(root); cleanup=onCleanup(@()closeGui(app));
texts=uiTextValues(app.Figure,'Text'); assert(any(contains(texts,'Gray PAM4')));
items=string(D2DWorkbench.probeItems());
for name=["RX raw samples" "RX logical samples" "RX leveling centroids" "RX leveling occupancy" "RX leveling scale"]
    assert(any(items==name),char(name));
end
disp('GUI Gray/leveling visibility tests OK');
end

function values=uiTextValues(parent,property)
h=findall(parent,'-property',property); values=strings(0,1);
for k=1:numel(h), try, v=get(h(k),property); if ischar(v)||isstring(v), values(end+1,1)=string(v); end, catch, end, end
end

function closeGui(app)
if isvalid(app)&&isvalid(app.Figure), delete(app.Figure); end
end
