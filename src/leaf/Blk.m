classdef Blk < handle
    properties
        name = ''
        cfg = struct()
        log = struct()
    end
    methods
        function obj = Blk(name)
            if nargin > 0, obj.name = char(name); end
        end
        function configure(obj,c), obj.cfg = c; end
        function out = run(obj,in) %#ok<INUSD>
            error('Blk:Abstract','%s must implement run().',class(obj));
        end
        function record(obj,node,data), obj.log.(node) = data; end
        function dump(obj,indent)
            if nargin < 2, indent = ''; end
            fprintf('%s%s  <%s>\n',indent,obj.name,class(obj));
            nodes = fieldnames(obj.log);
            if ~isempty(nodes), fprintf('%s  nodes: %s\n',indent,strjoin(nodes.',', ')); end
        end
    end
end
