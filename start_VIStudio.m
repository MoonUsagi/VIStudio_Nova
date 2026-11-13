function fig=start_VIStudio(projectFile,visible)
% Start the current VIStudio Nova frontend. Legacy versioned entries remain.
root=fileparts(mfilename('fullpath')); if isfolder(fullfile(root,'src')), addpath(fullfile(root,'src')); else, addpath(root); end
if nargin<1, projectFile=""; end; if nargin<2, visible='on'; end
fig=VIStudioV20(projectFile,visible);
end
