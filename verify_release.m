function report=verify_release
% Verify the immutable release inventory; extra local output files are ignored.
root=fileparts(mfilename('fullpath')); addpath(fullfile(root,'src')); manifest=jsondecode(fileread(fullfile(root,'RELEASE_MANIFEST.json'))); entries=manifest.Files; modified=strings(0,1); missing=strings(0,1);
for k=1:numel(entries)
    relative=string(entries(k).Path); assert(~startsWith(relative,["/","\"]) && isempty(regexp(char(relative),'(^|[\\/])\.\.([\\/]|$)|^[A-Za-z]:','once')),'VIStudioRelease:Path','Unsafe manifest path.'); file=fullfile(root,relative);
    if ~isfile(file), missing(end+1)=relative; elseif VIStudioToolsV3.fileHash(file)~=string(entries(k).SHA256), modified(end+1)=relative; end
end
report=struct('Version',string(manifest.Version),'Checked',numel(entries),'Missing',missing,'Modified',modified); assert(isempty(missing) && isempty(modified),'VIStudioRelease:Integrity','Release files are missing or modified. See report or compare SHA256SUMS.'); fprintf('VIStudio %s: %d release files verified.\n',report.Version,report.Checked);
end
