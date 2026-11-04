classdef VIStudioHomeV16 < handle
    properties (SetAccess=private)
        UIFigure
        Handles=struct()
        Project=[]
        Workspaces={}
        Snapshot=[]
    end
    methods
        function app=VIStudioHomeV16(file,visible)
            if nargin<1, file=""; end; if nargin<2, visible='on'; end
            app.build();
            if strlength(string(file))>0, app.loadProject(file);
            else
                state=VIStudioHomeStateV16.read(); if isfield(state,'Projects') && ~isempty(state.Projects)
                    file=state.Projects.File(1); if isfile(file), try, app.loadProject(file); catch err, app.Handles.Status.Text=string(err.message); end; else, app.Handles.Status.Text='上次專案檔已搬移；可用開啟專案重新連結 / Last project is missing; open its new location'; end
                end
            end
            app.refresh(); app.UIFigure.Visible=validatestring(visible,{'on','off'});
        end
        function delete(app), if ~isempty(app.UIFigure) && isvalid(app.UIFigure), delete(app.UIFigure); end, end
        function createProject(app,name,task,folder)
            project=VIStudioProjectV16.create(name,task,folder); app.Project=project; VIStudioHomeStateV16.rememberProject(project); app.refresh(); app.Handles.Status.Text='新專案已保存；請連結影像或資料集 / Project saved; link images or dataset';
        end
        function loadProject(app,file)
            project=VIStudioProjectV16(file); app.Project=project; VIStudioHomeStateV16.rememberProject(project); app.refresh(); app.Handles.Status.Text="已開啟 / Opened: "+project.File;
        end
        function attachResource(app,role,file)
            app.requireProject(); app.Project.attach(role,file); app.Project.save(); VIStudioHomeStateV16.rememberProject(app.Project); app.refresh();
        end
        function workspace=openStage(app,stage)
            app.requireProject(); stage=string(validatestring(stage,{'data','label','train','evaluate','inspect'})); workspace=[];
            if stage=="data", app.Handles.Role.Value='ImageFolder'; app.Handles.Status.Text='選擇下方資源類型，再按連結／重新定位 / Choose a resource and link its location'; return; end
            workspace=VIStudioWorkspaceV16(app.Project,stage,char(app.UIFigure.Visible)); app.Workspaces{end+1}=workspace;
        end
        function workspace=openTask(app,task)
            task=string(task); workspace=[];
            if ~isempty(app.Project) && task==app.Project.Info.Task, workspace=app.openStage('train'); return; end
            if ismember(task,["labeler","quality"])
                if ~isempty(app.Project), workspace=app.openStage('label'); if task=="quality", workspace.Inner.openAdvanced('quality'); else, workspace.Inner.openAdvanced('assist'); end
                else, workspace=VIStudioLabelerV16(char(app.UIFigure.Visible)); kind='assist'; if task=="quality", kind='quality'; end; workspace.openAdvanced(kind); app.Workspaces{end+1}=workspace; end
            else
                if ismember(task,["classification","detection","anomaly"]), workspace=VIStudioVisionAppV16(task,char(app.UIFigure.Visible)); elseif task=="semantic", workspace=VIStudioSemanticAppV16(char(app.UIFigure.Visible)); else, workspace=VIStudioTaskAppV16(task,char(app.UIFigure.Visible)); end
                app.Workspaces{end+1}=workspace;
            end
        end
        function refresh(app)
            if ~isvalid(app.UIFigure), return; end; app.refreshRecent();
            if isempty(app.Project)
                app.Handles.Title.Text='建立第一個專案 / Create your first project'; app.Handles.Path.Text='先建立或開啟專案，再連結資料、標記、模型與結果 / Create/open a project to organize your workflow'; app.Handles.StageTable.Data=table(); app.Handles.Resources.Data=table(); app.Handles.Summary.Data=table(); app.Handles.Note.Text='尚無評估報告 / No evaluation report'; app.Handles.Next.Enable='off'; return;
            end
            s=app.Project.status(); app.Snapshot=s; info=app.Project.Info; app.Handles.Title.Text=info.Name+"  /  "+app.taskTitle(info.Task); app.Handles.Path.Text=app.Project.File; app.Handles.SideTask.Text="目前任務 / Task"+newline+app.taskTitle(info.Task);
            values=[string(s.Images),string(s.Classes),string(s.Reviewed)+" / "+string(s.ReviewTotal),string(s.Pending),string(s.Annotations),"待連結 / None"]; if s.ModelState=="LINKED_NOT_RUN", values(6)="已連結 / Linked"; elseif s.ModelState=="MISSING", values(6)="缺檔 / Missing"; end
            for k=1:6, app.Handles.Stats(k).Text=values(k); end
            guide=s.Stages(:,{'Title','State','Hint'}); guide.State=app.stateTitle(guide.State); app.Handles.StageTable.Data=guide; app.Handles.Next.Enable='on'; app.Handles.Next.Text="下一步 / Next: "+app.stageTitle(s.Next); app.Handles.Next.ButtonPushedFcn=@(~,~) app.action(@() app.openStage(s.Next));
            roles=VIStudioProjectV16.roles()'; paths=strings(numel(roles),1); states=paths;
            for k=1:numel(roles), paths(k)=info.(roles(k)); states(k)="NOT_LINKED"; if strlength(paths(k))>0, states(k)="MISSING"; if isfile(paths(k)) || (roles(k)=="ImageFolder" && isfolder(paths(k))), states(k)="LINKED"; end, end, end
            labels=["影像資料夾 / Images";"標記工作 / Annotations";"資料集 / Dataset";"模型 / Model";"評估報告 / Report"]; displayStates=states; displayStates(states=="LINKED")="已連結 / Linked"; displayStates(states=="NOT_LINKED")="待連結 / Link"; displayStates(states=="MISSING")="缺檔 / Missing";
            app.Handles.Resources.Data=table(labels,displayStates,paths,'VariableNames',{'Resource','State','Path'}); app.Handles.Summary.Data=s.Evaluation.Summary; app.Handles.Note.Text=s.Evaluation.Meaning;
            app.Handles.ReportPath.Text="模型 / Model: "+info.ModelFile+newline+"評估 / Report: "+info.EvaluationFile;
            if isempty(s.Issues), app.Handles.Status.Text=s.Meaning; else, app.Handles.Status.Text=strjoin(s.Issues," · "); end
        end
    end
    methods (Access=private)
        function build(app)
            p=VIStudioThemeV16.palette(); app.UIFigure=uifigure('Name','VIStudio V16 | 專案工作台 Project Hub','Position',[40 40 1480 940],'Visible','off','Color',p.Canvas,'CloseRequestFcn',@(~,~) delete(app)); root=uigridlayout(app.UIFigure,[2 2],'ColumnWidth',{220,'1x'},'RowHeight',{'1x',38},'Padding',[12 10 12 8],'RowSpacing',8);
            side=uigridlayout(root,[10 1],'RowHeight',{86,32,38,38,38,38,80,'1x',42,28},'Padding',[14 10 14 12],'BackgroundColor',p.Navy); side.Layout.Row=1; side.Layout.Column=1;
            uiimage(side,'ImageSource',VIStudioThemeV16.logo(),'ScaleMethod','fit'); uilabel(side,'Text','PROJECT HUB  /  V16','FontColor',p.Mint,'FontWeight','bold','FontSize',12);
            uibutton(side,'Text','新增專案 / New project','ButtonPushedFcn',@(~,~) app.newProjectUI()); uibutton(side,'Text','開啟專案 / Open project','ButtonPushedFcn',@(~,~) app.action(@() app.pickProject())); uibutton(side,'Text','儲存專案 / Save project','ButtonPushedFcn',@(~,~) app.action(@() app.saveProject())); uibutton(side,'Text','重新整理 / Refresh','ButtonPushedFcn',@(~,~) app.action(@() app.refresh()));
            app.Handles.SideTask=uilabel(side,'Text','先建立專案 / Start a project','FontColor',[1 1 1],'FontSize',14,'WordWrap','on'); uilabel(side,'Text',"資料 → 標記 → 訓練 → 評估 → 檢測"+newline+"Data → Review → Train → Evaluate → Inspect",'FontColor',[.66 .76 .85],'WordWrap','on','VerticalAlignment','top'); uibutton(side,'Text','操作說明 / Help','ButtonPushedFcn',@(~,~) app.help()); uilabel(side,'Text','Local · Bilingual · Versioned','FontColor',[.52 .66 .76],'FontSize',10);
            tabs=uitabgroup(root); app.Handles.Tabs=tabs; tabs.Layout.Row=1; tabs.Layout.Column=2;
            page=uitab(tabs,'Title','專案首頁 / Project'); g=uigridlayout(page,[7 1],'RowHeight',{28,30,76,38,174,38,'1x'},'RowSpacing',8,'Padding',[14 12 14 10]);
            app.Handles.Title=uilabel(g,'Text','建立第一個專案 / Create a project','FontSize',21,'FontWeight','bold','FontColor',p.Text); app.Handles.Path=uilabel(g,'Text','','Interpreter','none','FontSize',10,'FontColor',p.Muted);
            stats=uigridlayout(g,[1 6],'ColumnSpacing',8,'Padding',[0 0 0 0]); names={'影像 / Images','類別 / Classes','已覆核 / Reviewed','待確認 / Pending','標記 / Objects','模型 / Model'}; app.Handles.Stats=gobjects(1,6);
            for k=1:6, panel=uipanel(stats,'BorderType','line','BorderColor',[.84 .89 .92],'BackgroundColor',[1 1 1]); box=uigridlayout(panel,[2 1],'RowHeight',{22,'1x'},'Padding',[8 4 8 4],'RowSpacing',2,'BackgroundColor',[1 1 1]); uilabel(box,'Text',names{k},'FontSize',11,'FontColor',p.Muted); app.Handles.Stats(k)=uilabel(box,'Text','—','FontSize',17,'FontWeight','bold','FontColor',p.Text); end
            bar=uigridlayout(g,[1 5],'Padding',[0 0 0 0]); stages={'data','label','train','evaluate','inspect'}; labels={'1 資料 / Data','2 標記 / Label','3 訓練 / Train','4 評估 / Evaluate','5 檢測 / Inspect'};
            for k=1:5, stage=stages{k}; uibutton(bar,'Text',labels{k},'ButtonPushedFcn',@(~,~) app.action(@() app.openStage(stage))); end
            app.Handles.StageTable=uitable(g,'RowName',{},'ColumnName',{'步驟 / Step','狀態 / State','下一步提示 / Guidance'},'ColumnWidth',{175,190,'auto'});
            bar=uigridlayout(g,[1 4],'ColumnWidth',{'1x',155,155,155},'Padding',[0 0 0 0]); app.Handles.Next=uibutton(bar,'Text','下一步 / Next','Enable','off'); app.Handles.Role=uidropdown(bar,'Items',{'影像 / Images','標記 / Labels','資料集 / Dataset','模型 / Model','評估 / Report'},'ItemsData',cellstr(VIStudioProjectV16.roles()),'Tooltip','選擇資源類型 / Resource type'); uibutton(bar,'Text','連結／定位 / Link','ButtonPushedFcn',@(~,~) app.action(@() app.pickResource())); uibutton(bar,'Text','解除連結 / Unlink','ButtonPushedFcn',@(~,~) app.action(@() app.unlink())); app.Handles.Resources=uitable(g,'RowName',{},'ColumnName',{'資源 / Resource','狀態 / State','檔案 / File'},'ColumnWidth',{170,120,'auto'},'CellSelectionCallback',@(~,e) app.selectResource(e));
            page=uitab(tabs,'Title','工作區 / Workspaces'); app.buildWorkspaces(page);
            page=uitab(tabs,'Title','模型與報告 / Model & Report'); g=uigridlayout(page,[5 1],'RowHeight',{90,60,'1x',42,100}); app.Handles.ReportPath=uilabel(g,'Text','尚未連結 / No resources linked','WordWrap','on','Interpreter','none'); app.Handles.Note=uilabel(g,'Text','尚無評估報告 / No report','WordWrap','on'); app.Handles.Summary=uitable(g); uilabel(g,'Text','連結報告不等於驗收通過；首頁不啟動模型 / Reports do not imply acceptance; no models run on home','FontColor',p.Muted); resources=VIStudioHomeStateV16.resources(); uitable(g,'Data',resources(:,{'Model','Status'}));
            page=uitab(tabs,'Title','最近專案 / Recent'); g=uigridlayout(page,[3 1],'RowHeight',{44,'1x',38}); uilabel(g,'Text','保留最近 12 個專案；檔案搬移後可重新選擇專案檔 / Up to 12 projects; reopen moved files at their new location','WordWrap','on'); app.Handles.Recent=uitable(g,'SelectionType','row','ColumnWidth',{170,110,'auto',145}); bar=uigridlayout(g,[1 2]); uibutton(bar,'Text','繼續所選 / Resume','ButtonPushedFcn',@(~,~) app.action(@() app.resume())); uibutton(bar,'Text','重新定位專案 / Locate','ButtonPushedFcn',@(~,~) app.action(@() app.pickProject()));
            app.Handles.Status=uilabel(root,'Text','V16 獨立版本；先建立專案，再連結既有資料 / Independent V16; create a project and link resources','WordWrap','on','FontSize',11); app.Handles.Status.Layout.Row=2; app.Handles.Status.Layout.Column=[1 2]; VIStudioThemeV16.apply(root);
        end
        function buildWorkspaces(app,page)
            root=fileparts(mfilename('fullpath')); g=uigridlayout(page,[2 4],'RowHeight',{'1x','1x'},'ColumnWidth',{'1x','1x','1x','1x'},'Padding',[14 12 14 12]); tasks={'classification','detection','anomaly','semantic','instance','keypoints','labeler','quality'};
            for k=1:numel(tasks)
                task=tasks{k}; panel=uipanel(g,'BackgroundColor',[1 1 1]); card=uigridlayout(panel,[4 1],'RowHeight',{'1x',36,40,34},'Padding',[10 8 10 8]); uiimage(card,'ImageSource',fullfile(root,'V14_Assets',[task '.png']),'ScaleMethod','fit'); uilabel(card,'Text',app.taskTitle(task),'WordWrap','on','FontWeight','bold','FontSize',16); uilabel(card,'Text','同任務會帶入目前專案；其他任務開啟獨立工作區 / Project links apply to matching tasks','WordWrap','on','FontSize',10); uibutton(card,'Text','開啟 / Open','ButtonPushedFcn',@(~,~) app.action(@() app.openTask(task)));
            end
        end
        function requireProject(app), assert(~isempty(app.Project),'VIStudioV16:NoProject','請先新增或開啟專案 / Create or open a project first.'); end
        function saveProject(app), app.requireProject(); app.Project.save(); VIStudioHomeStateV16.rememberProject(app.Project); app.refresh(); end
        function pickProject(app), [f,p]=uigetfile('*.mat','VIStudioProject.mat'); if ~isequal(f,0), app.loadProject(fullfile(p,f)); end, end
        function pickResource(app)
            app.requireProject(); role=string(app.Handles.Role.Value); if role=="ImageFolder", file=uigetdir(pwd); if isequal(file,0), return; end; else, [f,p]=uigetfile('*.mat'); if isequal(f,0), return; end; file=fullfile(p,f); end; app.attachResource(role,file);
        end
        function unlink(app), app.requireProject(); app.Project.detach(app.Handles.Role.Value); app.Project.save(); app.refresh(); end
        function selectResource(app,event), if isempty(event.Indices), return; end; roles=VIStudioProjectV16.roles(); app.Handles.Role.Value=char(roles(event.Indices(1,1))); end
        function refreshRecent(app), state=VIStudioHomeStateV16.read(); if isfield(state,'Projects'), app.Handles.Recent.Data=state.Projects; end, end
        function resume(app), rows=app.Handles.Recent.Selection; if isempty(rows), rows=1; end; if size(rows,2)==2, rows=rows(1,1); else, rows=rows(1); end; data=app.Handles.Recent.Data; assert(istable(data) && rows<=height(data),'VIStudioV16:Recent','Select a recent project.'); app.loadProject(data.File(rows)); end
        function newProjectUI(app)
            fig=uifigure('Name','新專案 / New project','Position',[240 180 620 310]); g=uigridlayout(fig,[5 2],'RowHeight',{40,40,40,'1x',40},'ColumnWidth',{130,'1x'}); uilabel(g,'Text','名稱 / Name'); name=uieditfield(g,'text','Value','My Vision Project'); uilabel(g,'Text','任務 / Task'); task=uidropdown(g,'Items',{'classification','detection','anomaly','semantic','instance','keypoints'}); uilabel(g,'Text','專案資料夾 / Folder'); path=uieditfield(g,'text','Placeholder','選擇資料夾 / Select a folder','Editable','off'); uibutton(g,'Text','選資料夾 / Browse','ButtonPushedFcn',@(~,~) browse()); text=uilabel(g,'Text','只建立專案設定檔；影像與模型由你連結 / Creates project metadata; link your existing images and models','WordWrap','on'); uibutton(g,'Text','建立 / Create','ButtonPushedFcn',@(~,~) create()); VIStudioThemeV16.apply(fig);
            function browse(), folder=uigetdir(pwd); if ~isequal(folder,0), path.Value=folder; end, end
            function create(), try, assert(strlength(string(path.Value))>0,'Choose a folder.'); app.createProject(name.Value,task.Value,path.Value); delete(fig); catch err, uialert(fig,err.message,'Project'); end, end
        end
        function help(app), uialert(app.UIFigure,"1 新增專案並選任務。"+newline+"2 連結影像、標記或資料集。"+newline+"3 依步驟開啟工作區。"+newline+"4 變更後按工作區上方「同步至專案」。"+newline+"5 回首頁重新整理，查看已保存的進度。"+newline+"模型連結不等於訓練／推論已驗證。",'操作引導 / Workflow','Icon','info'); end
        function action(app,callback), try, callback(); catch err, app.Handles.Status.Text=string(err.message); if strcmp(app.UIFigure.Visible,'off'), rethrow(err); end; uialert(app.UIFigure,err.message,'VIStudio V16','Interpreter','none'); end, end
    end
    methods (Static)
        function labels=stageTitle(stages)
            keys=["data","label","train","evaluate","inspect"]; names=["資料 / Data","標記 / Label","訓練 / Train","評估 / Evaluate","檢測 / Inspect"]; labels=string(stages); for k=1:numel(keys), labels(string(stages)==keys(k))=names(k); end
        end
        function labels=stateTitle(states)
            keys=["EMPTY","CHECK_LINKS","DATA_LINKED","NOT_STARTED","IN_PROGRESS","REVIEWED","DATASET_LINKED","NEEDS_DATA","NEEDS_SPLIT","READY_TO_CONFIGURE","FOLDER_LINKED","REVIEW_PENDING","NEEDS_MODEL","READY_TO_EVALUATE","REPORT_LINKED_UNVERIFIED","REPORT_MODEL_MISMATCH","REPORT_ERROR","MODEL_LINKED_NOT_RUN"];
            names=["待連結資料 / Link data","檢查檔案連結 / Check links","已連結資料 / Data linked","待建立標記 / Start labeling","覆核中 / In review","已完成覆核 / Reviewed","已連結資料集 / Dataset linked","待準備資料 / Prepare data","待切分資料 / Assign splits","可設定訓練 / Configure","已連結資料夾 / Folder linked","先覆核候選 / Review pending","待連結模型 / Link model","可執行評估 / Evaluate","報告待確認 / Report linked","報告模型不符 / Mismatch","報告需修正 / Check report","已連結，尚未檢測 / Not run"];
            labels=string(states); for k=1:numel(keys), labels(string(states)==keys(k))=names(k); end
        end
        function text=taskTitle(task)
            tasks=["classification","detection","anomaly","semantic","instance","keypoints","labeler","quality"]; labels=["影像分類 / Classification","物件偵測 / Detection","異常偵測 / Anomaly","語意分割 / Semantic","實例分割 / Instance","關鍵點／肢節 / Keypoints","AI 輔助標記 / AI Labeler","標記品質 / Annotation QA"]; ix=find(tasks==string(task),1); if isempty(ix), text=string(task); else, text=labels(ix); end
        end
    end
end
