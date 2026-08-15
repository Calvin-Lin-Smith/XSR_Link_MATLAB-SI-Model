function h = plotEye(x, sps, fileName)
%PLOTEYE Plot a two-UI eye diagram.
x=x(:); n=floor(numel(x)/(2*sps));
if n<2, error('plotEye:ShortWaveform','Need at least four UI.'); end
seg=reshape(x(1:n*2*sps),2*sps,n);
h=figure('Visible','off'); plot((0:2*sps-1)'/sps,seg,'Color',[0 0.25 0.7]);
xlabel('UI'); ylabel('Normalized amplitude'); grid on; xlim([0 2]);
if nargin>=3 && ~isempty(fileName), exportgraphics(h,fileName); end
end
