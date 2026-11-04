function fig=VIStudioV17(projectFile,visible)
% V17 source release: independent measurement plus the existing vision hub.
if nargin<1, projectFile=""; end; if nargin<2, visible='on'; end
app=VIStudioHomeV17(projectFile,visible); fig=app.UIFigure; setappdata(fig,'VIStudioHomeV16',app); setappdata(fig,'VIStudioHomeV17',app);
end
