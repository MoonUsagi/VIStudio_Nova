function fig=VIStudioV25(projectFile,visible)
% V25 source release: independent measurement plus the existing vision hub.
if nargin<1, projectFile=""; end; if nargin<2, visible='on'; end
app=VIStudioHomeV25(projectFile,visible); fig=app.UIFigure; setappdata(fig,'VIStudioHomeV16',app); setappdata(fig,'VIStudioHomeV25',app);
end
