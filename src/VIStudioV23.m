function fig=VIStudioV23(projectFile,visible)
% V23 source release: independent measurement plus the existing vision hub.
if nargin<1, projectFile=""; end; if nargin<2, visible='on'; end
app=VIStudioHomeV23(projectFile,visible); fig=app.UIFigure; setappdata(fig,'VIStudioHomeV16',app); setappdata(fig,'VIStudioHomeV23',app);
end
