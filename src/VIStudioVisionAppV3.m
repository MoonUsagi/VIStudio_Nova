classdef VIStudioVisionAppV3 < matlab.apps.AppBase
    % V3: review, projects, filtering, ROI, evaluation and resumable batches.
    % Original and V2 workspaces remain unchanged.
    properties (SetAccess=private)
        UIFigure
        Task
        Results=table()
        LastPrediction=[]
    end
    properties (Access=private)
        UI=struct()
        Model=[]
        Classes=strings(0,1)
        InputSize=[224 224 3]
        InputImage=[]
        InputFile=""
        Dataset=[]
        ModelName=""
        Busy=false
        LogLines={}
        ModelPath=""
        ModelDigest=""
        ROI=[]
        PixelThreshold=[]
        NormalLabel="good"
        Calibrated=false
        Filter
        VisibleRows=[]
        SelectedFile=""
        GroundTruth=[]
        Language='bilingual'
        TranslationRecords={}
        BatchSignature=""
        LastMessage=""
    end
    methods
        function app=VIStudioVisionAppV3(task,visible)
            if nargin<2, visible='on'; end
            app.Task=string(validatestring(task,{'classification','detection','anomaly'}));
            app.Filter=VIStudioToolsV3.defaultFilter();
            app.buildUI(); registerApp(app,app.UIFigure);
            app.captureTranslations();
            app.UIFigure.Visible=validatestring(visible,{'on','off'});
            app.log('V3 工作區已就緒，請載入模型。 / Ready. Load a model to begin.');
            app.refresh();
        end
        function delete(app)
            if ~isempty(app.UIFigure) && isvalid(app.UIFigure), delete(app.UIFigure); end
        end
        function loadModel(app,file)
            app.assertIdle(); app.Busy=true; app.refresh();
            cleanup=onCleanup(@() app.finish());
            p=app.progress('載入模型 / Load model','驗證模型 / Validating model',false);
            progressCleanup=onCleanup(@() delete(p));
            loaded=load(file);
            assert(isfield(loaded,'model'),'VIStudioV3:MissingModel', ...
                'MAT 檔必須包含 model。 / The MAT file must contain model.');
            candidate=loaded.model;
            if app.Task=="classification"
                assert(isa(candidate,'dlnetwork'),'VIStudioV3:InvalidClassifier', ...
                    '分類需使用 dlnetwork。 / Classification requires a dlnetwork.');
                assert(isscalar(candidate.InputNames) && isscalar(candidate.OutputNames), ...
                    'VIStudioV3:InvalidClassifier','需單一輸入與輸出。 / A single input and output are required.');
                layer=getLayer(candidate,candidate.InputNames{1});
                assert(isa(layer,'nnet.cnn.layer.ImageInputLayer'),'VIStudioV3:InvalidClassifier', ...
                    '需二維影像輸入層。 / A 2D image input layer is required.');
                input=layer.InputSize;
                classes=[];
                if isfield(loaded,'metadata') && isfield(loaded.metadata,'ClassNames')
                    classes=loaded.metadata.ClassNames;
                elseif isfield(loaded,'classNames')
                    classes=loaded.classNames;
                end
                classes=string(classes(:));
                assert(numel(classes)>=2 && all(~ismissing(classes)) && all(strlength(classes)>0) && ...
                    numel(unique(classes))==numel(classes),'VIStudioV3:MissingClasses', ...
                    '需提供 metadata.ClassNames，順序須對應模型輸出。 / Provide ordered metadata.ClassNames.');
                validateattributes(input,{'numeric'},{'vector','numel',3,'positive','integer','finite'});
                assert(ismember(input(3),[1 3]),'VIStudioV3:InvalidChannels', ...
                    '僅支援灰階或 RGB 模型。 / Only grayscale and RGB models are supported.');
                scores=minibatchpredict(candidate,zeros(input,'uint8'),'ExecutionEnvironment','cpu');
                VIStudioVisionAppV3.probabilities(scores,numel(classes));
            elseif app.Task=="detection"
                supported=["yoloxObjectDetector","yolov4ObjectDetector","yolov3ObjectDetector", ...
                    "yolov2ObjectDetector","ssdObjectDetector","fasterRCNNObjectDetector"];
                assert(ismember(string(class(candidate)),supported),'VIStudioV3:InvalidDetector', ...
                    '請使用 YOLOX、YOLOv2–4、SSD 或 Faster R-CNN。 / Unsupported detector type.');
                classes=string(candidate.ClassNames(:)); input=candidate.InputSize;
                validateattributes(input,{'numeric'},{'vector','numel',3,'positive','integer','finite'});
                % Probe before replacing the active model.
                detect(candidate,zeros(input,'uint8'),'Threshold',0.99,'ExecutionEnvironment','cpu');
            else
                assert(ismember(string(class(candidate)),["patchCoreAnomalyDetector","fcddAnomalyDetector", ...
                    "efficientADAnomalyDetector"]),'VIStudioV3:InvalidAnomalyModel', ...
                    '請載入異常偵測模型。 / An anomaly detector is required.');
                input=[224 224 3];
                if isprop(candidate,'ImageSize') && ~isempty(candidate.ImageSize), input=candidate.ImageSize; end
                if isfield(loaded,'metadata') && isfield(loaded.metadata,'ImageSize')
                    input=[loaded.metadata.ImageSize(1:2) 3];
                end
                validateattributes(input,{'numeric'},{'vector','numel',3,'positive','integer','finite'});
                score=predict(candidate,zeros(input,'uint8'),'ExecutionEnvironment','cpu');
                validateattributes(score,{'numeric'},{'scalar','finite','real'});
                classes=["Normal";"Anomaly"];
            end
            digest=VIStudioToolsV3.fileHash(file);
            app.Model=candidate; app.Classes=classes; app.InputSize=double(input(:)');
            app.ModelPath=VIStudioToolsV3.canonicalPath(file); app.ModelDigest=digest;
            if app.Task=="anomaly"
                app.NormalLabel="good"; app.PixelThreshold=[];
                app.Calibrated=~isempty(candidate.Threshold) && isfinite(candidate.Threshold);
                if app.Calibrated, app.UI.Threshold.Value=double(candidate.Threshold); end
                if isfield(loaded,'metadata')
                    md=loaded.metadata;
                    if isfield(md,'Calibrated'), app.Calibrated=logical(md.Calibrated); end
                    if isfield(md,'NormalLabel') && strlength(string(md.NormalLabel))>0, app.NormalLabel=string(md.NormalLabel); end
                end
                app.UI.NormalClass.Value=char(app.NormalLabel);
            end
            [~,name,extension]=fileparts(file); app.ModelName=string(name)+string(extension);
            app.clearResults(); app.clearPrediction(); app.Filter=VIStudioToolsV3.defaultFilter();
            app.UI.ModelInfo.Text=sprintf('%s\n%d × %d × %d  ·  %d 類別 / classes', ...
                class(candidate),app.InputSize,numel(classes));
            app.UI.ClassList.Value=cellstr(classes);
            app.UI.FilterClass.Items=[{'全部類別 / All classes'};cellstr(classes)];
            app.UI.FilterClass.ItemsData=["all";classes]; app.UI.FilterClass.Value="all";
            app.resetFilters();
            app.log('已載入模型 / Loaded: '+app.ModelName);
        end
        function importFolder(app,folder)
            app.assertIdle();
            ds=imageDatastore(folder,'IncludeSubfolders',true,'LabelSource','foldernames');
            assert(~isempty(ds.Files),'VIStudioV3:EmptyFolder','資料夾內沒有影像。 / No images found.');
            preview=VIStudioData.readImage(ds.Files{1},[]);
            app.Dataset=ds; app.clearResults();
            app.UI.DatasetPath.Text=folder;
            app.UI.DatasetPath.UserData="";
            app.UI.DatasetCount.Text=sprintf('%d %s',numel(ds.Files),app.caption('張','images'));
            imshow(preview,'Parent',app.UI.Preview);
            title(app.UI.Preview,app.caption('資料預覽','Dataset preview'));
            app.log(sprintf('已匯入 %d 張影像 / Imported %d images.',numel(ds.Files),numel(ds.Files)));
            app.refresh();
        end
        function inspectImage(app,file)
            app.assertIdle();
            image=VIStudioData.readImage(file,[]);
            app.InputImage=image; app.InputFile=string(file); app.clearPrediction();
            imshow(image,'Parent',app.UI.Original);
            [~,name,extension]=fileparts(file);
            title(app.UI.Original,string(name)+string(extension),'Interpreter','none');
            app.log('已載入影像 / Image loaded.'); app.refresh();
        end
        function prediction=predictImage(app,file)
            app.assertIdle(); app.requireModel();
            if nargin>1, app.inspectImage(file); end
            assert(~isempty(app.InputImage),'VIStudioV3:MissingImage', ...
                '請先載入影像。 / Load an image first.');
            app.Busy=true; app.refresh(); cleanup=onCleanup(@() app.finish());
            p=app.progress('影像檢測 / Inspection','計算預測 / Running prediction',false);
            progressCleanup=onCleanup(@() delete(p));
            prediction=app.predict(app.InputImage);
            app.renderPrediction(prediction);
            app.LastPrediction=prediction;
            app.UI.Tabs.SelectedTab=app.UI.InspectionTab;
            app.log('檢測完成 / Inspection complete.');
        end
        function results=runBatch(app,resume)
            if nargin<2, resume=false; end
            app.assertIdle(); app.requireModel();
            assert(~isempty(app.Dataset),'VIStudioV3:MissingDataset','請先匯入資料夾。 / Import a folder first.');
            signature=app.signature();
            if resume
                assert(app.BatchSignature==signature,'VIStudioV3:IncompatibleCheckpoint', ...
                    '設定已改變，無法沿用進度。 / Settings changed; start a new batch.');
            else
                app.clearResults(); app.BatchSignature=signature;
            end
            labeled=app.Task~="detection" && app.UI.UseLabels.Value;
            if labeled && app.Task=="classification"
                assert(all(ismember(string(app.Dataset.Labels),app.Classes)), ...
                    'VIStudioV3:UnknownLabels','資料夾標籤不在模型類別中。 / Unknown folder labels.');
            end
            app.Busy=true; app.refresh(); cleanup=onCleanup(@() app.finish());
            p=app.progress('批次檢測 / Batch inspection','開始 / Starting',true);
            progressCleanup=onCleanup(@() delete(p)); paused=false;
            for k=1:numel(app.Dataset.Files)
                file=string(app.Dataset.Files{k});
                if resume && ~isempty(app.Results)
                    existing=find(app.Results.File==file,1);
                    if ~isempty(existing) && ~contains(app.Results.Status(existing),'Error') && isfile(file) && ...
                            app.Results.SourceHash(existing)==VIStudioToolsV3.fileHash(file), continue; end
                end
                drawnow;
                if ~isempty(p)
                    if p.CancelRequested, paused=true; break; end
                    p.Value=(k-1)/numel(app.Dataset.Files); p.Message=sprintf('%d / %d',k,numel(app.Dataset.Files));
                end
                actual=""; correct=NaN; errorMessage="";
                try
                    image=VIStudioData.readImage(file,[]); prediction=app.predict(image);
                    if labeled
                        actual=string(app.Dataset.Labels(k));
                        if app.Task=="anomaly"
                            if actual==app.NormalLabel, actual="Normal"; else, actual="Anomaly"; end
                        end
                        correct=double(actual==prediction.Label);
                    end
                catch err
                    errorMessage=string(err.message);
                    prediction=struct('Label',"",'Confidence',NaN,'Count',0,'Status',"失敗 / Error", ...
                        'Milliseconds',NaN,'Boxes',zeros(0,4),'Scores',[],'Labels',strings(0,1), ...
                        'Mask',[],'DefectArea',NaN,'DefectRegions',NaN,'ROI',[]);
                end
                row=app.resultRow(file,prediction,actual,correct,errorMessage);
                if isempty(app.Results)
                    app.Results=row;
                else
                    existing=find(app.Results.File==file,1);
                    if isempty(existing), app.Results=[app.Results;row]; else, app.Results(existing,:)=row; end
                end
                app.updateViews();
            end
            results=app.Results; app.UI.Tabs.SelectedTab=app.UI.ResultsTab;
            if paused, app.log('已暫停，進度已保留。 / Paused. Resume to continue.');
            else, app.log('批次完成；失敗影像可按繼續重試。 / Batch complete; resume retries failed images.'); end
        end
        function results=resumeBatch(app)
            results=app.runBatch(true);
        end
        function exportResults(app,file,scope)
            app.assertIdle();
            if nargin<3, scope='filtered'; end
            if strcmp(scope,'all'), results=app.Results; else, results=app.filteredResults(); end
            assert(~isempty(results),'VIStudioV3:MissingResults','尚無可匯出結果。 / No results to export.');
            results.Model=repmat(app.ModelName,height(results),1);
            results.Threshold=repmat(app.UI.Threshold.Value,height(results),1);
            writetable(results,file,'Encoding','UTF-8');
            app.log('結果已匯出 / Results exported.');
        end
        function setConfidence(app,value)
            app.assertIdle();
            validateattributes(value,{'numeric'},{'scalar','real','finite','>=',0});
            if app.Task~="anomaly", assert(value<=1,'Confidence must be at most 1.'); end
            if app.Task=="anomaly", app.Calibrated=true; end
            app.UI.Threshold.Value=value; app.settingsChanged();
        end
        function useFolderLabels(app,value)
            app.assertIdle();
            assert(app.Task~="detection",'VIStudioV3:NotClassification','僅供影像標籤評估 / Image-label evaluation only.');
            validateattributes(value,{'logical'},{'scalar'});
            app.UI.UseLabels.Value=value; app.clearResults(); app.refresh();
        end
        function selectWorkspace(app,name)
            % For scripted previews: data, results, or inspection.
            key=validatestring(name,{'data','results','inspection','review','evaluation'});
            tabs=struct('data',app.UI.DataTab,'results',app.UI.ResultsTab,'inspection',app.UI.InspectionTab, ...
                'review',app.UI.ReviewTab,'evaluation',app.UI.EvaluationTab);
            app.UI.Tabs.SelectedTab=tabs.(key);
        end
        function setFilter(app,options)
            app.assertIdle(); filter=VIStudioToolsV3.defaultFilter();
            fields=fieldnames(options);
            for k=1:numel(fields)
                assert(isfield(filter,fields{k}),'VIStudioV3:InvalidFilter','Unknown filter field.');
                filter.(fields{k})=options.(fields{k});
            end
            for field={'Query','Class','Status','Review'}, filter.(field{1})=string(filter.(field{1})); end
            assert(filter.MinConfidence<=filter.MaxConfidence,'VIStudioV3:InvalidFilter','Invalid confidence range.');
            VIStudioToolsV3.filterResults(app.Results,filter);
            app.Filter=filter; app.updateViews();
            app.UI.Search.Value=char(filter.Query);
            if ismember(filter.Class,string(app.UI.FilterClass.ItemsData)), app.UI.FilterClass.Value=filter.Class; end
            app.UI.FilterStatus.Value=char(filter.Status); app.UI.FilterReview.Value=char(filter.Review);
            minimum=filter.MinConfidence; if ~isfinite(minimum), minimum=0; end
            maximum=filter.MaxConfidence;
            if ~isfinite(maximum), maximum=1; if app.Task=="anomaly", maximum=realmax; end; end
            app.UI.Minimum.Value=minimum; app.UI.Maximum.Value=maximum;
        end
        function results=filteredResults(app)
            results=VIStudioToolsV3.filterResults(app.Results,app.Filter);
        end
        function setReview(app,file,state,label,note)
            app.assertIdle();
            state=string(validatestring(state,{'pending','accepted','corrected','rejected'}));
            if nargin<4, label=""; end
            if nargin<5, note=""; end
            label=string(label); note=string(note);
            row=find(app.Results.File==string(file),1);
            assert(~isempty(row),'VIStudioV3:MissingResult','找不到此影像結果。 / Result not found.');
            if state=="accepted" && strlength(label)==0, label=app.Results.Prediction(row); end
            if state=="corrected", assert(strlength(label)>0,'VIStudioV3:MissingReviewLabel','請輸入正確答案。 / Enter the corrected label.'); end
            if app.Task~="detection" && any(state==["accepted","corrected"])
                assert(ismember(label,app.Classes),'VIStudioV3:UnknownLabels','覆核答案不在模型類別中。 / Unknown review label.');
            end
            app.Results.ReviewState(row)=state; app.Results.ReviewedLabel(row)=label;
            app.Results.ReviewNote(row)=note;
            app.Results.ReviewTime(row)=string(datetime('now','Format','yyyy-MM-dd HH:mm:ss'));
            app.updateViews(); app.log('覆核已儲存，原始預測保留。 / Review saved; prediction retained.');
        end
        function setROI(app,roi)
            app.assertIdle();
            if ~isempty(roi)
                validateattributes(roi,{'numeric'},{'vector','numel',4,'integer','positive','finite'});
                if ~isempty(app.InputImage), VIStudioToolsV3.cropImage(app.InputImage,roi); end
            end
            if app.Task=="anomaly" && ~isequal(app.ROI,double(roi))
                app.Calibrated=false; app.PixelThreshold=[];
            end
            app.ROI=double(roi); app.settingsChanged();
            if isempty(roi), app.UI.ROIInfo.Text='全圖 / Full image';
            else, app.UI.ROIInfo.Text=sprintf('ROI [%d %d %d %d]',roi); end
        end
        function setPixelThreshold(app,value)
            app.assertIdle();
            assert(app.Task=="anomaly",'VIStudioV3:NotAnomaly','Only available for anomaly inspection.');
            validateattributes(value,{'numeric'},{'scalar','real','finite','nonnegative'});
            app.PixelThreshold=value; app.UI.PixelThreshold.Value=value; app.settingsChanged();
        end
        function setNormalClass(app,label)
            app.assertIdle(); label=string(label);
            assert(isscalar(label) && strlength(label)>0,'VIStudioV3:MissingLabels','Normal label cannot be empty.');
            app.NormalLabel=label; app.UI.NormalClass.Value=char(label); app.settingsChanged();
        end
        function setLanguage(app,language)
            app.assertIdle(); app.Language=validatestring(language,{'bilingual','zh','en'});
            for k=1:size(app.TranslationRecords,1)
                h=app.TranslationRecords{k,1}; property=app.TranslationRecords{k,2};
                if ~isvalid(h), continue; end
                if isequal(h.(property),app.TranslationRecords{k,4})
                    value=VIStudioToolsV3.translate(app.TranslationRecords{k,3},app.Language);
                    h.(property)=value; app.TranslationRecords{k,4}=value;
                end
            end
            app.UI.Language.Value=app.Language; app.updateViews(); app.refresh();
            titles=struct('classification',{{'影像分類','Image Classification'}}, ...
                'detection',{{'物件偵測','Object Detection'}},'anomaly',{{'異常偵測','Anomaly Detection'}});
            taskTitle=titles.(char(app.Task));
            if strcmp(app.Language,'en'), name=taskTitle{2};
            elseif strcmp(app.Language,'zh'), name=taskTitle{1};
            else, name=[taskTitle{1} ' ' taskTitle{2}]; end
            app.UI.Header.Text=['VIStudio V3 / ' name]; app.UIFigure.Name=['VIStudio V3 | ' name];
            count=0; if ~isempty(app.Dataset), count=numel(app.Dataset.Files); end
            app.UI.DatasetCount.Text=sprintf('%d %s',count,app.caption('張','images'));
            title(app.UI.Preview,app.caption('資料預覽','Dataset preview'));
            if ~isempty(app.UI.DatasetPath.UserData) && strlength(string(app.UI.DatasetPath.UserData))>0
                app.UI.DatasetPath.Text=char(app.caption('專案影像清單','Project image list')+": "+string(app.UI.DatasetPath.UserData));
            end
            if isempty(app.ROI), app.UI.ROIInfo.Text=app.caption('全圖','Full image'); end
            app.UI.FilterClass.Items=[{char(app.caption('全部類別','All classes'))};cellstr(app.Classes)];
            if strlength(app.LastMessage)>0, app.UI.Footer.Text=VIStudioToolsV3.translate(app.LastMessage,app.Language); end
        end
        function saveProject(app,file)
            app.assertIdle(); app.requireModel();
            assert(~strcmpi(VIStudioToolsV3.canonicalPath(file),app.ModelPath), ...
                'VIStudioV3:ModelOverwrite','專案不可覆蓋模型。 / Project cannot overwrite its model.');
            project=struct('Version',1,'Task',app.Task,'ModelPath',app.ModelPath,'ModelDigest',app.ModelDigest, ...
                'Threshold',app.UI.Threshold.Value,'Environment',app.UI.Environment.Value, ...
                'ROI',app.ROI,'PixelThreshold',app.PixelThreshold,'NormalLabel',app.NormalLabel, ...
                'Calibrated',app.Calibrated,'Language',app.Language,'UseLabels',false, ...
                'Files',strings(0,1),'Labels',strings(0,1),'Results',app.Results,'Filter',app.Filter, ...
                'InputFile',app.InputFile,'BatchSignature',app.BatchSignature,'GroundTruth',app.GroundTruth);
            if app.Task~="detection", project.UseLabels=app.UI.UseLabels.Value; end
            if ~isempty(app.Dataset), project.Files=string(app.Dataset.Files); project.Labels=string(app.Dataset.Labels); end
            [folder,~,ext]=fileparts(file); if isempty(folder), folder=pwd; end
            assert(strcmpi(ext,'.mat'),'VIStudioV3:ProjectExtension','請使用 .mat 專案檔。 / Use a .mat project file.');
            temporary=[tempname(folder) '.mat'];
            cleanup=onCleanup(@() app.removeTemporary(temporary));
            save(temporary,'project','-v7.3'); movefile(temporary,file,'f');
            app.log('專案已儲存 / Project saved.');
        end
        function openProject(app,file)
            app.assertIdle(); loaded=load(file,'project');
            assert(isfield(loaded,'project'),'VIStudioV3:InvalidProject','Missing project.'); p=loaded.project;
            required={'Version','Task','ModelPath','ModelDigest','Threshold','Environment','ROI','PixelThreshold', ...
                'NormalLabel','Calibrated','Language','UseLabels','Files','Labels','Results','Filter','InputFile','BatchSignature'};
            assert(isstruct(p) && isscalar(p) && all(isfield(p,required)) && p.Version==1 && p.Task==app.Task, ...
                'VIStudioV3:InvalidProject','專案格式或任務不符。 / Project version or task does not match.');
            assert(isfile(p.ModelPath) && VIStudioToolsV3.fileHash(p.ModelPath)==p.ModelDigest, ...
                'VIStudioV3:ChangedModel','模型遺失或內容已變更。 / Model is missing or has changed.');
            assert(numel(p.Files)==numel(p.Labels) && all(isfile(p.Files)), ...
                'VIStudioV3:MissingProjectImages','專案影像遺失。 / Project images are missing.');
            validateattributes(p.Threshold,{'numeric'},{'scalar','real','finite','nonnegative'});
            if app.Task~="anomaly", assert(p.Threshold<=1,'Invalid confidence threshold.'); end
            validatestring(p.Environment,{'auto','cpu','gpu'}); validatestring(p.Language,{'bilingual','zh','en'});
            validateattributes(p.UseLabels,{'logical'},{'scalar'});
            validateattributes(p.Calibrated,{'logical'},{'scalar'});
            if ~isempty(p.ROI), validateattributes(p.ROI,{'numeric'},{'vector','numel',4,'positive','integer','finite'}); end
            if ~isempty(p.PixelThreshold), validateattributes(p.PixelThreshold,{'numeric'},{'scalar','real','finite','nonnegative'}); end
            app.validateResultTable(p.Results,p.Files); VIStudioToolsV3.filterResults(p.Results,p.Filter);
            assert(strlength(string(p.InputFile))==0 || isfile(p.InputFile),'VIStudioV3:MissingProjectImages','Selected image is missing.');
            ds=[];
            if ~isempty(p.Files), ds=imageDatastore(cellstr(p.Files)); ds.Labels=categorical(p.Labels); end
            groundTruth=[];
            if isfield(p,'GroundTruth') && ~isempty(p.GroundTruth), groundTruth=VIStudioData.detectionTable(p.GroundTruth); end
            % All project data is validated before committing a replacement model.
            app.loadModel(p.ModelPath);
            app.Dataset=ds; app.ROI=p.ROI; app.PixelThreshold=p.PixelThreshold;
            app.NormalLabel=string(p.NormalLabel); app.Calibrated=p.Calibrated;
            app.UI.Threshold.Value=p.Threshold; app.UI.Environment.Value=p.Environment;
            if app.Task~="detection", app.UI.UseLabels.Value=p.UseLabels; end
            app.Results=p.Results; app.Filter=p.Filter; app.BatchSignature=string(p.BatchSignature);
            app.GroundTruth=groundTruth;
            if app.Task=="anomaly"
                app.UI.NormalClass.Value=char(app.NormalLabel);
                if ~isempty(app.PixelThreshold), app.UI.PixelThreshold.Value=app.PixelThreshold; end
            end
            if isempty(app.ROI), app.UI.ROIInfo.Text='全圖 / Full image';
            else, app.UI.ROIInfo.Text=sprintf('ROI [%d %d %d %d]',app.ROI); end
            if strlength(string(p.InputFile))>0, app.inspectImage(p.InputFile); end
            if ~isempty(ds)
                app.UI.DatasetPath.Text=char("專案影像清單 / Project image list: "+string(file));
                app.UI.DatasetPath.UserData=string(file);
                app.UI.DatasetCount.Text=sprintf('%d 張 / images',numel(ds.Files));
                for k=1:numel(ds.Files)
                    try
                        preview=VIStudioData.readImage(ds.Files{k},[]);
                        imshow(preview,'Parent',app.UI.Preview); break
                    catch
                        % Corrupt images remain available for error reporting/retry.
                    end
                end
            end
            app.setLanguage(p.Language); app.setFilter(p.Filter); app.updateViews(); app.refresh();
            app.log('專案已重開 / Project restored.');
        end
        function report=exportImages(app,folder)
            app.assertIdle(); results=app.filteredResults();
            results=results(~contains(results.Status,'Error'),:);
            assert(~isempty(results),'VIStudioV3:MissingResults','No successful results to export.');
            names=strings(height(results),1);
            for k=1:height(results)
                assert(isfile(results.File(k)), 'VIStudioV3:ChangedImage', ...
                    '來源影像不存在。 / Source image is missing: %s',results.File(k));
                currentHash=VIStudioToolsV3.fileHash(results.File(k));
                assert(currentHash==results.SourceHash(k), 'VIStudioV3:ChangedImage', ...
                    '來源影像已變更，請重新檢測。 / Source image changed; run inspection again: %s\nExpected: %s\nCurrent: %s', ...
                    results.File(k),results.SourceHash(k),currentHash);
                [~,stem]=fileparts(results.File(k)); stem=regexprep(stem,'[^\w\-]','_');
                names(k)=sprintf('%05d_%s_V3.png',k,stem);
                assert(~isfile(fullfile(folder,names(k))) && ~isfile(fullfile(folder,"mask_"+names(k))), ...
                    'VIStudioV3:ExportExists','匯出目標已存在，請選擇新資料夾。 / Choose a new export folder.');
            end
            if ~isfolder(folder), mkdir(folder); end
            report=table(results.File,strings(height(results),1),strings(height(results),1), ...
                'VariableNames',{'Source','ResultImage','MaskImage'});
            for k=1:height(results)
                image=VIStudioData.readImage(results.File(k),[]);
                if app.Task=="detection"
                    boxes=VIStudioToolsV3.decodeBoxes(results.BoxesJSON(k),results.Objects(k));
                    labels=string(jsondecode(results.LabelsJSON(k))); scores=jsondecode(results.ScoresJSON(k));
                    if ~isempty(boxes), image=insertObjectAnnotation(image,'rectangle',boxes,cellstr(compose('%s %.1f%%',labels(:),100*scores(:)))); end
                elseif app.Task=="anomaly"
                    if strlength(results.MaskRLEJSON(k))>0
                        mask=VIStudioToolsV3.decodeMask(results.MaskRLEJSON(k),jsondecode(results.MaskSizeJSON(k))');
                        image=labeloverlay(image,mask,'Transparency',0.55);
                        maskFile=fullfile(folder,"mask_"+names(k)); imwrite(mask,maskFile); report.MaskImage(k)=maskFile;
                    else
                        prediction=app.predict(image); roi=prediction.ROI;
                        rgb=ind2rgb(uint8(255*rescale(imresize(prediction.Map,roi([4 3])))),turbo(256));
                        [crop,~]=VIStudioToolsV3.cropImage(image,roi); image=im2double(image);
                        image(roi(2)+(0:roi(4)-1),roi(1)+(0:roi(3)-1),:)=0.7*im2double(crop)+0.3*rgb;
                        image=im2uint8(image);
                    end
                end
                text=sprintf('%s | score %.5g | %s',results.Prediction(k),results.Confidence(k),results.ReviewState(k));
                image=insertText(image,[1 1],text,'FontSize',14,'BoxOpacity',0.65);
                output=fullfile(folder,names(k)); imwrite(image,output); report.ResultImage(k)=output;
            end
            app.log('結果影像已匯出 / Result images exported.');
        end
        function summary=evaluateResults(app,useReviewed)
            app.assertIdle(); if nargin<2, useReviewed=false; end
            assert(~isempty(app.Results),'VIStudioV3:MissingResults','Run a batch first.');
            if app.Task=="detection"
                summary=app.evaluateDetection(); return
            end
            app.UI.EvalSource.Value=logical(useReviewed);
            data=app.Results(~contains(app.Results.Status,'Error'),:);
            actual=data.Actual; source=app.caption('資料夾標籤','Folder labels');
            if useReviewed
                actual(:)=""; keep=ismember(data.ReviewState,["accepted","corrected"]);
                actual(keep)=data.ReviewedLabel(keep); source=app.caption('人工覆核','Human review');
            end
            keep=strlength(actual)>0 & ismember(data.Prediction,app.Classes);
            [perClass,summary,matrix]=VIStudioToolsV3.classificationMetrics(actual(keep),data.Prediction(keep),app.Classes);
            delete(app.UI.EvalPlot.Children);
            active=(sum(matrix,1)'+sum(matrix,2))>0;
            confusionchart(app.UI.EvalPlot,matrix(active,active),cellstr(app.Classes(active)));
            app.UI.EvalTable.Data=sortrows(perClass,'Support','descend');
            app.UI.EvalInfo.Text=sprintf('%s | n=%d | Accuracy %.1f%% | Macro F1 %.3f',source,summary.Images,100*summary.Accuracy,summary.MacroF1);
            app.UI.Tabs.SelectedTab=app.UI.EvaluationTab;
        end
        function importGroundTruth(app,file)
            app.assertIdle(); assert(app.Task=="detection",'Only detection uses box ground truth.');
            loaded=load(file);
            if isfield(loaded,'gTruth'), value=loaded.gTruth;
            elseif isfield(loaded,'exportROI'), value=loaded.exportROI;
            else, error('VIStudioV3:MissingGroundTruth','Missing gTruth or exportROI.'); end
            app.GroundTruth=VIStudioData.detectionTable(value,fileparts(file));
            app.log('評估標註已匯入 / Evaluation ground truth loaded.');
        end
    end
    methods (Access=private)
        function buildV3Tools(app)
            dataGrid=app.UI.DataTab.Children(1);
            pixelHeight=1; if app.Task=="anomaly", pixelHeight=62; end
            dataGrid.RowHeight={38,34,38,42,34,36,pixelHeight,'1x',65};
            app.UI.Import.Layout.Row=3; app.UI.DatasetCount.Layout.Row=3;
            app.UI.DatasetPath.Layout.Row=4;
            if app.Task~="detection", app.UI.UseLabels.Layout.Row=5; end
            if app.Task=="detection"
                labels=findall(dataGrid,'-isa','matlab.ui.control.Label');
                for label=reshape(labels,1,[])
                    if contains(string(label.Text),'Counts and boxes')
                        label.Text='可在評估頁匯入標註並計算 AP50 與 mAP。 / Import ground truth in Evaluation to calculate AP50 and mAP.';
                        label.Layout.Row=5;
                    end
                end
            end
            app.UI.Preview.Layout.Row=8; app.UI.Log.Layout.Row=9;
            projectBar=uigridlayout(dataGrid,[1 3],'Padding',[0 0 0 0]);
            projectBar.Layout.Row=2; projectBar.Layout.Column=[1 2];
            app.UI.SaveProject=uibutton(projectBar,'Text','儲存專案 / Save project', ...
                'ButtonPushedFcn',@(~,~) app.uiAction(@() app.pickSaveProject()));
            app.UI.OpenProject=uibutton(projectBar,'Text','重開專案 / Open project', ...
                'ButtonPushedFcn',@(~,~) app.uiAction(@() app.pickOpenProject()));
            app.UI.ExportImages=uibutton(projectBar,'Text','匯出影像 / Export images', ...
                'ButtonPushedFcn',@(~,~) app.uiAction(@() app.pickImageExport()));
            roiBar=uigridlayout(dataGrid,[1 3],'ColumnWidth',{180,150,'1x'},'Padding',[0 0 0 0]);
            roiBar.Layout.Row=6; roiBar.Layout.Column=[1 2];
            app.UI.DrawROI=uibutton(roiBar,'Text','選取範圍 / Select ROI', ...
                'ButtonPushedFcn',@(~,~) app.uiAction(@() app.drawROI()));
            app.UI.ClearROI=uibutton(roiBar,'Text','清除範圍 / Clear ROI', ...
                'ButtonPushedFcn',@(~,~) app.uiAction(@() app.setROI([])));
            app.UI.ROIInfo=uilabel(roiBar,'Text','全圖 / Full image');
            if app.Task=="anomaly"
                bar=uigridlayout(dataGrid,[2 4],'ColumnWidth',{150,'1x',155,'1x'}, ...
                    'RowHeight',{26,26},'Padding',[0 0 0 0],'RowSpacing',4);
                bar.Layout.Row=7; bar.Layout.Column=[1 2];
                uilabel(bar,'Text','正常類別 / Normal class');
                app.UI.NormalClass=uieditfield(bar,'text','Value',char(app.NormalLabel), ...
                    'ValueChangedFcn',@(~,~) app.uiAction(@() app.setNormalClass(app.UI.NormalClass.Value)));
                uilabel(bar,'Text','像素門檻 / Pixel threshold');
                app.UI.PixelThreshold=uieditfield(bar,'numeric','Value',0.5,'Limits',[0 realmax]);
                text=uilabel(bar,'Text','遮罩使用原始分數 / Mask uses raw scores','FontSize',11);
                text.Layout.Row=2; text.Layout.Column=[1 2];
                app.UI.ApplyPixel=uibutton(bar,'Text','套用像素門檻 / Apply pixel threshold', ...
                    'ButtonPushedFcn',@(~,~) app.uiAction(@() app.setPixelThreshold(app.UI.PixelThreshold.Value)));
                app.UI.ApplyPixel.Layout.Row=2; app.UI.ApplyPixel.Layout.Column=[3 4];
            end
            resultGrid=app.UI.ResultsTab.Children(1);
            resultGrid.RowHeight={36,34,30,48,'1x',34};
            app.UI.Metrics.Layout.Row=4; app.UI.Results.Layout.Row=5;
            oldLabels=findall(resultGrid,'-isa','matlab.ui.control.Label');
            for h=reshape(oldLabels,1,[])
                if contains(string(h.Text),'Select a row'), h.Layout.Row=6; end
            end
            bar=uigridlayout(resultGrid,[1 6],'ColumnWidth',{'2x','1x','1x','1x',68,85},'Padding',[0 0 0 0]);
            bar.Layout.Row=2; bar.Layout.Column=[1 3];
            app.UI.Search=uieditfield(bar,'text','Placeholder','搜尋檔名與備註 / Search files and notes', ...
                'ValueChangedFcn',@(~,~) app.uiAction(@() app.applyFilters()));
            app.UI.FilterClass=uidropdown(bar,'Items',{'全部類別 / All classes'},'ItemsData',"all", ...
                'ValueChangedFcn',@(~,~) app.uiAction(@() app.applyFilters()));
            app.UI.FilterStatus=uidropdown(bar,'Items',{'全部狀態 / All status','待覆核 / Review','已辨識 / Classified', ...
                '有物件 / Objects','無物件 / Empty','正常 / Normal','異常 / Anomaly','失敗 / Error'}, ...
                'ItemsData',{'all','review','classified','objects','empty','normal','anomaly','error'}, ...
                'ValueChangedFcn',@(~,~) app.uiAction(@() app.applyFilters()));
            app.UI.FilterReview=uidropdown(bar,'Items',{'全部覆核 / All reviews','未覆核 / Pending','已確認 / Accepted', ...
                '已修正 / Corrected','已排除 / Rejected'},'ItemsData',{'all','pending','accepted','corrected','rejected'}, ...
                'ValueChangedFcn',@(~,~) app.uiAction(@() app.applyFilters()));
            app.UI.ResetFilter=uibutton(bar,'Text','重設 / Reset','ButtonPushedFcn',@(~,~) app.resetFilters());
            app.UI.Resume=uibutton(bar,'Text','繼續 / Resume','ButtonPushedFcn',@(~,~) app.uiAction(@() app.resumeBatch()));
            scoreBar=uigridlayout(resultGrid,[1 4],'ColumnWidth',{170,100,170,100},'Padding',[0 0 0 0]);
            scoreBar.Layout.Row=3; scoreBar.Layout.Column=[1 3];
            uilabel(scoreBar,'Text','最低分數 / Minimum score');
            app.UI.Minimum=uieditfield(scoreBar,'numeric','Value',0,'Limits',[0 realmax], ...
                'ValueChangedFcn',@(~,~) app.uiAction(@() app.applyFilters()));
            uilabel(scoreBar,'Text','最高分數 / Maximum score');
            maximum=1; if app.Task=="anomaly", maximum=realmax; end
            app.UI.Maximum=uieditfield(scoreBar,'numeric','Value',maximum,'Limits',[0 realmax], ...
                'ValueChangedFcn',@(~,~) app.uiAction(@() app.applyFilters()));
            app.UI.Results.ColumnName={'檔案 / File','預測 / Prediction','分數 / Score','物件 / Objects','狀態 / Status','覆核 / Review'};
            app.UI.ReviewTab=uitab(app.UI.Tabs,'Title','04 覆核 Review');
            grid=uigridlayout(app.UI.ReviewTab,[6 2],'RowHeight',{38,'1x',32,32,54,36}, ...
                'ColumnWidth',{'1x','1x'},'Padding',[16 12 16 12]);
            h=uilabel(grid,'Text','保留預測，另記人工判定 / Preserve predictions and record human decisions', ...
                'FontSize',15,'FontWeight','bold','WordWrap','on'); h.Layout.Row=1; h.Layout.Column=[1 2];
            app.UI.ReviewTable=uitable(grid,'RowName',{},'ColumnEditable',false, ...
                'ColumnName',{'檔案 / File','預測 / Prediction','分數 / Score','覆核狀態 / Review state','覆核答案 / Reviewed label','備註 / Notes'}, ...
                'CellSelectionCallback',@(~,event) app.reviewSelected(event));
            app.UI.ReviewTable.Layout.Row=2; app.UI.ReviewTable.Layout.Column=[1 2];
            app.UI.ReviewFile=uilabel(grid,'Text','請選取結果 / Select a result','WordWrap','on');
            app.UI.ReviewFile.Layout.Row=3; app.UI.ReviewFile.Layout.Column=[1 2];
            app.UI.ReviewState=uidropdown(grid,'Items',{'未覆核 / Pending','已確認 / Accepted','已修正 / Corrected','已排除 / Rejected'}, ...
                'ItemsData',{'pending','accepted','corrected','rejected'});
            app.UI.ReviewState.Layout.Row=4; app.UI.ReviewState.Layout.Column=1;
            app.UI.ReviewLabel=uieditfield(grid,'text','Placeholder','正確類別 / Correct label');
            app.UI.ReviewLabel.Layout.Row=4; app.UI.ReviewLabel.Layout.Column=2;
            app.UI.ReviewNote=uitextarea(grid,'Placeholder','覆核備註 / Review notes');
            app.UI.ReviewNote.Layout.Row=5; app.UI.ReviewNote.Layout.Column=[1 2];
            app.UI.ApplyReview=uibutton(grid,'Text','儲存覆核 / Save review','ButtonPushedFcn',@(~,~) app.uiAction(@() app.applyReview()));
            app.UI.ApplyReview.Layout.Row=6; app.UI.ApplyReview.Layout.Column=1;
            app.UI.InspectReview=uibutton(grid,'Text','檢視影像 / Inspect image','ButtonPushedFcn',@(~,~) app.uiAction(@() app.predictSelected()));
            app.UI.InspectReview.Layout.Row=6; app.UI.InspectReview.Layout.Column=2;
            app.UI.EvaluationTab=uitab(app.UI.Tabs,'Title','05 評估 Evaluation');
            grid=uigridlayout(app.UI.EvaluationTab,[4 2],'RowHeight',{38,58,'1x',150},'Padding',[16 12 16 12]);
            app.UI.EvalSource=uicheckbox(grid,'Text','以人工覆核為答案 / Use human-reviewed labels','Value',false);
            app.UI.EvalSource.Layout.Row=1; app.UI.EvalSource.Layout.Column=1;
            app.UI.Evaluate=uibutton(grid,'Text','計算評估指標 / Calculate metrics', ...
                'ButtonPushedFcn',@(~,~) app.uiAction(@() app.evaluateResults(app.UI.EvalSource.Value)));
            app.UI.Evaluate.Layout.Row=1; app.UI.Evaluate.Layout.Column=2;
            app.UI.EvalInfo=uilabel(grid,'Text','需正確答案才能評估 / Ground truth is required','WordWrap','on');
            app.UI.EvalInfo.Layout.Row=2; app.UI.EvalInfo.Layout.Column=[1 2];
            app.UI.EvalPlot=uipanel(grid); app.UI.EvalPlot.Layout.Row=3; app.UI.EvalPlot.Layout.Column=[1 2];
            app.UI.EvalTable=uitable(grid,'RowName',{}); app.UI.EvalTable.Layout.Row=4; app.UI.EvalTable.Layout.Column=[1 2];
            if app.Task=="detection"
                delete(app.UI.EvalSource);
                app.UI.ImportGT=uibutton(grid,'Text','匯入標註 / Import ground truth', ...
                    'ButtonPushedFcn',@(~,~) app.uiAction(@() app.pickGroundTruth()));
                app.UI.ImportGT.Layout.Row=1; app.UI.ImportGT.Layout.Column=1;
                app.UI.Evaluate.ButtonPushedFcn=@(~,~) app.uiAction(@() app.evaluateResults(false));
            end
        end
        function row=resultRow(~,file,prediction,actual,correct,errorMessage)
            mask=""; maskSize="";
            if ~isempty(prediction.Mask)
                mask=VIStudioToolsV3.encodeMask(prediction.Mask); maskSize=string(jsonencode(size(prediction.Mask)));
            end
            hash=""; if isfile(file), hash=VIStudioToolsV3.fileHash(file); end
            row=table(string(file),prediction.Label,prediction.Confidence,prediction.Count,prediction.Status, ...
                prediction.Milliseconds,actual,correct,string(jsonencode(num2cell(prediction.Boxes,2))), ...
                string(jsonencode(num2cell(prediction.Scores(:)'))),string(jsonencode(cellstr(prediction.Labels))), ...
                "pending","","","",errorMessage,mask,maskSize,prediction.DefectArea,prediction.DefectRegions,hash, ...
                'VariableNames',{'File','Prediction','Confidence','Objects','Status','Milliseconds','Actual','Correct', ...
                'BoxesJSON','ScoresJSON','LabelsJSON','ReviewState','ReviewedLabel','ReviewNote','ReviewTime', ...
                'Error','MaskRLEJSON','MaskSizeJSON','DefectArea','DefectRegions','SourceHash'});
        end
        function updateViews(app)
            [view,app.VisibleRows]=VIStudioToolsV3.filterResults(app.Results,app.Filter);
            if isempty(view)
                app.UI.Results.Data=[]; app.UI.ReviewTable.Data=[];
            else
                view.Status=VIStudioToolsV3.translate(view.Status,app.Language);
                app.UI.Results.Data=view(:,{'File','Prediction','Confidence','Objects','Status','ReviewState'});
                app.UI.ReviewTable.Data=view(:,{'File','Prediction','Confidence','ReviewState','ReviewedLabel','ReviewNote'});
            end
            if ~isempty(app.Results)
                app.UI.Metrics.Text=sprintf('%s %d/%d | %s %d | %s %d', ...
                    app.caption('顯示','Visible'),height(view),height(app.Results),app.caption('已覆核','Reviewed'), ...
                    sum(app.Results.ReviewState~="pending"),app.caption('失敗','Errors'),sum(contains(app.Results.Status,'Error')));
            end
            app.refresh();
        end
        function applyFilters(app)
            filter=struct('Query',string(app.UI.Search.Value),'Class',string(app.UI.FilterClass.Value), ...
                'Status',string(app.UI.FilterStatus.Value),'Review',string(app.UI.FilterReview.Value), ...
                'MinConfidence',app.UI.Minimum.Value,'MaxConfidence',app.UI.Maximum.Value);
            if filter.MinConfidence==0, filter.MinConfidence=-Inf; end
            if (app.Task~="anomaly" && filter.MaxConfidence==1) || filter.MaxConfidence==realmax, filter.MaxConfidence=Inf; end
            app.setFilter(filter);
        end
        function resetFilters(app)
            app.UI.Search.Value=''; app.UI.FilterClass.Value="all"; app.UI.FilterStatus.Value='all'; app.UI.FilterReview.Value='all';
            app.UI.Minimum.Value=0; app.UI.Maximum.Value=1;
            if app.Task=="anomaly", app.UI.Maximum.Value=realmax; end
            app.Filter=VIStudioToolsV3.defaultFilter(); app.updateViews();
        end
        function reviewSelected(app,event)
            if isempty(event.Indices) || isempty(app.VisibleRows) || app.Busy, return; end
            row=app.VisibleRows(event.Indices(1,1)); app.SelectedFile=app.Results.File(row);
            app.UI.ReviewFile.Text=char(app.SelectedFile); app.UI.ReviewState.Value=char(app.Results.ReviewState(row));
            app.UI.ReviewLabel.Value=char(app.Results.ReviewedLabel(row));
            app.UI.ReviewNote.Value=cellstr(splitlines(app.Results.ReviewNote(row)));
        end
        function applyReview(app)
            assert(strlength(app.SelectedFile)>0,'VIStudioV3:MissingResult','請先選取結果。 / Select a result first.');
            app.setReview(app.SelectedFile,app.UI.ReviewState.Value,app.UI.ReviewLabel.Value, ...
                join(string(app.UI.ReviewNote.Value),newline));
        end
        function predictSelected(app)
            assert(strlength(app.SelectedFile)>0,'VIStudioV3:MissingResult','Select a result first.');
            app.predictImage(app.SelectedFile);
        end
        function signature=signature(app)
            files=string(app.Dataset.Files);
            labels=false; if app.Task~="detection", labels=app.UI.UseLabels.Value; end
            signature=string(jsonencode(struct('Model',app.ModelDigest,'Files',files, ...
                'Threshold',app.UI.Threshold.Value,'ROI',app.ROI,'Pixel',app.PixelThreshold, ...
                'Normal',app.NormalLabel,'UseLabels',labels,'Calibrated',app.Calibrated)));
        end
        function summary=evaluateDetection(app)
            assert(~isempty(app.GroundTruth),'VIStudioV3:MissingGroundTruth','請匯入矩形標註。 / Import box ground truth.');
            data=app.Results(~contains(app.Results.Status,'Error'),:);
            [found,rows]=ismember(lower(data.File),lower(string(app.GroundTruth.imageFilename)));
            assert(all(found) && ~isempty(data),'VIStudioV3:MissingGroundTruth','部分結果沒有對應標註。 / Ground truth is missing for results.');
            boxes=cell(height(data),1); scores=boxes; labels=boxes;
            truthBoxes=boxes; truthLabels=boxes;
            classes=string(app.GroundTruth.Properties.VariableNames(2:end));
            for k=1:height(data)
                boxes{k}=VIStudioToolsV3.decodeBoxes(data.BoxesJSON(k),data.Objects(k));
                scores{k}=double(jsondecode(data.ScoresJSON(k))); scores{k}=scores{k}(:);
                rawLabels=string(jsondecode(data.LabelsJSON(k)));
                labels{k}=categorical(rawLabels(:),classes);
                gtBoxes=zeros(0,4); gtNames=strings(0,1);
                for c=1:numel(classes)
                    column=app.GroundTruth.(classes(c)); current=column{rows(k)};
                    gtBoxes=[gtBoxes;current]; %#ok<AGROW>
                    gtNames=[gtNames;repmat(classes(c),size(current,1),1)]; %#ok<AGROW>
                end
                truthBoxes{k}=gtBoxes; truthLabels{k}=categorical(gtNames,classes);
            end
            predicted=table(boxes,scores,labels,'VariableNames',{'Boxes','Scores','Labels'});
            % Explicit 0-by-1 categorical vectors also support an empty first image.
            truth=table(truthBoxes,truthLabels,'VariableNames',{'Boxes','Labels'});
            metrics=evaluateObjectDetection(predicted,truth,0.5);
            ap=averagePrecision(metrics,'ClassName',classes(:),'OverlapThreshold',0.5);
            [precision,recall]=precisionRecall(metrics,'ClassName',classes(:),'OverlapThreshold',0.5);
            summary=struct('Images',height(data),'mAP50',mean(ap(:),'omitnan'));
            app.UI.EvalTable.Data=table(classes(:),ap(:),'VariableNames',{'Class','AP50'});
            delete(app.UI.EvalPlot.Children);
            plotGrid=uigridlayout(app.UI.EvalPlot,[1 1],'Padding',[12 12 12 12]);
            ax=uiaxes(plotGrid); hold(ax,'on');
            for k=1:numel(classes), plot(ax,recall{k},precision{k},'DisplayName',classes(k)); end
            hold(ax,'off'); grid(ax,'on'); xlabel(ax,'Recall'); ylabel(ax,'Precision'); legend(ax,'show');
            ax.XLim=[0 1]; ax.YLim=[0 1.05]; ax.Toolbar.Visible='off';
            app.UI.EvalInfo.Text=sprintf('n=%d | mAP@IoU 0.50 = %.3f | Current confidence threshold %.3g', ...
                height(data),summary.mAP50,app.UI.Threshold.Value);
            app.UI.Tabs.SelectedTab=app.UI.EvaluationTab;
        end
        function drawROI(app)
            assert(~isempty(app.InputImage),'VIStudioV3:MissingImage','請先在檢測頁載入影像。 / Load an inspection image first.');
            app.UI.Tabs.SelectedTab=app.UI.InspectionTab;
            object=drawrectangle(app.UI.Original,'Color',[0.1 0.8 0.6]);
            if ~isempty(object) && isvalid(object)
                position=round(object.Position); delete(object); app.setROI(position);
            end
        end
        function pickSaveProject(app)
            [file,folder]=uiputfile('*.mat','儲存專案 / Save project','VIStudioV3_project.mat');
            if ~isequal(file,0), app.saveProject(fullfile(folder,file)); end
        end
        function pickOpenProject(app)
            [file,folder]=uigetfile('*.mat','重開專案 / Open project');
            if ~isequal(file,0), app.openProject(fullfile(folder,file)); end
        end
        function pickImageExport(app)
            folder=uigetdir(pwd,'選擇匯出位置 / Select export parent folder');
            if ~isequal(folder,0)
                output=fullfile(folder,['VIStudioV3_' char(datetime('now','Format','yyyyMMdd_HHmmss_SSS'))]);
                app.exportImages(output);
            end
        end
        function pickGroundTruth(app)
            [file,folder]=uigetfile('*.mat','匯入評估標註 / Import ground truth');
            if ~isequal(file,0), app.importGroundTruth(fullfile(folder,file)); end
        end
        function captureTranslations(app)
            objects=findall(app.UIFigure);
            for h=reshape(objects,1,[])
                if isequal(h,app.UI.Language), continue; end
                for property={'Text','Title','ColumnName','Items','Placeholder','Tooltip'}
                    field=property{1}; if ~isprop(h,field), continue; end
                    value=h.(field);
                    if ischar(value) || isstring(value) || iscellstr(value)
                        if any(contains(string(value),' / ')) || any(contains(string(value),' 資料 Data')) || ...
                                any(contains(string(value),' 結果 Results')) || any(contains(string(value),' 檢測 Inspection')) || ...
                                any(contains(string(value),' 覆核 Review')) || any(contains(string(value),' 評估 Evaluation'))
                            app.TranslationRecords(end+1,:)={h,field,value,value};
                        end
                    end
                end
            end
        end
        function validateResultTable(~,results,files)
            if isempty(results), assert(istable(results),'VIStudioV3:InvalidProject','Results must be a table.'); return; end
            required={'File','Prediction','Confidence','Objects','Status','Milliseconds','Actual','Correct', ...
                'BoxesJSON','ScoresJSON','LabelsJSON','ReviewState','ReviewedLabel','ReviewNote','ReviewTime', ...
                'Error','MaskRLEJSON','MaskSizeJSON','DefectArea','DefectRegions','SourceHash'};
            assert(istable(results) && all(ismember(required,results.Properties.VariableNames)) && ...
                all(ismember(results.File,string(files))) && numel(unique(results.File))==height(results), ...
                'VIStudioV3:InvalidProject','Project results are invalid.');
            assert(all(ismember(results.ReviewState,["pending","accepted","corrected","rejected"])), ...
                'VIStudioV3:InvalidProject','Invalid review state.');
        end
        function removeTemporary(~,file)
            if isfile(file), delete(file); end
        end
        function text=caption(app,chinese,english)
            if strcmp(app.Language,'zh'), text=chinese;
            elseif strcmp(app.Language,'en'), text=english;
            else, text=[chinese ' / ' english]; end
        end
        function buildUI(app)
            titleText='影像分類 Classification';
            if app.Task=="detection", titleText='物件偵測 Object Detection'; end
            if app.Task=="anomaly", titleText='異常偵測 Anomaly Detection'; end
            navy=[0.075 0.13 0.22]; teal=[0.06 0.56 0.46]; muted=[0.38 0.43 0.5];
            app.UIFigure=uifigure('Name',['VIStudio V3 | ' titleText], ...
                'Position',[45 45 1380 860],'Color',[0.95 0.96 0.98], ...
                'Visible','off','CloseRequestFcn',@(~,~) app.closeApp());
            root=uigridlayout(app.UIFigure,[3 1],'RowHeight',{76,'1x',32},'Padding',[20 12 20 8]);
            header=uigridlayout(root,[1 4],'ColumnWidth',{'1x',150,145,120}, ...
                'BackgroundColor',navy,'Padding',[20 8 16 8]);
            app.UI.Header=uilabel(header,'Text',['VIStudio V3  /  ' titleText],'FontSize',23,'FontWeight','bold','FontColor',[1 1 1]);
            app.UI.ModelStatus=uilabel(header,'Text','尚無模型 / No model', ...
                'HorizontalAlignment','right','FontColor',[0.65 0.77 0.9]);
            app.UI.Ready=uilabel(header,'Text','等待載入 / Waiting','HorizontalAlignment','right', ...
                'FontColor',[0.4 0.85 0.75],'FontWeight','bold');
            app.UI.Language=uidropdown(header,'Items',{'雙語 / Bilingual','中文 / Chinese','英文 / English'}, ...
                'ItemsData',{'bilingual','zh','en'},'Value','bilingual', ...
                'ValueChangedFcn',@(~,~) app.setLanguage(app.UI.Language.Value));
            body=uigridlayout(root,[1 2],'ColumnWidth',{315,'1x'},'ColumnSpacing',16,'Padding',[0 0 0 0]);
            panel=uipanel(body,'Title','模型與檢測設定 / Model & Inspection','FontWeight','bold');
            side=uigridlayout(panel,[15 1],'RowHeight', ...
                {32,18,44,18,28,18,28,34,30,30,18,64,36,30,28}, ...
                'Padding',[14 10 14 10],'RowSpacing',3,'Scrollable','on');
            app.UI.Load=uibutton(side,'Text','載入模型 / Load model .mat', ...
                'FontWeight','bold','ButtonPushedFcn',@(~,~) app.uiAction(@() app.pickModel()));
            uilabel(side,'Text','模型資訊 / Model information','FontWeight','bold');
            app.UI.ModelInfo=uilabel(side,'Text','尚未載入 / Not loaded','WordWrap','on','FontColor',muted);
            label='覆核門檻 / Review confidence';
            if app.Task=="detection", label='偵測信心門檻 / Detection confidence'; end
            if app.Task=="anomaly", label='影像異常門檻 / Image anomaly threshold'; end
            uilabel(side,'Text',label,'FontWeight','bold');
            app.UI.Threshold=uieditfield(side,'numeric','Limits',[0 1],'Value',0.5, ...
                'ValueChangedFcn',@(~,~) app.setConfidence(app.UI.Threshold.Value));
            if app.Task=="anomaly", app.UI.Threshold.Limits=[0 realmax]; end
            uilabel(side,'Text','運算裝置 / Execution environment','FontWeight','bold');
            app.UI.Environment=uidropdown(side,'Items',{'auto','cpu','gpu'}, ...
                'Value','auto','ValueChangedFcn',@(~,~) app.settingsChanged());
            app.UI.Batch=uibutton(side,'Text','執行批次 / Run batch', ...
                'BackgroundColor',teal,'FontColor',[1 1 1],'FontWeight','bold', ...
                'ButtonPushedFcn',@(~,~) app.uiAction(@() app.runBatch()));
            app.UI.Export=uibutton(side,'Text','匯出結果 / Export CSV', ...
                'ButtonPushedFcn',@(~,~) app.uiAction(@() app.pickExport()));
            if app.Task=="classification"
                app.UI.Visual=uidropdown(side,'Items',{'類別分數 / Class scores','Grad-CAM 熱圖 / Heatmap'}, ...
                    'ValueChangedFcn',@(~,~) app.visualChanged());
            else
                app.UI.Visual=uicheckbox(side,'Text','顯示類別與分數 / Show labels & scores', ...
                    'Value',true,'ValueChangedFcn',@(~,~) app.visualChanged());
                if app.Task=="anomaly", app.UI.Visual.Text='顯示缺陷遮罩 / Show defect mask'; end
            end
            uilabel(side,'Text','模型類別 / Model classes','FontWeight','bold');
            app.UI.ClassList=uitextarea(side,'Editable','off','Value',{'尚未載入 / Not loaded'});
            uilabel(side,'Text','覆核、評估與專案管理 / Review, evaluation and projects', ...
                'WordWrap','on','FontColor',muted);
            app.UI.Legacy=uibutton(side,'Text','原版訓練工具 / Original training', ...
                'ButtonPushedFcn',@(~,~) app.uiAction(@() app.openLegacy()));
            app.UI.Check=uibutton(side,'Text','環境檢查 / Check setup', ...
                'ButtonPushedFcn',@(~,~) app.uiAction(@() app.checkSetup()));
            app.UI.Tabs=uitabgroup(body);
            app.UI.DataTab=uitab(app.UI.Tabs,'Title','01 資料 Data');
            dg=uigridlayout(app.UI.DataTab,[6 2],'RowHeight',{42,40,46,42,'1x',88}, ...
                'ColumnWidth',{'1x',140},'Padding',[18 14 18 14],'RowSpacing',8,'Scrollable','on');
            label=uilabel(dg,'Text','建立檢測資料集 / Prepare inspection data', ...
                'FontSize',18,'FontWeight','bold'); label.Layout.Column=[1 2]; label.Layout.Row=1;
            app.UI.Import=uibutton(dg,'Text','匯入影像資料夾 / Import image folder', ...
                'ButtonPushedFcn',@(~,~) app.uiAction(@() app.pickFolder()));
            app.UI.Import.Layout.Row=2; app.UI.Import.Layout.Column=1;
            app.UI.DatasetCount=uilabel(dg,'Text','0 張 / images','FontWeight','bold','HorizontalAlignment','right');
            app.UI.DatasetCount.Layout.Row=2; app.UI.DatasetCount.Layout.Column=2;
            app.UI.DatasetPath=uilabel(dg,'Text','尚未匯入 / No folder selected','WordWrap','on','FontColor',muted);
            app.UI.DatasetPath.Layout.Column=[1 2];
            app.UI.DatasetPath.Layout.Row=3;
            if app.Task~="detection"
                app.UI.UseLabels=uicheckbox(dg,'Text','使用資料夾標籤評估準確率 / Evaluate using folder labels', ...
                    'Value',false,'ValueChangedFcn',@(~,~) app.labelsChanged());
                app.UI.UseLabels.Layout.Column=[1 2];
                app.UI.UseLabels.Layout.Row=4;
            else
                label=uilabel(dg,'Text','輸出逐張物件數與方框；本版不計算 mAP。 / Counts and boxes; mAP is not evaluated.', ...
                    'WordWrap','on','FontColor',muted); label.Layout.Column=[1 2]; label.Layout.Row=4;
            end
            app.UI.Preview=uiaxes(dg); app.UI.Preview.Layout.Column=[1 2];
            app.UI.Preview.Layout.Row=5;
            app.emptyAxes(app.UI.Preview,'影像預覽 / Image preview');
            app.UI.Log=uitextarea(dg,'Editable','off','FontSize',12); app.UI.Log.Layout.Column=[1 2];
            app.UI.Log.Layout.Row=6;
            app.UI.ResultsTab=uitab(app.UI.Tabs,'Title','02 結果 Results');
            rg=uigridlayout(app.UI.ResultsTab,[4 3],'RowHeight',{40,58,'1x',40}, ...
                'ColumnWidth',{'1x','1x','1x'},'Padding',[18 14 18 14]);
            label=uilabel(rg,'Text','逐張結果與批次摘要 / Batch results', ...
                'FontSize',18,'FontWeight','bold'); label.Layout.Column=[1 3]; label.Layout.Row=1;
            app.UI.Metrics=uilabel(rg,'Text','等待批次檢測 / Run a batch to view results', ...
                'WordWrap','on','FontSize',14,'FontWeight','bold'); app.UI.Metrics.Layout.Column=[1 3];
            app.UI.Metrics.Layout.Row=2;
            app.UI.Results=uitable(rg,'ColumnEditable',false,'RowName',{}, ...
                'ColumnName',{'檔案 File','預測 Prediction','信心 Confidence','物件 Objects', ...
                '狀態 Status','耗時 ms','實際 Actual','正確 Correct'}, ...
                'CellSelectionCallback',@(~,event) app.resultSelected(event));
            app.UI.Results.Layout.Column=[1 3];
            app.UI.Results.Layout.Row=3;
            label=uilabel(rg,'Text','選取任一列即可開啟檢測影像。 / Select a row to inspect its image.', ...
                'WordWrap','on','FontColor',muted); label.Layout.Column=[1 3]; label.Layout.Row=4;
            app.UI.InspectionTab=uitab(app.UI.Tabs,'Title','03 檢測 Inspection');
            ig=uigridlayout(app.UI.InspectionTab,[5 2],'RowHeight',{42,38,'1x',58,106}, ...
                'ColumnWidth',{'1x','1x'},'Padding',[18 14 18 14]);
            label=uilabel(ig,'Text','原圖與檢測結果 / Original & prediction', ...
                'FontSize',18,'FontWeight','bold'); label.Layout.Column=[1 2]; label.Layout.Row=1;
            app.UI.Open=uibutton(ig,'Text','載入影像 / Open image', ...
                'ButtonPushedFcn',@(~,~) app.uiAction(@() app.pickImage()));
            app.UI.Open.Layout.Row=2; app.UI.Open.Layout.Column=1;
            app.UI.Predict=uibutton(ig,'Text','執行檢測 / Run inspection','FontWeight','bold', ...
                'ButtonPushedFcn',@(~,~) app.uiAction(@() app.predictImage()));
            app.UI.Predict.Layout.Row=2; app.UI.Predict.Layout.Column=2;
            app.UI.Original=uiaxes(ig); app.emptyAxes(app.UI.Original,'原始影像 / Original');
            app.UI.Original.Layout.Row=3; app.UI.Original.Layout.Column=1;
            app.UI.Output=uiaxes(ig); app.emptyAxes(app.UI.Output,'檢測結果 / Prediction');
            app.UI.Output.Layout.Row=3; app.UI.Output.Layout.Column=2;
            app.UI.Verdict=uilabel(ig,'Text','等待影像 / Waiting for image', ...
                'FontSize',17,'FontWeight','bold','WordWrap','on'); app.UI.Verdict.Layout.Column=[1 2];
            app.UI.Verdict.Layout.Row=4;
            app.UI.Details=uitable(ig,'RowName',{},'ColumnEditable',false);
            app.UI.Details.Layout.Column=[1 2];
            app.UI.Details.Layout.Row=5;
            app.UI.Footer=uilabel(root,'Text','就緒 / Ready','FontColor',muted,'WordWrap','on');
            app.buildV3Tools();
        end
        function prediction=predict(app,image)
            timer=tic;
            fullSize=[size(image,1) size(image,2)];
            [image,roi]=VIStudioToolsV3.cropImage(image,app.ROI);
            prediction=struct('Label',"",'Confidence',NaN,'Count',NaN,'Status',"", ...
                'Milliseconds',0,'Boxes',zeros(0,4),'Scores',[],'Labels',strings(0,1), ...
                'Mask',[],'Map',[],'DefectArea',NaN,'DefectRegions',NaN,'ROI',roi);
            if app.Task=="classification"
                input=app.prepareImage(image);
                scores=minibatchpredict(app.Model,input,'ExecutionEnvironment',app.UI.Environment.Value);
                scores=VIStudioVisionAppV3.probabilities(scores,numel(app.Classes));
                [confidence,index]=max(scores);
                prediction.Label=app.Classes(index); prediction.Confidence=confidence;
                prediction.Scores=scores; prediction.Labels=app.Classes;
                prediction.Status="已辨識 / Classified";
                if confidence<app.UI.Threshold.Value, prediction.Status="待覆核 / Review"; end
            elseif app.Task=="detection"
                [boxes,scores,labels]=detect(app.Model,image,'Threshold',app.UI.Threshold.Value, ...
                    'ExecutionEnvironment',app.UI.Environment.Value);
                boxes=double(boxes); scores=double(scores(:)); labels=string(labels(:));
                validateattributes(boxes,{'numeric'},{'2d','ncols',4,'real','finite'});
                assert(size(boxes,1)==numel(scores) && numel(scores)==numel(labels), ...
                    'VIStudioV3:InvalidPrediction','方框、分數與標籤數量不一致。 / Detection output lengths differ.');
                assert(all(isfinite(scores)) && all(scores>=0 & scores<=1), ...
                    'VIStudioV3:InvalidPrediction','偵測分數無效。 / Invalid detection scores.');
                assert(isempty(boxes) || all(boxes(:,3:4)>0,'all'), ...
                    'VIStudioV3:InvalidPrediction','方框尺寸無效。 / Invalid box dimensions.');
                % Some detectors threshold objectness before combining class
                % scores. Enforce the displayed final-confidence threshold.
                keep=scores>=app.UI.Threshold.Value;
                boxes=boxes(keep,:); scores=scores(keep); labels=labels(keep);
                boxes(:,1:2)=boxes(:,1:2)+roi(1:2)-1;
                prediction.Boxes=boxes; prediction.Scores=scores; prediction.Labels=labels;
                prediction.Count=numel(scores); prediction.Label=strjoin(unique(labels,'stable'),', ');
                prediction.Status="偵測到物件 / Objects found";
                if isempty(scores)
                    prediction.Status="無物件 / No objects";
                else
                    prediction.Confidence=max(scores);
                end
            else
                input=app.prepareImage(image);
                score=double(predict(app.Model,input,'ExecutionEnvironment',app.UI.Environment.Value));
                validateattributes(score,{'numeric'},{'scalar','finite','real'});
                prediction.Confidence=score; prediction.Scores=score;
                prediction.Label="Uncalibrated"; prediction.Status="待校準 / Uncalibrated";
                if app.Calibrated
                    prediction.Label="Normal"; prediction.Status="正常 / Normal";
                    if score>=app.UI.Threshold.Value, prediction.Label="Anomaly"; prediction.Status="異常 / Anomaly"; end
                end
                map=anomalyMap(app.Model,input,'ExecutionEnvironment',app.UI.Environment.Value);
                if isa(map,'dlarray'), map=extractdata(map); end
                if isa(map,'gpuArray'), map=gather(map); end
                validateattributes(map,{'numeric'},{'2d','finite','real'});
                prediction.Map=map;
                if ~isempty(app.PixelThreshold)
                    % Pixel masks use raw scores, independently of display heatmaps.
                    local=imresize(map>=app.PixelThreshold,roi([4 3]),'nearest');
                    mask=false(fullSize); mask(roi(2)+(0:roi(4)-1),roi(1)+(0:roi(3)-1))=local;
                    prediction.Mask=mask; prediction.DefectArea=nnz(mask);
                    regions=bwconncomp(mask); prediction.DefectRegions=regions.NumObjects;
                    prediction.Count=regions.NumObjects;
                end
            end
            prediction.Milliseconds=1000*toc(timer);
        end
        function image=prepareImage(app,image)
            image=imresize(image,app.InputSize(1:2));
            if app.InputSize(3)==1, image=rgb2gray(image); end
        end
        function renderPrediction(app,prediction)
            ax=app.UI.Output; cla(ax,'reset');
            status=VIStudioToolsV3.translate(prediction.Status,app.Language);
            if app.Task=="classification"
                [scores,order]=sort(prediction.Scores,'descend'); count=min(5,numel(scores));
                app.UI.Details.Data=table(app.Classes(order(1:count)),scores(1:count), ...
                    'VariableNames',{'Class','Confidence'});
                app.UI.Details.ColumnName={'類別 / Class','信心 / Confidence'};
                if startsWith(app.UI.Visual.Value,'Grad-CAM')
                    [~,index]=max(prediction.Scores);
                    [crop,roi]=VIStudioToolsV3.cropImage(app.InputImage,app.ROI);
                    map=gradCAM(app.Model,app.prepareImage(crop),index);
                    if isa(map,'dlarray'), map=extractdata(map); end
                    if isa(map,'gpuArray'), map=gather(map); end
                    if ndims(map)==3, map=mean(map,3); end
                    map=rescale(imresize(map,roi([4 3])));
                    rgb=ind2rgb(uint8(255*map),turbo(256));
                    overlay=im2double(app.InputImage);
                    overlay(roi(2)+(0:roi(4)-1),roi(1)+(0:roi(3)-1),:)=0.7*im2double(crop)+0.3*rgb;
                    imshow(overlay,'Parent',ax);
                    title(ax,'Grad-CAM · 相對強度 / Relative intensity');
                else
                    barh(ax,100*scores(1:count),'FaceColor',[0.06 0.56 0.46]);
                    ax.YTick=1:count; ax.YTickLabel=cellstr(app.Classes(order(1:count)));
                    ax.YDir='reverse'; ax.XLim=[0 100]; ax.XGrid='on';
                    xlabel(ax,app.caption('信心 (%)','Confidence (%)')); title(ax,app.caption('前五類別','Top classes'));
                    ax.TickLabelInterpreter='none';
                end
                app.UI.Verdict.Text=sprintf('%s  ·  %s  ·  %.1f%%  ·  %.1f ms', ...
                    status,prediction.Label,100*prediction.Confidence,prediction.Milliseconds);
                color=[0.06 0.56 0.46];
                if prediction.Confidence<app.UI.Threshold.Value, color=[0.76 0.43 0.09]; end
            elseif app.Task=="detection"
                image=app.InputImage;
                if ~isempty(prediction.Boxes)
                    if app.UI.Visual.Value
                        labels=compose('%s %.1f%%',prediction.Labels,100*prediction.Scores);
                        image=insertObjectAnnotation(image,'rectangle',prediction.Boxes,cellstr(labels),'LineWidth',3);
                    else
                        image=insertShape(image,'rectangle',prediction.Boxes,'LineWidth',3,'Color','green');
                    end
                end
                imshow(image,'Parent',ax); title(ax,app.caption('偵測方框','Detection boxes'));
                app.UI.Details.Data=table(prediction.Labels,prediction.Scores,prediction.Boxes(:,1), ...
                    prediction.Boxes(:,2),prediction.Boxes(:,3),prediction.Boxes(:,4), ...
                    'VariableNames',{'Class','Confidence','X','Y','Width','Height'});
                app.UI.Details.ColumnName={'類別 / Class','信心 / Confidence','X','Y','寬 / Width','高 / Height'};
                app.UI.Verdict.Text=sprintf('%s  ·  %d %s  ·  %.1f ms', ...
                    status,prediction.Count,app.caption('物件','objects'),prediction.Milliseconds);
                color=[0.06 0.56 0.46];
            else
                image=app.InputImage;
                plotTitle=app.caption('缺陷遮罩','Defect mask');
                if ~isempty(prediction.Mask) && app.UI.Visual.Value
                    image=labeloverlay(image,prediction.Mask,'Transparency',0.55);
                else
                    plotTitle=app.caption('異常熱圖','Anomaly heatmap');
                    map=rescale(imresize(prediction.Map,prediction.ROI([4 3])));
                    rgb=ind2rgb(uint8(255*map),turbo(256));
                    [crop,roi]=VIStudioToolsV3.cropImage(image,prediction.ROI);
                    image=im2double(image);
                    image(roi(2)+(0:roi(4)-1),roi(1)+(0:roi(3)-1),:)=0.7*im2double(crop)+0.3*rgb;
                end
                imshow(image,'Parent',ax); title(ax,plotTitle);
                app.UI.Details.Data=table(prediction.Confidence,prediction.DefectArea,prediction.DefectRegions, ...
                    'VariableNames',{'AnomalyScore','DefectPixels','Regions'});
                app.UI.Details.ColumnName={'異常分數 / Anomaly score','缺陷像素 / Defect pixels','區域數 / Regions'};
                app.UI.Verdict.Text=sprintf('%s | score %.5g | %g px | %g regions', ...
                    status,prediction.Confidence,prediction.DefectArea,prediction.DefectRegions);
                if isempty(app.PixelThreshold)
                    app.UI.Verdict.Text=string(app.UI.Verdict.Text)+' | 請設定像素門檻 / Set pixel threshold';
                end
                color=[0.06 0.56 0.46];
                if prediction.Label=="Anomaly", color=[0.8 0.2 0.15]; end
            end
            app.UI.Verdict.FontColor=color;
            app.UI.Details.ColumnName=VIStudioToolsV3.translate(app.UI.Details.ColumnName,app.Language);
            ax.Toolbar.Visible='off';
        end
        function refresh(app)
            fields=fieldnames(app.UI);
            for k=1:numel(fields)
                h=app.UI.(fields{k});
                if ~isvalid(h), continue; end
                if isprop(h,'Enable'), h.Enable=app.enabled(true); end
            end
            ready=~isempty(app.Model);
            app.UI.Batch.Enable=app.enabled(ready && ~isempty(app.Dataset));
            app.UI.Predict.Enable=app.enabled(ready && ~isempty(app.InputImage));
            app.UI.Export.Enable=app.enabled(~isempty(app.Results));
            app.UI.SaveProject.Enable=app.enabled(ready);
            app.UI.ExportImages.Enable=app.enabled(~isempty(app.Results));
            app.UI.Resume.Enable=app.enabled(ready && strlength(app.BatchSignature)>0);
            app.UI.ApplyReview.Enable=app.enabled(strlength(app.SelectedFile)>0);
            app.UI.InspectReview.Enable=app.enabled(strlength(app.SelectedFile)>0);
            if app.Busy, app.UI.Ready.Text='處理中 / Processing';
            elseif ready, app.UI.Ready.Text='可檢測 / Ready';
            else, app.UI.Ready.Text='等待模型 / Waiting'; end
            if ready
                app.UI.ModelStatus.Text=char(app.ModelName);
                app.UI.ModelInfo.Text=sprintf('%s\n%d × %d × %d · %d %s', ...
                    class(app.Model),app.InputSize,numel(app.Classes),app.caption('類別','classes'));
            end
            app.UI.Ready.Text=VIStudioToolsV3.translate(app.UI.Ready.Text,app.Language);
        end
        function state=enabled(app,condition)
            state='off'; if condition && ~app.Busy, state='on'; end
        end
        function assertIdle(app)
            assert(~app.Busy,'VIStudioV3:Busy','工作進行中，請稍候。 / A task is running.');
        end
        function requireModel(app)
            assert(~isempty(app.Model),'VIStudioV3:MissingModel','請先載入模型。 / Load a model first.');
        end
        function finish(app)
            app.Busy=false; app.refresh();
        end
        function settingsChanged(app)
            app.clearResults(); app.clearPrediction();
            app.log('設定已變更，請重新檢測。 / Settings changed. Run inspection again.'); app.refresh();
        end
        function labelsChanged(app)
            app.clearResults(); app.refresh();
        end
        function visualChanged(app)
            if ~isempty(app.LastPrediction)
                app.uiAction(@() app.renderPrediction(app.LastPrediction));
            end
        end
        function clearResults(app)
            app.Results=table(); app.UI.Results.Data=[];
            app.BatchSignature=""; app.SelectedFile="";
            if isfield(app.UI,'ReviewTable'), app.UI.ReviewTable.Data=[]; end
            if isfield(app.UI,'EvalPlot')
                delete(app.UI.EvalPlot.Children); app.UI.EvalTable.Data=[];
                app.UI.EvalInfo.Text='需正確答案才能評估 / Ground truth is required';
            end
            app.UI.Metrics.Text='等待批次檢測 / Run a batch to view results';
        end
        function clearPrediction(app)
            app.LastPrediction=[]; app.UI.Details.Data=[];
            cla(app.UI.Output,'reset'); app.emptyAxes(app.UI.Output,'檢測結果 / Prediction');
            app.UI.Verdict.Text='等待檢測 / Waiting for inspection';
            app.UI.Verdict.FontColor=[0.38 0.43 0.5];
        end
        function uiAction(app,action)
            if app.Busy, return; end
            try
                action();
            catch err
                app.log('操作未完成 / Action failed: '+string(err.message));
                if strcmp(err.identifier,'VIStudioV3:Cancelled'), return; end
                if strcmp(app.UIFigure.Visible,'on')
                    uialert(app.UIFigure,err.message,'無法完成 / Cannot complete','Interpreter','none');
                else
                    rethrow(err);
                end
            end
        end
        function resultSelected(app,event)
            if app.Busy || isempty(event.Indices) || isempty(app.Results), return; end
            row=app.VisibleRows(event.Indices(1,1));
            if row<=height(app.Results), app.uiAction(@() app.predictImage(app.Results.File(row))); end
        end
        function pickModel(app)
            [file,folder]=uigetfile('*.mat','載入模型 / Load model');
            if ~isequal(file,0), app.loadModel(fullfile(folder,file)); end
        end
        function pickFolder(app)
            folder=uigetdir(pwd,'選擇影像資料夾 / Select image folder');
            if ~isequal(folder,0), app.importFolder(folder); end
        end
        function pickImage(app)
            [file,folder]=uigetfile({'*.png;*.jpg;*.jpeg;*.bmp;*.tif;*.tiff','影像 / Images'});
            if ~isequal(file,0)
                app.inspectImage(fullfile(folder,file)); app.UI.Tabs.SelectedTab=app.UI.InspectionTab;
            end
        end
        function pickExport(app)
            [file,folder]=uiputfile('*.csv','匯出結果 / Export results','VIStudioV3_results.csv');
            if ~isequal(file,0), app.exportResults(fullfile(folder,file)); end
        end
        function openLegacy(app)
            if app.Task=="classification", VIStudio_ClassificationApp_T1;
            elseif app.Task=="detection", VIStudio_ObjectDetectionApp_T1;
            else, VIStudioAnomalyApp; end
        end
        function checkSetup(app)
            required={'imageDatastore','minibatchpredict','gradCAM'};
            if app.Task=="detection", required={'imageDatastore','yoloxObjectDetector','insertObjectAnnotation'}; end
            if app.Task=="anomaly", required={'imageDatastore','patchCoreAnomalyDetector','anomalyMap','bwconncomp'}; end
            lines={['MATLAB ' version('-release')]};
            for k=1:numel(required)
                state='可使用 / Available';
                if isempty(which(required{k})), state='未安裝 / Missing'; end
                lines{end+1}=[required{k} ': ' state]; %#ok<AGROW>
            end
            uialert(app.UIFigure,strjoin(lines,newline),'環境檢查 / Setup check','Icon','info');
        end
        function log(app,message)
            app.LastMessage=string(message);
            message=VIStudioToolsV3.translate(message,app.Language);
            app.LogLines{end+1}=[char(datetime('now','Format','HH:mm:ss')) '  ' char(message)];
            app.LogLines=app.LogLines(max(1,end-49):end);
            app.UI.Log.Value=app.LogLines; app.UI.Footer.Text=char(message);
        end
        function p=progress(app,title,message,cancelable)
            p=[];
            if strcmp(app.UIFigure.Visible,'off'), return; end
            if cancelable
                p=uiprogressdlg(app.UIFigure,'Title',title,'Message',message,'Cancelable','on');
            else
                p=uiprogressdlg(app.UIFigure,'Title',title,'Message',message,'Indeterminate','on');
            end
        end
        function closeApp(app)
            if app.Busy
                uialert(app.UIFigure,'請等待工作完成，或取消批次預測。 / Wait for completion or cancel the batch.', ...
                    '工作進行中 / Task running');
                return
            end
            delete(app);
        end
    end
    methods (Static)
        function scores=probabilities(scores,count)
            if isa(scores,'dlarray'), scores=extractdata(scores); end
            if isa(scores,'gpuArray'), scores=gather(scores); end
            scores=double(scores(:));
            assert(numel(scores)==count && all(isfinite(scores)) && isreal(scores), ...
                'VIStudioV3:InvalidScores','模型輸出與類別清單不符。 / Model output does not match the class list.');
            if any(scores<0 | scores>1) || abs(sum(scores)-1)>1e-4
                scores=exp(scores-max(scores)); scores=scores/sum(scores);
            end
        end
    end
    methods (Static,Access=private)
        function emptyAxes(ax,caption)
            title(ax,caption); ax.XTick=[]; ax.YTick=[]; ax.Box='on'; ax.Toolbar.Visible='off';
        end
    end
end
