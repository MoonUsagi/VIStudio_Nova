classdef VIStudioHomeStateV16
    methods (Static)
        function rememberProject(project)
            folder=VIStudioHomeStateV16.root(); state=VIStudioHomeStateV16.read();
            if ~isfield(state,'Projects'), state.Projects=table(strings(0,1),strings(0,1),strings(0,1),strings(0,1),'VariableNames',{'Name','Task','File','Updated'}); end
            r=state.Projects; r(strcmpi(string(r.File),project.File),:)=[]; state.Projects=[table(project.Info.Name,project.Info.Task,project.File,project.Info.Updated,'VariableNames',r.Properties.VariableNames);r]; state.Projects=state.Projects(1:min(12,height(state.Projects)),:); VIStudioHomeStateV16.write(state,folder);
        end
        function folder=root()
            folder=fullfile(fileparts(mfilename('fullpath')),'V16_User');
            override=getenv('VISTUDIO_V16_USER_DIR'); if ~isempty(override), folder=override; end
        end
        function s=read(folder)
            if nargin<1, folder=VIStudioHomeStateV16.root(); end
            s=struct('Recent',table(strings(0,1),strings(0,1),strings(0,1),'VariableNames',{'Kind','File','Opened'}),'Hero',""); file=fullfile(folder,'home.mat');
            if isfile(file)
                try
                    loaded=load(file,'state'); candidate=loaded.state; assert(all(isfield(candidate,{'Recent','Hero'})) && istable(candidate.Recent) && all(ismember({'Kind','File','Opened'},candidate.Recent.Properties.VariableNames)));
                    assert(all(ismember(string(candidate.Recent.Kind),["session","setup","dataset"]))); candidate.Hero=string(candidate.Hero); assert(isscalar(candidate.Hero)); s=candidate;
                catch
                    warning('VIStudioV16:HomeState','Home preferences could not be read; default launcher remains available.');
                end
            end
        end
        function remember(kind,file,folder)
            if nargin<3, folder=VIStudioHomeStateV16.root(); end
            kind=string(validatestring(kind,{'session','setup','dataset'})); file=VIStudioToolsV3.canonicalPath(file); assert(isfile(file),'VIStudioV16:Recent','Recent file is missing.'); state=VIStudioHomeStateV16.read(folder); r=state.Recent; r(r.Kind==kind & strcmpi(r.File,file),:)=[]; state.Recent=[table(kind,string(file),string(datetime('now','Format','yyyy-MM-dd HH:mm')),'VariableNames',r.Properties.VariableNames);r]; state.Recent=state.Recent(1:min(8,height(state.Recent)),:); VIStudioHomeStateV16.write(state,folder);
        end
        function setHero(file,folder)
            if nargin<2, folder=VIStudioHomeStateV16.root(); end
            image=imread(file); state=VIStudioHomeStateV16.read(folder); if ~isfolder(folder), mkdir(folder); end; target=fullfile(folder,'hero.png'); imwrite(image,target); state.Hero=string(target); VIStudioHomeStateV16.write(state,folder);
        end
        function write(state,folder)
            if ~isfolder(folder), mkdir(folder); end; temp=[tempname(folder) '.mat']; save(temp,'state'); movefile(temp,fullfile(folder,'home.mat'),'f');
        end
        function status=resources()
            names=["Mask R-CNN";"SOLOv2";"HRNet";"SAM"]; api=["maskrcnn";"solov2";"hrnetObjectKeypointDetector";"segmentAnythingModel"]; states=strings(4,1);
            for k=1:4, states(k)="API_MISSING"; if exist(char(api(k)),'file')>0 || exist(char(api(k)),'class')>0, states(k)="API_FOUND_NOT_RUN"; end, end
            status=table(names,api,states,'VariableNames',{'Model','API','Status'});
        end
    end
end
