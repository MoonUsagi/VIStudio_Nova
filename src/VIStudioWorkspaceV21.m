classdef VIStudioWorkspaceV21 < handle
    properties (SetAccess=private)
        Inner
        Project
        Stage
        Task
        Messages=strings(0,1)
    end
    methods
        function app=VIStudioWorkspaceV21(project,stage,visible)
            if nargin<3, visible='on'; end; visible=validatestring(char(visible),{'on','off'}); assert(isa(project,'VIStudioProjectV16'),'VIStudioV21:Project','A project is required.'); app.Project=project; app.Stage=string(validatestring(stage,{'label','train','evaluate','inspect'})); app.Task=project.Info.Task;
            if app.Stage=="label"
                app.Inner=VIStudioLabelerV21('off'); app.Inner.openAdvanced(app.Task);
                if isfile(project.Info.SessionFile), app.tryLoad(@() app.Inner.loadSession(project.Info.SessionFile));
                elseif isfile(project.Info.DatasetFile) && ismember(app.Task,["instance","keypoints"]), app.tryLoad(@() app.Inner.importStructured(project.Info.DatasetFile));
                elseif isfolder(project.Info.ImageFolder), app.tryLoad(@() app.Inner.loadFolder(project.Info.ImageFolder)); end
            elseif ismember(app.Task,["instance","keypoints"])
                app.Inner=VIStudioTaskAppV21(app.Task,'off'); pane=app.Inner.Pane;
                if isfile(project.Info.DatasetFile), app.tryLoad(@() pane.loadDataset(project.Info.DatasetFile)); end
                if ismember(app.Stage,["evaluate","inspect"]) && isfile(project.Info.ModelFile), app.tryLoad(@() pane.loadModel(project.Info.ModelFile)); end
                tabs=pane.Handles.Tabs; title='資料'; if app.Stage~="train", title='檢測'; end; app.selectTab(tabs,title);
            elseif app.Task=="semantic"
                app.Inner=VIStudioSemanticAppV21('off'); pane=app.Inner.Semantic;
                if isfile(project.Info.DatasetFile), app.tryLoad(@() pane.loadDataset(project.Info.DatasetFile)); end
                if ismember(app.Stage,["evaluate","inspect"]) && isfile(project.Info.ModelFile), app.tryLoad(@() pane.loadModel(project.Info.ModelFile)); end
                title='資料'; if app.Stage=="evaluate", title='評估'; elseif app.Stage=="inspect", title='檢測'; end; app.selectTab(pane.Handles.Tabs,title);
            else
                app.Inner=VIStudioVisionAppV21(app.Task,'off');
                if app.Stage=="train"
                    if app.Task=="detection" && isfile(project.Info.DatasetFile), app.tryLoad(@() app.Inner.loadTrainingAnnotations(project.Info.DatasetFile)); elseif isfolder(project.Info.ImageFolder), app.tryLoad(@() app.Inner.loadTrainingFolder(project.Info.ImageFolder)); end
                    app.Inner.selectWorkspace('training');
                else
                    if isfile(project.Info.ModelFile), app.tryLoad(@() app.Inner.loadModel(project.Info.ModelFile)); end
                    target='inspection'; if app.Stage=="evaluate", target='evaluation'; end; app.Inner.selectWorkspace(target);
                end
            end
            fig=app.Inner.UIFigure; h=VIStudioThemeV21.install(fig,app.Task); h.Title.Text=project.Info.Name+" / "+VIStudioHomeV16.stageTitle(app.Stage); h.Home.ButtonPushedFcn=@(~,~) VIStudioV21(app.Project.File); h.Sync.Enable='on'; h.Sync.Tooltip='另存目前可保存的資料／標記／報告並更新專案連結 / Save new artifacts and update project links'; h.Sync.ButtonPushedFcn=@(~,~) app.syncUI();
            app.refreshGuide(); setappdata(fig,'VIStudioProjectWorkspaceV16',app); fig.Visible=validatestring(visible,{'on','off'});
        end
        function folder=sync(app)
            % Every synchronization creates new artifacts; old files stay intact.
            assert(isfile(app.Project.File),'VIStudioV21:Project','Save the project first.'); root=fullfile(fileparts(app.Project.File),'Runs'); if ~isfolder(root), mkdir(root); end; folder=tempname(root); mkdir(folder); linked=false;
            if app.Stage=="label"
                file=fullfile(folder,'annotations.mat'); app.Inner.saveSession(file); app.Project.attach('SessionFile',file); linked=true;
            elseif isa(app.Inner,'VIStudioTaskAppV21')
                pane=app.Inner.Pane;
                if ~isempty(pane.Dataset)
                    data=pane.Dataset; VIStudioStructuredV15.assertUnchanged(data); manifest=data.manifest; objects=data.objects; classes=data.classes; schema=data.schema; file=fullfile(folder,'dataset.mat'); save(file,'manifest','objects','classes','schema','-v7.3'); app.Project.attach('DatasetFile',file); linked=true;
                end
                if ~isempty(pane.Artifact) && isfile(pane.Artifact.File), app.Project.attach('ModelFile',pane.Artifact.File); linked=true; end
                if ~isempty(pane.Evaluation), evaluation=pane.Evaluation; file=fullfile(folder,'results.mat'); save(file,'evaluation','-v7.3'); app.Project.attach('EvaluationFile',file); linked=true; end
                pane.saveSetup(fullfile(folder,'setup.mat'));
            elseif isa(app.Inner,'VIStudioSemanticAppV21')
                pane=app.Inner.Semantic;
                if ~isempty(pane.Data), manifest=pane.Data; classes=pane.Classes; schema=struct('Version',13,'Task',"semantic"); file=fullfile(folder,'dataset.mat'); save(file,'manifest','classes','schema','-v7.3'); app.Project.attach('DatasetFile',file); linked=true; end
                if ~isempty(pane.Artifact) && isfile(pane.Artifact.File), app.Project.attach('ModelFile',pane.Artifact.File); linked=true; end
                if ~isempty(pane.Evaluation), evaluation=pane.Evaluation; file=fullfile(folder,'results.mat'); save(file,'evaluation','-v7.3'); app.Project.attach('EvaluationFile',file); linked=true; end
            else
                file=app.Inner.ActiveModelFile; if strlength(file)>0 && isfile(file), app.Project.attach('ModelFile',file); linked=true; end
                if ~isempty(app.Inner.Results), results=app.Inner.Results; save(fullfile(folder,'inspection-results.mat'),'results','-v7.3'); linked=true; end
            end
            assert(linked,'VIStudioV21:NothingToSync','No saved model/data or results are available. Configure the workspace, save a model or attach a resource first.'); app.Project.save(); VIStudioHomeStateV16.rememberProject(app.Project); app.refreshGuide();
        end
        function delete(app), if ~isempty(app.Inner) && isvalid(app.Inner), delete(app.Inner); end, end
    end
    methods (Access=private)
        function tryLoad(app,callback), try, callback(); catch err, app.Messages(end+1)=string(err.message); end, end
        function refreshGuide(app)
            s=app.Project.status(); row=s.Stages.Stage==app.Stage; h=getappdata(app.Inner.UIFigure,'VIStudioThemeV21'); text=s.Stages.Hint(row); if ~isempty(app.Messages), text=text+" · 載入提醒 / Load issue: "+strjoin(app.Messages," | "); end; h.Guide.Text=text;
        end
        function syncUI(app), try, folder=app.sync(); h=getappdata(app.Inner.UIFigure,'VIStudioThemeV21'); h.Guide.Text="已另存並同步 / Saved and linked: "+string(folder); catch err, uialert(app.Inner.UIFigure,err.message,'同步 / Sync','Interpreter','none'); end, end
        function selectTab(~,tabs,text), pages=tabs.Children; ix=find(contains(string({pages.Title}),text),1); if ~isempty(ix), tabs.SelectedTab=pages(ix); end, end
    end
end
