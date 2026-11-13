classdef VIStudioVisionAppV20 < matlab.apps.AppBase
    % V20 training/inspection plus model explanations and the independent V20 labeler.
    properties (SetAccess=private)
        UIFigure
        Task
        Results=table()
        LastPrediction=[]
    end
    properties (Dependent,SetAccess=private)
        ActiveModel
        ActiveModelFile
        ActiveMetadata
        TrainingSamples
        TrainingDistribution
        TrainingSelection
    end
    properties (Access=private)
        Workbench=[]
        DefectPane=[]
        DefectOptions=VIStudioDefectsV10.defaults()
        TrainingPane=[]
        ModelViewer=[]
        LabelerApp=[]
        ModelMetadata=struct()
        CalibrationData=[]
        CalibrationSource=""
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
        function app=VIStudioVisionAppV20(task,visible)
            if nargin<2, visible='on'; end
            app.Task=string(validatestring(task,{'classification','detection','anomaly'}));
            app.Filter=VIStudioToolsV3.defaultFilter();
            app.buildUI(); app.buildIntegratedTraining(); app.buildModelTools(); app.buildDefectTools(); app.buildWorkbench(); registerApp(app,app.UIFigure);
            VIStudioThemeV20.install(app.UIFigure,app.Task); app.captureTranslations();
            app.UIFigure.Visible=validatestring(visible,{'on','off'});
            app.log('V20 已就緒，可訓練或載入模型。 / Ready. Train or load a model to begin.');
            app.refresh();
        end
        function tools=advancedTools(app), tools=app.Workbench; end
        function delete(app)
            if ~isempty(app.Workbench) && isvalid(app.Workbench), delete(app.Workbench); end
            if ~isempty(app.LabelerApp) && isvalid(app.LabelerApp), delete(app.LabelerApp); end
            if ~isempty(app.TrainingPane) && isvalid(app.TrainingPane), delete(app.TrainingPane); end
            if ~isempty(app.UIFigure) && isvalid(app.UIFigure), delete(app.UIFigure); end
        end
        function value=get.ActiveModel(app), value=app.Model; end
        function value=get.ActiveModelFile(app), value=app.ModelPath; end
        function value=get.ActiveMetadata(app)
            value=app.ModelMetadata;
            value.ClassNames=app.Classes; value.ImageSize=app.InputSize(1:2);
            value.ModelName=app.ModelName; value.Task=app.Task; value.ExecutionEnvironment=app.UI.Environment.Value;
            if app.Task=="anomaly"
                value.DefectRules=app.DefectOptions; value.InspectionROI=app.ROI;
                value.NormalLabel=app.NormalLabel; value.Calibrated=app.Calibrated;
                value.Threshold=app.UI.Threshold.Value; value.PixelThreshold=app.PixelThreshold;
                value.PixelPercentile=app.UI.PixelPercentile.Value;
            end
        end
        function options=defectRules(app), options=app.DefectOptions; end
        function report=lastDefectMeasurement(app)
            report=[]; if ~isempty(app.DefectPane), report=app.DefectPane.Report; end
        end
        function configureDefectRules(app,value)
            app.assertIdle(); assert(app.Task=="anomaly",'VIStudioV15:NotAnomaly','Defect rules are available for anomaly models.');
            candidate=VIStudioDefectsV10.options(value,app.DefectOptions); previous=app.LastPrediction;
            app.DefectOptions=candidate; app.DefectPane.sync(candidate); app.clearResults();
            if ~isempty(previous) && isfield(previous,'Measurement')
                context=previous.Measurement.Context; context.Map=previous.Map;
                previous.Measurement=VIStudioDefectsV10.analyze(previous.Mask,previous.ROI,candidate,context);
                app.LastPrediction=previous; app.renderPrediction(previous);
            else, app.clearPrediction(); end
            app.log('量測規則已更新；批次結果已清除。 / Measurement rules updated; batch results cleared.'); app.refresh();
        end
        function scale=calibrateDefectScale(app,points,lengthMM)
            app.assertIdle(); assert(~isempty(app.InputImage),'VIStudioV15:MissingImage','Load an image first.');
            scale=VIStudioDefectsV10.referenceScale(points,lengthMM);
            assert(all(points(:,1)>=1 & points(:,1)<=size(app.InputImage,2)) && all(points(:,2)>=1 & points(:,2)<=size(app.InputImage,1)), ...
                'VIStudioV15:ScaleReference','Reference points must lie inside the source image.');
            app.configureDefectRules(struct('ScaleEnabled',true,'MMPerPixelX',scale,'MMPerPixelY',scale));
        end
        function saveDefectRules(app,file)
            app.assertIdle(); assert(app.Task=="anomaly",'VIStudioV15:NotAnomaly','Anomaly rules only.');
            assert(~isfile(file),'VIStudioV15:FileExists','Choose a new rules filename.');
            profile=struct('Version',1,'Options',app.DefectOptions); save(file,'profile');
        end
        function loadDefectRules(app,file)
            app.assertIdle(); loaded=load(file,'profile');
            assert(isfield(loaded,'profile') && isstruct(loaded.profile) && isscalar(loaded.profile) && ...
                all(isfield(loaded.profile,{'Version','Options'})) && loaded.profile.Version==1,'VIStudioV15:DefectProfile','Invalid rules profile.');
            candidate=VIStudioDefectsV10.options(loaded.profile.Options); app.configureDefectRules(candidate);
        end
        function exportDefectMeasurement(app,folder)
            app.assertIdle(); report=app.lastDefectMeasurement(); assert(~isempty(report),'VIStudioV15:MissingMeasurement','Run an inspection first.');
            VIStudioDefectsV10.export(report,folder,app.InputImage);
        end
        function output=exportBatchDefectMeasurements(app,folder,scope)
            app.assertIdle(); assert(app.Task=="anomaly",'VIStudioV15:NotAnomaly','Anomaly measurements only.');
            if nargin<3, scope='filtered'; end
            if strcmp(scope,'all'), selected=app.Results; else, selected=app.filteredResults(); end
            assert(~isempty(selected) && ismember('MeasurementJSON',selected.Properties.VariableNames), ...
                'VIStudioV15:MissingMeasurement','Run a V20 anomaly batch first.');
            assert(~isfolder(folder) && ~isfile(folder),'VIStudioV15:FileExists','Choose a new export folder.');
            usable=strlength(selected.MeasurementJSON)>0 & strlength(selected.Error)==0;
            assert(any(usable),'VIStudioV15:MissingMeasurement','No successful measurement records.');
            for k=find(usable)'
                assert(isfile(selected.File(k)) && VIStudioToolsV3.fileHash(selected.File(k))==selected.SourceHash(k), ...
                    'VIStudioV15:SourceChanged','Source image changed after inspection; rerun before export.');
            end
            mkdir(folder); writetable(selected,fullfile(folder,'batch_measurements.csv'),'Encoding','UTF-8');
            output=table(selected.File(usable),strings(sum(usable),1),'VariableNames',{'Source','ReportFolder'}); row=0;
            for k=find(usable)'
                report=VIStudioDefectsV10.fromJSON(selected.MeasurementJSON(k)); image=VIStudioData.readImage(selected.File(k),[]);
                assert(~isfield(report.Context,'InputPixelHash') || VIStudioDataHealthV8.pixelHash(image)==string(report.Context.InputPixelHash), ...
                    'VIStudioV15:SourceChanged','Source pixels changed after inspection.');
                child=fullfile(folder,sprintf('image_%05d',k)); VIStudioDefectsV10.export(report,child,image); row=row+1; output.ReportFolder(row)=string(child);
            end
            writetable(output,fullfile(folder,'reports.csv'),'Encoding','UTF-8');
        end
        function value=get.TrainingSamples(app), value=app.TrainingPane.Samples; end
        function value=get.TrainingDistribution(app), value=app.TrainingPane.Distribution; end
        function value=get.TrainingSelection(app), value=app.TrainingPane.SelectedFile; end
        function names=modelChoices(app), names=app.TrainingPane.modelChoices(); end
        function state=trainingModelAvailability(app), state=app.TrainingPane.availability(); end
        function chooseTrainingModel(app,name)
            app.assertIdle(); app.TrainingPane.chooseModel(name); app.refresh();
        end
        function setTrainingOptions(app,options)
            app.assertIdle(); app.TrainingPane.setOptions(options); app.refresh();
        end
        function setDatasetSource(app,role,path), app.assertIdle(); app.TrainingPane.setDatasetSource(role,path); app.refresh(); end
        function configureDataset(app,config), app.assertIdle(); app.TrainingPane.configureDataset(config); app.refresh(); end
        function plan=buildDatasetPlan(app), app.assertIdle(); plan=app.TrainingPane.buildDatasetPlan(); end
        function plan=datasetPlan(app), plan=app.TrainingPane.Dataset.Plan; end
        function records=trainingExperiments(app), app.TrainingPane.Experiments.refresh(); records=app.TrainingPane.Experiments.Records; end
        function result=compareExperiments(app,rows), app.assertIdle(); result=app.TrainingPane.Experiments.compare(rows); end
        function activateExperiment(app,row), app.assertIdle(); app.TrainingPane.Experiments.activate(row); app.refresh(); end
        function exportExperiments(app,rows,folder), app.assertIdle(); app.TrainingPane.Experiments.export(rows,folder); end
        function useDatasetRole(app,role)
            app.assertIdle(); role=string(validatestring(role,{'test','calibration'}));
            plan=app.TrainingPane.buildDatasetPlan(); VIStudioDatasetV9.assertUnchanged(plan); rows=plan.Manifest.Split==role;
            assert(any(rows),'VIStudioV15:EmptyRole','The selected dataset role is empty.');
            ds=imageDatastore(cellstr(plan.Manifest.File(rows))); ds.Labels=categorical(plan.Manifest.Label(rows));
            if role=="calibration"
                assert(app.Task=="anomaly",'VIStudioV15:NotAnomaly','Calibration is available for anomaly models.');
                app.CalibrationData=ds; app.CalibrationSource="";
                app.UI.CalibrationPath.Text="資料集校準清單 / Managed calibration: "+plan.Fingerprint;
                app.UI.CalibrationNormal.Items=cellstr(categories(ds.Labels));
                if ismember(app.NormalLabel,string(categories(ds.Labels))), app.UI.CalibrationNormal.Value=char(app.NormalLabel); end
                app.UI.CalibrationResults.Data=[]; app.UI.CalibrationInfo.Text=sprintf('%d 張校準影像 / calibration images',numel(ds.Files));
                app.UI.Tabs.SelectedTab=app.UI.CalibrationTab;
            else
                app.Dataset=ds; app.clearResults(); app.UI.DatasetPath.Text="獨立測試集 / Held-out test: "+plan.Fingerprint; app.UI.DatasetPath.UserData="";
                if app.Task=="detection", app.GroundTruth=plan.Annotations(rows,:); else, app.UI.UseLabels.Value=true; end
                imshow(VIStudioData.readImage(ds.Files{1},[]),'Parent',app.UI.Preview); app.UI.Tabs.SelectedTab=app.UI.DataTab;
            end
            app.refresh();
        end
        function report=checkTrainingData(app), app.assertIdle(); report=app.TrainingPane.checkData(); end
        function report=checkDataFolder(app,folder)
            app.assertIdle(); report=VIStudioDataHealthV8.folder(folder,app.Task); app.TrainingPane.Health.show(report);
        end
        function report=trainingHealthReport(app), report=app.TrainingPane.Health.Report; end
        function run=trainingRun(app), run=app.TrainingPane.Monitor; end
        function history=trainingHistory(app), history=app.TrainingPane.Monitor.History; end
        function requestTrainingStop(app), app.TrainingPane.Monitor.requestStop(); end
        function state=trainingState(app), state=app.TrainingPane.state(); end
        function setAdvancedTrainingOptions(app,options)
            app.assertIdle(); app.TrainingPane.setAdvanced(options); app.refresh();
        end
        function artifact=loadTrainingModel(app,file,variable)
            if nargin<3, variable=""; end
            app.assertIdle(); artifact=app.TrainingPane.loadExternal(file,variable); app.refresh();
        end
        function prepared=prepareTrainingData(app)
            app.assertIdle(); prepared=app.TrainingPane.prepare(); app.refresh();
        end
        function prepared=preparedTrainingData(app), prepared=app.TrainingPane.Prepared; end
        function result=visualizeModel(app,file,options)
            app.assertIdle(); app.requireModel();
            assert(~isempty(app.ModelViewer),'VIStudioV15:VisualTask','Model visualization is available for classification and detection.');
            if nargin<2 || strlength(string(file))==0
                file=app.InputFile; if strlength(file)==0, file=app.TrainingSelection; end
            end
            assert(strlength(string(file))>0,'VIStudioV15:MissingImage','Load or select an image first.');
            app.Busy=true; app.refresh(); cleanup=onCleanup(@() app.finish());
            if nargin<3, result=app.ModelViewer.explain(file); else, result=app.ModelViewer.explain(file,options); end
            app.UI.Tabs.SelectedTab=app.UI.VisualizationTab; app.syncWorkspace();
        end
        function result=lastVisualization(app)
            result=[]; if ~isempty(app.ModelViewer), result=app.ModelViewer.Result; end
        end
        function exportVisualization(app,file), app.assertIdle(); app.ModelViewer.export(file); end
        function labeler=openLabeler(app,folder,visible)
            app.assertIdle();
            if nargin<3, visible='on'; end
            visible=validatestring(visible,{'on','off'});
            if isempty(app.LabelerApp) || ~isvalid(app.LabelerApp)
                app.LabelerApp=VIStudioLabelerV20(visible,@(output) app.receiveLabels(output));
                state=app.TrainingPane.state();
                if nargin>1, app.LabelerApp.loadFolder(folder);
                elseif state.Kind=="annotations" && strlength(state.Source)>0, app.LabelerApp.loadSession(state.Source);
                elseif ~isempty(app.TrainingSamples), app.LabelerApp.loadFiles(app.TrainingSamples.File);
                elseif ~isempty(app.Dataset), app.LabelerApp.loadFiles(app.Dataset.Files); end
            end
            if ~isempty(app.Model), app.LabelerApp.setPrelabelModel(app.Model,app.ActiveMetadata,app.Task,app.ModelDigest); end
            app.LabelerApp.openAdvanced(app.Task); app.LabelerApp.setLanguage(app.Language);
            labeler=app.LabelerApp; labeler.UIFigure.Visible=visible; if strcmp(visible,'on'), figure(labeler.UIFigure); end
        end
        function setInferenceEnvironment(app,environment)
            app.assertIdle(); app.UI.Environment.Value=validatestring(environment,{'auto','cpu','gpu'});
            app.settingsChanged();
        end
        function loadTrainingFolder(app,folder)
            app.assertIdle(); app.TrainingPane.loadFolder(folder); app.refresh();
            app.log('訓練資料已載入，檢測資料維持獨立。 / Training data loaded; inspection data remains separate.');
        end
        function loadTrainingAnnotations(app,file)
            app.assertIdle(); app.TrainingPane.loadAnnotations(file); app.refresh();
            app.log('偵測訓練標註已載入。 / Detection training annotations loaded.');
        end
        function filterTrainingImages(app,query,label)
            app.assertIdle(); if nargin<3, label="all"; end
            app.TrainingPane.filterImages(query,label); app.refresh();
        end
        function nextTrainingImage(app,step)
            app.assertIdle(); app.TrainingPane.nextImage(step); app.refresh();
        end
        function model=train(app)
            app.assertIdle(); app.Busy=true; app.refresh(); cleanup=onCleanup(@() app.finish());
            app.log('開始訓練，完成後會自動啟用模型。 / Training. The completed model will be activated automatically.');
            app.UI.Tabs.SelectedTab=app.UI.TrainingTab;
            app.TrainingPane.Tabs.SelectedTab=app.TrainingPane.Monitor.Handles.Status.Parent.Parent;
            drawnow;
            model=app.TrainingPane.train();
            % A persistent, unique checkpoint keeps project references restorable.
            folder=fullfile(fileparts(mfilename('fullpath')),'V16_Models');
            if ~isfolder(folder), mkdir(folder); end
            [~,unique]=fileparts(tempname(folder));
            file=fullfile(folder,char(app.Task+"_"+string(unique)+".mat"));
            app.TrainingPane.saveCheckpoint(file);
            app.Busy=false; app.loadModel(file);
            state=app.TrainingPane.state(); app.UI.Environment.Value=state.Options.Environment;
            if app.Task=="anomaly"
                app.UI.Tabs.SelectedTab=app.UI.CalibrationTab; app.syncWorkspace();
                if ~app.TrainingPane.Monitor.StopRequested
                    app.log('訓練完成，模型已啟用。請用獨立資料校準門檻。 / Model activated. Calibrate using independent data.');
                end
            else
                if strlength(app.TrainingSelection)>0, app.inspectImage(app.TrainingSelection); end
                app.UI.Tabs.SelectedTab=app.UI.InspectionTab; app.syncWorkspace();
                if ~app.TrainingPane.Monitor.StopRequested
                    app.log('訓練完成，模型已啟用，可直接檢測。 / Model activated. Ready for inspection.');
                end
            end
            if app.TrainingPane.Monitor.StopRequested
                app.log('訓練已停止；回傳的模型權重已另存。異常模型仍須重新校準。 / Training stopped; returned weights saved separately. Recalibrate anomaly models.');
            end
            app.syncWorkspace();
        end
        function predictTrainingImage(app)
            app.assertIdle(); app.requireModel();
            assert(strlength(app.TrainingSelection)>0,'VIStudioV15:MissingImage','Select a training photo first.');
            app.predictImage(app.TrainingSelection);
        end
        function saveModel(app,file)
            app.assertIdle(); app.requireModel();
            assert(~isfile(file),'VIStudioV15:FileExists','請使用新的模型檔名。 / Choose a new filename.');
            [folder,~,extension]=fileparts(char(file)); if isempty(folder), folder=pwd; end
            assert(strcmpi(extension,'.mat'),'VIStudioV15:ModelExtension','Use a .mat filename.');
            model=app.Model; metadata=app.ActiveMetadata; %#ok<NASGU>
            if app.Task=="anomaly"
                model.Threshold=[];
                if app.Calibrated, model.Threshold=app.UI.Threshold.Value; end
            end
            temporary=[tempname(folder) '.mat']; cleanup=onCleanup(@() app.removeTemporary(temporary));
            save(temporary,'model','metadata','-v7.3'); movefile(temporary,file);
            app.log('模型已匯出 / Model exported: '+string(file));
        end
        function loadCalibrationFolder(app,folder)
            app.assertIdle(); assert(app.Task=="anomaly",'VIStudioV15:NotAnomaly','Only anomaly models use calibration.');
            ds=imageDatastore(folder,'IncludeSubfolders',true,'LabelSource','foldernames');
            assert(~isempty(ds.Files),'VIStudioV15:EmptyCalibration','No calibration images found.');
            classes=string(categories(ds.Labels));
            app.CalibrationData=ds; app.CalibrationSource=VIStudioToolsV3.canonicalPath(folder);
            app.UI.CalibrationPath.Text=char(app.CalibrationSource);
            app.UI.CalibrationNormal.Items=cellstr(classes);
            if ismember(app.NormalLabel,classes), app.UI.CalibrationNormal.Value=char(app.NormalLabel); end
            app.UI.CalibrationResults.Data=[];
            app.UI.CalibrationInfo.Text=sprintf('%d 張校準影像 / calibration images',numel(ds.Files));
            app.refresh();
        end
        function summary=calibrateAnomaly(app,normal,percentile)
            app.assertIdle(); app.requireModel();
            assert(app.Task=="anomaly" && ~isempty(app.CalibrationData),'VIStudioV15:MissingCalibration','Load independent calibration images first.');
            if nargin<2, normal=string(app.UI.CalibrationNormal.Value); end
            if nargin<3, percentile=app.UI.PixelPercentile.Value; end
            validateattributes(percentile,{'numeric'},{'scalar','finite','>=',50,'<',100});
            normal=string(normal); labels=string(app.CalibrationData.Labels); actual=labels~=normal;
            assert(any(actual) && any(~actual),'VIStudioV15:CalibrationClasses', ...
                '校準資料需包含正常與異常影像。 / Calibration needs normal and anomaly images.');
            app.assertIndependentCalibration();
            app.Busy=true; app.refresh(); cleanup=onCleanup(@() app.finish());
            p=app.progress('異常門檻校準 / Anomaly calibration','計算獨立校準分數 / Scoring independent calibration images',true);
            progressCleanup=onCleanup(@() delete(p));
            scores=zeros(numel(labels),1); pixelPool=single.empty(0,1);
            for k=1:numel(labels)
                drawnow;
                if ~isempty(p)
                    assert(~p.CancelRequested,'VIStudioV15:Cancelled','Calibration cancelled; previous thresholds retained.');
                    p.Value=(k-1)/numel(labels); p.Message=sprintf('%d / %d',k,numel(labels));
                end
                prediction=app.predict(VIStudioData.readImage(app.CalibrationData.Files{k},[]));
                scores(k)=prediction.Confidence;
                if ~actual(k)
                    map=single(prediction.Map(:)); indices=round(linspace(1,numel(map),min(4096,numel(map))));
                    pixelPool=[pixelPool;map(indices)]; %#ok<AGROW>
                    if numel(pixelPool)>1e6, pixelPool=pixelPool(round(linspace(1,numel(pixelPool),1e6))); end
                end
            end
            threshold=double(anomalyThreshold(actual,scores,true));
            pixel=double(prctile(pixelPool,percentile));
            validateattributes(threshold,{'numeric'},{'scalar','finite','nonnegative'});
            validateattributes(pixel,{'numeric'},{'scalar','finite','nonnegative'});
            app.Model.Threshold=threshold; app.UI.Threshold.Value=threshold; app.Calibrated=true;
            app.NormalLabel=normal; app.UI.NormalClass.Value=char(normal);
            app.PixelThreshold=pixel; app.UI.PixelThreshold.Value=pixel;
            app.UI.PixelPercentile.Value=percentile; app.UI.CalibrationNormal.Value=char(normal);
            app.clearResults(); app.clearPrediction();
            predicted=scores>=threshold;
            app.UI.CalibrationResults.Data=table(string(app.CalibrationData.Files),actual,scores,predicted, ...
                'VariableNames',{'File','ActualAnomaly','Score','PredictedAnomaly'});
            ax=app.UI.CalibrationPlot; cla(ax); histogram(ax,scores(~actual),'DisplayName','Normal'); hold(ax,'on');
            histogram(ax,scores(actual),'DisplayName','Anomaly'); xline(ax,threshold,'--','Threshold','DisplayName','Threshold');
            hold(ax,'off'); legend(ax,'show'); xlabel(ax,'Anomaly score'); ylabel(ax,'Images');
            summary=struct('Images',numel(labels),'Threshold',threshold,'PixelThreshold',pixel,'PixelPercentile',percentile);
            app.UI.CalibrationInfo.Text=sprintf('%s %.5g | %s %.5g (P%.1f)', ...
                app.caption('影像門檻','Image threshold'),threshold,app.caption('像素門檻','Pixel threshold'),pixel,percentile);
            app.log('影像與像素門檻已校準。校準結果不是獨立測試準確率。 / Thresholds calibrated. Calibration results are not held-out test accuracy.');
        end
        function loadModel(app,file)
            app.assertIdle(); app.Busy=true; app.refresh();
            cleanup=onCleanup(@() app.finish());
            p=app.progress('載入模型 / Load model','驗證模型 / Validating model',false);
            progressCleanup=onCleanup(@() delete(p));
            loaded=load(file);
            assert(isfield(loaded,'model'),'VIStudioV15:MissingModel', ...
                'MAT 檔必須包含 model。 / The MAT file must contain model.');
            candidate=loaded.model;
            if app.Task=="classification"
                assert(isa(candidate,'dlnetwork'),'VIStudioV15:InvalidClassifier', ...
                    '分類需使用 dlnetwork。 / Classification requires a dlnetwork.');
                assert(isscalar(candidate.InputNames) && isscalar(candidate.OutputNames), ...
                    'VIStudioV15:InvalidClassifier','需單一輸入與輸出。 / A single input and output are required.');
                layer=getLayer(candidate,candidate.InputNames{1});
                assert(isa(layer,'nnet.cnn.layer.ImageInputLayer'),'VIStudioV15:InvalidClassifier', ...
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
                    numel(unique(classes))==numel(classes),'VIStudioV15:MissingClasses', ...
                    '需提供 metadata.ClassNames，順序須對應模型輸出。 / Provide ordered metadata.ClassNames.');
                validateattributes(input,{'numeric'},{'vector','numel',3,'positive','integer','finite'});
                assert(ismember(input(3),[1 3]),'VIStudioV15:InvalidChannels', ...
                    '僅支援灰階或 RGB 模型。 / Only grayscale and RGB models are supported.');
                scores=minibatchpredict(candidate,zeros(input,'uint8'),'ExecutionEnvironment','cpu');
                VIStudioVisionAppV20.probabilities(scores,numel(classes));
            elseif app.Task=="detection"
                supported=["yoloxObjectDetector","yolov4ObjectDetector","yolov3ObjectDetector", ...
                    "yolov2ObjectDetector","ssdObjectDetector","fasterRCNNObjectDetector"];
                assert(ismember(string(class(candidate)),supported),'VIStudioV15:InvalidDetector', ...
                    '請使用 YOLOX、YOLOv2–4、SSD 或 Faster R-CNN。 / Unsupported detector type.');
                classes=string(candidate.ClassNames(:)); input=candidate.InputSize;
                validateattributes(input,{'numeric'},{'vector','numel',3,'positive','integer','finite'});
                % Probe before replacing the active model.
                detect(candidate,zeros(input,'uint8'),'Threshold',0.99,'ExecutionEnvironment','cpu');
            else
                assert(ismember(string(class(candidate)),["patchCoreAnomalyDetector","fcddAnomalyDetector", ...
                    "efficientADAnomalyDetector","VIStudioTeacherStudentV8","VIStudioTeacherStudentV6"]),'VIStudioV15:InvalidAnomalyModel', ...
                    '請載入異常偵測模型。 / An anomaly detector is required.');
                input=[224 224 3];
                if isprop(candidate,'ImageSize') && ~isempty(candidate.ImageSize), input=candidate.ImageSize; end
                if numel(input)==2, input=[input 3]; end
                if isfield(loaded,'metadata') && isfield(loaded.metadata,'ImageSize')
                    input=[loaded.metadata.ImageSize(1:2) 3];
                end
                validateattributes(input,{'numeric'},{'vector','numel',3,'positive','integer','finite'});
                score=predict(candidate,zeros(input,'uint8'),'ExecutionEnvironment','cpu');
                validateattributes(score,{'numeric'},{'scalar','finite','real'});
                classes=["Normal";"Anomaly"];
            end
            candidateRules=VIStudioDefectsV10.defaults(); candidateROI=[];
            if app.Task=="anomaly" && isfield(loaded,'metadata') && isfield(loaded.metadata,'InspectionROI')
                candidateROI=loaded.metadata.InspectionROI;
                if ~isempty(candidateROI), validateattributes(candidateROI,{'numeric'},{'vector','numel',4,'integer','positive','finite','real'}); candidateROI=double(candidateROI(:)'); end
            end
            if app.Task=="anomaly" && isfield(loaded,'metadata') && isfield(loaded.metadata,'DefectRules')
                candidateRules=VIStudioDefectsV10.options(loaded.metadata.DefectRules);
            end
            digest=VIStudioToolsV3.fileHash(file);
            app.ModelMetadata=struct(); if isfield(loaded,'metadata'), app.ModelMetadata=loaded.metadata; end
            if isfield(app.ModelMetadata,'ExecutionEnvironment')
                app.UI.Environment.Value=validatestring(app.ModelMetadata.ExecutionEnvironment,{'auto','cpu','gpu'});
            end
            app.Model=candidate; app.Classes=classes; app.InputSize=double(input(:)');
            app.ModelPath=VIStudioToolsV3.canonicalPath(file); app.ModelDigest=digest;
            if ~isempty(app.ModelViewer)
                metadata=app.ActiveMetadata; metadata.ModelFile=app.ModelPath; metadata.ModelDigest=digest;
                if isfield(app.ModelMetadata,'ModelName'), metadata.ModelName=app.ModelMetadata.ModelName;
                else, [~,name]=fileparts(file); metadata.ModelName=string(name); end
                app.ModelViewer.setModel(candidate,metadata);
            end
            if app.Task=="anomaly"
                app.DefectOptions=candidateRules; app.DefectPane.sync(candidateRules); app.ROI=candidateROI;
                if isempty(app.ROI), app.UI.ROIInfo.Text='全圖 / Full image'; else, app.UI.ROIInfo.Text=sprintf('ROI [%d %d %d %d]',app.ROI); end
                app.NormalLabel="good"; app.PixelThreshold=[];
                app.Calibrated=~isempty(candidate.Threshold) && isfinite(candidate.Threshold);
                if app.Calibrated, app.UI.Threshold.Value=double(candidate.Threshold); end
                if isfield(loaded,'metadata')
                    md=loaded.metadata;
                    if isfield(md,'Calibrated'), app.Calibrated=logical(md.Calibrated); end
                    if app.Calibrated && isfield(md,'Threshold')
                        validateattributes(md.Threshold,{'numeric'},{'scalar','finite','real','nonnegative'});
                        app.UI.Threshold.Value=double(md.Threshold);
                    end
                    if isfield(md,'NormalLabel') && strlength(string(md.NormalLabel))>0, app.NormalLabel=string(md.NormalLabel); end
                    if isfield(md,'PixelThreshold') && ~isempty(md.PixelThreshold)
                        validateattributes(md.PixelThreshold,{'numeric'},{'scalar','finite','real','nonnegative'});
                        app.PixelThreshold=double(md.PixelThreshold); app.UI.PixelThreshold.Value=app.PixelThreshold;
                    end
                    if isfield(md,'PixelPercentile')
                        validateattributes(md.PixelPercentile,{'numeric'},{'scalar','finite','>=',50,'<',100});
                        app.UI.PixelPercentile.Value=md.PixelPercentile;
                    end
                end
                app.UI.NormalClass.Value=char(app.NormalLabel);
            end
            [~,name,extension]=fileparts(file); app.ModelName=string(name)+string(extension);
            if isfield(app.ModelMetadata,'ModelName') && strlength(string(app.ModelMetadata.ModelName))>0
                app.ModelName=string(app.ModelMetadata.ModelName);
            end
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
            assert(~isempty(ds.Files),'VIStudioV15:EmptyFolder','資料夾內沒有影像。 / No images found.');
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
            assert(~isempty(app.InputImage),'VIStudioV15:MissingImage', ...
                '請先載入影像。 / Load an image first.');
            app.Busy=true; app.refresh(); cleanup=onCleanup(@() app.finish());
            p=app.progress('影像檢測 / Inspection','計算預測 / Running prediction',false);
            progressCleanup=onCleanup(@() delete(p));
            prediction=app.predict(app.InputImage);
            if app.Task=="anomaly"
                prediction.Measurement.Context.SourceFile=app.InputFile;
            end
            app.renderPrediction(prediction);
            app.LastPrediction=prediction;
            app.UI.Tabs.SelectedTab=app.UI.InspectionTab; app.syncWorkspace();
            app.log('檢測完成 / Inspection complete.');
        end
        function results=runBatch(app,resume)
            if nargin<2, resume=false; end
            app.assertIdle(); app.requireModel();
            assert(~isempty(app.Dataset),'VIStudioV15:MissingDataset','請先匯入資料夾。 / Import a folder first.');
            signature=app.signature();
            if resume
                assert(app.BatchSignature==signature,'VIStudioV15:IncompatibleCheckpoint', ...
                    '設定已改變，無法沿用進度。 / Settings changed; start a new batch.');
            else
                app.clearResults(); app.BatchSignature=signature;
            end
            labeled=app.Task~="detection" && app.UI.UseLabels.Value;
            if labeled && app.Task=="classification"
                assert(all(ismember(string(app.Dataset.Labels),app.Classes)), ...
                    'VIStudioV15:UnknownLabels','資料夾標籤不在模型類別中。 / Unknown folder labels.');
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
            results=app.Results; app.UI.Tabs.SelectedTab=app.UI.ResultsTab; app.syncWorkspace();
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
            assert(~isempty(results),'VIStudioV15:MissingResults','尚無可匯出結果。 / No results to export.');
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
            assert(app.Task~="detection",'VIStudioV15:NotClassification','僅供影像標籤評估 / Image-label evaluation only.');
            validateattributes(value,{'logical'},{'scalar'});
            app.UI.UseLabels.Value=value; app.clearResults(); app.refresh();
        end
        function selectWorkspace(app,name)
            % For scripted previews: data, results, or inspection.
            key=validatestring(name,{'training','calibration','data','results','inspection','review','evaluation','visualization','measurement','advanced'});
            if strcmp(key,'calibration'), assert(app.Task=="anomaly",'VIStudioV15:NotAnomaly','Calibration is only available for anomaly models.'); end
            tabs=struct('data',app.UI.DataTab,'results',app.UI.ResultsTab,'inspection',app.UI.InspectionTab, ...
                'review',app.UI.ReviewTab,'evaluation',app.UI.EvaluationTab,'training',app.UI.TrainingTab);
            if app.Task=="anomaly", tabs.calibration=app.UI.CalibrationTab; end
            if ~isempty(app.ModelViewer), tabs.visualization=app.UI.VisualizationTab; end
            tabs.advanced=app.UI.AdvancedTab;
            if ~isempty(app.DefectPane), tabs.measurement=app.UI.MeasurementTab; end
            assert(isfield(tabs,key),'VIStudioV15:VisualTask','This workspace is unavailable for the selected task.');
            app.UI.Tabs.SelectedTab=tabs.(key); app.syncWorkspace();
        end
        function setFilter(app,options)
            app.assertIdle(); filter=VIStudioToolsV3.defaultFilter();
            fields=fieldnames(options);
            for k=1:numel(fields)
                assert(isfield(filter,fields{k}),'VIStudioV15:InvalidFilter','Unknown filter field.');
                filter.(fields{k})=options.(fields{k});
            end
            for field={'Query','Class','Status','Review'}, filter.(field{1})=string(filter.(field{1})); end
            assert(filter.MinConfidence<=filter.MaxConfidence,'VIStudioV15:InvalidFilter','Invalid confidence range.');
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
            assert(~isempty(row),'VIStudioV15:MissingResult','找不到此影像結果。 / Result not found.');
            if state=="accepted" && strlength(label)==0, label=app.Results.Prediction(row); end
            if state=="corrected", assert(strlength(label)>0,'VIStudioV15:MissingReviewLabel','請輸入正確答案。 / Enter the corrected label.'); end
            if app.Task~="detection" && any(state==["accepted","corrected"])
                assert(ismember(label,app.Classes),'VIStudioV15:UnknownLabels','覆核答案不在模型類別中。 / Unknown review label.');
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
            assert(app.Task=="anomaly",'VIStudioV15:NotAnomaly','Only available for anomaly inspection.');
            validateattributes(value,{'numeric'},{'scalar','real','finite','nonnegative'});
            app.PixelThreshold=value; app.UI.PixelThreshold.Value=value; app.settingsChanged();
        end
        function setNormalClass(app,label)
            app.assertIdle(); label=string(label);
            assert(isscalar(label) && strlength(label)>0,'VIStudioV15:MissingLabels','Normal label cannot be empty.');
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
            if ~isempty(app.DefectPane), app.DefectPane.setLanguage(app.Language); end
            app.UI.Language.Value=app.Language; app.updateViews(); app.refresh();
            titles=struct('classification',{{'影像分類','Image Classification'}}, ...
                'detection',{{'物件偵測','Object Detection'}},'anomaly',{{'異常偵測','Anomaly Detection'}});
            taskTitle=titles.(char(app.Task));
            if strcmp(app.Language,'en'), name=taskTitle{2};
            elseif strcmp(app.Language,'zh'), name=taskTitle{1};
            else, name=[taskTitle{1} ' ' taskTitle{2}]; end
            app.UI.Header.Text=['VIStudio V20 / ' name]; app.UIFigure.Name=['VIStudio V20 | ' name];
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
                'VIStudioV15:ModelOverwrite','專案不可覆蓋模型。 / Project cannot overwrite its model.');
            project=struct('Version',1,'Task',app.Task,'ModelPath',app.ModelPath,'ModelDigest',app.ModelDigest, ...
                'Threshold',app.UI.Threshold.Value,'Environment',app.UI.Environment.Value, ...
                'ROI',app.ROI,'PixelThreshold',app.PixelThreshold,'NormalLabel',app.NormalLabel, ...
                'Calibrated',app.Calibrated,'Language',app.Language,'UseLabels',false, ...
                'Files',strings(0,1),'Labels',strings(0,1),'Results',app.Results,'Filter',app.Filter, ...
                'InputFile',app.InputFile,'BatchSignature',app.BatchSignature,'GroundTruth',app.GroundTruth);
            project.TrainingState=app.TrainingPane.state();
            if app.Task=="anomaly", project.DefectRules=app.DefectOptions; end
            if app.Task=="anomaly"
                project.CalibrationSource=app.CalibrationSource;
                project.CalibrationFiles=strings(0,1); project.CalibrationLabels=strings(0,1);
                if ~isempty(app.CalibrationData), project.CalibrationFiles=string(app.CalibrationData.Files); project.CalibrationLabels=string(app.CalibrationData.Labels); end
                project.CalibrationNormal=string(app.UI.CalibrationNormal.Value);
                project.PixelPercentile=app.UI.PixelPercentile.Value;
            end
            if app.Task~="detection", project.UseLabels=app.UI.UseLabels.Value; end
            if ~isempty(app.Dataset), project.Files=string(app.Dataset.Files); project.Labels=string(app.Dataset.Labels); end
            [folder,~,ext]=fileparts(file); if isempty(folder), folder=pwd; end
            assert(strcmpi(ext,'.mat'),'VIStudioV15:ProjectExtension','請使用 .mat 專案檔。 / Use a .mat project file.');
            temporary=[tempname(folder) '.mat'];
            cleanup=onCleanup(@() app.removeTemporary(temporary));
            save(temporary,'project','-v7.3'); movefile(temporary,file,'f');
            app.log('專案已儲存 / Project saved.');
        end
        function openProject(app,file)
            app.assertIdle(); loaded=load(file,'project');
            assert(isfield(loaded,'project'),'VIStudioV15:InvalidProject','Missing project.'); p=loaded.project;
            required={'Version','Task','ModelPath','ModelDigest','Threshold','Environment','ROI','PixelThreshold', ...
                'NormalLabel','Calibrated','Language','UseLabels','Files','Labels','Results','Filter','InputFile','BatchSignature'};
            assert(isstruct(p) && isscalar(p) && all(isfield(p,required)) && p.Version==1 && p.Task==app.Task, ...
                'VIStudioV15:InvalidProject','專案格式或任務不符。 / Project version or task does not match.');
            assert(isfile(p.ModelPath) && VIStudioToolsV3.fileHash(p.ModelPath)==p.ModelDigest, ...
                'VIStudioV15:ChangedModel','模型遺失或內容已變更。 / Model is missing or has changed.');
            assert(numel(p.Files)==numel(p.Labels) && all(isfile(p.Files)), ...
                'VIStudioV15:MissingProjectImages','專案影像遺失。 / Project images are missing.');
            validateattributes(p.Threshold,{'numeric'},{'scalar','real','finite','nonnegative'});
            if app.Task~="anomaly", assert(p.Threshold<=1,'Invalid confidence threshold.'); end
            validatestring(p.Environment,{'auto','cpu','gpu'}); validatestring(p.Language,{'bilingual','zh','en'});
            validateattributes(p.UseLabels,{'logical'},{'scalar'});
            validateattributes(p.Calibrated,{'logical'},{'scalar'});
            if ~isempty(p.ROI), validateattributes(p.ROI,{'numeric'},{'vector','numel',4,'positive','integer','finite'}); end
            if ~isempty(p.PixelThreshold), validateattributes(p.PixelThreshold,{'numeric'},{'scalar','real','finite','nonnegative'}); end
            app.validateResultTable(p.Results,p.Files); VIStudioToolsV3.filterResults(p.Results,p.Filter);
            assert(strlength(string(p.InputFile))==0 || isfile(p.InputFile),'VIStudioV15:MissingProjectImages','Selected image is missing.');
            ds=[];
            if ~isempty(p.Files), ds=imageDatastore(cellstr(p.Files)); ds.Labels=categorical(p.Labels); end
            groundTruth=[];
            if isfield(p,'GroundTruth') && ~isempty(p.GroundTruth), groundTruth=VIStudioData.detectionTable(p.GroundTruth); end
            if isfield(p,'TrainingState'), app.TrainingPane.validateState(p.TrainingState); end
            if app.Task=="anomaly" && isfield(p,'CalibrationSource') && strlength(string(p.CalibrationSource))>0
                calibration=imageDatastore(p.CalibrationSource,'IncludeSubfolders',true,'LabelSource','foldernames');
                assert(~isempty(calibration.Files) && ismember(string(p.CalibrationNormal),string(categories(calibration.Labels))), ...
                    'VIStudioV15:MissingCalibration','Calibration files or the normal class are missing.');
                validateattributes(p.PixelPercentile,{'numeric'},{'scalar','finite','>=',50,'<',100});
            end
            managedCalibration=[];
            if app.Task=="anomaly" && isfield(p,'CalibrationFiles') && ~isempty(p.CalibrationFiles)
                assert(numel(p.CalibrationFiles)==numel(p.CalibrationLabels) && all(isfile(p.CalibrationFiles)), ...
                    'VIStudioV15:MissingCalibration','Managed calibration files are missing.');
                managedCalibration=imageDatastore(cellstr(p.CalibrationFiles)); managedCalibration.Labels=categorical(p.CalibrationLabels);
                assert(ismember(string(p.CalibrationNormal),string(categories(managedCalibration.Labels))), ...
                    'VIStudioV15:MissingCalibration','Managed normal label is missing.');
                validateattributes(p.PixelPercentile,{'numeric'},{'scalar','finite','>=',50,'<',100});
            end
            projectRules=[];
            if app.Task=="anomaly" && isfield(p,'DefectRules'), projectRules=VIStudioDefectsV10.options(p.DefectRules); end
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
            if isfield(p,'TrainingState'), app.TrainingPane.restore(p.TrainingState); end
            if app.Task=="anomaly" && isfield(p,'CalibrationSource') && strlength(string(p.CalibrationSource))>0
                app.loadCalibrationFolder(p.CalibrationSource);
                app.UI.CalibrationNormal.Value=char(p.CalibrationNormal); app.UI.PixelPercentile.Value=p.PixelPercentile;
            end
            if ~isempty(managedCalibration)
                app.CalibrationData=managedCalibration; app.CalibrationSource=string(p.CalibrationSource);
                app.UI.CalibrationNormal.Items=cellstr(categories(managedCalibration.Labels)); app.UI.CalibrationNormal.Value=char(p.CalibrationNormal);
                app.UI.PixelPercentile.Value=p.PixelPercentile; app.UI.CalibrationPath.Text='專案校準清單 / Project calibration list';
            end
            if ~isempty(projectRules), app.DefectOptions=projectRules; app.DefectPane.sync(projectRules); end
            app.setLanguage(p.Language); app.setFilter(p.Filter); app.updateViews(); app.refresh();
            app.log('專案已重開 / Project restored.');
        end
        function report=exportImages(app,folder)
            app.assertIdle(); results=app.filteredResults();
            results=results(~contains(results.Status,'Error'),:);
            assert(~isempty(results),'VIStudioV15:MissingResults','No successful results to export.');
            names=strings(height(results),1);
            for k=1:height(results)
                assert(isfile(results.File(k)), 'VIStudioV15:ChangedImage', ...
                    '來源影像不存在。 / Source image is missing: %s',results.File(k));
                currentHash=VIStudioToolsV3.fileHash(results.File(k));
                assert(currentHash==results.SourceHash(k), 'VIStudioV15:ChangedImage', ...
                    '來源影像已變更，請重新檢測。 / Source image changed; run inspection again: %s\nExpected: %s\nCurrent: %s', ...
                    results.File(k),results.SourceHash(k),currentHash);
                [~,stem]=fileparts(results.File(k)); stem=regexprep(stem,'[^\w\-]','_');
                names(k)=sprintf('%05d_%s_V15.png',k,stem);
                assert(~isfile(fullfile(folder,names(k))) && ~isfile(fullfile(folder,"mask_"+names(k))), ...
                    'VIStudioV15:ExportExists','匯出目標已存在，請選擇新資料夾。 / Choose a new export folder.');
            end
            if ~isfolder(folder), mkdir(folder); end
            report=table(results.File,strings(height(results),1),strings(height(results),1), ...
                'VariableNames',{'Source','ResultImage','MaskImage'});
            for k=1:height(results)
                image=VIStudioData.readImage(results.File(k),[]);
                if app.Task=="anomaly" && ismember('MeasurementJSON',results.Properties.VariableNames) && strlength(results.MeasurementJSON(k))>0
                    assert(VIStudioToolsV3.fileHash(results.File(k))==results.SourceHash(k),'VIStudioV15:SourceChanged','Source image changed after inspection; rerun inspection before export.');
                    measurement=VIStudioDefectsV10.fromJSON(results.MeasurementJSON(k)); image=VIStudioDefectsV10.overlay(image,measurement);
                end
                if app.Task=="detection"
                    boxes=VIStudioToolsV3.decodeBoxes(results.BoxesJSON(k),results.Objects(k));
                    labels=string(jsondecode(results.LabelsJSON(k))); scores=jsondecode(results.ScoresJSON(k));
                    if ~isempty(boxes), image=insertObjectAnnotation(image,'rectangle',boxes,cellstr(compose('%s %.1f%%',labels(:),100*scores(:)))); end
                elseif app.Task=="anomaly"
                    if ismember('MeasurementJSON',results.Properties.VariableNames) && strlength(results.MeasurementJSON(k))>0
                        measurement=VIStudioDefectsV10.fromJSON(results.MeasurementJSON(k));
                        if measurement.Available
                            maskFile=fullfile(folder,"mask_"+names(k)); imwrite(measurement.FilteredMask,maskFile); report.MaskImage(k)=maskFile;
                        end
                    elseif strlength(results.MaskRLEJSON(k))>0
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
                if ismember('QualityDecision',results.Properties.VariableNames) && strlength(results.QualityDecision(k))>0, text=text+" | Rules: "+results.QualityDecision(k); end
                image=insertText(image,[1 1],text,'FontSize',14,'BoxOpacity',0.65);
                output=fullfile(folder,names(k)); imwrite(image,output); report.ResultImage(k)=output;
            end
            app.log('結果影像已匯出 / Result images exported.');
        end
        function summary=evaluateResults(app,useReviewed)
            app.assertIdle(); if nargin<2, useReviewed=false; end
            assert(~isempty(app.Results),'VIStudioV15:MissingResults','Run a batch first.');
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
            app.UI.Tabs.SelectedTab=app.UI.EvaluationTab; app.syncWorkspace();
        end
        function importGroundTruth(app,file)
            app.assertIdle(); assert(app.Task=="detection",'Only detection uses box ground truth.');
            loaded=load(file);
            if isfield(loaded,'gTruth'), value=loaded.gTruth;
            elseif isfield(loaded,'exportROI'), value=loaded.exportROI;
            else, error('VIStudioV15:MissingGroundTruth','Missing gTruth or exportROI.'); end
            app.GroundTruth=VIStudioData.detectionTable(value,fileparts(file));
            app.log('評估標註已匯入 / Evaluation ground truth loaded.');
        end
    end
    methods (Access=private)
        function buildWorkbench(app)
            app.UI.AdvancedTab=uitab(app.UI.Tabs,'Title','進階工作台 / Advanced Workbench');
            callbacks=struct('Source',@() app.InputFile,'Busy',@(value) app.workbenchBusy(value), ...
                'Activate',@(file) app.activateAdvancedModel(file),'DefectRules',@() app.DefectOptions,'Retrain',@(task,path) app.retrainAdvanced(task,path));
            app.Workbench=VIStudioWorkbenchV20(app.UI.AdvancedTab,app.Task,callbacks);
        end
        function workbenchBusy(app,value), app.Busy=value; app.refresh(); end
        function retrainAdvanced(app,task,path)
            if ismember(string(task),["instance","keypoints"]), app.Workbench.Structured.loadDataset(path); app.selectWorkspace('advanced'); app.Workbench.Handles.Tabs.SelectedTab=app.Workbench.Structured.Handles.Root.Parent; return; end
            if string(task)=="semantic", app.Workbench.Semantic.loadDataset(path); app.selectWorkspace('advanced'); app.Workbench.selectSemantic(); return; end
            target=app;
            if string(task)~=app.Task, target=VIStudioVisionAppV20(task); end
            if string(task)=="detection", target.loadTrainingAnnotations(path); else, target.loadTrainingFolder(path); end
            target.selectWorkspace('training');
        end
        function activateAdvancedModel(app,file)
            if app.Task=="anomaly", app.loadModel(file);
            else, other=VIStudioVisionAppV20('anomaly'); other.loadModel(file); end
        end
        function buildDefectTools(app)
            if app.Task~="anomaly", return; end
            app.UI.MeasurementTab=uitab(app.UI.Tabs,'Title','07 缺陷量測 / Defect Measurement');
            callbacks=struct('Configure',@(options) app.configureDefectRules(options),'Predict',@() app.inspectForMeasurement(), ...
                'Reference',@(points,lengthMM) app.calibrateDefectScale(points,lengthMM), ...
                'Save',@(file) app.saveDefectRules(file),'Load',@(file) app.loadDefectRules(file),'Export',@(folder) app.exportDefectMeasurement(folder),'ExportBatch',@() app.pickBatchDefectReports());
            app.DefectPane=VIStudioDefectPaneV10(app.UI.MeasurementTab,app.UI.Tabs.Parent,callbacks);
        end
        function pickBatchDefectReports(app)
            parent=uigetdir(pwd,'Select batch report parent folder'); if isequal(parent,0), return; end
            [~,name]=fileparts(tempname(parent)); app.exportBatchDefectMeasurements(fullfile(parent,['measurements_' name]));
        end
        function inspectForMeasurement(app)
            app.predictImage(); app.UI.Tabs.SelectedTab=app.UI.MeasurementTab; app.syncWorkspace();
        end
        function buildModelTools(app)
            if app.Task~="anomaly"
                app.UI.VisualizationTab=uitab(app.UI.Tabs,'Title','06 模型視覺化 / Model Visualization');
                callbacks=struct('Explain',@() app.uiAction(@() app.visualizeModel()));
                app.ModelViewer=VIStudioModelViewerV7(app.UI.VisualizationTab,app.Task,callbacks);
                app.UI.Tabs.SelectedTab=app.UI.TrainingTab;
            end
            bar=app.UI.SaveProject.Parent; bar.ColumnWidth={'1x','1x','1x','1x','1x'};
            app.UI.Labeler=uibutton(bar,'Text','標註工具 / Labeler', ...
                'ButtonPushedFcn',@(~,~) app.uiAction(@() app.openLabeler()));
            % A training-tab entry keeps the labeler easy to find before a model exists.
            tab=uitab(app.TrainingPane.Tabs,'Title','10 標註工具 / Labeler');
            grid=uigridlayout(tab,[3 1],'RowHeight',{70,52,'1x'});
            uilabel(grid,'Text','矩形、多邊形、像素畫筆與模型預標註；人工確認後可匯出並送回訓練。 / Boxes, polygons, pixel brushes and model candidates; reviewed labels can be exported back to training.','WordWrap','on');
            uibutton(grid,'Text','開啟 V20 標註工作室 / Open V20 Labeler','ButtonPushedFcn',@(~,~) app.uiAction(@() app.openLabeler()));
        end
        function receiveLabels(app,output)
            app.assertIdle(); if ismember(string(output.Task),["instance","keypoints"]), app.retrainAdvanced(output.Task,output.Path); return; end; if string(output.Task)=="semantic", app.retrainAdvanced("semantic",output.Path); return; end; assert(string(output.Task)==app.Task,'VIStudioV15:LabelTask','Choose an export task matching the training workspace.');
            if output.Task=="semantic", app.retrainAdvanced("semantic",output.Path); return; end
            if app.Task=="detection", app.loadTrainingAnnotations(output.Path);
            else, app.loadTrainingFolder(output.Path); end
            app.selectWorkspace('training');
        end
        function buildIntegratedTraining(app)
            app.UIFigure.Position=[40 40 1380 740];
            body=app.UI.Tabs.Parent;
            app.UI.InspectionSettings=app.UI.ModelInfo.Parent.Parent;
            previous=app.UI.Tabs.Children;
            app.UI.TrainingTab=uitab(app.UI.Tabs,'Title','訓練 / Training');
            callbacks=struct('Train',@() app.uiAction(@() app.train()), ...
                'Save',@() app.uiAction(@() app.pickSaveModel()), ...
                'Inspect',@() app.uiAction(@() app.predictTrainingImage()), ...
                'Load',@() app.uiAction(@() app.pickTrainingData()),'Changed',@() app.refresh(), ...
                'UseDataset',@(role) app.useDatasetRole(role),'ActivateRun',@(file) app.loadModel(file));
            app.TrainingPane=VIStudioTrainingPaneV9(app.Task,body,app.UI.TrainingTab,callbacks);
            app.UI.TrainingSettings=app.TrainingPane.SettingsPanel;
            if app.Task=="anomaly"
                app.buildCalibration();
                app.UI.Tabs.Children=[app.UI.TrainingTab;app.UI.CalibrationTab;previous(:)];
            else, app.UI.Tabs.Children=[app.UI.TrainingTab;previous(:)]; end
            app.UI.Legacy.Text='模型訓練 / Model training';
            app.UI.Legacy.ButtonPushedFcn=@(~,~) app.selectWorkspace('training');
            bar=app.UI.SaveProject.Parent; bar.ColumnWidth={'1x','1x','1x','1x'};
            app.UI.SaveModel=uibutton(bar,'Text','匯出模型 / Export model', ...
                'ButtonPushedFcn',@(~,~) app.uiAction(@() app.pickSaveModel()));
            app.UI.Tabs.SelectionChangedFcn=@(~,~) app.syncWorkspace();
            app.UI.Tabs.SelectedTab=app.UI.TrainingTab; app.syncWorkspace();
        end
        function syncWorkspace(app)
            if ~isfield(app.UI,'TrainingTab'), return; end
            advanced=isfield(app.UI,'AdvancedTab') && isequal(app.UI.Tabs.SelectedTab,app.UI.AdvancedTab);
            body=app.UI.Tabs.Parent;
            if advanced
                body.ColumnWidth={0,'1x'}; app.UI.TrainingSettings.Visible='off'; app.UI.InspectionSettings.Visible='off';
                if ~isempty(app.DefectPane), app.DefectPane.SettingsPanel.Visible='off'; end
                return;
            end
            body.ColumnWidth={310,'1x'};
            training=isequal(app.UI.Tabs.SelectedTab,app.UI.TrainingTab);
            measuring=~isempty(app.DefectPane) && isequal(app.UI.Tabs.SelectedTab,app.UI.MeasurementTab);
            if ~isempty(app.DefectPane), app.DefectPane.SettingsPanel.Visible=app.enabled(measuring); end
            if measuring
                app.UI.TrainingSettings.Visible='off'; app.UI.InspectionSettings.Visible='off';
            elseif training
                app.UI.InspectionSettings.Visible='off'; app.UI.TrainingSettings.Visible='on';
            else
                app.UI.TrainingSettings.Visible='off'; app.UI.InspectionSettings.Visible='on';
            end
        end
        function buildCalibration(app)
            app.UI.CalibrationTab=uitab(app.UI.Tabs,'Title','校準 / Calibration');
            grid=uigridlayout(app.UI.CalibrationTab,[6 2],'RowHeight',{40,46,38,42,'1x',150}, ...
                'ColumnWidth',{'1x','1x'},'Padding',[16 12 16 12]);
            app.UI.LoadCalibration=uibutton(grid,'Text','匯入獨立校準資料 / Load independent calibration data', ...
                'ButtonPushedFcn',@(~,~) app.uiAction(@() app.pickCalibration()));
            app.UI.LoadCalibration.Layout.Column=[1 2];
            app.UI.CalibrationPath=uilabel(grid,'Text','請與訓練資料分開 / Keep calibration data separate from training','WordWrap','on');
            app.UI.CalibrationPath.Layout.Row=2; app.UI.CalibrationPath.Layout.Column=[1 2];
            app.UI.CalibrationNormal=uidropdown(grid,'Items',{'good'},'Tooltip','正常資料夾 / Normal folder');
            app.UI.CalibrationNormal.Layout.Row=3; app.UI.CalibrationNormal.Layout.Column=1;
            bar=uigridlayout(grid,[1 2],'ColumnWidth',{'1x',90},'Padding',[0 0 0 0]); bar.Layout.Row=3; bar.Layout.Column=2;
            uilabel(bar,'Text','正常像素百分位 / Normal pixel percentile','WordWrap','on');
            app.UI.PixelPercentile=uieditfield(bar,'numeric','Value',99,'Limits',[50 99.99]);
            app.UI.Calibrate=uibutton(grid,'Text','校準影像與像素門檻 / Calibrate thresholds', ...
                'ButtonPushedFcn',@(~,~) app.uiAction(@() app.calibrateAnomaly()));
            app.UI.Calibrate.Layout.Row=4; app.UI.Calibrate.Layout.Column=1;
            app.UI.CalibrationInfo=uilabel(grid,'Text','尚未校準 / Not calibrated','WordWrap','on');
            app.UI.CalibrationInfo.Layout.Row=4; app.UI.CalibrationInfo.Layout.Column=2;
            app.UI.CalibrationPlot=uiaxes(grid); app.UI.CalibrationPlot.Layout.Row=5; app.UI.CalibrationPlot.Layout.Column=[1 2];
            app.UI.CalibrationResults=uitable(grid,'RowName',{}, ...
                'ColumnName',{'檔案 / File','異常真值 / Actual anomaly','分數 / Score','異常預測 / Predicted anomaly'});
            app.UI.CalibrationResults.Layout.Row=6; app.UI.CalibrationResults.Layout.Column=[1 2];
        end
        function assertIndependentCalibration(app)
            training=strings(0,1); pixels=strings(0,1);
            if isfield(app.ModelMetadata,'SourceFiles'), training=string(app.ModelMetadata.SourceFiles(:)); end
            if isfield(app.ModelMetadata,'SourcePixelHashes'), pixels=string(app.ModelMetadata.SourcePixelHashes(:)); end
            training=training(isfile(training));
            for k=1:numel(training)
                training(k)=VIStudioToolsV3.canonicalPath(training(k));
                pixels(end+1,1)=VIStudioDataHealthV8.pixelHash(VIStudioData.readImage(training(k),[]));
            end
            files=string(app.CalibrationData.Files);
            for k=1:numel(files)
                files(k)=VIStudioToolsV3.canonicalPath(files(k));
                hash=VIStudioDataHealthV8.pixelHash(VIStudioData.readImage(files(k),[]));
                assert(~any(lower(training)==lower(files(k))) && ~any(pixels==hash), ...
                    'VIStudioV15:CalibrationOverlap','校準資料含訓練／驗證的影像內容 / Calibration overlaps training or validation content.');
            end
        end
        function pickTrainingData(app)
            if app.Task=="detection"
                [file,folder]=uigetfile('*.mat','匯入訓練標註 / Import training annotations');
                if ~isequal(file,0), app.loadTrainingAnnotations(fullfile(folder,file)); end
            else
                folder=uigetdir(pwd,'載入訓練資料 / Load training images');
                if ~isequal(folder,0), app.loadTrainingFolder(folder); end
            end
        end
        function pickSaveModel(app)
            [file,folder]=uiputfile('*.mat','匯出模型 / Export model','VIStudioV9_model.mat');
            if ~isequal(file,0), app.saveModel(fullfile(folder,file)); end
        end
        function pickCalibration(app)
            folder=uigetdir(pwd,'選擇獨立校準資料 / Choose independent calibration images');
            if ~isequal(folder,0), app.loadCalibrationFolder(folder); end
        end
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
            row.QualityDecision=""; row.MeasuredRegions=NaN; row.MeasuredAreaPx=NaN; row.MeasuredAreaMM2=NaN;
            row.RuleDigest=""; row.MeasurementJSON="";
            if isfield(prediction,'Measurement')
                report=prediction.Measurement; report.Context.SourceFile=string(file); report.Context.SourceHash=hash;
                row.QualityDecision=report.Decision; row.MeasuredRegions=report.Count; row.MeasuredAreaPx=report.TotalAreaPx; row.MeasuredAreaMM2=report.TotalAreaMM2;
                row.RuleDigest=report.RuleDigest; row.MeasurementJSON=VIStudioDefectsV10.toJSON(report);
            elseif strlength(errorMessage)>0, row.QualityDecision="ERROR"; end
        end
        function updateViews(app)
            [view,app.VisibleRows]=VIStudioToolsV3.filterResults(app.Results,app.Filter);
            if isempty(view)
                app.UI.Results.Data=[]; app.UI.ReviewTable.Data=[];
            else
                view.Status=VIStudioToolsV3.translate(view.Status,app.Language);
                columns={'File','Prediction','Confidence','Objects','Status','ReviewState'};
                if app.Task=="anomaly" && ismember('QualityDecision',view.Properties.VariableNames), columns=[columns {'QualityDecision','MeasuredRegions','MeasuredAreaPx','MeasuredAreaMM2'}]; end
                app.UI.Results.Data=view(:,columns);
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
            assert(strlength(app.SelectedFile)>0,'VIStudioV15:MissingResult','請先選取結果。 / Select a result first.');
            app.setReview(app.SelectedFile,app.UI.ReviewState.Value,app.UI.ReviewLabel.Value, ...
                join(string(app.UI.ReviewNote.Value),newline));
        end
        function predictSelected(app)
            assert(strlength(app.SelectedFile)>0,'VIStudioV15:MissingResult','Select a result first.');
            app.predictImage(app.SelectedFile);
        end
        function signature=signature(app)
            files=string(app.Dataset.Files);
            labels=false; if app.Task~="detection", labels=app.UI.UseLabels.Value; end
            signature=string(jsonencode(struct('Model',app.ModelDigest,'Files',files, ...
                'Threshold',app.UI.Threshold.Value,'ROI',app.ROI,'Pixel',app.PixelThreshold, ...
                'Normal',app.NormalLabel,'UseLabels',labels,'Calibrated',app.Calibrated,'DefectRules',app.DefectOptions)));
        end
        function summary=evaluateDetection(app)
            assert(~isempty(app.GroundTruth),'VIStudioV15:MissingGroundTruth','請匯入矩形標註。 / Import box ground truth.');
            data=app.Results(~contains(app.Results.Status,'Error'),:);
            [found,rows]=ismember(lower(data.File),lower(string(app.GroundTruth.imageFilename)));
            assert(all(found) && ~isempty(data),'VIStudioV15:MissingGroundTruth','部分結果沒有對應標註。 / Ground truth is missing for results.');
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
            app.UI.Tabs.SelectedTab=app.UI.EvaluationTab; app.syncWorkspace();
        end
        function drawROI(app)
            assert(~isempty(app.InputImage),'VIStudioV15:MissingImage','請先在檢測頁載入影像。 / Load an inspection image first.');
            app.UI.Tabs.SelectedTab=app.UI.InspectionTab; app.syncWorkspace();
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
                    if strcmp(field,'Items') && ~isempty(app.TrainingPane) && ...
                            (isequal(h,app.TrainingPane.Handles.Model) || isequal(h,app.TrainingPane.Handles.NormalClass)), continue; end
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
            if isempty(results), assert(istable(results),'VIStudioV15:InvalidProject','Results must be a table.'); return; end
            required={'File','Prediction','Confidence','Objects','Status','Milliseconds','Actual','Correct', ...
                'BoxesJSON','ScoresJSON','LabelsJSON','ReviewState','ReviewedLabel','ReviewNote','ReviewTime', ...
                'Error','MaskRLEJSON','MaskSizeJSON','DefectArea','DefectRegions','SourceHash'};
            assert(istable(results) && all(ismember(required,results.Properties.VariableNames)) && ...
                all(ismember(results.File,string(files))) && numel(unique(results.File))==height(results), ...
                'VIStudioV15:InvalidProject','Project results are invalid.');
            assert(all(ismember(results.ReviewState,["pending","accepted","corrected","rejected"])), ...
                'VIStudioV15:InvalidProject','Invalid review state.');
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
            app.UIFigure=uifigure('Name',['VIStudio V20 | ' titleText], ...
                'Position',[45 45 1380 860],'Color',[0.95 0.96 0.98], ...
                'Visible','off','CloseRequestFcn',@(~,~) app.closeApp());
            root=uigridlayout(app.UIFigure,[3 1],'RowHeight',{76,'1x',32},'Padding',[20 12 20 8]);
            header=uigridlayout(root,[1 4],'ColumnWidth',{'1x',150,145,120}, ...
                'BackgroundColor',navy,'Padding',[20 8 16 8]);
            app.UI.Header=uilabel(header,'Text',['VIStudio V20  /  ' titleText],'FontSize',23,'FontWeight','bold','FontColor',[1 1 1]);
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
            inputPixelHash=""; if app.Task=="anomaly", inputPixelHash=VIStudioDataHealthV8.pixelHash(image); end
            [image,roi]=VIStudioToolsV3.cropImage(image,app.ROI);
            prediction=struct('Label',"",'Confidence',NaN,'Count',NaN,'Status',"", ...
                'Milliseconds',0,'Boxes',zeros(0,4),'Scores',[],'Labels',strings(0,1), ...
                'Mask',[],'Map',[],'DefectArea',NaN,'DefectRegions',NaN,'ROI',roi);
            if app.Task=="classification"
                input=app.prepareImage(image);
                scores=minibatchpredict(app.Model,input,'ExecutionEnvironment',app.UI.Environment.Value);
                scores=VIStudioVisionAppV20.probabilities(scores,numel(app.Classes));
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
                    'VIStudioV15:InvalidPrediction','方框、分數與標籤數量不一致。 / Detection output lengths differ.');
                assert(all(isfinite(scores)) && all(scores>=0 & scores<=1), ...
                    'VIStudioV15:InvalidPrediction','偵測分數無效。 / Invalid detection scores.');
                assert(isempty(boxes) || all(boxes(:,3:4)>0,'all'), ...
                    'VIStudioV15:InvalidPrediction','方框尺寸無效。 / Invalid box dimensions.');
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
            if app.Task=="anomaly"
                context=struct('Calibrated',app.Calibrated,'ImageScore',prediction.Confidence,'ImageThreshold',app.UI.Threshold.Value, ...
                    'PixelThreshold',NaN,'Map',prediction.Map,'ModelDigest',app.ModelDigest,'InputPixelHash',inputPixelHash);
                if ~isempty(app.PixelThreshold), context.PixelThreshold=app.PixelThreshold; end
                prediction.Measurement=VIStudioDefectsV10.analyze(prediction.Mask,roi,app.DefectOptions,context);
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
            if app.Task=="anomaly" && isfield(prediction,'Measurement')
                report=prediction.Measurement; app.DefectPane.show(app.InputImage,report);
                if report.Decision~="DISABLED"
                    app.UI.Verdict.Text=string(app.UI.Verdict.Text)+" | 規則 / Rules: "+report.Decision;
                    if report.Decision=="NG", color=[.8 .15 .12]; elseif report.Decision=="REVIEW", color=[.7 .4 .05]; else, color=[.06 .56 .46]; end
                end
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
            if ~isempty(app.DefectPane), app.DefectPane.busy(app.Busy,~isempty(app.Results)); end
            app.UI.Batch.Enable=app.enabled(ready && ~isempty(app.Dataset));
            app.UI.Predict.Enable=app.enabled(ready && ~isempty(app.InputImage));
            app.UI.Export.Enable=app.enabled(~isempty(app.Results));
            app.UI.SaveProject.Enable=app.enabled(ready);
            app.UI.ExportImages.Enable=app.enabled(~isempty(app.Results));
            if isfield(app.UI,'SaveModel'), app.UI.SaveModel.Enable=app.enabled(ready); end
            if isfield(app.UI,'Calibrate'), app.UI.Calibrate.Enable=app.enabled(ready && ~isempty(app.CalibrationData)); end
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
            if ~isempty(app.TrainingPane), app.TrainingPane.busy(app.Busy,ready,app.Language,app.ModelName); app.syncWorkspace(); end
            if ~isempty(app.Workbench), app.Workbench.busy(app.Busy); end
        end
        function state=enabled(app,condition)
            state='off'; if condition && ~app.Busy, state='on'; end
        end
        function assertIdle(app)
            assert(~app.Busy,'VIStudioV15:Busy','工作進行中，請稍候。 / A task is running.');
        end
        function requireModel(app)
            assert(~isempty(app.Model),'VIStudioV15:MissingModel','請先載入模型。 / Load a model first.');
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
            if isfield(app.UI,'CalibrationResults')
                app.UI.CalibrationResults.Data=[]; cla(app.UI.CalibrationPlot);
                app.UI.CalibrationInfo.Text=app.caption('門檻或模型已更新，需重新校準才顯示分布','Recalibrate to view the current score distribution');
            end
        end
        function clearPrediction(app)
            app.LastPrediction=[]; app.UI.Details.Data=[];
            if ~isempty(app.DefectPane), app.DefectPane.source(app.InputImage); end
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
                if strcmp(err.identifier,'VIStudioV15:Cancelled'), return; end
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
                app.inspectImage(fullfile(folder,file)); app.UI.Tabs.SelectedTab=app.UI.InspectionTab; app.syncWorkspace();
            end
        end
        function pickExport(app)
            [file,folder]=uiputfile('*.csv','匯出結果 / Export results','VIStudioV3_results.csv');
            if ~isequal(file,0), app.exportResults(fullfile(folder,file)); end
        end
        function openLegacy(app)
            app.selectWorkspace('training');
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
            if ~isempty(app.LabelerApp) && isvalid(app.LabelerApp) && ~app.LabelerApp.requestClose(), return; end
            delete(app);
        end
    end
    methods (Static)
        function scores=probabilities(scores,count)
            if isa(scores,'dlarray'), scores=extractdata(scores); end
            if isa(scores,'gpuArray'), scores=gather(scores); end
            scores=double(scores(:));
            assert(numel(scores)==count && all(isfinite(scores)) && isreal(scores), ...
                'VIStudioV15:InvalidScores','模型輸出與類別清單不符。 / Model output does not match the class list.');
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
