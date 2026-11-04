classdef VIStudioTrainingPaneV9 < handle
    % Reuse the V4 data browser; V6 owns preparation, training and checkpoints.
    properties (SetAccess=private)
        SettingsPanel
        Tabs
        Handles=struct()
        Source=""
        SourceKind=""
        Task
        Prepared=[]
        Health
        Monitor
        Dataset
        DatasetPane
        Experiments
    end
    properties (Access=private)
        Engine
        OwnMetadata=struct()
        OwnModel=[]
        OwnInfo=[]
        External=[]
        Advanced=VIStudioTrainingOptionsV6.defaults()
        AdvancedUI=struct()
        Callbacks
    end
    properties (Dependent,SetAccess=private)
        Samples
        Distribution
        SelectedFile
        Metadata
    end
    methods
        function pane=VIStudioTrainingPaneV9(task,body,tab,callbacks)
            pane.Task=string(task); pane.Callbacks=callbacks; pane.Dataset=VIStudioDatasetV9(task); pane.Engine=VIStudioTrainingAppV4(task,'off');
            fig=pane.Engine.UIFigure;
            pane.SettingsPanel=findall(fig,'Title','模型與訓練 / Model & Training');
            pane.Tabs=findall(fig,'-isa','matlab.ui.container.TabGroup');
            pane.Handles.Train=findall(fig,'Text','開始訓練 / Train');
            pane.Handles.Save=findall(fig,'Text','儲存模型 / Save model');
            pane.Handles.Inspect=findall(fig,'Text','開啟 V3 檢測 / Open inspection');
            pane.Handles.Status=findall(fig,'Text','尚未訓練 / No trained model');
            text='載入資料夾 / Load folder'; if task=="detection", text='載入標註 MAT / Load annotations'; end
            pane.Handles.Load=findall(fig,'Text',text);
            pane.Handles.Summary=findall(fig,'Text','類別資料夾作為標籤 / Subfolders define labels');
            filters=findall(pane.Tabs,'-isa','matlab.ui.control.DropDown');
            pane.Handles.ClassFilter=filters(arrayfun(@(h) isequal(string(h.ItemsData),"all"),filters));
            models=pane.Engine.modelChoices();
            menus=findall(pane.SettingsPanel,'-isa','matlab.ui.control.DropDown');
            pane.Handles.Model=menus(arrayfun(@(h) isequal(string(h.ItemsData),models),menus));
            assert(isscalar(pane.Handles.Model),'VIStudioV9:TrainingLayout','Unable to identify the model selector.');
            grid=pane.Handles.Model.Parent;
            fields={'Epochs','Batch','LearnRate','Validation','Size','NormalClass','Environment'};
            rows=[5 7 9 11 13 15 17];
            for k=1:numel(fields)
                children=grid.Children;
                pane.Handles.(fields{k})=children(arrayfun(@(h) isequal(h.Layout.Row,rows(k)),children));
            end
            pane.Handles.Hint=grid.Children(arrayfun(@(h) isequal(h.Layout.Row,3),grid.Children));
            models=pane.modelChoices();
            display=cellstr(models);
            for k=1:numel(models)
                available=pane.availability(models(k));
                if ~available.Available, display{k}=[display{k} ' [未安裝 / Unavailable]']; end
            end
            pane.Handles.Model.ItemsData={}; pane.Handles.Model.Items=display; pane.Handles.Model.ItemsData=cellstr(models);
            pane.Handles.Model.ValueChangedFcn=@(~,~) callbacks.Changed();
            pane.SettingsPanel.Parent=body; pane.SettingsPanel.Layout.Row=1; pane.SettingsPanel.Layout.Column=1;
            pane.SettingsPanel.Visible='off';
            parent=uigridlayout(tab,[1 1],'Padding',[0 0 0 0]); pane.Tabs.Parent=parent;
            pane.Tabs.Layout.Row=1; pane.Tabs.Layout.Column=1;
            pane.Handles.Train.ButtonPushedFcn=@(~,~) callbacks.Train();
            pane.Handles.Save.ButtonPushedFcn=@(~,~) callbacks.Save();
            pane.Handles.Inspect.ButtonPushedFcn=@(~,~) callbacks.Inspect();
            pane.Handles.Load.ButtonPushedFcn=@(~,~) callbacks.Load();
            % The embedded browser also refreshes the host's model-dependent buttons.
            search=findall(pane.Tabs,'Placeholder','搜尋檔名 / Search filename');
            previous=findall(pane.Tabs,'Text','上一張 / Previous');
            next=findall(pane.Tabs,'Text','下一張 / Next');
            boxes=findall(pane.Tabs,'Text','顯示標註 / Show boxes');
            tables=findall(pane.Tabs,'-isa','matlab.ui.control.Table');
            files=tables(arrayfun(@(h) ~isempty(h.CellSelectionCallback),tables));
            targets={search,'ValueChangedFcn';pane.Handles.ClassFilter,'ValueChangedFcn'; ...
                previous,'ButtonPushedFcn';next,'ButtonPushedFcn';boxes,'ValueChangedFcn';files,'CellSelectionCallback'};
            for k=1:size(targets,1)
                object=targets{k,1}; property=targets{k,2}; original=object.(property);
                object.(property)=@(source,event) pane.afterEvent(original,source,event,callbacks.Changed);
            end
            pane.buildAdvanced();
            tab=uitab(pane.Tabs,'Title','06 資料健檢 / Data Health');
            pane.Health=VIStudioHealthPaneV8(tab,pane.Task,@() pane.checkData());
            tab=uitab(pane.Tabs,'Title','07 訓練監控 / Training Monitor');
            pane.Monitor=VIStudioTrainingRunV9(tab);
            tab=uitab(pane.Tabs,'Title','08 資料集管理 / Dataset Manager');
            actions=struct('Build',@() pane.buildDatasetPlan(),'Source',@(role,path) pane.setDatasetSource(role,path),'Use',callbacks.UseDataset,'Changed',callbacks.Changed);
            pane.DatasetPane=VIStudioDatasetPaneV9(tab,pane.Dataset,actions);
            tab=uitab(pane.Tabs,'Title','09 實驗比較 / Experiments');
            pane.Experiments=VIStudioExperimentsV9(tab,pane.Task,callbacks.ActivateRun);
        end
        function delete(pane)
            if ~isempty(pane.Engine) && isvalid(pane.Engine), delete(pane.Engine); end
            if ~isempty(pane.SettingsPanel) && isvalid(pane.SettingsPanel), delete(pane.SettingsPanel); end
            if ~isempty(pane.Tabs) && isvalid(pane.Tabs), delete(pane.Tabs); end
        end
        function value=get.Samples(pane), value=pane.Engine.Samples; end
        function value=get.Distribution(pane), value=pane.Engine.Distribution; end
        function value=get.SelectedFile(pane), value=pane.Engine.SelectedFile; end
        function value=get.Metadata(pane), value=pane.OwnMetadata; end
        function names=modelChoices(pane)
            names=pane.Engine.modelChoices();
            if pane.Task=="anomaly", names=[names "Teacher–Student / ResNet-18"]; end
            names=[names "External MAT"];
        end
        function chooseModel(pane,name)
            assert(ismember(string(name),pane.modelChoices()),'VIStudioV9:Model','Unknown model.');
            pane.Handles.Model.Value=char(name);
        end
        function setOptions(pane,options), pane.Engine.setTrainingOptions(options); end
        function setAdvanced(pane,options)
            value=VIStudioTrainingOptionsV6.merge(pane.currentAdvanced(),options); pane.Advanced=value;
            fields=fieldnames(pane.AdvancedUI);
            for k=1:numel(fields), pane.AdvancedUI.(fields{k}).Value=value.(fields{k}); end
        end
        function artifact=loadExternal(pane,file,variable)
            if nargin<3, variable=""; end
            artifact=VIStudioModelIOV8.read(file,pane.Task,variable); pane.External=artifact;
            pane.Handles.ExternalPath.Value=char(artifact.File); pane.Handles.ExternalVariable.Value=char(artifact.Variable);
            pane.Handles.ExternalSummary.Text=string(class(artifact.Model))+" · "+join(string(artifact.InputSize),' × ')+newline+ ...
                "SHA-256: "+artifact.Digest;
            pane.chooseModel("External MAT");
        end
        function prepared=prepare(pane)
            state=pane.state(); external=[];
            if state.Model=="External MAT", assert(~isempty(pane.External),'VIStudioV9:ExternalMissing','Load an external MAT model first.'); external=pane.External; end
            input=VIStudioTrainingBackendV9.inputSize(pane.Task,state.Model,state.Options,external);
            plan=pane.buildDatasetPlan(); VIStudioDatasetV9.assertUnchanged(plan);
            prepared=VIStudioPreparedDataV9.build(pane.Task,plan.Samples,plan.Annotations,state.Options, ...
                pane.currentAdvanced(),input,pane.newFolder(),plan.Manifest.Split);
            pane.Prepared=prepared; pane.showPrepared();
        end
        function loadFolder(pane,folder)
            pane.Engine.loadFolder(folder); pane.Source=VIStudioToolsV3.canonicalPath(folder); pane.SourceKind="folder"; pane.Dataset.setSource("train",pane.Source); pane.DatasetPane.sync();
        end
        function loadAnnotations(pane,file)
            pane.Engine.loadAnnotations(file); pane.Source=VIStudioToolsV3.canonicalPath(file); pane.SourceKind="annotations"; pane.Dataset.setSource("train",pane.Source); pane.DatasetPane.sync();
        end
        function setDatasetSource(pane,role,path)
            if string(role)=="train"
                if pane.Task=="detection", pane.loadAnnotations(path); else, pane.loadFolder(path); end
            else, pane.Dataset.setSource(role,path); pane.DatasetPane.sync(); end
        end
        function configureDataset(pane,config)
            candidate=VIStudioDatasetV9(pane.Task); candidate.restore(pane.Dataset.Config); candidate.configure(config);
            path=string(candidate.Config.Sources.train);
            assert(strlength(path)>0 || strlength(pane.Source)==0,'VIStudioV9:DatasetTrain','Replace the training source instead of clearing it.');
            if strlength(path)>0 && VIStudioToolsV3.canonicalPath(path)~=pane.Source
                if pane.Task=="detection", pane.loadAnnotations(path); else, pane.loadFolder(path); end
            end
            pane.Dataset.restore(candidate.Config); pane.DatasetPane.sync();
        end
        function plan=buildDatasetPlan(pane)
            state=pane.state(); plan=pane.Dataset.build(state.Options.Validation,pane.currentAdvanced().Seed);
            pane.DatasetPane.show(plan); pane.Health.show(plan.Health);
        end
        function filterImages(pane,query,label), pane.Engine.filterImages(query,label); end
        function nextImage(pane,step), pane.Engine.nextImage(step); end
        function report=checkData(pane)
            if strlength(string(pane.Dataset.Config.Sources.train))>0
                plan=pane.buildDatasetPlan(); report=plan.Health; return;
            end
            if pane.SourceKind=="annotations", report=VIStudioDataHealthV8.annotations(pane.Source);
            elseif pane.SourceKind=="folder", report=VIStudioDataHealthV8.folder(pane.Source,pane.Task);
            else, report=VIStudioDataHealthV8.scan([],[],pane.Task,[]); end
            pane.Health.show(report);
        end
        function model=train(pane)
            state=pane.availability();
            assert(state.Available,'VIStudioV9:ModelUnavailable', ...
                '本機缺少模型訓練函式。 / Missing training functions: %s',join(state.Missing,', '));
            settings=pane.state(); external=[];
            if settings.Model=="External MAT", external=pane.External; end
            report=pane.checkData();
            assert(report.Errors==0,'VIStudioV9:DataHealth','資料健檢有 %d 項錯誤；請查看 Data Health。 / Resolve %d data errors before training.',report.Errors,report.Errors);
            pane.Monitor.begin(pane.Task,settings.Model,settings.Options,pane.currentAdvanced());
            try
                [model,metadata,info,prepared]=VIStudioTrainingBackendV9.train(pane.Task,settings.Model,pane.Samples, ...
                    pane.Dataset.Plan.Annotations,settings.Options,pane.currentAdvanced(),external,pane.newFolder(),pane.Monitor,pane.Dataset.Plan);
            catch err
                status="failed"; if strcmp(err.identifier,'VIStudioV9:Cancelled'), status="stopped"; end
                pane.Monitor.finish(status,err.message); rethrow(err);
            end
            pane.OwnModel=model; pane.OwnMetadata=metadata; pane.OwnInfo=info; pane.Prepared=prepared; pane.showPrepared();
        end
        function state=availability(pane,name)
            if nargin<2, name=string(pane.Handles.Model.Value); end
            if name=="External MAT"
                if isempty(pane.External), required="Load external MAT first";
                elseif pane.Task=="detection", required=VIStudioModelIOV8.detectorTrainer(pane.External.Model);
                elseif pane.Task=="classification", required="trainnet";
                elseif (isa(pane.External.Model,'VIStudioTeacherStudentV8') || isa(pane.External.Model,'VIStudioTeacherStudentV6')), required="dlfeval";
                elseif isa(pane.External.Model,'patchCoreAnomalyDetector'), required="trainPatchCoreAnomalyDetector";
                elseif isa(pane.External.Model,'fcddAnomalyDetector'), required="trainFCDDAnomalyDetector";
                else, required="Supported retraining API"; end
            elseif startsWith(name,'Teacher–Student'), required=["imagePretrainedNetwork","dlfeval"];
            elseif pane.Task=="classification", required=["imagePretrainedNetwork","trainnet"];
            elseif pane.Task=="detection", required=["yoloxObjectDetector","trainYOLOXObjectDetector"];
            elseif startsWith(name,'PatchCore'), required=["patchCoreAnomalyDetector","trainPatchCoreAnomalyDetector"];
            elseif startsWith(name,'FCDD'), required=["fcddAnomalyDetector","trainFCDDAnomalyDetector","pretrainedEncoderNetwork"];
            else, required=["efficientADAnomalyDetector","trainEfficientADAnomalyDetector"]; end
            missing=required(arrayfun(@(f) isempty(which(char(f))),required));
            state=struct('Model',string(name),'Available',isempty(missing),'Missing',missing);
        end
        function saveCheckpoint(pane,file)
            assert(~isempty(pane.OwnModel),'VIStudioV9:MissingModel','Train a model first.');
            assert(~isfile(file),'VIStudioV9:Exists','Choose a new checkpoint filename.');
            model=pane.OwnModel; metadata=pane.OwnMetadata; info=pane.OwnInfo; %#ok<NASGU>
            save(file,'model','metadata','info','-v7.3');
            pane.Monitor.attachCheckpoint(file); pane.Experiments.refresh();
        end
        function state=state(pane)
            fields={'Epochs','Batch','LearnRate','Validation','Environment','Size','NormalClass'};
            options=struct();
            for k=1:numel(fields), options.(fields{k})=pane.Handles.(fields{k}).Value; end
            state=struct('Task',pane.Task,'Source',pane.Source,'Kind',pane.SourceKind, ...
                'Model',string(pane.Handles.Model.Value),'Options',options,'AdvancedOptions',pane.currentAdvanced());
            state.DatasetConfig=pane.Dataset.Config;
            if ~isempty(pane.External)
                state.ExternalFile=pane.External.File; state.ExternalVariable=pane.External.Variable; state.ExternalDigest=pane.External.Digest;
            end
        end
        function validateState(pane,state)
            assert(isstruct(state) && isscalar(state) && all(isfield(state,{'Task','Source','Kind','Model','Options'})) && ...
                state.Task==pane.Task && ismember(string(state.Model),pane.modelChoices()), ...
                'VIStudioV9:TrainingProject','Invalid training state.');
            assert(isstruct(state.Options) && all(isfield(state.Options, ...
                {'Epochs','Batch','LearnRate','Validation','Environment','Size','NormalClass'})), ...
                'VIStudioV9:TrainingProject','Invalid training options.');
            if isfield(state,'DatasetConfig')
                VIStudioDatasetV9.validateConfig(state.DatasetConfig);
                path=string(state.DatasetConfig.Sources.train); source=string(state.Source);
                match=strlength(path)==0 && strlength(source)==0;
                if strlength(path)>0 && strlength(source)>0, match=VIStudioToolsV3.canonicalPath(path)==VIStudioToolsV3.canonicalPath(source); end
                assert(match,'VIStudioV9:DatasetProject','Dataset training source does not match the training browser source.');
            end
            if isfield(state,'AdvancedOptions'), VIStudioTrainingOptionsV6.merge(VIStudioTrainingOptionsV6.defaults(),state.AdvancedOptions); end
            if isfield(state,'ExternalFile')
                candidate=VIStudioModelIOV8.read(state.ExternalFile,pane.Task,state.ExternalVariable);
                assert(candidate.Digest==string(state.ExternalDigest),'VIStudioV9:ExternalChanged','External MAT contents changed.');
            end
            assert(string(state.Model)~="External MAT" || isfield(state,'ExternalFile'),'VIStudioV9:ExternalMissing','External model reference missing.');
            validateattributes(state.Options.Epochs,{'numeric'},{'scalar','integer','>=',1,'<=',10000});
            validateattributes(state.Options.Batch,{'numeric'},{'scalar','integer','>=',1,'<=',512});
            validateattributes(state.Options.LearnRate,{'numeric'},{'scalar','finite','>=',1e-8,'<=',1});
            validateattributes(state.Options.Validation,{'numeric'},{'scalar','finite','>=',0,'<=',50});
            validatestring(state.Options.Environment,{'auto','cpu','gpu'});
            sizes=[224 256]; if pane.Task=="detection", sizes=[320 416 640]; end
            assert(ismember(state.Options.Size,sizes),'VIStudioV9:TrainingProject','Invalid training image size.');
            if strlength(string(state.Source))==0, return; end
            if state.Kind=="folder" && pane.Task~="detection"
                [~,summary]=VIStudioTrainingDataV4.folder(state.Source);
                assert(ismember(string(state.Options.NormalClass),summary.Class),'VIStudioV9:TrainingProject','Training class is missing.');
            elseif state.Kind=="annotations" && pane.Task=="detection"
                VIStudioTrainingDataV4.groundTruth(state.Source);
            else, error('VIStudioV9:TrainingProject','Training source does not match its task.'); end
        end
        function restore(pane,state)
            pane.validateState(state);
            if strlength(string(state.Source))>0
                if state.Kind=="folder", pane.loadFolder(state.Source); else, pane.loadAnnotations(state.Source); end
            end
            if isfield(state,'ExternalFile'), pane.loadExternal(state.ExternalFile,state.ExternalVariable); end
            pane.chooseModel(state.Model); pane.setOptions(state.Options);
            if isfield(state,'AdvancedOptions'), pane.setAdvanced(state.AdvancedOptions); end
            if isfield(state,'DatasetConfig'), pane.Dataset.restore(state.DatasetConfig); pane.DatasetPane.sync(); end
        end
        function busy(pane,value,ready,language,modelName)
            if value
                objects=[findall(pane.SettingsPanel);findall(pane.Tabs)];
                for h=reshape(objects,1,[]), if isprop(h,'Enable'), h.Enable='off'; end, end
            else
                objects=[findall(pane.SettingsPanel);findall(pane.Tabs)];
                for h=reshape(objects,1,[]), if isprop(h,'Enable'), h.Enable='on'; end, end
                pane.Monitor.Handles.Stop.Enable='off';
                pane.DatasetPane.sync();
                if ~isempty(pane.Dataset.Plan), pane.DatasetPane.show(pane.Dataset.Plan); end
                pane.Engine.setTrainingOptions(struct());
                pane.updateAdvancedGates();
                if pane.Dataset.Config.Mode=="explicit"
                    pane.Handles.Validation.Enable='off';
                end
                names=pane.modelChoices(); display=cellstr(names);
                for k=1:numel(names)
                    status=pane.availability(names(k));
                    if ~status.Available, display{k}=[display{k} ' [未就緒 / Not ready]']; end
                end
                pane.Handles.Model.Items=display;
                available=pane.availability();
                if ~available.Available
                    pane.Handles.Train.Enable='off';
                    pane.Handles.Hint.Text='未安裝此模型的訓練函式 / Training functions are unavailable';
                end
                if startsWith(string(pane.Handles.Model.Value),'Teacher–Student')
                    pane.Handles.Hint.Text='凍結教師，僅以正常影像訓練學生；訓練後請校準 / Frozen teacher, normal-only student; calibrate after training';
                elseif string(pane.Handles.Model.Value)=="External MAT" && available.Available
                    if pane.Task=="classification"
                        pane.Handles.Hint.Text='載入權重續訓，重新建立最佳化器；類別須相符或更換分類頭 / Warm-start weights; reset optimizer; match classes or replace head';
                    elseif pane.Task=="detection"
                        pane.Handles.Hint.Text='載入偵測權重續訓；標註類別須一致 / Warm-start detector weights; annotation classes must match';
                    elseif isa(pane.External.Model,'patchCoreAnomalyDetector')
                        pane.Handles.Hint.Text='沿用骨幹，使用目前正常影像重新建庫；完成後重新校準 / Refit memory on current normal images; recalibrate afterwards';
                    else
                        pane.Handles.Hint.Text='沿用模型權重續訓；訓練後重新校準。老師學生僅訓練正常影像 / Warm-start weights; recalibrate afterwards. Teacher–Student uses normal images only';
                    end
                end
                pane.Handles.Hint.Text=VIStudioToolsV3.translate(pane.Handles.Hint.Text,language);
                pane.Handles.Save.Enable='off'; pane.Handles.Inspect.Enable='off';
                if ready, pane.Handles.Save.Enable='on'; end
                if ready && strlength(pane.SelectedFile)>0, pane.Handles.Inspect.Enable='on'; end
                pane.Handles.Inspect.Text=VIStudioToolsV3.translate('檢測目前照片 / Inspect selected image',language);
                if ready
                    pane.Handles.Status.Text=string(VIStudioToolsV3.translate('目前模型 / Active model',language))+": "+modelName;
                else
                    pane.Handles.Status.Text=VIStudioToolsV3.translate('尚無模型，可先訓練或載入 / Train or load a model to begin',language);
                end
                if ~isempty(pane.Samples)
                    pane.Handles.Summary.Text=sprintf('%d %s · %d %s',height(pane.Samples), ...
                        VIStudioToolsV3.translate('張影像 / images',language),height(pane.Distribution), ...
                        VIStudioToolsV3.translate('類別 / classes',language));
                    if pane.Task=="detection"
                        pane.Handles.Summary.Text=string(pane.Handles.Summary.Text)+sprintf(' · %d %s',sum(pane.Distribution.Count), ...
                            VIStudioToolsV3.translate('標註框 / boxes',language));
                    end
                    pane.Handles.ClassFilter.Items=[{char(VIStudioToolsV3.translate('全部類別 / All classes',language))};cellstr(pane.Distribution.Class)];
                end
            end
        end
    end
    methods (Access=private)
        function o=currentAdvanced(pane)
            o=pane.Advanced; fields=fieldnames(pane.AdvancedUI);
            for k=1:numel(fields), o.(fields{k})=pane.AdvancedUI.(fields{k}).Value; end
            o=VIStudioTrainingOptionsV6.merge(VIStudioTrainingOptionsV6.defaults(),o);
        end
        function gt=groundTruth(pane)
            gt=[];
            if pane.Task=="detection"
                assert(strlength(pane.Source)>0,'VIStudioV9:MissingData','Load box annotations first.');
                [~,~,gt]=VIStudioTrainingDataV4.groundTruth(pane.Source);
            end
        end
        function folder=newFolder(~)
            root=fullfile(fileparts(mfilename('fullpath')),'V9_Prepared');
            if ~isfolder(root), mkdir(root); end
            [~,name]=fileparts(tempname(root)); folder=fullfile(root,name);
        end
        function buildAdvanced(pane)
            advanced=uitab(pane.Tabs,'Title','03 進階參數 / Advanced');
            grid=uigridlayout(advanced,[16 2],'ColumnWidth',{290,'1x'},'RowHeight',repmat({30},1,16),'Scrollable','on');
            specs={
                'Solver','最佳化器 / Optimizer',{'adam','sgdm','rmsprop'};
                'L2','權重正則化 / L2 regularization',[];
                'Momentum','動量（SGDM） / Momentum (SGDM)',[];
                'GradientThreshold','梯度裁切 / Gradient clipping',[];
                'Schedule','學習率排程 / Learning rate schedule',{'none','piecewise'};
                'DropFactor','學習率衰減倍率 / Drop factor',[];
                'DropPeriod','衰減週期（epochs） / Drop period',[];
                'Shuffle','洗牌方式 / Shuffle',{'every-epoch','once','never'};
                'ValidationFrequency','驗證間隔（iterations） / Validation interval',[];
                'Patience','提前停止耐心值（0=關閉） / Patience (0=off)',[];
                'Seed','隨機種子 / Random seed',[];
                'FreezeBackbone','凍結分類骨幹 / Freeze classifier backbone','bool';
                'ReplaceHead','外部分類模型更換分類頭 / Replace external classifier head','bool';
                'CompressionRatio','PatchCore 記憶庫比例 / Memory compression ratio',[]};
            pane.addControls(grid,specs);
            note=uilabel(grid,'Text','參數依模型啟用；PatchCore 不使用 epochs 或最佳化器。 / Options depend on model; PatchCore has no epochs or optimizer.','WordWrap','on');
            note.Layout.Row=[15 16]; note.Layout.Column=[1 2];
            augmentation=uitab(pane.Tabs,'Title','04 擴充與合成 / Augmentation & Synthesis');
            root=uigridlayout(augmentation,[1 2],'ColumnWidth',{350,'1x'});
            settings=uigridlayout(root,[17 2],'ColumnWidth',{220,'1x'},'RowHeight',repmat({30},1,17),'Scrollable','on');
            specs={
                'AugmentCopies','每張額外擴充數 / Augmented copies',[];
                'FlipLR','隨機水平翻轉 / Random horizontal flip','bool';
                'FlipUD','隨機垂直翻轉 / Random vertical flip','bool';
                'Rotation','旋轉上限（度） / Rotation (degrees)',[];
                'Translate','平移比例上限 / Translation fraction',[];
                'ScaleMin','縮放下限 / Minimum scale',[];
                'ScaleMax','縮放上限 / Maximum scale',[];
                'Brightness','亮度變化 / Brightness variation',[];
                'Contrast','對比變化 / Contrast variation',[];
                'Noise','高斯雜訊標準差 / Gaussian noise sigma',[];
                'SynthMode','合成方式 / Synthesis mode',{'none','cutpaste','scratch','noise','copy-paste'};
                'SynthCopies','每張合成數 / Synthetic copies',[];
                'DefectFraction','合成區域比例 / Synthetic area fraction',[]};
            pane.addControls(settings,specs);
            button=uibutton(settings,'Text','產生並預覽 / Prepare & preview','ButtonPushedFcn',@(~,~) pane.uiPrepare());
            button.Layout.Row=14; button.Layout.Column=[1 2];
            note=uilabel(settings,'Text','先切分原始資料，只擴充訓練集。異常合成僅從正常影像產生並標成異常；物件複製會新增標註。 / Split originals first; training-only variants. Synthetic defects are abnormal; copied objects receive boxes.','WordWrap','on');
            note.Layout.Row=[15 17]; note.Layout.Column=[1 2];
            view=uigridlayout(root,[4 2],'RowHeight',{34,'1x',45,'1x'});
            pane.Handles.PreparedSummary=uilabel(view,'Text','尚未產生資料 / No prepared data','WordWrap','on');
            pane.Handles.PreparedSummary.Layout.Column=[1 2];
            pane.Handles.Before=uiaxes(view); pane.Handles.Before.Layout.Row=2; pane.Handles.Before.Layout.Column=1;
            pane.Handles.After=uiaxes(view); pane.Handles.After.Layout.Row=2; pane.Handles.After.Layout.Column=2;
            pane.Handles.Before.Toolbar.Visible='off'; pane.Handles.After.Toolbar.Visible='off';
            disableDefaultInteractivity(pane.Handles.Before); disableDefaultInteractivity(pane.Handles.After);
            note=uilabel(view,'Text','點選任一列檢查來源、衍生影像與標註；Manifest 保存種子、來源雜湊與合成遮罩路徑。 / Select a row to inspect source, variant and boxes. Manifest records provenance and masks.','WordWrap','on');
            note.Layout.Row=3; note.Layout.Column=[1 2];
            pane.Handles.PreparedTable=uitable(view,'CellSelectionCallback',@(~,e) pane.previewRow(e));
            pane.Handles.PreparedTable.Layout.Row=4; pane.Handles.PreparedTable.Layout.Column=[1 2];
            external=uitab(pane.Tabs,'Title','05 外部模型 / External MAT');
            grid=uigridlayout(external,[6 2],'ColumnWidth',{260,'1x'},'RowHeight',{32,32,42,110,80,'1x'});
            uilabel(grid,'Text','模型變數（留空自動選取） / Variable (blank=auto)');
            pane.Handles.ExternalVariable=uieditfield(grid,'text','Value','');
            uilabel(grid,'Text','已載入模型 / Loaded model');
            pane.Handles.ExternalPath=uieditfield(grid,'text','Editable','off');
            button=uibutton(grid,'Text','載入外部 MAT / Load external MAT','ButtonPushedFcn',@(~,~) pane.uiExternal());
            button.Layout.Row=3; button.Layout.Column=[1 2];
            pane.Handles.ExternalSummary=uilabel(grid,'Text','尚未載入 / No external model','WordWrap','on');
            pane.Handles.ExternalSummary.Layout.Row=4; pane.Handles.ExternalSummary.Layout.Column=[1 2];
            note=uilabel(grid,'Text','載入模型權重續訓，最佳化器會重建。分類需要 metadata.ClassNames 或 classNames，或勾選更換分類頭。偵測類別須與標註一致。PatchCore 重新建庫；異常模型續訓後需重新校準。 / Weights warm-start; optimizer resets. Classification needs class metadata or a new head. Detection classes must match. PatchCore refits memory; recalibrate anomaly models.','WordWrap','on');
            note.Layout.Row=[5 6]; note.Layout.Column=[1 2];
            pane.updateAdvancedGates();
        end
        function addControls(pane,grid,specs)
            for k=1:size(specs,1)
                field=specs{k,1}; kind=specs{k,3}; label=uilabel(grid,'Text',specs{k,2},'WordWrap','on'); label.Layout.Row=k; label.Layout.Column=1;
                if iscell(kind), control=uidropdown(grid,'Items',kind,'Value',char(pane.Advanced.(field)));
                elseif isequal(kind,'bool'), control=uicheckbox(grid,'Text','','Value',pane.Advanced.(field));
                else, control=uieditfield(grid,'numeric','Value',pane.Advanced.(field)); end
                control.Layout.Row=k; control.Layout.Column=2; pane.AdvancedUI.(field)=control;
                control.ValueChangedFcn=@(~,~) pane.Callbacks.Changed();
            end
        end
        function updateAdvancedGates(pane)
            name=string(pane.Handles.Model.Value); patch=startsWith(name,'PatchCore');
            if name=="External MAT" && ~isempty(pane.External), patch=isa(pane.External.Model,'patchCoreAnomalyDetector'); end
            neural={'Solver','L2','Momentum','GradientThreshold','Schedule','DropFactor','DropPeriod','Shuffle'};
            for k=1:numel(neural), pane.AdvancedUI.(neural{k}).Enable=pane.onoff(~patch); end
            pane.AdvancedUI.Momentum.Enable=pane.onoff(~patch && string(pane.AdvancedUI.Solver.Value)=="sgdm");
            pane.AdvancedUI.CompressionRatio.Enable=pane.onoff(patch);
            pane.AdvancedUI.FreezeBackbone.Enable=pane.onoff(pane.Task=="classification");
            pane.AdvancedUI.ReplaceHead.Enable=pane.onoff(pane.Task=="classification" && name=="External MAT");
            pane.AdvancedUI.ValidationFrequency.Enable=pane.onoff(pane.Task~="anomaly");
            pane.AdvancedUI.Patience.Enable=pane.onoff(pane.Task~="anomaly");
            modes={'none','cutpaste','scratch','noise'};
            if pane.Task=="detection", modes={'none','noise','copy-paste'}; end
            pane.AdvancedUI.SynthMode.Items=modes;
        end
        function showPrepared(pane)
            m=pane.Prepared.Manifest;
            name=string(pane.Handles.Model.Value); used=m.Split=="train";
            normalOnly=startsWith(name,'Teacher–Student') || startsWith(name,'PatchCore');
            if name=="External MAT" && ~isempty(pane.External)
                normalOnly=(isa(pane.External.Model,'VIStudioTeacherStudentV8') || isa(pane.External.Model,'VIStudioTeacherStudentV6')) || isa(pane.External.Model,'patchCoreAnomalyDetector');
            end
            if normalOnly, used=used & m.Label==string(pane.Handles.NormalClass.Value); end
            pane.Handles.PreparedSummary.Text=sprintf('準備 / Prepared: %d · 驗證 / Validation: %d · 實際訓練 / Used: %d\n擴充 / Augmented: %d · 合成 / Synthetic: %d', ...
                height(m),sum(m.Split=="validation"),sum(used),sum(m.Kind=="augmentation"),sum(m.Kind=="synthetic"));
            data=m(:,{'Kind','Label','Split','Objects','Seed'});
            data.Image=strings(height(m),1); data.Source=strings(height(m),1);
            for k=1:height(m)
                [~,name,ext]=fileparts(m.File(k)); data.Image(k)=name+ext;
                [~,name,ext]=fileparts(m.SourceFile(k)); data.Source(k)=name+ext;
            end
            pane.Handles.PreparedTable.Data=data;
            pane.Handles.PreparedTable.ColumnWidth={110,135,90,65,80,110,110};
            row=find(m.Kind=="synthetic",1); if isempty(row), row=find(m.Kind=="augmentation",1); end
            if isempty(row), row=1; end
            pane.drawPrepared(row);
        end
        function drawPrepared(pane,row)
            m=pane.Prepared.Manifest; before=VIStudioData.readImage(m.SourceFile(row),[]); after=imread(m.File(row));
            if m.Objects(row)>0
                boxes=VIStudioToolsV3.decodeBoxes(m.BoxesJSON(row),m.Objects(row));
                after=insertShape(after,'Rectangle',boxes,'Color','yellow','LineWidth',2);
            end
            imshow(before,'Parent',pane.Handles.Before); title(pane.Handles.Before,'來源 / Source');
            text="原始 / Original";
            if m.Kind(row)=="augmentation", text="擴充 / Augmented";
            elseif m.Kind(row)=="synthetic", text="合成 / Synthetic"; end
            imshow(after,'Parent',pane.Handles.After); title(pane.Handles.After,text,'Interpreter','none');
            if strlength(m.MaskFile(row))>0
                mask=imread(m.MaskFile(row)); hold(pane.Handles.After,'on');
                layer=imagesc(pane.Handles.After,cat(3,zeros(size(mask)),ones(size(mask)),zeros(size(mask))));
                layer.AlphaData=0.25*double(mask>0); hold(pane.Handles.After,'off');
            end
        end
        function previewRow(pane,event)
            if ~isempty(event.Indices) && ~isempty(pane.Prepared), pane.drawPrepared(event.Indices(1,1)); end
        end
        function uiPrepare(pane)
            try, pane.prepare(); pane.Callbacks.Changed();
            catch error, uialert(ancestor(pane.Tabs,'figure'),error.message,'資料準備 / Data preparation'); end
        end
        function uiExternal(pane)
            [file,path]=uigetfile('*.mat','External training model'); if isequal(file,0), return; end
            try, pane.loadExternal(fullfile(path,file),pane.Handles.ExternalVariable.Value); pane.Callbacks.Changed();
            catch error, uialert(ancestor(pane.Tabs,'figure'),error.message,'外部模型 / External model'); end
        end
        function value=onoff(~,condition)
            value='off'; if condition, value='on'; end
        end
        function afterEvent(~,original,source,event,changed)
            original(source,event); changed();
        end
    end
end
