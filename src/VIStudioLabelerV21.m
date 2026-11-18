classdef VIStudioLabelerV21 < handle
    % Independent editable labeler. Original MLAPP and legacy sessions stay intact.
    properties (SetAccess=private)
        UIFigure
        Data
        SelectedID=""
        CurrentIndex=1
        LastExport=[]
        QualityReport=[]
        Recovery
        Handles=struct()
    end
    properties (Access=private)
        CustomPoseTemplate=[]
        Sam=[]
        SamStatus="NOT_CHECKED"
        QualityFigure=[]
        CachedFile=""
        RenderedFile=""
        Rendering=false
        Model=[]
        ModelMetadata=struct()
        ModelTask=""
        ModelDigest=""
        Busy=false
        SendCallback=[]
        Language='bilingual'
        Translations={}
        Image=[]
        AutosaveTimer=[]
        ROIListeners={}
    end
    methods
        function app=VIStudioLabelerV21(visible,callback,recoveryRoot)
            if nargin<1, visible='on'; end
            if nargin<2, callback=[]; end
            if nargin<3, recoveryRoot=fullfile(VIStudioHomeStateV16.root(),'Recovery'); end
            app.Recovery=VIStudioRecoveryV8(recoveryRoot);
            app.Data=VIStudioAnnotationDataV15; app.SendCallback=callback; app.buildUI(); app.buildAdvancedTools(); app.buildProductivity(); app.captureTranslations();
            VIStudioThemeV21.install(app.UIFigure,'標記工作室 / Annotation'); app.UIFigure.Visible=visible; app.refresh();
            app.configureAutosave(true,60);
            available=app.availableRecoveries();
            if ~isempty(available), app.Handles.RecoveryStatus.Text=sprintf('%d 個可恢復工作階段 / recoverable sessions',height(available)); end
        end
        function delete(app)
            if ~isempty(app.QualityFigure) && isvalid(app.QualityFigure), delete(app.QualityFigure); end
            if ~isempty(app.AutosaveTimer) && isvalid(app.AutosaveTimer), stop(app.AutosaveTimer); delete(app.AutosaveTimer); end
            if ~isempty(app.Data) && app.Data.Dirty && ~app.Rendering
                try, app.saveRecovery(); catch err, warning('VIStudioV15:RecoveryWrite','%s',err.message); end
            end
            app.Rendering=true;
            for k=1:numel(app.ROIListeners), if isvalid(app.ROIListeners{k}), delete(app.ROIListeners{k}); end, end
            app.ROIListeners={};
            if ~isempty(app.UIFigure) && isvalid(app.UIFigure), delete(app.UIFigure); end
        end
        function loadFolder(app,folder)
            ds=imageDatastore(folder,'IncludeSubfolders',true); app.loadFiles(ds.Files);
        end
        function loadFiles(app,files)
            app.assertIdle(); app.Data.loadFiles(files); app.clearPrompts(); app.CachedFile=""; app.RenderedFile=""; app.newRecoveryBranch(); app.CurrentIndex=1; app.SelectedID=""; app.refresh();
        end
        function loadSession(app,file)
            app.assertIdle(); app.Data.loadSession(file); VIStudioHomeStateV16.remember('session',file); app.clearPrompts(); app.CachedFile=""; app.RenderedFile=""; app.Recovery.resolve("loaded"); app.newRecoveryBranch(); app.CurrentIndex=1; app.SelectedID=""; app.refresh();
        end
        function importStructured(app,file), app.assertIdle(); app.Data.importStructured(file); app.clearPrompts(); app.CachedFile=""; app.RenderedFile=""; app.CurrentIndex=1; app.SelectedID=""; app.newRecoveryBranch(); app.refresh(); end
        function openAdvanced(app,kind)
            title='物件'; if ismember(string(kind),["assist","quality"]), title='AI'; elseif ismember(string(kind),["semantic","detection","classification","anomaly"]), title='標記'; end
            pages=app.Handles.ToolTabs.Children; app.Handles.ToolTabs.SelectedTab=pages(find(contains(string({pages.Title}),title),1));
            if ismember(string(kind),["instance","keypoints","semantic","detection","classification","anomaly"]), app.Handles.DatasetTask.Value=char(kind); app.modeChanged(); end
        end
        function saveSession(app,file), app.assertIdle(); app.Data.saveSession(file); VIStudioHomeStateV16.remember('session',file); app.Recovery.resolve("saved"); app.newRecoveryBranch(); app.refresh(); end
        function configureAutosave(app,enabled,seconds)
            validateattributes(seconds,{'numeric'},{'scalar','finite','>=',1,'<=',3600});
            if ~isempty(app.AutosaveTimer) && isvalid(app.AutosaveTimer), stop(app.AutosaveTimer); delete(app.AutosaveTimer); end
            app.Handles.Autosave.Value=logical(enabled); app.Handles.AutosaveInterval.Value=seconds;
            app.AutosaveTimer=timer('ExecutionMode','fixedSpacing','Period',seconds,'BusyMode','drop', ...
                'Name','VIStudio V21 Labeler recovery','TimerFcn',@(~,~) app.autosaveTick());
            if enabled, start(app.AutosaveTimer); end
        end
        function file=saveRecovery(app)
            context=struct('CurrentIndex',app.CurrentIndex,'SelectedID',app.SelectedID);
            file=app.Recovery.write(app.Data,context);
            if strlength(file)>0
                app.Handles.RecoveryStatus.Text="已備份，尚未手動儲存 / Recovery saved; session still unsaved · "+string(datetime('now','Format','HH:mm:ss'));
            end
        end
        function entries=availableRecoveries(app), entries=VIStudioRecoveryV8.list(app.Recovery.Root); end
        function restoreRecovery(app,file)
            app.assertIdle(); [state,context]=VIStudioRecoveryV8.read(file,app.Recovery.Root);
            assert(isstruct(context) && all(isfield(context,{'CurrentIndex','SelectedID'})), ...
                'VIStudioV15:RecoveryContext','Invalid recovery context.');
            validateattributes(context.CurrentIndex,{'numeric'},{'scalar','finite','integer','positive'});
            app.Data.restoreRecovery(state);
            app.newRecoveryBranch(); app.CurrentIndex=max(1,min(numel(app.Data.Files),context.CurrentIndex));
            app.SelectedID=string(context.SelectedID); app.refresh();
            app.saveRecovery();
            VIStudioRecoveryV8.resolveSnapshot(file,app.Recovery.Root,'recovered');
            app.Handles.RecoveryStatus.Text='已恢復，請手動儲存 / Recovered; please save session';
        end
        function file=currentFile(app)
            file=""; if ~isempty(app.Data.Files), file=app.Data.Files(app.CurrentIndex); end
        end
        function selectImage(app,index)
            app.assertIdle(); validateattributes(index,{'numeric'},{'scalar','integer','>=',1,'<=',numel(app.Data.Files)});
            if app.CurrentIndex~=index, app.clearPrompts(); end
            app.CurrentIndex=index; app.SelectedID=""; app.refresh();
        end
        function addClass(app,name,color)
            if nargin<3, color=lines(1); end
            app.assertIdle(); app.Data.addClass(name,color); app.refresh(); app.Handles.Class.Value=char(string(name));
        end
        function renameClass(app,old,new), app.assertIdle(); app.Data.renameClass(old,new); app.refresh(); end
        function deleteClass(app,name,remove)
            if nargin<3, remove=false; end
            app.assertIdle(); app.Data.deleteClass(name,remove); app.refresh();
        end
        function id=paintStroke(app,vertices,erase)
            app.assertIdle(); if nargin<3, erase=false; end; validateattributes(erase,{'logical'},{'scalar'}); file=app.requireImage(); label=app.selectedClass(); info=imfinfo(file);
            stroke=app.Data.stroke(vertices,app.Handles.Radius.Value,[info(1).Height info(1).Width]); assert(any(stroke,'all'),'VIStudioV15:EmptyStroke','Stroke lies outside image.');
            rows=app.Data.current(file); row=find(rows.ID==app.SelectedID & rows.Type=="mask",1);
            if ~erase && ~isempty(row) && rows.Label(row)~=label, row=[]; end
            if erase
                assert(~isempty(row),'VIStudioV15:MaskSelection','Select a mask before erasing.'); mask=rows.Geometry{row} & ~stroke;
            elseif ~isempty(row), mask=rows.Geometry{row} | stroke; else, mask=stroke; end
            if isempty(row), app.SelectedID=app.Data.add(file,label,'mask',mask);
            elseif any(mask,'all'), app.Data.update(rows.ID(row),mask);
            else, app.Data.remove(rows.ID(row)); app.SelectedID=""; end
            id=app.SelectedID; app.refresh();
        end
        function id=addAnnotation(app,type,geometry,label)
            app.assertIdle(); if nargin<4, label=app.selectedClass(); end
            id=app.Data.add(app.requireImage(),label,type,geometry); app.SelectedID=id; app.refresh();
        end
        function updateAnnotation(app,id,geometry,label)
            app.assertIdle(); if nargin<4, app.Data.update(id,geometry); else, app.Data.update(id,geometry,label); end
            app.SelectedID=string(id); app.refresh();
        end
        function removeAnnotation(app,id)
            app.assertIdle(); if nargin<2, id=app.SelectedID; end
            app.Data.remove(id); app.SelectedID=""; app.refresh();
        end
        function undo(app), app.assertIdle(); app.Data.undo(); app.refresh(); end
        function redo(app), app.assertIdle(); app.Data.redo(); app.refresh(); end
        function acceptPredictions(app,selectedOnly)
            app.assertIdle(); if nargin<2, selectedOnly=false; end
            if selectedOnly
                assert(strlength(app.SelectedID)>0,'VIStudioV15:Annotation','Select an annotation first.');
                app.Data.accept(app.requireImage(),app.SelectedID);
            else, app.Data.accept(app.requireImage()); end
            app.refresh();
        end
        function rejectPredictions(app), app.assertIdle(); app.Data.reject(app.requireImage()); app.refresh(); end
        function markReviewed(app,value)
            app.assertIdle(); if nargin<2, value=true; end
            app.Data.markReviewed(app.requireImage(),logical(value)); app.refresh();
        end
        function setPrelabelModel(app,model,metadata,task,digest)
            app.assertIdle(); if nargin<5, digest="active-model"; end
            assert((string(task)=="semantic" && isa(model,'dlnetwork')) || VIStudioModelIOV8.matches(model,task),'VIStudioV15:PrelabelModel','Model type does not match task.');
            if string(task)=="semantic"
                VIStudioSemanticV13.validateClasses(metadata.SemanticClasses); names=string(metadata.SemanticClasses.Name(metadata.SemanticClasses.ID~=0)); app.Data.mergeClasses(names);
            elseif task=="classification"
                assert(isfield(metadata,'ClassNames') && ~isempty(metadata.ClassNames),'VIStudioV15:PrelabelClasses','Model class names are required.');
                app.Data.mergeClasses(metadata.ClassNames);
            elseif task=="detection"
                app.Data.mergeClasses(string(model.ClassNames));
            else
                app.Data.mergeClasses("defect");
            end
            app.Model=model; app.ModelMetadata=metadata; app.ModelTask=string(task); app.ModelDigest=string(digest);
            app.Handles.ModelTask.Value=char(task); app.Handles.DatasetTask.Value=char(task);
            app.Handles.ModelInfo.Text=string(task)+" · "+string(class(model)); app.refresh();
        end
        function loadPrelabelModel(app,file,task,variable)
            if nargin<4, variable=""; end
            if string(task)=="semantic", artifact=VIStudioSemanticV13.load(file); else, artifact=VIStudioModelIOV8.read(file,string(task),variable); end
            metadata=artifact.Metadata; if ~isfield(metadata,'ClassNames'), metadata.ClassNames=artifact.Classes; end
            app.setPrelabelModel(artifact.Model,metadata,string(task),artifact.Digest);
        end
        function count=prelabelCurrent(app,threshold)
            app.assertIdle(); if nargin<2, threshold=app.Handles.Threshold.Value; end
            app.Busy=true; app.refreshControls(); cleanup=onCleanup(@() app.finish());
            count=app.predictFile(app.requireImage(),threshold); app.refresh();
        end
        function count=prelabelAll(app,threshold,progress)
            app.assertIdle(); if nargin<2, threshold=app.Handles.Threshold.Value; end
            if nargin<3, progress=@(~,~) false; end
            app.requireImage(); app.Busy=true; app.refreshControls(); cleanup=onCleanup(@() app.finish()); count=0;
            for k=1:numel(app.Data.Files)
                if progress(k,numel(app.Data.Files)), break; end
                count=count+app.predictFile(app.Data.Files(k),threshold); drawnow;
            end
            app.refresh();
        end
        function [data,map]=exportDetection(app,file,convertShapes)
            app.assertIdle(); if nargin<3, convertShapes=false; end
            [data,map]=app.Data.exportDetection(file,convertShapes); app.LastExport=struct('Task',"detection",'Path',string(file));
        end
        function output=exportDataset(app,folder,task)
            app.assertIdle(); output=app.Data.exportDataset(folder,task); app.LastExport=struct('Task',string(task),'Path',output.Images);
        end
        function output=exportSemantic(app,folder,conflict)
            app.assertIdle(); if nargin<3, conflict=app.Handles.Conflict.Value; end
            output=app.Data.exportSemantic(folder,conflict); app.LastExport=struct('Task',"semantic",'Path',output.Path);
        end
        function filterImages(app,query,status)
            app.Handles.Search.Value=char(query); app.Handles.Filter.Value=char(status); app.refresh();
        end
        function setView(app,opacity,mode)
            app.Handles.Opacity.Value=opacity; app.Handles.View.Value=validatestring(mode,{'fill','outline','hidden'}); app.refresh();
        end
        function startInstance(app), app.assertIdle(); app.SelectedID=""; app.Handles.DatasetTask.Value='instance'; app.refresh(); end
        function id=mergeSelected(app,ids)
            app.assertIdle(); if nargin<2, selection=app.Handles.Records.Selection; if size(selection,2)==2, selection=unique(selection(:,1)); end; assert(~isempty(selection),'VIStudioV15:InstanceSelection','Select table rows.'); ids=app.Handles.Records.Data.ID(selection); end
            id=app.Data.mergeInstances(ids); app.SelectedID=id; app.refresh();
        end
        function ids=splitSelected(app)
            app.assertIdle(); ids=app.Data.splitInstance(app.SelectedID); app.SelectedID=ids(1); app.refresh();
        end
        function setPoseTemplate(app,template)
            if ~isfield(template,'Name'), template.Name="custom"; end; g=VIStudioPoseV15.geometry(template,nan(numel(template.Names),2),zeros(numel(template.Names),1),[1 1 2 2]); VIStudioPoseV15.validate(g,[2 2]); app.CustomPoseTemplate=template;
        end
        function id=addPose(app,geometry,label,source,score,digest)
            app.assertIdle(); if nargin<3, label=app.selectedClass(); end; if nargin<4, source="manual"; end; if nargin<5, score=NaN; end; if nargin<6, digest=""; end
            id=app.Data.addKeypoints(app.requireImage(),label,geometry,source,score,digest); app.SelectedID=id; app.refresh();
        end
        function output=exportStructured(app,folder,task)
            app.assertIdle(); output=app.Data.exportStructured(folder,task); app.LastExport=struct('Task',string(task),'Path',output.Path);
        end
        function setSAM(app,model)
            app.assertIdle(); assert(ismethod(model,'extractEmbeddings') && ismethod(model,'segmentObjectsFromEmbeddings'),'VIStudioV15:SAMModel','Use a native SAM object.'); app.Sam=model; app.SamStatus="LOADED_NOT_RUN"; app.Handles.SamStatus.Text='已載入，尚未推論 / Loaded; not run';
        end
        function id=suggestSAM(app,foreground,background,box)
            app.assertIdle(); assert(~isempty(app.Sam),'VIStudioV15:SAMUnavailable','Load or initialize SAM first.'); image=VIStudioData.readImage(app.requireImage(),[]); [mask,evidence]=VIStudioTaskModelsV15.assist(app.Sam,image,foreground,background,box);
            id=app.Data.add(app.currentFile(),app.selectedClass(),'mask',mask,'model',evidence.Score,"SAM / "+string(class(app.Sam))); app.SelectedID=id; app.SamStatus="INFERENCE_VERIFIED"; app.refresh(); app.Handles.SamStatus.Text='SAM 候選待覆核 / SAM candidate needs review';
        end
        function report=analyzeQuality(app)
            report=VIStudioAnnotationQualityV15.analyze(app.Data,app.Handles.MinArea.Value,app.Handles.DuplicateIoU.Value); app.QualityReport=report; app.showQuality(report);
        end
        function report=compareReviewer(app,file)
            other=VIStudioAnnotationDataV15; other.loadSession(file); report=VIStudioAnnotationQualityV15.compare(app.Data,other); app.QualityReport=report; app.showQuality(report);
        end
        function quickClass(app,index)
            validateattributes(index,{'numeric'},{'scalar','integer','positive','<=',height(app.Data.Classes)}); app.Handles.Class.Value=char(app.Data.Classes.Name(index)); app.Handles.Status.Text="目前類別 / Active class: "+app.Data.Classes.Name(index);
        end
        function reviewAndNext(app), app.markReviewed(true); app.nextPending(); end
        function batchCandidates(app,files,decision,ids)
            app.assertIdle(); if nargin<4, app.Data.reviewCandidates(files,decision); else, app.Data.reviewCandidates(files,decision,ids); end; app.refresh();
        end
        function selectAnnotation(app,id)
            rows=app.Data.current(app.requireImage()); assert(any(rows.ID==string(id)),'VIStudioV15:Annotation','Choose a current annotation.'); app.SelectedID=string(id); app.refresh();
        end
        function editPose(app,operation,varargin)
            rows=app.Data.current(app.requireImage()); row=find(rows.ID==app.SelectedID & rows.Type=="keypoints",1); assert(~isempty(row),'VIStudioV15:PoseSelection','Select a pose.'); g=rows.Geometry{row};
            switch string(operation)
                case "swap", g=VIStudioPoseV15.swap(g,varargin{1},varargin{2});
                case "mirror", pairs=VIStudioPoseV15.leftRightPairs(g.Names); g=VIStudioPoseV15.mirror(g,pairs);
                case "edges", g.Edges=double(varargin{1});
                otherwise, error('VIStudioV15:PoseOperation','Unknown pose operation.');
            end
            app.updateAnnotation(app.SelectedID,g);
        end
        function file=exportCoco(app,folder,task)
            app.assertIdle(); staging=tempname; cleanup=onCleanup(@() app.removeStaging(staging)); output=app.Data.exportStructured(staging,task); data=VIStudioStructuredV15.read(output.Path); file=VIStudioCocoV15.export(data,folder);
        end
        function importCoco(app,file,imageRoot,folder,task,mapping)
            output=VIStudioCocoV15.import(file,imageRoot,folder,task,mapping); app.importStructured(output.Path); for k=1:numel(app.Data.Files), app.Data.markReviewed(app.Data.Files(k),false); end; app.openAdvanced(task); app.refresh();
        end
        function setLanguage(app,language)
            app.Language=validatestring(language,{'bilingual','zh','en'});
            for k=1:size(app.Translations,1)
                object=app.Translations{k,1}; field=app.Translations{k,2};
                if isvalid(object) && isequal(object.(field),app.Translations{k,4})
                    value=VIStudioToolsV3.translate(app.Translations{k,3},app.Language); object.(field)=value; app.Translations{k,4}=value;
                end
            end
            app.Handles.Language.Value=app.Language;
        end
        function sendToTraining(app)
            app.assertIdle(); assert(~isempty(app.SendCallback) && ~isempty(app.LastExport),'VIStudioV15:TrainingExport','Export reviewed data from an integrated labeler first.');
            app.SendCallback(app.LastExport);
        end
        function closed=requestClose(app)
            closed=false; if app.Busy, return; end
            if app.confirmDiscard(), closed=true; delete(app); end
        end
    end
    methods (Access=private)
        function newRecoveryBranch(app), app.Recovery=VIStudioRecoveryV8(app.Recovery.Root); end
        function autosaveTick(app)
            if app.Busy || app.Rendering || ~app.Data.Dirty || app.Recovery.LastRevision==app.Data.Revision, return; end
            try, app.saveRecovery(); catch err
                if isvalid(app.Handles.RecoveryStatus), app.Handles.RecoveryStatus.Text="備份失敗 / Backup failed: "+string(err.message); end
            end
        end
        function pickRecovery(app)
            entries=app.availableRecoveries();
            if isempty(entries), uialert(app.UIFigure,'沒有通過完整性驗證的恢復資料 / No verified recovery snapshots.','Recovery'); return; end
            dialog=uifigure('Name','恢復未儲存標註 / Recover unsaved annotations','Position',[180 180 950 380],'WindowStyle','modal');
            grid=uigridlayout(dialog,[2 1],'RowHeight',{'1x',40});
            table=uitable(grid,'Data',entries,'SelectionType','row'); table.Selection=1;
            uibutton(grid,'Text','恢復選取工作 / Recover selected session','ButtonPushedFcn',@(~,~) restore());
            function restore()
                selected=table.Selection;
                if isempty(selected), return; end
                file=entries.Snapshot(selected(1)); delete(dialog); app.restoreRecovery(file);
            end
        end

        function buildUI(app)
            app.UIFigure=uifigure('Name','VIStudio Labeler V21 | 多類別標記工作室','Position',[50 50 1500 920],'Visible','off', ...
                'CloseRequestFcn',@(~,~) app.close(),'WindowKeyPressFcn',@(~,e) app.key(e));
            root=uigridlayout(app.UIFigure,[4 3],'RowHeight',{44,'1x',36,32},'ColumnWidth',{230,'1x',330});
            bar=uigridlayout(root,[1 7],'Padding',[0 0 0 0]); bar.Layout.Column=[1 3];
            uibutton(bar,'Text','載入影像 / Load images','ButtonPushedFcn',@(~,~) app.action(@() app.pickFolder()));
            uibutton(bar,'Text','開啟工作 / Open session','ButtonPushedFcn',@(~,~) app.action(@() app.pickSession()));
            uibutton(bar,'Text','另存工作 / Save session','ButtonPushedFcn',@(~,~) app.action(@() app.pickSave()));
            app.Handles.Undo=uibutton(bar,'Text','復原 / Undo','ButtonPushedFcn',@(~,~) app.action(@() app.undo()));
            app.Handles.Redo=uibutton(bar,'Text','重做 / Redo','ButtonPushedFcn',@(~,~) app.action(@() app.redo()));
            uibutton(bar,'Text','匯出資料 / Export','ButtonPushedFcn',@(~,~) app.action(@() app.pickExport()));
            app.Handles.Language=uidropdown(bar,'Items',{'雙語 / Bilingual','中文 / Chinese','英文 / English'},'ItemsData',{'bilingual','zh','en'},'Value','bilingual','ValueChangedFcn',@(~,~) app.setLanguage(app.Handles.Language.Value));
            list=uigridlayout(root,[4 1],'RowHeight',{32,32,'1x',130}); list.Layout.Row=2; list.Layout.Column=1;
            app.Handles.Search=uieditfield(list,'text','Placeholder','搜尋檔名 / Search filename','ValueChangedFcn',@(~,~) app.refresh());
            app.Handles.Filter=uidropdown(list,'Items',{'全部 / All','待覆核 / Pending','已覆核 / Reviewed'},'ItemsData',{'all','pending','reviewed'},'ValueChangedFcn',@(~,~) app.refresh());
            app.Handles.ImageList=uilistbox(list,'Items',{},'ValueChangedFcn',@(~,~) app.action(@() app.selectImage(str2double(app.Handles.ImageList.Value)))); app.Handles.Thumbnail=uiaxes(list);
            body=uigridlayout(root,[4 1],'RowHeight',{36,'1x',30,150}); body.Layout.Row=2; body.Layout.Column=2;
            nav=uigridlayout(body,[1 4],'ColumnWidth',{105,'1x',105,145},'Padding',[0 0 0 0]);
            uibutton(nav,'Text','上一張 / Prev','ButtonPushedFcn',@(~,~) app.action(@() app.navigate(-1)));
            app.Handles.Files=uidropdown(nav,'Items',{'(none)'},'ValueChangedFcn',@(~,~) app.action(@() app.selectImage(str2double(app.Handles.Files.Value))));
            uibutton(nav,'Text','下一張 / Next','ButtonPushedFcn',@(~,~) app.action(@() app.navigate(1)));
            app.Handles.Review=uibutton(nav,'Text','完成覆核 / Reviewed','BackgroundColor',[.08 .48 .36],'FontColor',[1 1 1],'ButtonPushedFcn',@(~,~) app.action(@() app.markReviewed()));
            app.Handles.Axes=uiaxes(body); app.Handles.ImageInfo=uilabel(body,'Text','尚無影像 / No images'); app.Handles.Records=uitable(body,'CellSelectionCallback',@(~,e) app.selectRecord(e));
            tabs=uitabgroup(root); tabs.Layout.Row=2; tabs.Layout.Column=3; app.Handles.ToolTabs=tabs;
            page=uitab(tabs,'Title','標記 / Edit'); settings=uigridlayout(page,[18 2],'ColumnWidth',{'1x','1x'},'RowHeight',repmat({32},1,18),'Scrollable','on');
            h=uilabel(settings,'Text','資料任務 / Dataset task'); app.Handles.DatasetTask=uidropdown(settings,'Items',{'instance','keypoints','semantic','detection','classification','anomaly'},'Value','instance','ValueChangedFcn',@(~,~) app.refresh());
            app.Handles.Class=uidropdown(settings,'Items',{'(none)'}); app.Handles.Class.Layout.Column=[1 2];
            app.Handles.Name=uieditfield(settings,'text','Placeholder','類別名稱 / Class name'); app.Handles.Name.Layout.Column=[1 2];
            uibutton(settings,'Text','新增 / Add','ButtonPushedFcn',@(~,~) app.action(@() app.addClass(app.Handles.Name.Value)));
            uibutton(settings,'Text','改名 / Rename','ButtonPushedFcn',@(~,~) app.action(@() app.renameClass(app.selectedClass(),app.Handles.Name.Value)));
            uibutton(settings,'Text','刪除類別 / Delete class','ButtonPushedFcn',@(~,~) app.action(@() app.uiDeleteClass()));
            uibutton(settings,'Text','忽略區 / Ignore','ButtonPushedFcn',@(~,~) app.action(@() app.selectIgnore()));
            uilabel(settings,'Text','工具 / Tool'); app.Handles.Tool=uidropdown(settings,'Items',{'矩形 / Rectangle','多邊形 / Polygon','遮罩 / Mask','畫筆 / Brush','橡皮擦 / Eraser'},'ItemsData',{'rectangle','polygon','mask','brush','eraser'},'Value','mask');
            uilabel(settings,'Text','半徑 px / Radius'); app.Handles.Radius=uieditfield(settings,'numeric','Value',8,'Limits',[1 200]);
            h=uibutton(settings,'Text','開始繪製 / Draw (R/P/M/B/E)','ButtonPushedFcn',@(~,~) app.action(@() app.draw())); h.Layout.Column=[1 2];
            uibutton(settings,'Text','刪除所選 / Delete','ButtonPushedFcn',@(~,~) app.action(@() app.removeAnnotation()));
            uibutton(settings,'Text','變更類別 / Relabel','ButtonPushedFcn',@(~,~) app.action(@() app.relabel()));
            app.Handles.AssignImage=uibutton(settings,'Text','整張分類 / Image class','ButtonPushedFcn',@(~,~) app.action(@() app.addAnnotation('image',[]))); app.Handles.AssignImage.Layout.Column=[1 2];
            uilabel(settings,'Text','透明度 / Opacity'); app.Handles.Opacity=uieditfield(settings,'numeric','Value',.3,'Limits',[0 1],'ValueChangedFcn',@(~,~) app.refresh());
            uilabel(settings,'Text','顯示 / View'); app.Handles.View=uidropdown(settings,'Items',{'填色 / Fill','輪廓 / Outline','原圖 / Image'},'ItemsData',{'fill','outline','hidden'},'ValueChangedFcn',@(~,~) app.refresh());
            uilabel(settings,'Text','跨類別重疊 / Conflicts'); app.Handles.Conflict=uidropdown(settings,'Items',{'拒絕匯出 / Error','重疊忽略 / Ignore','後標優先 / Last'},'ItemsData',{'error','ignore','last'});
            app.Handles.Convert=uicheckbox(settings,'Text','框轉換 / To boxes'); app.Handles.Convert.Layout.Column=[1 2];
            h=uibutton(settings,'Text','匯出並送回訓練 / Export & train','ButtonPushedFcn',@(~,~) app.action(@() app.exportAndSend())); h.Layout.Column=[1 2];
            h=uilabel(settings,'Text','未標區域為背景；__ignore__ 不參與損失與評估 / Unpainted pixels are background; Ignore is excluded','WordWrap','on'); h.Layout.Column=[1 2]; h.Layout.Row=[16 18];
            page=uitab(tabs,'Title','模型與覆核 / Review'); settings=uigridlayout(page,[12 2],'RowHeight',repmat({34},1,12),'Scrollable','on');
            app.Handles.ModelTask=uidropdown(settings,'Items',{'semantic','detection','classification','anomaly'});
            uibutton(settings,'Text','載入 MAT / Load MAT','ButtonPushedFcn',@(~,~) app.action(@() app.pickModel()));
            app.Handles.ModelInfo=uilabel(settings,'Text','尚無模型 / No model','WordWrap','on'); app.Handles.ModelInfo.Layout.Column=[1 2];
            uilabel(settings,'Text','候選門檻 / Threshold'); app.Handles.Threshold=uieditfield(settings,'numeric','Value',.5,'Limits',[0 1]);
            app.Handles.Prelabel=uibutton(settings,'Text','本張預標 / Current','ButtonPushedFcn',@(~,~) app.action(@() app.prelabelCurrent()));
            app.Handles.PrelabelAll=uibutton(settings,'Text','全部預標 / All','ButtonPushedFcn',@(~,~) app.action(@() app.uiPrelabelAll()));
            uibutton(settings,'Text','接受所選 / Accept selected','ButtonPushedFcn',@(~,~) app.action(@() app.acceptPredictions(true)));
            uibutton(settings,'Text','接受本張 / Accept image','ButtonPushedFcn',@(~,~) app.action(@() app.acceptPredictions()));
            h=uibutton(settings,'Text','拒絕待確認標記 / Reject pending','ButtonPushedFcn',@(~,~) app.action(@() app.rejectPredictions())); h.Layout.Column=[1 2];
            h=uibutton(settings,'Text','下一張待覆核 / Next pending','ButtonPushedFcn',@(~,~) app.action(@() app.nextPending())); h.Layout.Column=[1 2];
            h=uilabel(settings,'Text','候選必須經人工接受或修改，才能完成覆核並匯出 / Review all candidates before exporting','WordWrap','on'); h.Layout.Column=[1 2]; h.Layout.Row=[8 11];
            bar=uigridlayout(root,[1 5],'ColumnWidth',{130,65,145,145,'1x'},'Padding',[0 0 0 0]); bar.Layout.Row=3; bar.Layout.Column=[1 3];
            app.Handles.Autosave=uicheckbox(bar,'Text','自動備份 / Autosave','Value',true,'ValueChangedFcn',@(~,~) app.configureAutosave(app.Handles.Autosave.Value,app.Handles.AutosaveInterval.Value));
            app.Handles.AutosaveInterval=uieditfield(bar,'numeric','Value',60,'Limits',[1 3600],'ValueChangedFcn',@(~,~) app.configureAutosave(app.Handles.Autosave.Value,app.Handles.AutosaveInterval.Value));
            uibutton(bar,'Text','立即備份 / Backup','ButtonPushedFcn',@(~,~) app.action(@() app.saveRecovery())); uibutton(bar,'Text','恢復工作 / Recover','ButtonPushedFcn',@(~,~) app.action(@() app.pickRecovery())); app.Handles.RecoveryStatus=uilabel(bar,'Text','獨立 V21 備份 / Separate V21 recovery');
            app.Handles.Status=uilabel(root,'Text','就緒 / Ready','WordWrap','on'); app.Handles.Status.Layout.Row=4; app.Handles.Status.Layout.Column=[1 3];
        end
        function buildAdvancedTools(app)
            page=uitab(app.Handles.ToolTabs,'Title','物件與點位 / Objects'); g=uigridlayout(page,[9 2],'RowHeight',{34,34,34,34,34,'1x',34,34,40},'ColumnWidth',{'1x','1x'});
            uibutton(g,'Text','新增實例 / New object','ButtonPushedFcn',@(~,~) app.startInstance()); uibutton(g,'Text','拆分 / Split','ButtonPushedFcn',@(~,~) app.action(@() app.splitSelected()));
            h=uibutton(g,'Text','合併選取列 / Merge selected rows','ButtonPushedFcn',@(~,~) app.action(@() app.mergeSelected())); h.Layout.Column=[1 2];
            app.Handles.PoseTemplate=uidropdown(g,'Items',{'industrial','human'},'ValueChangedFcn',@(~,~) app.resetPoseTemplate()); uibutton(g,'Text','建立點位 / New pose','ButtonPushedFcn',@(~,~) app.action(@() app.createPose()));
            h=uilabel(g,'Text','點位表：0未知、1遮擋、2可見 / 0 unknown, 1 occluded, 2 visible','WordWrap','on'); h.Layout.Column=[1 2];
            h=uibutton(g,'Text','載入範本 / Load','ButtonPushedFcn',@(~,~) app.action(@() app.pickPoseTemplate())); h.Layout.Row=5; h.Layout.Column=1; h=uibutton(g,'Text','另存範本 / Save','ButtonPushedFcn',@(~,~) app.action(@() app.savePoseTemplate())); h.Layout.Row=5; h.Layout.Column=2;
            app.Handles.Points=uitable(g,'ColumnName',{'Name','X','Y','V'},'ColumnWidth',{112,52,52,55},'RowName',{},'ColumnEditable',[false true true true],'CellEditCallback',@(~,~) app.action(@() app.applyPoseTable())); app.Handles.Points.Layout.Row=6; app.Handles.Points.Layout.Column=[1 2];
            app.Handles.PointIndex=uieditfield(g,'numeric','Value',1,'Limits',[1 Inf],'Tooltip','點位序號 / Point index'); uibutton(g,'Text','點選位置 / Place point','ButtonPushedFcn',@(~,~) app.action(@() app.placePosePoint()));
            h=uibutton(g,'Text','點位距離與角度 / Distances & angles','ButtonPushedFcn',@(~,~) app.action(@() app.showPoseMeasurements())); h.Layout.Column=[1 2];
            h=uilabel(g,'Text','先用橡皮擦切開，再拆成連通實例 / Erase a gap, then split components','WordWrap','on'); h.Layout.Column=[1 2];
            page=uitab(app.Handles.ToolTabs,'Title','AI與品質 / AI & QA'); g=uigridlayout(page,[13 2],'RowHeight',repmat({34},1,13),'Scrollable','on');
            app.Handles.SamChoice=uidropdown(g,'Items',{'sam2-tiny','sam-base'}); uibutton(g,'Text','檢查 SAM / Initialize','ButtonPushedFcn',@(~,~) app.action(@() app.initializeSAM()));
            h=uibutton(g,'Text','載入 SAM MAT / Load SAM','ButtonPushedFcn',@(~,~) app.action(@() app.pickSAM())); h.Layout.Column=[1 2];
            app.Handles.Foreground=uitable(g,'Data',zeros(0,2),'ColumnName',{'FG X','FG Y'},'ColumnWidth',{55,55},'RowName',{},'ColumnEditable',[true true]); app.Handles.Foreground.Layout.Row=[3 4];
            app.Handles.Background=uitable(g,'Data',zeros(0,2),'ColumnName',{'BG X','BG Y'},'ColumnWidth',{55,55},'RowName',{},'ColumnEditable',[true true]); app.Handles.Background.Layout.Row=[3 4]; app.Handles.Background.Layout.Column=2;
            uibutton(g,'Text','加前景點 / Add FG','ButtonPushedFcn',@(~,~) app.action(@() app.capturePrompt(true))); uibutton(g,'Text','加背景點 / Add BG','ButtonPushedFcn',@(~,~) app.action(@() app.capturePrompt(false)));
            app.Handles.SamBox=uieditfield(g,'text','Placeholder','x y w h (optional)'); uibutton(g,'Text','產生候選 / Suggest','ButtonPushedFcn',@(~,~) app.action(@() app.suggestFromUI()));
            app.Handles.SamStatus=uilabel(g,'Text','NOT_CHECKED / 尚未檢查','WordWrap','on'); app.Handles.SamStatus.Layout.Column=[1 2];
            uilabel(g,'Text','最小區域 px / Min area'); app.Handles.MinArea=uieditfield(g,'numeric','Value',4,'Limits',[0 Inf]);
            uilabel(g,'Text','重複 IoU / Duplicate'); app.Handles.DuplicateIoU=uieditfield(g,'numeric','Value',.95,'Limits',[.01 1]);
            uibutton(g,'Text','品質分析 / Analyze QA','ButtonPushedFcn',@(~,~) app.action(@() app.analyzeQuality())); uibutton(g,'Text','比對覆核者 / Compare','ButtonPushedFcn',@(~,~) app.action(@() app.pickReviewer()));
            h=uibutton(g,'Text','匯出品質報告 / Export QA','ButtonPushedFcn',@(~,~) app.action(@() app.exportQuality())); h.Layout.Column=[1 2];
        end
        function buildProductivity(app)
            page=uitab(app.Handles.ToolTabs,'Title','效率與交換 / Workflow'); g=uigridlayout(page,[15 2],'RowHeight',repmat({36},1,15),'Scrollable','on');
            h=uilabel(g,'Text','1–9 類別 · N 待覆核 · F 完成並下一張 · Q 接受本張 · X 拒絕待確認 · K 放點 / Class, pending, review, accept, reject, point','WordWrap','on'); h.Layout.Column=[1 2]; h.Layout.Row=[1 3];
            uibutton(g,'Text','完成並下一張 / Done + next','ButtonPushedFcn',@(~,~) app.action(@() app.reviewAndNext())); uibutton(g,'Text','下一待覆核 / Pending','ButtonPushedFcn',@(~,~) app.action(@() app.nextPending()));
            uibutton(g,'Text','批次接受 / Batch accept','ButtonPushedFcn',@(~,~) app.action(@() app.pickBatch('accept'))); uibutton(g,'Text','批次拒絕 / Batch reject','ButtonPushedFcn',@(~,~) app.action(@() app.pickBatch('reject')));
            app.Handles.Continuous=uicheckbox(g,'Text','連續放點 / Continuous points'); app.Handles.Continuous.Layout.Column=[1 2];
            app.Handles.SwapA=uieditfield(g,'numeric','Value',1,'Limits',[1 Inf],'Tooltip','點位 A / Point A'); app.Handles.SwapB=uieditfield(g,'numeric','Value',2,'Limits',[1 Inf],'Tooltip','點位 B / Point B');
            uibutton(g,'Text','交換兩點 / Swap points','ButtonPushedFcn',@(~,~) app.action(@() app.editPose('swap',app.Handles.SwapA.Value,app.Handles.SwapB.Value))); uibutton(g,'Text','鏡像＋左右交換 / Mirror','ButtonPushedFcn',@(~,~) app.action(@() app.editPose('mirror')));
            uibutton(g,'Text','骨架編輯 / Edit edges','ButtonPushedFcn',@(~,~) app.action(@() app.editEdgesUI())); uibutton(g,'Text','鏡像範本 / Mirror template','ButtonPushedFcn',@(~,~) app.action(@() app.mirrorTemplate()));
            uibutton(g,'Text','COCO 匯入 / Import','ButtonPushedFcn',@(~,~) app.action(@() app.importCocoUI())); uibutton(g,'Text','COCO 匯出 / Export','ButtonPushedFcn',@(~,~) app.action(@() app.exportCocoUI()));
            h=uilabel(g,'Text','批次操作先選影像；不自動完成整張覆核。鏡像以物件框中心反射，並依 left_/right_ 或 _left/_right 交換左右點。','WordWrap','on'); h.Layout.Column=[1 2]; h.Layout.Row=[11 15];
        end
        function pickBatch(app,decision)
            [rows,ok]=listdlg('ListString',cellstr(app.Data.Files),'SelectionMode','multiple','PromptString','選擇本次處理影像 / Choose images for this batch'); if ok, app.batchCandidates(app.Data.Files(rows),decision); end
        end
        function mirrorTemplate(app)
            t=app.poseTemplate(); pairs=VIStudioPoseV15.leftRightPairs(t.Names); order=1:numel(t.Names); for k=1:size(pairs,1), order(pairs(k,:))=order(fliplr(pairs(k,:))); end; t.Names=t.Names(order); t.Edges=reshape(order(t.Edges),size(t.Edges)); t.Name=string(t.Name)+"_mirrored"; app.setPoseTemplate(t); app.Handles.Status.Text='鏡像點位順序範本已套用；既有標記不變 / Mirrored template applies to new poses';
        end
        function editEdgesUI(app)
            rows=app.Data.current(app.requireImage()); row=find(rows.ID==app.SelectedID & rows.Type=="keypoints",1); assert(~isempty(row),'VIStudioV15:PoseSelection','Select a pose.'); selected=app.SelectedID; p=rows.Geometry{row};
            fig=uifigure('Name','骨架編輯 / Skeleton editor','Position',[200 160 650 480]); g=uigridlayout(fig,[4 1],'RowHeight',{60,'1x',32,40}); uilabel(g,'Text',strjoin(string((1:numel(p.Names))')+": "+p.Names," · "),'WordWrap','on'); t=uitable(g,'Data',p.Edges,'ColumnName',{'From index','To index'},'ColumnEditable',[true true]);
            bar=uigridlayout(g,[1 2]); uibutton(bar,'Text','新增連線 / Add edge','ButtonPushedFcn',@(~,~) addEdge()); uibutton(bar,'Text','刪除所選 / Delete selected','ButtonPushedFcn',@(~,~) removeEdge()); uibutton(g,'Text','套用至所選骨架與新範本 / Apply','ButtonPushedFcn',@(~,~) apply());
            function addEdge(), t.Data(end+1,:)=[1 min(2,numel(p.Names))]; end
            function removeEdge(), r=t.Selection; if size(r,2)==2, r=unique(r(:,1)); end; t.Data(r,:)=[]; end
            function apply()
                try
                    assert(app.SelectedID==selected,'VIStudioV15:PoseSelection','Selection changed; reopen the editor.'); app.editPose('edges',t.Data); template=struct('Name',"edited",'Names',p.Names,'Edges',t.Data); app.setPoseTemplate(template); delete(fig);
                catch err, uialert(fig,err.message,'骨架 / Skeleton'); end
            end
        end
        function importCocoUI(app)
            [f,p]=uigetfile('*.json'); if isequal(f,0), return; end; file=fullfile(p,f); preview=VIStudioCocoV15.inspect(file); task=app.Handles.DatasetTask.Value; assert(ismember(task,{'instance','keypoints'}),'VIStudioV15:COCOTask','Choose instance or keypoints first.');
            fig=uifigure('Name','COCO 對應預覽 / Mapping preview','Position',[150 150 850 450]); g=uigridlayout(fig,[3 1],'RowHeight',{60,'1x',40}); uilabel(g,'Text',sprintf('%d images / %d annotations · 編輯 TargetClass；點位順序依 Keypoints，不自動重排。匯入後需人工覆核。',preview.Images,preview.Annotations),'WordWrap','on'); t=uitable(g,'Data',preview.Categories,'ColumnEditable',[false false true false]); uibutton(g,'Text','選影像根目錄與新資料夾 / Import','ButtonPushedFcn',@(~,~) finish());
            function finish()
                try
                    imageRoot=uigetdir(p); if isequal(imageRoot,0), return; end; parent=uigetdir(pwd); if isequal(parent,0), return; end; app.importCoco(file,imageRoot,tempname(parent),task,t.Data); delete(fig);
                catch err, uialert(fig,err.message,'COCO'); end
            end
        end
        function exportCocoUI(app), parent=uigetdir(pwd); if ~isequal(parent,0), file=app.exportCoco(tempname(parent),app.Handles.DatasetTask.Value); app.Handles.Status.Text="COCO: "+file; end, end
        function removeStaging(~,folder), if isfolder(folder) && startsWith(string(folder),string(tempdir)), rmdir(folder,'s'); end, end
        function syncPoseTable(app)
            if ~isfield(app.Handles,'Points'), return; end; rows=app.Data.current(app.currentFile()); row=find(rows.ID==app.SelectedID & rows.Type=="keypoints",1); if isempty(row), app.Handles.Points.Data=table(); return; end; p=rows.Geometry{row}; app.Handles.Points.Data=table(p.Names,p.XY(:,1),p.XY(:,2),p.Visibility,'VariableNames',{'Name','X','Y','Visibility'});
        end
        function resetPoseTemplate(app), app.CustomPoseTemplate=[]; end
        function t=poseTemplate(app), t=app.CustomPoseTemplate; if isempty(t), t=VIStudioPoseV15.template(app.Handles.PoseTemplate.Value); end, end
        function pickPoseTemplate(app), [f,p]=uigetfile('*.mat'); if ~isequal(f,0), loaded=load(fullfile(p,f),'template'); app.setPoseTemplate(loaded.template); end, end
        function savePoseTemplate(app), [f,p]=uiputfile('*.mat'); if ~isequal(f,0), file=fullfile(p,f); assert(~isfile(file),'VIStudioV15:FileExists','Choose a new template file.'); template=app.poseTemplate(); save(file,'template'); end, end
        function createPose(app)
            app.requireImage(); t=app.poseTemplate(); info=imfinfo(app.currentFile()); g=VIStudioPoseV15.geometry(t,nan(numel(t.Names),2),zeros(numel(t.Names),1),[1 1 info.Width info.Height]); app.addPose(g);
        end
        function applyPoseTable(app)
            rows=app.Data.current(app.currentFile()); row=find(rows.ID==app.SelectedID & rows.Type=="keypoints",1); assert(~isempty(row),'VIStudioV15:PoseSelection','Select a pose.'); p=rows.Geometry{row}; table=app.Handles.Points.Data; p.XY=[table.X table.Y]; p.Visibility=table.Visibility; p.XY(p.Visibility==0,:)=NaN;
            try, app.updateAnnotation(app.SelectedID,p); catch err, app.syncPoseTable(); rethrow(err); end
        end
        function movePosePoint(app,id,index,position)
            if app.Rendering || app.Busy, return; end; rows=app.Data.current(app.currentFile()); row=find(rows.ID==id,1); if isempty(row), return; end; p=rows.Geometry{row}; p.XY(index,:)=position; p.Visibility(index)=2; app.action(@() app.updateAnnotation(id,p));
        end
        function placePosePoint(app)
            while true
                rows=app.Data.current(app.requireImage()); row=find(rows.ID==app.SelectedID & rows.Type=="keypoints",1); assert(~isempty(row),'VIStudioV15:PoseSelection','Select a pose.'); p=rows.Geometry{row}; id=app.SelectedID; file=app.currentFile(); index=app.Handles.PointIndex.Value;
                validateattributes(index,{'numeric'},{'scalar','integer','>=',1,'<=',numel(p.Names)}); roi=drawpoint(app.Handles.Axes); if ~isvalid(roi), return; end; position=roi.Position; delete(roi); if isempty(position), return; end
                assert(app.SelectedID==id && app.currentFile()==file,'VIStudioV15:PoseSelection','Selection changed during point placement.'); p.XY(index,:)=position; p.Visibility(index)=2; app.updateAnnotation(id,p);
                if index>=numel(p.Names), return; end; app.Handles.PointIndex.Value=index+1; if ~app.Handles.Continuous.Value, return; end
            end
        end
        function showPoseMeasurements(app)
            rows=app.Data.current(app.requireImage()); row=find(rows.ID==app.SelectedID & rows.Type=="keypoints",1); assert(~isempty(row),'VIStudioV15:PoseSelection','Select a pose.'); fig=uifigure('Name','點位量測 / Pose measurements','Position',[150 150 680 400]); grid=uigridlayout(fig,[2 1],'RowHeight',{35,'1x'}); uilabel(grid,'Text','影像像素與角度；不代表已完成毫米校正 / Pixels and image angles'); uitable(grid,'Data',VIStudioPoseV15.measure(rows.Geometry{row}));
        end
        function initializeSAM(app)
            o=VIStudioTaskModelsV15.defaults('assist'); o.Model=string(app.Handles.SamChoice.Value); [model,status]=VIStudioTaskModelsV15.create(o); app.SamStatus=status.State; app.Handles.SamStatus.Text=status.State+" · "+status.Message; if ~isempty(model), app.setSAM(model); end
        end
        function pickSAM(app), [f,p]=uigetfile('*.mat'); if ~isequal(f,0), a=VIStudioTaskModelsV15.load(fullfile(p,f),'assist'); app.setSAM(a.Model); end, end
        function clearPrompts(app)
            if isfield(app.Handles,'Foreground'), app.Handles.Foreground.Data=zeros(0,2); app.Handles.Background.Data=zeros(0,2); app.Handles.SamBox.Value=''; end
        end
        function capturePrompt(app,foreground)
            app.requireImage(); roi=drawpoint(app.Handles.Axes); position=roi.Position; delete(roi); if isempty(position), return; end
            if foreground, app.Handles.Foreground.Data=[app.Handles.Foreground.Data;position]; else, app.Handles.Background.Data=[app.Handles.Background.Data;position]; end
        end
        function suggestFromUI(app)
            box=sscanf(strrep(app.Handles.SamBox.Value,',',' '),'%f')'; if ~isempty(box), assert(numel(box)==4,'VIStudioV15:Prompt','Box requires x y w h.'); end; app.suggestSAM(app.Handles.Foreground.Data,app.Handles.Background.Data,box);
        end
        function showQuality(app,report)
            if ~isempty(app.QualityFigure) && isvalid(app.QualityFigure), delete(app.QualityFigure); end
            app.QualityFigure=uifigure('Name','標記品質 / Annotation quality','Position',[120 120 1000 650],'Visible',app.UIFigure.Visible); g=uigridlayout(app.QualityFigure,[3 1],'RowHeight',{55,'1x',150});
            if isfield(report,'Issues'), uilabel(g,'Text',sprintf('影像 / Images %d · 已覆核 / Reviewed %d · 標記 / Annotations %d · 提示 / Warnings %d',report.Summary.Images,report.Summary.ReviewedImages,report.Summary.Annotations,report.Summary.Warnings),'WordWrap','on'); uitable(g,'Data',report.Issues,'CellSelectionCallback',@(~,e) app.jumpIssue(report.Issues,e)); uitable(g,'Data',report.Classes);
            else, uilabel(g,'Text',sprintf('Matched images: %d | Mean IoU: %g | Mean Dice: %g',report.MatchedImages,report.MeanIoU,report.MeanDice)); uitable(g,'Data',report.Regions); uilabel(g,'Text',report.Meaning); end
        end
        function jumpIssue(app,issues,event)
            if isempty(event.Indices), return; end; row=event.Indices(1,1); index=find(app.Data.Files==issues.File(row),1); if ~isempty(index), app.selectImage(index); app.SelectedID=issues.AnnotationID(row); app.refresh(); end
        end
        function pickReviewer(app), [f,p]=uigetfile('*.mat'); if ~isequal(f,0), app.compareReviewer(fullfile(p,f)); end, end
        function exportQuality(app), assert(~isempty(app.QualityReport),'VIStudioV15:QualityReport','Analyze first.'); parent=uigetdir(pwd); if ~isequal(parent,0), VIStudioAnnotationQualityV15.export(app.QualityReport,tempname(parent)); end, end
        function modeChanged(app)
            app.Handles.AssignImage.Visible=app.enabled(strcmp(app.Handles.DatasetTask.Value,'classification'));
        end
        function selectIgnore(app)
            if ~ismember("__ignore__",app.Data.Classes.Name), app.addClass('__ignore__',[.45 .45 .45]); else, app.Handles.Class.Value='__ignore__'; end
        end
        function refresh(app)
            if ~isvalid(app.UIFigure), return; end
            app.Rendering=true; cleanup=onCleanup(@() app.endRender()); ax=app.Handles.Axes;
            for k=1:numel(app.ROIListeners), if isvalid(app.ROIListeners{k}), delete(app.ROIListeners{k}); end, end
            app.ROIListeners={}; preserve=app.RenderedFile==app.currentFile() && strlength(app.RenderedFile)>0; oldX=ax.XLim; oldY=ax.YLim; cla(ax);
            names=app.Data.Classes.Name; old=string(app.Handles.Class.Value);
            if isempty(names), names="(none)"; end
            app.Handles.Class.Items=cellstr(names);
            if ismember(old,names), app.Handles.Class.Value=char(old); else, app.Handles.Class.Value=char(names(1)); end
            if isempty(app.Data.Files)
                app.Handles.Files.ItemsData={}; app.Handles.Files.Items={'(none)'}; app.Handles.Records.Data=table(); app.Image=[];
                app.refreshControls(); return;
            end
            app.CurrentIndex=min(max(1,app.CurrentIndex),numel(app.Data.Files));
            files=app.Data.Files; display=strings(numel(files),1);
            for k=1:numel(files)
                [~,name,ext]=fileparts(files(k)); flag="○"; if app.Data.Reviewed(k), flag="✓"; end
                display(k)=sprintf('%s %d · %s%s',flag,k,name,ext);
            end
            app.Handles.Files.ItemsData={}; app.Handles.Files.Items=cellstr(display); app.Handles.Files.ItemsData=cellstr(string((1:numel(files))'));
            app.Handles.Files.Value=char(string(app.CurrentIndex));
            file=app.currentFile(); if app.CachedFile~=file, app.Image=VIStudioData.readImage(file,[]); app.CachedFile=file; end
            imshow(app.Image,'Parent',ax); if preserve, ax.XLim=oldX; ax.YLim=oldY; end; app.RenderedFile=file; hold(ax,'on');
            imshow(app.Image,'Parent',app.Handles.Thumbnail);
            keep=contains(lower(files),lower(string(app.Handles.Search.Value))); status=string(app.Handles.Filter.Value);
            if status=="pending", keep=keep & ~app.Data.Reviewed; elseif status=="reviewed", keep=keep & app.Data.Reviewed; end
            app.Handles.ImageList.ItemsData={}; app.Handles.ImageList.Items=cellstr(display(keep)); app.Handles.ImageList.ItemsData=cellstr(string(find(keep)));
            if any(find(keep)==app.CurrentIndex), app.Handles.ImageList.Value=char(string(app.CurrentIndex)); end
            rows=app.Data.current(file);
            if ~ismember(app.SelectedID,rows.ID), app.SelectedID=""; end
            instanceColors=lines(max(1,height(rows)));
            for k=1:height(rows)
                row=rows(k,:); color=app.Data.Classes.Color(app.Data.Classes.Name==row.Label,:); label=row.Label;
                if strcmp(app.Handles.DatasetTask.Value,'instance'), color=instanceColors(k,:); label="#"+k+" "+label; end
                if ~row.Reviewed, label="? "+label; color=[1 .55 .05]; end
                roi=[];
                if strcmp(app.Handles.View.Value,'hidden'), continue; end
                if row.Type=="rectangle"
                    roi=drawrectangle(ax,'Position',row.Geometry{1},'Color',color,'Label',char(label),'FaceAlpha',app.Handles.Opacity.Value*.1);
                elseif row.Type=="polygon"
                    roi=drawpolygon(ax,'Position',row.Geometry{1},'Color',color,'Label',char(label),'FaceAlpha',app.Handles.Opacity.Value*.25);
                elseif row.Type=="keypoints"
                    g=row.Geometry{1};
                    for edge=1:size(g.Edges,1), pair=g.Edges(edge,:); if all(g.Visibility(pair)>0), plot(ax,g.XY(pair,1),g.XY(pair,2),'-','Color',color,'LineWidth',2); end, end
                    for point=1:numel(g.Names)
                        if g.Visibility(point)==0, continue; end; pointColor=color; if g.Visibility(point)==1, pointColor=[.95 .35 .7]; end; dot=drawpoint(ax,'Position',g.XY(point,:),'Color',pointColor,'Label',char(g.Names(point)),'LabelVisible','hover'); if all(g.Box(3:4)>1), dot.DrawingArea=[g.Box(1:2) g.Box(3:4)-1]; end; id=row.ID; index=point;
                        app.ROIListeners{end+1}=addlistener(dot,'ROIMoved',@(source,~) app.movePosePoint(id,index,source.Position));
                    end
                elseif row.Type=="mask"
                    mask=row.Geometry{1}; overlay=imagesc(ax,repmat(reshape(color,1,1,3),size(mask,1),size(mask,2),1)); if strcmp(app.Handles.View.Value,'fill'), overlay.AlphaData=app.Handles.Opacity.Value*double(mask); else, overlay.AlphaData=zeros(size(mask)); end
                    overlay.PickableParts='none'; visboundaries(ax,mask,'Color',color,'LineWidth',1+2*double(row.ID==app.SelectedID)); if strcmp(app.Handles.DatasetTask.Value,'instance'), [yy,xx]=find(mask); text(ax,mean(xx),mean(yy),char(label),'Color','white','BackgroundColor',color,'FontSize',10,'Margin',3,'Interpreter','none'); end
                end
                if ~isempty(roi)
                    if strcmp(app.Handles.View.Value,'outline'), roi.FaceAlpha=0; end
                    area=[1 1 size(app.Image,2)-1 size(app.Image,1)-1];
                    if row.Type=="rectangle", area=[1 1 size(app.Image,2) size(app.Image,1)]; end
                    roi.DrawingArea=area; roi.Selected=row.ID==app.SelectedID;
                    roi.LabelVisible='hover';
                    id=row.ID;
                    app.ROIListeners{end+1}=addlistener(roi,'ROIMoved',@(s,~) app.roiMoved(id,s.Position));
                    app.ROIListeners{end+1}=addlistener(roi,'ROIClicked',@(~,~) app.roiSelected(id));
                    app.ROIListeners{end+1}=addlistener(roi,'DeletingROI',@(~,~) app.roiDeleted(id));
                    app.ROIListeners{end+1}=addlistener(roi,'ObjectBeingDestroyed',@(~,~) app.roiDeleted(id));
                end
            end
            hold(ax,'off'); ax.Toolbar.Visible='on'; app.modeChanged(); app.syncPoseTable();
            data=rows(:,{'Label','Type','Source','Score','Reviewed'}); data.ID=rows.ID; app.Handles.Records.Data=data;
            app.Handles.Records.ColumnWidth={140,90,75,80,75,'auto'};
            app.Handles.ImageInfo.Text=sprintf('%d / %d · %d × %d · %d 標記 / annotations · %d 待確認 / pending', ...
                app.CurrentIndex,numel(files),size(app.Image,2),size(app.Image,1),height(rows),sum(~rows.Reviewed));
            app.Handles.Status.Text=sprintf('完成覆核 / Reviewed: %d / %d · R/P/M/B/E 繪製 / draw · Del 刪除 / delete · Ctrl+Z/Y 復原重做 / undo-redo · A/D 上下張 / navigate', ...
                sum(app.Data.Reviewed),numel(files)); app.refreshControls();
        end
        function refreshControls(app)
            objects=findall(app.UIFigure);
            for h=reshape(objects,1,[]), if isprop(h,'Enable'), h.Enable=app.enabled(~app.Busy); end, end
            [undo,redo]=app.Data.history(); app.Handles.Undo.Enable=app.enabled(~app.Busy && undo>0); app.Handles.Redo.Enable=app.enabled(~app.Busy && redo>0);
            app.Handles.Prelabel.Enable=app.enabled(~app.Busy && ~isempty(app.Model) && ~isempty(app.Data.Files));
            app.Handles.PrelabelAll.Enable=app.Handles.Prelabel.Enable;
            app.Handles.Threshold.Enable=app.enabled(~app.Busy && app.ModelTask~="anomaly");
        end
        function count=predictFile(app,file,threshold)
            assert(~isempty(app.Model),'VIStudioV15:PrelabelModel','Load or train a model first.');
            validateattributes(threshold,{'numeric'},{'scalar','finite','>=',0,'<=',1}); image=VIStudioData.readImage(file,[]);
            labels=strings(0,1); types=strings(0,1); shapes=cell(0,1); scores=zeros(0,1);
            if app.ModelTask=="semantic"
                input=getLayer(app.Model,app.Model.InputNames{1}).InputSize; classes=app.ModelMetadata.SemanticClasses; o=VIStudioSemanticV13.defaults();
                if isfield(app.ModelMetadata,'Options'), for f=fieldnames(app.ModelMetadata.Options)', if isfield(o,f{1}), o.(f{1})=app.ModelMetadata.Options.(f{1}); end, end, end
                artifact=struct('Model',app.Model,'InputSize',input,'Classes',string(classes.Name),'Metadata',app.ModelMetadata,'Digest',app.ModelDigest);
                if string(o.DataMode)=="tiles"
                    result=VIStudioSemanticTilesV13.predict(artifact,image,o); predicted=result.Labels; confidence=result.ConfidenceMap;
                else
                    map=VIStudioSemanticV13.probabilities(artifact,imresize(image,input(1:2))); [confidence,index]=max(map,[],3); ids=uint16(classes.ID); predicted=imresize(reshape(ids(index),size(index)),size(image,[1 2]),'nearest'); confidence=imresize(confidence,size(image,[1 2]),'bilinear');
                end
                for c=1:height(classes)
                    if classes.ID(c)==0, continue; end
                    region=predicted==classes.ID(c) & confidence>=threshold; if ~any(region,'all'), continue; end
                    labels(end+1,1)=classes.Name(c); types(end+1,1)="mask"; shapes{end+1,1}=logical(region); scores(end+1,1)=mean(confidence(region));
                end
            elseif app.ModelTask=="detection"
                [boxes,scores,labels]=detect(app.Model,image,'Threshold',threshold,'ExecutionEnvironment','cpu');
                labels=string(labels(:)); scores=double(scores(:)); keep=scores>=threshold; boxes=double(boxes(keep,:)); labels=labels(keep); scores=scores(keep);
                % Bound boxes before committing a candidate pass.
                lo=max(boxes(:,1:2),1); hi=min(boxes(:,1:2)+boxes(:,3:4),[size(image,2)+1 size(image,1)+1]);
                boxes=[lo max(0,hi-lo)]; keep=all(boxes(:,3:4)>0,2); boxes=boxes(keep,:); labels=labels(keep); scores=scores(keep);
                types=repmat("rectangle",numel(scores),1); shapes=num2cell(boxes,2);
            elseif app.ModelTask=="classification"
                input=getLayer(app.Model,app.Model.InputNames{1}).InputSize; data=imresize(image,input(1:2)); if input(3)==1, data=rgb2gray(data); end
                classes=string(app.ModelMetadata.ClassNames(:)); probabilities=VIStudioModelVisualsV7.classScores(app.Model,data,'cpu',numel(classes));
                [score,index]=max(probabilities);
                if score>=threshold, labels=classes(index); types="image"; shapes={[]}; scores=score; end
            else
                md=app.ModelMetadata;
                assert(isfield(md,'Calibrated') && md.Calibrated && isfield(md,'PixelThreshold') && ~isempty(md.PixelThreshold) && ...
                    isfield(md,'Threshold') && ~isempty(md.Threshold), ...
                    'VIStudioV15:PrelabelCalibration','Anomaly pre-labeling needs a calibrated pixel threshold.');
                validateattributes(md.Threshold,{'numeric'},{'scalar','finite','real'});
                validateattributes(md.PixelThreshold,{'numeric'},{'scalar','finite','real'});
                inputSize=[224 224]; if isfield(md,'ImageSize'), inputSize=md.ImageSize(1:2); end
                input=imresize(image,inputSize); score=double(predict(app.Model,input,'ExecutionEnvironment','cpu'));
                validateattributes(score,{'numeric'},{'scalar','finite','real'});
                map=anomalyMap(app.Model,input,'ExecutionEnvironment','cpu'); if isa(map,'dlarray'), map=extractdata(map); end
                map=gather(map); validateattributes(map,{'numeric'},{'2d','finite','real'});
                mask=imresize(map>=md.PixelThreshold,[size(image,1) size(image,2)],'nearest');
                if score>=md.Threshold && any(mask,'all'), labels="defect"; types="mask"; shapes={logical(mask)}; scores=score; end
            end
            app.Data.applyPredictions(file,labels,types,shapes,scores,app.ModelDigest); count=numel(labels);
        end
        function draw(app)
            app.assertIdle(); app.requireImage(); label=app.selectedClass(); type=string(app.Handles.Tool.Value); ax=app.Handles.Axes; roi=[];
            app.Rendering=true; cleanup=onCleanup(@() app.endRender());
            if type=="rectangle", roi=drawrectangle(ax,'DrawingArea',[1 1 size(app.Image,2) size(app.Image,1)]);
            elseif type=="polygon", roi=drawpolygon(ax,'DrawingArea',[1 1 size(app.Image,2)-1 size(app.Image,1)-1]);
            else, roi=drawfreehand(ax,'Closed',type=="mask",'DrawingArea',[1 1 size(app.Image,2)-1 size(app.Image,1)-1]); end
            if ~isvalid(roi) || isempty(roi.Position), app.refresh(); return; end
            position=roi.Position;
            if type=="rectangle" || type=="polygon"
                delete(roi); app.SelectedID=app.Data.add(app.currentFile(),label,type,position);
            elseif type=="mask"
                mask=createMask(roi,size(app.Image,1),size(app.Image,2)); delete(roi); app.SelectedID=app.Data.add(app.currentFile(),label,'mask',logical(mask));
            else
                delete(roi); app.Rendering=false; app.paintStroke(position,type=="eraser"); return;
            end
            app.Rendering=false; app.refresh();
        end
        function roiMoved(app,id,position)
            if app.Rendering || app.Busy, return; end
            app.action(@() app.updateAnnotation(id,position));
        end
        function roiSelected(app,id), if ~app.Rendering, app.SelectedID=id; app.syncPoseTable(); end, end
        function roiDeleted(app,id)
            if app.Rendering || app.Busy || ~ismember(id,app.Data.Annotations.ID), return; end
            app.Data.remove(id); app.SelectedID="";
            % Avoid recursively deleting a ROI during its DeletingROI event.
            rows=app.Data.current(app.currentFile()); data=rows(:,{'Label','Type','Source','Score','Reviewed'}); data.ID=rows.ID;
            app.Handles.Records.Data=data; app.Handles.Status.Text='已刪除標記，可復原 / Annotation deleted; undo is available'; app.refreshControls();
        end
        function selectRecord(app,event)
            if isempty(event.Indices), return; end
            data=app.Handles.Records.Data; app.SelectedID=data.ID(event.Indices(1,1)); app.refresh();
        end
        function relabel(app)
            rows=app.Data.current(app.requireImage()); row=find(rows.ID==app.SelectedID,1);
            assert(~isempty(row),'VIStudioV15:Annotation','Select an annotation first.'); app.updateAnnotation(rows.ID(row),rows.Geometry{row},app.selectedClass());
        end
        function nextPending(app)
            app.assertIdle(); rows=find(~app.Data.Reviewed); index=rows(find(rows>app.CurrentIndex,1));
            if isempty(index) && ~isempty(rows), index=rows(1); end
            if ~isempty(index), app.selectImage(index); end
        end
        function navigate(app,step)
            app.requireImage(); app.selectImage(min(numel(app.Data.Files),max(1,app.CurrentIndex+step)));
        end
        function uiDeleteClass(app)
            name=app.selectedClass(); choice=uiconfirm(app.UIFigure,'刪除此類別及相關標記？可使用復原。 / Delete class and its annotations? Undo is available.', ...
                '刪除類別 / Delete class','Options',{'Delete','Cancel'},'DefaultOption','Cancel');
            if strcmp(choice,'Delete'), app.deleteClass(name,true); end
        end
        function pickFolder(app)
            if ~app.confirmDiscard(), return; end
            folder=uigetdir(pwd,'Label images'); if ~isequal(folder,0), app.loadFolder(folder); end
        end
        function pickSession(app)
            if ~app.confirmDiscard(), return; end
            [file,path]=uigetfile('*.mat','Open V21 or legacy labeler session'); if ~isequal(file,0), app.loadSession(fullfile(path,file)); end
        end
        function saved=pickSave(app)
            saved=false; [file,path]=uiputfile('*.mat','Save a new V21 session',['LabelerV13_' char(datetime('now','Format','yyyyMMdd_HHmmss')) '.mat']);
            if ~isequal(file,0), app.saveSession(fullfile(path,file)); saved=true; end
        end
        function pickModel(app)
            [file,path]=uigetfile('*.mat','Load pre-labeling model'); if isequal(file,0), return; end
            app.loadPrelabelModel(fullfile(path,file),app.Handles.ModelTask.Value);
        end
        function uiPrelabelAll(app)
            p=uiprogressdlg(app.UIFigure,'Title','模型預標註 / Model pre-labeling','Cancelable','on'); c=onCleanup(@() delete(p));
            app.prelabelAll(app.Handles.Threshold.Value,@progress);
            function stop=progress(index,total)
                p.Value=(index-1)/total; p.Message=sprintf('%d / %d',index,total); drawnow; stop=p.CancelRequested;
            end
        end
        function success=pickExport(app)
            success=false; task=string(app.Handles.DatasetTask.Value);
            if ismember(task,["instance","keypoints"])
                parent=uigetdir(pwd,'Choose a parent for a NEW dataset'); if isequal(parent,0), return; end; [~,name]=fileparts(tempname(parent)); app.exportStructured(fullfile(parent,[char(task) '_' name]),task);
            elseif task=="semantic"
                parent=uigetdir(pwd,'Choose a parent for a NEW semantic dataset'); if isequal(parent,0), return; end
                [~,name]=fileparts(tempname(parent)); app.exportSemantic(fullfile(parent,['semantic_' name]));
            elseif task=="detection"
                [file,path]=uiputfile('*.mat','Export reviewed detection annotations','V7_annotations.mat'); if isequal(file,0), return; end
                app.exportDetection(fullfile(path,file),app.Handles.Convert.Value);
            else
                parent=uigetdir(pwd,'Choose parent for a NEW dataset folder'); if isequal(parent,0), return; end
                name=['V7_' char(task) '_' char(datetime('now','Format','yyyyMMdd_HHmmss'))];
                app.exportDataset(fullfile(parent,name),task);
            end
            success=true; app.Handles.Status.Text='已匯出人工覆核資料 / Exported reviewed training data';
        end
        function exportAndSend(app)
            assert(~isempty(app.SendCallback),'VIStudioV15:StandaloneLabeler','Open this labeler from a V21 training workspace to send data back.');
            if app.pickExport(), app.sendToTraining(); end
        end
        function yes=confirmDiscard(app)
            yes=true; if ~app.Data.Dirty, return; end
            choice=uiconfirm(app.UIFigure,'有未儲存變更。 / There are unsaved changes.','標註工作階段 / Annotation session', ...
                'Options',{'Save','Discard','Cancel'},'DefaultOption','Cancel');
            yes=strcmp(choice,'Discard'); if yes, app.Recovery.resolve('discarded'); end
            if strcmp(choice,'Save'), yes=app.pickSave(); end
        end
        function close(app)
            app.requestClose();
        end
        function key(app,event)
            if app.Busy, return; end
            object=app.UIFigure.CurrentObject;
            if isa(object,'matlab.ui.control.EditField') || isa(object,'matlab.ui.control.NumericEditField') || ...
                isa(object,'matlab.ui.control.TextArea') || isa(object,'matlab.ui.control.Table') || isa(object,'matlab.ui.control.DropDown'), return; end
            ctrl=any(ismember(string(event.Modifier),["control","command"]));
            if ctrl
                switch event.Key
                    case 'z', app.action(@() app.undo()); case 'y', app.action(@() app.redo()); case 's', app.action(@() app.pickSave());
                end
                return;
            end
            switch event.Key
                case {'delete','backspace'}, app.action(@() app.removeAnnotation());
                case {'rightarrow','d'}, app.action(@() app.navigate(1));
                case {'leftarrow','a'}, app.action(@() app.navigate(-1));
                case 'v', app.action(@() app.markReviewed());
                case 'n', app.action(@() app.nextPending());
                case 'f', app.action(@() app.reviewAndNext());
                case 'k', app.action(@() app.placePosePoint());
                case 'q', app.action(@() app.acceptPredictions());
                case 'x', app.action(@() app.rejectPredictions());
                case {'1','2','3','4','5','6','7','8','9'}, app.action(@() app.quickClass(str2double(event.Key)));
                case {'r','p','m','b','e'}
                    keys={'r','p','m','b','e'}; modes={'rectangle','polygon','mask','brush','eraser'};
                    app.Handles.Tool.Value=modes{strcmp(keys,event.Key)}; app.action(@() app.draw());
            end
        end
        function value=selectedClass(app)
            value=string(app.Handles.Class.Value); assert(ismember(value,app.Data.Classes.Name),'VIStudioV15:LabelClass','Add or select a class first.');
        end
        function file=requireImage(app)
            file=app.currentFile(); assert(strlength(file)>0,'VIStudioV15:LabelImages','Load images first.');
        end
        function action(app,callback)
            try, callback(); catch err, if strcmp(app.UIFigure.Visible,'off'), rethrow(err); end; uialert(app.UIFigure,err.message,'標註工具 / Labeler','Interpreter','none'); end
        end
        function assertIdle(app), assert(~app.Busy,'VIStudioV15:LabelerBusy','Wait for pre-labeling to finish.'); end
        function finish(app), app.Busy=false; app.refreshControls(); end
        function endRender(app), app.Rendering=false; end
        function value=enabled(~,yes), value='off'; if yes, value='on'; end, end
        function captureTranslations(app)
            objects=findall(app.UIFigure);
            for object=reshape(objects,1,[])
                if isequal(object,app.Handles.Language), continue; end
                for property={'Text','Title','Placeholder','Items'}
                    field=property{1}; if ~isprop(object,field), continue; end
                    value=object.(field);
                    if (ischar(value) || isstring(value) || iscellstr(value)) && any(contains(string(value),' / '))
                        app.Translations(end+1,:)={object,field,value,value};
                    end
                end
            end
        end
    end
end
