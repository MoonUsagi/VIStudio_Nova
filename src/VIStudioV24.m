function fig=VIStudioV24(projectFile,visible)
% V24 source release: independent measurement plus the existing vision hub.
if nargin<1, projectFile=""; end; if nargin<2, visible='on'; end
app=VIStudioHomeV24(projectFile,visible); fig=app.UIFigure; setappdata(fig,'VIStudioHomeV16',app); setappdata(fig,'VIStudioHomeV24',app);
end
