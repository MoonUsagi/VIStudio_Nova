function fig=VIStudioV21(projectFile,visible)
% V21 source release: independent measurement plus the existing vision hub.
if nargin<1, projectFile=""; end; if nargin<2, visible='on'; end
app=VIStudioHomeV21(projectFile,visible); fig=app.UIFigure; setappdata(fig,'VIStudioHomeV16',app); setappdata(fig,'VIStudioHomeV21',app);
end
