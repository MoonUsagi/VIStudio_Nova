classdef VIStudioRecoveryV8 < handle
    % Each editor owns an isolated recovery journal; user files are never replaced.
    properties (SetAccess=private)
        Root
        Folder=""
        LastRevision=-1
        Status="active"
    end
    methods
        function store=VIStudioRecoveryV8(root)
            if nargin<1, root=fullfile(fileparts(mfilename('fullpath')),'V8_Recovery'); end
            store.Root=string(root);
        end
        function file=write(store,doc,context)
            file=""; if ~doc.Dirty || isempty(doc.Files) || store.Status~="active", return; end
            if ~isfolder(store.Root), mkdir(store.Root); end
            if strlength(store.Folder)==0, store.Folder=string(tempname(store.Root)); mkdir(store.Folder); end
            session=doc.recoveryState(); %#ok<NASGU>
            context.SavedAtUTC=string(datetime('now','TimeZone','UTC')); context.Revision=doc.Revision;
            recoveryContext=context; %#ok<NASGU>
            temporary=string(tempname(store.Folder))+".mat"; save(temporary,'session','recoveryContext','-v7.3');
            file=string(tempname(store.Folder))+".mat"; movefile(temporary,file);
            checkpoint=struct('File',file,'Digest',VIStudioToolsV3.fileHash(file),'SavedAtUTC',context.SavedAtUTC, ...
                'Revision',doc.Revision,'Images',numel(doc.Files),'Annotations',height(doc.Annotations));
            checkpoints=checkpoint; manifestFile=fullfile(store.Folder,'manifest.mat');
            if isfile(manifestFile)
                old=load(manifestFile,'manifest'); checkpoints=[checkpoint old.manifest.Checkpoints];
            end
            removed=checkpoints(4:end); checkpoints=checkpoints(1:min(3,numel(checkpoints)));
            manifest=struct('Version',8,'Status',"active",'Checkpoints',checkpoints); %#ok<NASGU>
            temporary=fullfile(store.Folder,'manifest_pending.mat'); save(temporary,'manifest'); movefile(temporary,manifestFile,'f');
            store.LastRevision=doc.Revision;
            for k=1:numel(removed)
                % Only remove a journal-owned direct child after committing the manifest.
                [parent,~,ext]=fileparts(removed(k).File);
                if string(parent)==store.Folder && ext==".mat" && isfile(removed(k).File), delete(removed(k).File); end
            end
        end
        function resolve(store,status)
            store.Status=string(status);
            if strlength(store.Folder)==0, return; end
            path=fullfile(store.Folder,'manifest.mat');
            if isfile(path)
                loaded=load(path,'manifest'); manifest=loaded.manifest; manifest.Status=store.Status; %#ok<NASGU>
                temporary=fullfile(store.Folder,'manifest_pending.mat'); save(temporary,'manifest'); movefile(temporary,path,'f');
            end
        end
    end
    methods (Static)
        function resolveSnapshot(file,root,status)
            VIStudioRecoveryV8.read(file,root); [parent,~,~]=fileparts(file);
            loaded=load(fullfile(parent,'manifest.mat'),'manifest'); manifest=loaded.manifest; manifest.Status=string(status); %#ok<NASGU>
            temporary=fullfile(parent,'manifest_pending.mat'); save(temporary,'manifest'); movefile(temporary,fullfile(parent,'manifest.mat'),'f');
        end
        function entries=list(root)
            entries=table('Size',[0 6],'VariableTypes',{'string','string','string','double','double','logical'}, ...
                'VariableNames',{'Snapshot','SessionFolder','SavedAtUTC','Images','Annotations','Fallback'});
            if ~isfolder(root), return; end
            files=dir(fullfile(root,'*','manifest.mat'));
            for k=1:numel(files)
                try
                    loaded=load(fullfile(files(k).folder,files(k).name),'manifest'); m=loaded.manifest;
                    if m.Version~=8 || m.Status~="active", continue; end
                    for j=1:numel(m.Checkpoints)
                        c=m.Checkpoints(j); [parent,~,~]=fileparts(c.File);
                        if string(parent)~=string(files(k).folder), continue; end
                        if isfile(c.File) && VIStudioToolsV3.fileHash(c.File)==c.Digest
                            entries(end+1,:)={string(c.File),string(files(k).folder),string(c.SavedAtUTC),c.Images,c.Annotations,j>1}; %#ok<AGROW>
                            break;
                        end
                    end
                catch
                    % One damaged journal must not hide other recoverable editors.
                end
            end
            if ~isempty(entries), entries=sortrows(entries,'SavedAtUTC','descend'); end
        end
        function [session,context]=read(file,root)
            file=VIStudioToolsV3.canonicalPath(file); [parent,~,~]=fileparts(file); [base,~,~]=fileparts(parent);
            valid=false; manifestFile=fullfile(parent,'manifest.mat');
            if string(base)==VIStudioToolsV3.canonicalPath(root) && isfile(manifestFile) && isfile(file)
                loaded=load(manifestFile,'manifest'); m=loaded.manifest;
                if m.Version==8 && m.Status=="active"
                    for k=1:numel(m.Checkpoints)
                        if string(m.Checkpoints(k).File)==file && VIStudioToolsV3.fileHash(file)==m.Checkpoints(k).Digest, valid=true; break; end
                    end
                end
            end
            assert(valid,'VIStudioV8:RecoveryIntegrity','Recovery snapshot is missing, resolved or failed its integrity check.');
            loaded=load(file,'session','recoveryContext'); session=loaded.session; context=loaded.recoveryContext;
        end
    end
end
