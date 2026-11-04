classdef VIStudioTrainingAppV4 < matlab.apps.AppBase
    % Native training workspace; original and V3 apps remain untouched.
    properties (SetAccess=private)
        UIFigure
        Task
        Samples=table()
        Distribution=table()
        SelectedFile=""
        TrainedModel=[]
        Metadata=struct()
    end
    properties (Access=private)
        UI=struct()
        GroundTruth=[]
        VisibleRows=[]
        SelectedRow=0
        Busy=false
        TrainingInfo=[]
    end
    methods
        function app=VIStudioTrainingAppV4(task,visible)
            if nargin<1, task='classification'; end
            if nargin<2, visible='on'; end
            app.Task=string(validatestring(task,{'classification','detection','anomaly'}));
            app.build(); registerApp(app,app.UIFigure); app.UIFigure.Visible=visible;
            app.refresh();
            if nargout==0, clear app; end
        end
        function delete(app)
            if ~isempty(app.UIFigure) && isvalid(app.UIFigure), delete(app.UIFigure); end
        end
        function names=modelChoices(app)
            names=VIStudioTrainingDataV4.models(app.Task);
        end
        function chooseModel(app,name)
            app.idle(); name=string(name);
            assert(isscalar(name) && ismember(name,app.modelChoices()),'VIStudioV4:UnknownModel','Unknown model.');
            app.UI.Model.Value=name; app.refresh();
        end
        function loadFolder(app,folder)
            app.idle(); assert(app.Task~="detection",'VIStudioV4:NeedLabels','偵測訓練請匯入框選標註 MAT。 / Import a box annotation MAT.');
            [samples,summary]=VIStudioTrainingDataV4.folder(folder);
            app.accept(samples,summary,[],folder);
        end
        function loadAnnotations(app,file)
            app.idle(); assert(app.Task=="detection",'VIStudioV4:InvalidTask','Only detection uses box annotations.');
            [samples,summary,gt]=VIStudioTrainingDataV4.groundTruth(file);
            app.accept(samples,summary,gt,file);
        end
        function filterImages(app,query,label)
            app.idle(); if nargin<3, label="all"; end
            label=string(label);
            assert(label=="all" || ismember(label,app.Distribution.Class),'VIStudioV4:UnknownClass','Unknown class.');
            app.UI.Search.Value=char(query); app.UI.Class.Value=label;
            app.updateBrowser();
        end
        function selectImage(app,index)
            app.idle(); validateattributes(index,{'numeric'},{'scalar','integer','>=',1,'<=',numel(app.VisibleRows)});
            app.SelectedRow=index; row=app.VisibleRows(index); file=app.Samples.File(row);
            app.SelectedFile=file; cla(app.UI.Image);
            try
                image=VIStudioData.readImage(file,[]); h=size(image,1); w=size(image,2);
                if app.Task=="detection" && app.UI.Boxes.Value
                    for c=1:height(app.Distribution)
                        name=app.Distribution.Class(c); boxes=app.GroundTruth.(name){row};
                        if ~isempty(boxes)
                            image=insertObjectAnnotation(image,'rectangle',boxes, ...
                                repmat(cellstr(name),size(boxes,1),1),'LineWidth',3);
                        end
                    end
                end
                imshow(image,'Parent',app.UI.Image); app.UI.Image.Toolbar.Visible='on';
                app.UI.ImageInfo.Text=sprintf('%s\n%s | %d × %d px | %d 物件 / objects', ...
                    file,app.Samples.Label(row),w,h,app.Samples.Objects(row));
            catch err
                app.UI.ImageInfo.Text=char(file+newline+"無法讀取 / Cannot read: "+string(err.message));
            end
            app.UI.Counter.Text=sprintf('%d / %d',index,numel(app.VisibleRows));
            app.UI.Files.Selection=[index 1]; app.refresh();
        end
        function nextImage(app,step)
            app.idle(); if isempty(app.VisibleRows), return; end
            app.selectImage(max(1,min(numel(app.VisibleRows),app.SelectedRow+step)));
        end
        function setTrainingOptions(app,options)
            app.idle(); names=fieldnames(options);
            allowed={'Epochs','Batch','LearnRate','Validation','Environment','Size','NormalClass'};
            assert(all(ismember(names,allowed)),'VIStudioV4:InvalidOptions','Unknown training option.');
            for k=1:numel(names), app.UI.(names{k}).Value=options.(names{k}); end
            app.refresh();
        end
        function model=train(app)
            app.idle(); assert(~isempty(app.Samples),'VIStudioV4:MissingData','請先載入訓練資料。 / Load training data first.');
            choice=string(app.UI.Model.Value); app.Busy=true; app.refresh();
            cleanup=onCleanup(@() app.finish());
            app.status('訓練中 / Training: '+choice); drawnow;
            progress=[];
            if strcmp(app.UIFigure.Visible,'on')
                progress=uiprogressdlg(app.UIFigure,'Title','訓練模型 / Train model', ...
                    'Message','首次使用可能下載預訓練權重 / First use may download weights','Indeterminate','on');
            end
            cleanupProgress=onCleanup(@() app.closeProgress(progress));
            environment=app.UI.Environment.Value; validation=app.UI.Validation.Value;
            info=[]; normal="";
            if app.Task=="classification"
                ds=imageDatastore(cellstr(app.Samples.File),'ReadFcn',@(f) VIStudioData.readImage(f,[]));
                ds.Labels=categorical(app.Samples.Label);
                [training,val,~]=VIStudioData.splitClassification(ds,[100-validation validation 0]);
                classes=string(categories(ds.Labels));
                candidate=imagePretrainedNetwork(choice,'NumClasses',numel(classes));
                input=candidate.Layers(1).InputSize;
                training=augmentedImageDatastore(input(1:2),training,'ColorPreprocessing','gray2rgb');
                validationData=[];
                if ~isempty(val.Files), validationData=augmentedImageDatastore(input(1:2),val,'ColorPreprocessing','gray2rgb'); end
                opts=app.options(environment,validationData);
                [candidate,info]=trainnet(training,candidate,"crossentropy",opts);
            elseif app.Task=="detection"
                classes=app.Distribution.Class;
                assert(all(app.Distribution.Count>0),'VIStudioV4:EmptyClass','每個標註類別至少需要一個框。 / Each class needs a box.');
                parts=VIStudioData.splitIndices(height(app.Samples),[100-validation validation],42);
                input=[app.UI.Size.Value app.UI.Size.Value 3];
                architecture=lower(extractAfter(choice,"YOLOX-"))+"-coco";
                candidate=yoloxObjectDetector(architecture,classes,'InputSize',input);
                training=app.detectionDatastore(parts{1},input); validationData=[];
                if ~isempty(parts{2}), validationData=app.detectionDatastore(parts{2},input); end
                opts=app.options(environment,validationData);
                [candidate,info]=trainYOLOXObjectDetector(training,candidate,opts,'FreezeSubNetwork','none');
            else
                normal=string(app.UI.NormalClass.Value); input=[app.UI.Size.Value app.UI.Size.Value 3];
                normalFiles=app.Samples.File(app.Samples.Label==normal);
                assert(numel(normalFiles)>=2,'VIStudioV4:MissingNormal','至少需要兩張正常影像。 / At least two normal images are required.');
                training=imageDatastore(cellstr(normalFiles),'ReadFcn',@(f) VIStudioData.readImage(f,input));
                classes=["Normal";"Anomaly"];
                if startsWith(choice,'PatchCore')
                    backbone="resnet18"; if contains(choice,'50'), backbone="resnet50"; end
                    candidate=patchCoreAnomalyDetector('Backbone',backbone);
                    candidate=trainPatchCoreAnomalyDetector(training,candidate,'CompressionRatio',0.1, ...
                        'MiniBatchSize',app.UI.Batch.Value,'ExecutionEnvironment',environment);
                elseif startsWith(choice,'FCDD')
                    files=app.Samples.File(app.Samples.Label~=normal);
                    assert(~isempty(files),'VIStudioV4:MissingAnomaly','FCDD 需要異常訓練影像。 / FCDD requires anomaly images.');
                    abnormal=imageDatastore(cellstr(files),'ReadFcn',@(f) VIStudioData.readImage(f,input));
                    candidate=fcddAnomalyDetector(pretrainedEncoderNetwork("resnet18",3));
                    candidate=trainFCDDAnomalyDetector(training,abnormal,candidate,app.options(environment,[]));
                else
                    network="pdn-small"; if contains(choice,'Medium'), network="pdn-medium"; end
                    candidate=efficientADAnomalyDetector('Network',network);
                    candidate=trainEfficientADAnomalyDetector(training,candidate,app.options(environment,[]));
                end
            end
            % Commit only after successful training. Save metadata describes the trained model.
            app.TrainedModel=candidate; app.TrainingInfo=info;
            app.Metadata=struct('ClassNames',classes,'ImageSize',input(1:2),'ModelName',choice, ...
                'NormalLabel',normal,'Calibrated',false,'Task',app.Task,'SourceFiles',app.Samples.File);
            model=candidate;
            app.UI.Trained.Text='已訓練 / Trained: '+choice;
            message="訓練完成，可儲存給 V3 檢測。 / Training complete. Save for V3 inspection.";
            if app.Task=="anomaly", message=message+newline+'異常門檻仍需以獨立資料校準。 / Calibrate thresholds with independent data.'; end
            app.status(message);
        end
        function saveModel(app,file)
            app.idle(); assert(~isempty(app.TrainedModel),'VIStudioV4:MissingModel','Train a model first.');
            assert(~isfile(file),'VIStudioV4:FileExists','檔案已存在，請使用新名稱。 / Choose a new filename.');
            [folder,~,ext]=fileparts(char(file));
            assert(strcmpi(ext,'.mat'),'VIStudioV4:InvalidExtension','Use .mat.');
            if isempty(folder), folder=pwd; end
            model=app.TrainedModel; metadata=app.Metadata; trainingInfo=app.TrainingInfo; %#ok<NASGU>
            temporary=[tempname(folder) '.mat']; clean=onCleanup(@() app.removeTemp(temporary));
            save(temporary,'model','metadata','trainingInfo','-v7.3');
            movefile(temporary,file); app.status('模型已儲存 / Model saved: '+string(file));
        end
    end
    methods (Access=private)
        function build(app)
            names=struct('classification','影像分類 / Classification','detection','物件偵測 / Object Detection','anomaly','異常偵測 / Anomaly Detection');
            app.UIFigure=uifigure('Name','VIStudio V4 | 訓練 Training | '+string(names.(app.Task)), ...
                'Position',[40 40 1360 740],'Visible','off','Color',[0.95 0.96 0.98], ...
                'CloseRequestFcn',@(~,~) app.close());
            root=uigridlayout(app.UIFigure,[3 1],'RowHeight',{72,'1x',48},'Padding',[18 12 18 10]);
            header=uigridlayout(root,[1 1],'BackgroundColor',[0.075 0.13 0.22],'Padding',[18 8 18 8]);
            uilabel(header,'Text','VIStudio V4  |  訓練 Training  |  '+string(names.(app.Task)), ...
                'FontSize',24,'FontWeight','bold','FontColor',[1 1 1]);
            body=uigridlayout(root,[1 2],'ColumnWidth',{310,'1x'},'Padding',[0 0 0 0],'ColumnSpacing',14);
            panel=uipanel(body,'Title','模型與訓練 / Model & Training','FontWeight','bold');
            sideRoot=uigridlayout(panel,[2 1],'RowHeight',{'1x',182},'Padding',[10 8 10 8]);
            heights={18,32,60,18,28,18,28,18,28,18,28,18,28,18,28,18,30};
            if app.Task=="classification", heights(12:15)={0,0,0,0};
            elseif app.Task=="detection", heights(14:15)={0,0}; end
            side=uigridlayout(sideRoot,[17 1],'RowHeight',heights, ...
                'Padding',[4 2 4 2],'RowSpacing',3,'Scrollable','on');
            uilabel(side,'Text','選擇模型 / Select model','FontWeight','bold');
            app.UI.Model=uidropdown(side,'Items',cellstr(app.modelChoices()),'ItemsData',app.modelChoices(), ...
                'ValueChangedFcn',@(~,~) app.refresh());
            app.UI.Hint=uilabel(side,'Text','','WordWrap','on','FontSize',11);
            uilabel(side,'Text','回合 / Epochs'); app.UI.Epochs=uieditfield(side,'numeric','Value',10,'Limits',[1 10000],'RoundFractionalValues','on');
            uilabel(side,'Text','批次大小 / Mini-batch'); app.UI.Batch=uieditfield(side,'numeric','Value',8,'Limits',[1 512],'RoundFractionalValues','on');
            uilabel(side,'Text','學習率 / Learning rate'); app.UI.LearnRate=uieditfield(side,'numeric','Value',0.0001,'Limits',[1e-8 1]);
            uilabel(side,'Text','驗證比例 (%) / Validation'); app.UI.Validation=uieditfield(side,'numeric','Value',20,'Limits',[0 50]);
            sizeLabel=uilabel(side,'Text','影像尺寸 / Image size');
            sizes=[224 256]; if app.Task=="detection", sizes=[320 416 640]; end
            app.UI.Size=uidropdown(side,'Items',cellstr(string(sizes)),'ItemsData',sizes);
            normalLabel=uilabel(side,'Text','正常類別 / Normal class'); app.UI.NormalClass=uidropdown(side,'Items',{'good'});
            if app.Task=="classification", sizeLabel.Visible='off'; app.UI.Size.Visible='off'; end
            if app.Task~="anomaly", normalLabel.Visible='off'; app.UI.NormalClass.Visible='off'; end
            uilabel(side,'Text','運算裝置 / Environment'); app.UI.Environment=uidropdown(side,'Items',{'auto','cpu','gpu'});
            actions=uigridlayout(sideRoot,[4 1],'RowHeight',{40,34,34,48},'Padding',[4 4 4 4],'RowSpacing',5);
            app.UI.Train=uibutton(actions,'Text','開始訓練 / Train','FontWeight','bold', ...
                'BackgroundColor',[0.06 0.56 0.46],'FontColor',[1 1 1],'ButtonPushedFcn',@(~,~) app.action(@() app.train()));
            app.UI.Save=uibutton(actions,'Text','儲存模型 / Save model','ButtonPushedFcn',@(~,~) app.action(@() app.pickSave()));
            app.UI.Inspect=uibutton(actions,'Text','開啟 V3 檢測 / Open inspection','ButtonPushedFcn',@(~,~) app.openInspection());
            app.UI.Trained=uilabel(actions,'Text','尚未訓練 / No trained model','WordWrap','on');
            app.UI.Tabs=uitabgroup(body);
            overview=uitab(app.UI.Tabs,'Title','01 資料分布 / Distribution');
            grid=uigridlayout(overview,[5 2],'RowHeight',{42,48,40,'1x',64},'ColumnWidth',{'2x','1x'},'Padding',[16 12 16 12]);
            text='載入資料夾 / Load folder'; if app.Task=="detection", text='載入標註 MAT / Load annotations'; end
            app.UI.Load=uibutton(grid,'Text',text,'FontWeight','bold','ButtonPushedFcn',@(~,~) app.action(@() app.pickData()));
            app.UI.Load.Layout.Column=[1 2];
            app.UI.Path=uilabel(grid,'Text','尚未載入資料 / No data loaded','WordWrap','on'); app.UI.Path.Layout.Row=2; app.UI.Path.Layout.Column=[1 2];
            app.UI.Summary=uilabel(grid,'Text','類別資料夾作為標籤 / Subfolders define labels','FontWeight','bold','WordWrap','on'); app.UI.Summary.Layout.Row=3; app.UI.Summary.Layout.Column=[1 2];
            app.UI.PiePanel=uipanel(grid,'Title','資料比例 / Data proportions'); app.UI.PiePanel.Layout.Row=4; app.UI.PiePanel.Layout.Column=1;
            app.UI.Counts=uitable(grid,'ColumnName',{'類別 / Class','數量 / Count'},'RowName',{}); app.UI.Counts.Layout.Row=4; app.UI.Counts.Layout.Column=2;
            app.UI.Log=uitextarea(grid,'Editable','off','Value',{'先載入資料，再選擇模型。 / Load data, then choose a model.'}); app.UI.Log.Layout.Row=5; app.UI.Log.Layout.Column=[1 2];
            app.UI.Browser=uitab(app.UI.Tabs,'Title','02 照片檢視 / Image Browser');
            grid=uigridlayout(app.UI.Browser,[4 2],'RowHeight',{36,42,'1x',86},'ColumnWidth',{310,'1x'},'Padding',[16 12 16 12]);
            app.UI.Search=uieditfield(grid,'text','Placeholder','搜尋檔名 / Search filename','ValueChangedFcn',@(~,~) app.action(@() app.updateBrowser()));
            app.UI.Class=uidropdown(grid,'Items',{'全部類別 / All classes'},'ItemsData',"all",'ValueChangedFcn',@(~,~) app.action(@() app.updateBrowser()));
            nav=uigridlayout(grid,[1 4],'ColumnWidth',{'1x','1x',90,180},'Padding',[0 0 0 0]); nav.Layout.Row=2; nav.Layout.Column=[1 2];
            app.UI.Previous=uibutton(nav,'Text','上一張 / Previous','ButtonPushedFcn',@(~,~) app.action(@() app.nextImage(-1)));
            app.UI.Next=uibutton(nav,'Text','下一張 / Next','ButtonPushedFcn',@(~,~) app.action(@() app.nextImage(1)));
            app.UI.Counter=uilabel(nav,'Text','0 / 0','HorizontalAlignment','center');
            app.UI.Boxes=uicheckbox(nav,'Text','顯示標註 / Show boxes','Value',true,'ValueChangedFcn',@(~,~) app.action(@() app.selectImage(app.SelectedRow)));
            app.UI.Files=uitable(grid,'ColumnName',{'檔名 / Filename','類別 / Class','物件 / Objects'},'RowName',{}, ...
                'CellSelectionCallback',@(~,e) app.clicked(e)); app.UI.Files.Layout.Row=3; app.UI.Files.Layout.Column=1;
            app.UI.Image=uiaxes(grid); app.UI.Image.Layout.Row=3; app.UI.Image.Layout.Column=2; app.UI.Image.XTick=[]; app.UI.Image.YTick=[];
            app.UI.ImageInfo=uilabel(grid,'Text','選取照片檢視原圖 / Select a photo','WordWrap','on','Interpreter','none'); app.UI.ImageInfo.Layout.Row=4; app.UI.ImageInfo.Layout.Column=[1 2];
            app.UI.Footer=uilabel(root,'Text','就緒 / Ready','WordWrap','on');
        end
        function accept(app,samples,summary,gt,path)
            app.Samples=samples; app.Distribution=summary; app.GroundTruth=gt;
            app.UI.Path.Text=path; app.UI.Counts.Data=summary;
            classes=summary.Class;
            app.UI.Class.Items=[{'全部類別 / All classes'};cellstr(classes)]; app.UI.Class.ItemsData=["all";classes]; app.UI.Class.Value="all";
            app.UI.NormalClass.Items=cellstr(classes);
            if ismember("good",classes), app.UI.NormalClass.Value='good'; end
            app.UI.Search.Value='';
            unit='張影像 / images'; basis='影像張數 / Image counts';
            if app.Task=="detection", unit='個標註框 / boxes'; basis='標註框數 / Box counts'; end
            app.UI.Summary.Text=sprintf('%d 張影像 / images · %d 類別 / classes',height(samples),height(summary));
            if app.Task=="detection", app.UI.Summary.Text=string(app.UI.Summary.Text)+sprintf(' · %d %s',sum(summary.Count),unit); end
            delete(app.UI.PiePanel.Children); pieGrid=uigridlayout(app.UI.PiePanel,[1 1]); ax=uiaxes(pieGrid);
            positive=summary.Count>0;
            if any(positive)
                counts=summary.Count(positive); names=summary.Class(positive);
                if numel(counts)>8
                    [counts,order]=sort(counts,'descend'); names=names(order);
                    counts=[counts(1:8);sum(counts(9:end))]; names=[names(1:8);"其他 / Other"];
                    basis=[basis ' · 前八類，其餘合併 / Top 8 + other'];
                end
                labels=compose('%s: %d (%.1f%%)',names,counts,100*counts/sum(counts));
                pie(ax,counts,cellstr(labels)); colormap(ax,lines(max(2,numel(counts))));
            else
                text(ax,0.5,0.5,'沒有標註框 / No boxes','HorizontalAlignment','center'); axis(ax,'off');
            end
            title(ax,basis); ax.Toolbar.Visible='off';
            app.updateBrowser(); app.status('資料已載入，可查看分布與照片。 / Data loaded. Browse distribution and photos.'); app.refresh();
        end
        function updateBrowser(app)
            if isempty(app.Samples), return; end
            app.VisibleRows=VIStudioTrainingDataV4.filter(app.Samples,app.UI.Search.Value,app.UI.Class.Value,app.GroundTruth);
            view=app.Samples(app.VisibleRows,:); files=strings(height(view),1);
            for k=1:height(view), [~,name,ext]=fileparts(view.File(k)); files(k)=name+ext; end
            app.UI.Files.Data=table(files,view.Label,view.Objects,'VariableNames',{'File','Class','Objects'});
            app.SelectedRow=0; app.SelectedFile="";
            if ~isempty(app.VisibleRows), app.selectImage(1);
            else, cla(app.UI.Image); app.UI.ImageInfo.Text='沒有符合條件的照片 / No matching photos'; app.UI.Counter.Text='0 / 0'; app.refresh(); end
        end
        function ds=detectionDatastore(app,indices,input)
            data=app.GroundTruth(indices,:);
            images=imageDatastore(data.imageFilename,'ReadFcn',@(f) VIStudioData.readImage(f,[]));
            boxes=boxLabelDatastore(data(:,2:end));
            ds=transform(combine(images,boxes),@(d) VIStudioTrainingDataV4.prepareDetection(d,input));
        end
        function opts=options(app,environment,validationData)
            args={'MaxEpochs',app.UI.Epochs.Value,'MiniBatchSize',app.UI.Batch.Value, ...
                'InitialLearnRate',app.UI.LearnRate.Value,'ExecutionEnvironment',environment, ...
                'Verbose',false,'Plots','none','Shuffle','every-epoch'};
            if ~isempty(validationData), args=[args {'ValidationData',validationData}]; end
            opts=trainingOptions('adam',args{:});
        end
        function refresh(app)
            fields=fieldnames(app.UI);
            for k=1:numel(fields)
                h=app.UI.(fields{k}); if isprop(h,'Enable'), h.Enable=app.on(~app.Busy); end
            end
            app.UI.Train.Enable=app.on(~app.Busy && ~isempty(app.Samples));
            app.UI.Save.Enable=app.on(~app.Busy && ~isempty(app.TrainedModel));
            app.UI.Previous.Enable=app.on(~app.Busy && app.SelectedRow>1);
            app.UI.Next.Enable=app.on(~app.Busy && app.SelectedRow<numel(app.VisibleRows));
            app.UI.Boxes.Enable=app.on(~app.Busy && app.Task=="detection" && app.SelectedRow>0);
            app.UI.NormalClass.Enable=app.on(~app.Busy && app.Task=="anomaly");
            app.UI.Size.Enable=app.on(~app.Busy && app.Task~="classification");
            patch=app.Task=="anomaly" && startsWith(string(app.UI.Model.Value),'PatchCore');
            app.UI.Validation.Enable=app.on(~app.Busy && app.Task~="anomaly");
            app.UI.Epochs.Enable=app.on(~app.Busy && ~patch); app.UI.LearnRate.Enable=app.on(~app.Busy && ~patch);
            hint="選擇後按訓練才載入權重。 / Weights load when training starts.";
            if app.Task=="classification", hint=hint+newline+'輸入尺寸依模型自動設定。 / Model defines input size.';
            elseif patch, hint=hint+newline+'只用正常影像訓練，不使用 Epochs。 / Normal-only; no epochs.';
            elseif app.Task=="anomaly" && startsWith(string(app.UI.Model.Value),'FCDD'), hint=hint+newline+'需正常與異常影像。 / Requires normal and anomaly images.';
            elseif app.Task=="anomaly", hint=hint+newline+'只用正常影像訓練。 / Trains on normal images only.'; end
            app.UI.Hint.Text=hint;
        end
        function pickData(app)
            if app.Task=="detection"
                [file,folder]=uigetfile('*.mat','載入標註 / Load annotations'); if ~isequal(file,0), app.loadAnnotations(fullfile(folder,file)); end
            else
                folder=uigetdir(pwd,'載入類別資料夾 / Load class folders'); if ~isequal(folder,0), app.loadFolder(folder); end
            end
        end
        function pickSave(app)
            [file,folder]=uiputfile('*.mat','儲存新模型 / Save new model','VIStudio_V4_model.mat');
            if ~isequal(file,0), app.saveModel(fullfile(folder,file)); end
        end
        function clicked(app,event)
            if ~isempty(event.Indices) && ~app.Busy, app.action(@() app.selectImage(event.Indices(1,1))); end
        end
        function openInspection(app)
            switch app.Task
                case "classification", VIStudioClassificationAppV3;
                case "detection", VIStudioObjectDetectionAppV3;
                case "anomaly", VIStudioAnomalyAppV3;
            end
        end
        function action(app,operation)
            try, operation(); catch err, app.status(string(err.message)); uialert(app.UIFigure,err.message,'無法完成 / Unable to complete'); end
        end
        function status(app,message)
            app.UI.Footer.Text=message; app.UI.Log.Value=cellstr(splitlines(string(message))); drawnow limitrate;
        end
        function idle(app), assert(~app.Busy,'VIStudioV4:Busy','正在訓練，請稍候。 / Training is running.'); end
        function finish(app), app.Busy=false; app.refresh(); end
        function close(app)
            if app.Busy, return; end
            delete(app);
        end
    end
    methods (Static,Access=private)
        function value=on(flag), if flag, value='on'; else, value='off'; end, end
        function closeProgress(progress), if ~isempty(progress) && isvalid(progress), delete(progress); end, end
        function removeTemp(file), if isfile(file), delete(file); end, end
    end
end
