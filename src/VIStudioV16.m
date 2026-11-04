function fig=VIStudioV16(projectFile,visible)
% V17 distribution compatibility adapter.
if nargin<1, projectFile=""; end; if nargin<2, visible='on'; end
fig=VIStudioV17(projectFile,visible);
end
