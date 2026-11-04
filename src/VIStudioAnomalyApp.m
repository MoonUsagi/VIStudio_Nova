classdef VIStudioAnomalyApp < matlab.apps.AppBase
    % Native, source-controlled anomaly inspection workspace.
    % Training, threshold calibration, and held-out testing use separate data.
    properties (Access = public)
        UIFigure
    end
    properties (Access = private)
        UI = struct()
        Data = struct('normal',[],'anomaly',[],'calibration',[],'test',[])
        Model = []
        ModelName = ""
        ImageSize = [224 224]
        Calibrated = false
        NormalLabel = ""
        Results = table()
        Scores = []
        Targets = []
        InputImage = []
        ScoreMap = []
        ImageScore = []
        Busy = false
        LogLines = {}
    end
    methods
        function app = VIStudioAnomalyApp(varargin)
            app.buildUI();
            registerApp(app,app.UIFigure);
            if nargin > 0
                app.UIFigure.Visible = varargin{1};
            end
            app.log('工作區已就緒。先匯入正常訓練影像，或載入已訓練模型。');
            app.refresh();
            if nargout == 0
                clear app
            end
        end
        function delete(app)
            if ~isempty(app.UIFigure) && isvalid(app.UIFigure)
                delete(app.UIFigure);
            end
        end
        function importImages(app,role,folder)
            %IMPORTIMAGES Import a dataset without an interactive file picker.
            % role: normal, anomaly, calibration, or test.
            role = char(validatestring(role,{'normal','anomaly','calibration','test'}));
            assert(~app.Busy,'目前正在處理其他工作。');
            app.acceptData(role,folder);
            app.refresh();
        end
        function inspectImage(app,file)
            %INSPECTIMAGE Load an image for inspection without a file picker.
            assert(~app.Busy,'目前正在處理其他工作。');
            app.acceptImage(file);
            app.refresh();
        end
        function saveDetector(app,file)
            %SAVEDETECTOR Save detector and preprocessing metadata to a MAT file.
            assert(~app.Busy && ~isempty(app.Model),'請先訓練或載入模型，並等待目前工作完成。');
            app.writeModel(file);
        end
        function loadDetector(app,file)
            %LOADDETECTOR Load and validate a saved detector before replacing it.
            assert(~app.Busy,'目前正在處理其他工作。');
            app.acceptModel(file);
            app.refresh();
        end
    end
    methods (Access = private)
        function buildUI(app)
            navy = [0.075 0.13 0.22];
            app.UIFigure = uifigure('Name','VIStudio | 異常偵測', ...
                'Position',[60 60 1380 880],'Color',[0.95 0.96 0.98], ...
                'Visible','off','CloseRequestFcn',@(~,~) app.closeApp());
            root = uigridlayout(app.UIFigure,[3 1], ...
                'RowHeight',{76,'1x',30},'Padding',[20 12 20 8]);
            header = uigridlayout(root,[1 3],'ColumnWidth',{'1x',180,150}, ...
                'BackgroundColor',navy,'Padding',[20 8 16 8]);
            uilabel(header,'Text','VIStudio   /   異常偵測', ...
                'FontSize',25,'FontWeight','bold','FontColor',[1 1 1]);
            app.UI.ModelStatus = uilabel(header,'Text','尚未載入模型', ...
                'FontColor',[0.65 0.77 0.90],'HorizontalAlignment','right');
            app.UI.ReadyStatus = uilabel(header,'Text','等待資料', ...
                'FontWeight','bold','FontColor',[0.4 0.85 0.75], ...
                'HorizontalAlignment','right');
            body = uigridlayout(root,[1 2],'ColumnWidth',{300,'1x'}, ...
                'Padding',[0 0 0 0],'ColumnSpacing',16);
            side = uipanel(body,'Title','模型與訓練設定','FontWeight','bold', ...
                'BackgroundColor',[1 1 1]);
            sg = uigridlayout(side,[17 1],'RowHeight', ...
                {18,30,32,18,28,18,28,18,28,18,28,28,38,30,30,64,30}, ...
                'Padding',[16 12 16 12],'RowSpacing',4,'Scrollable','on');
            uilabel(sg,'Text','偵測模型','FontWeight','bold');
            app.UI.ModelChoice = uidropdown(sg,'Items', ...
                {'PatchCore / ResNet-18','PatchCore / ResNet-50','FCDD / ResNet-18', ...
                'EfficientAD / Small','EfficientAD / Medium'}, ...
                'ValueChangedFcn',@(~,~) app.refresh());
            app.UI.ModelHint = uilabel(sg,'Text','','WordWrap','on','FontColor',[0.38 0.43 0.5]);
            uilabel(sg,'Text','影像尺寸（固定 RGB）','FontWeight','bold');
            app.UI.Size = uidropdown(sg,'Items',{'224 × 224','256 × 256'},'ItemsData',{224,256});
            uilabel(sg,'Text','訓練回合 Epochs','FontWeight','bold');
            app.UI.Epochs = uieditfield(sg,'numeric','Value',10,'Limits',[1 10000], ...
                'RoundFractionalValues','on');
            uilabel(sg,'Text','批次大小 Mini-batch','FontWeight','bold');
            app.UI.Batch = uieditfield(sg,'numeric','Value',8,'Limits',[1 512], ...
                'RoundFractionalValues','on');
            uilabel(sg,'Text','初始學習率','FontWeight','bold');
            app.UI.Rate = uieditfield(sg,'numeric','Value',0.0001,'Limits',[1e-8 1]);
            app.UI.Environment = uidropdown(sg,'Items',{'auto','cpu','gpu'},'Tooltip','運算裝置');
            app.UI.Train = uibutton(sg,'Text','開始訓練','FontWeight','bold', ...
                'BackgroundColor',[0.06 0.56 0.46],'FontColor',[1 1 1], ...
                'ButtonPushedFcn',@(~,~) app.run(@() app.train()));
            app.UI.Load = uibutton(sg,'Text','載入模型 .mat', ...
                'ButtonPushedFcn',@(~,~) app.run(@() app.loadModel()));
            app.UI.Save = uibutton(sg,'Text','儲存模型 .mat', ...
                'ButtonPushedFcn',@(~,~) app.run(@() app.saveModel()));
            uilabel(sg,'Text',sprintf(['01 匯入訓練資料\n02 訓練或載入模型\n' ...
                '03 使用獨立資料校準門檻\n04 檢測並匯出結果']), ...
                'WordWrap','on','FontColor',[0.38 0.43 0.5]);
            app.UI.Help = uibutton(sg,'Text','環境檢查', ...
                'ButtonPushedFcn',@(~,~) app.checkEnvironment());
            tabs = uitabgroup(body);
            dataTab = uitab(tabs,'Title','01  資料管理');
            dg = uigridlayout(dataTab,[7 3], ...
                'RowHeight',{34,48,48,48,48,'1x',76}, ...
                'ColumnWidth',{165,'1x',80},'Padding',[18 12 18 12], ...
                'RowSpacing',8,'Scrollable','on');
            t = uilabel(dg,'Text','分開管理資料，讓檢測結果可信賴。','FontSize',18,'FontWeight','bold');
            t.Layout.Column = [1 3];
            roles = {'normal','anomaly','calibration','test'};
            labels = {'正常訓練影像','異常訓練影像','門檻校準資料','獨立測試資料'};
            for k = 1:4
                role = roles{k};
                b = uibutton(dg,'Text',['匯入' labels{k}], ...
                    'ButtonPushedFcn',@(~,~) app.run(@() app.importData(role)));
                app.UI.(['Import_' role]) = b;
                app.UI.(['Path_' role]) = uilabel(dg,'Text','尚未匯入', ...
                    'WordWrap','on','FontColor',[0.4 0.45 0.52]);
                app.UI.(['Count_' role]) = uilabel(dg,'Text','0 張','FontWeight','bold');
            end
            app.UI.Preview = uiaxes(dg); app.UI.Preview.Layout.Column = [1 3];
            app.emptyAxes(app.UI.Preview,'匯入資料後顯示影像預覽');
            app.UI.Log = uitextarea(dg,'Editable','off','FontSize',12);
            app.UI.Log.Layout.Column = [1 3];
            calTab = uitab(tabs,'Title','02  門檻與評估');
            cg = uigridlayout(calTab,[6 3], ...
                'RowHeight',{38,36,44,'1x',46,'1x'}, ...
                'ColumnWidth',{'1x','1x','1x'},'Padding',[18 16 18 16]);
            t = uilabel(cg,'Text','使用校準集選門檻，使用測試集評估表現。', ...
                'FontSize',18,'FontWeight','bold'); t.Layout.Column = [1 3];
            uilabel(cg,'Text','正常類別（依資料夾標籤）');
            app.UI.NormalClass = uidropdown(cg,'Items',{'請先匯入校準資料'}, ...
                'ValueChangedFcn',@(~,~) app.refresh());
            app.UI.Calibrate = uibutton(cg,'Text','自動校準門檻', ...
                'ButtonPushedFcn',@(~,~) app.run(@() app.calibrate()));
            uilabel(cg,'Text','異常門檻 · 分數 ≥ 門檻判為異常');
            app.UI.Threshold = uieditfield(cg,'numeric','Value',0,'Limits',[0 realmax], ...
                'ValueChangedFcn',@(~,~) app.run(@() app.setThreshold()));
            app.UI.Evaluate = uibutton(cg,'Text','評估獨立測試集', ...
                'ButtonPushedFcn',@(~,~) app.run(@() app.evaluate()));
            app.UI.Histogram = uiaxes(cg); app.UI.Histogram.Layout.Column = [1 3];
            app.emptyAxes(app.UI.Histogram,'校準與測試分數分布');
            app.UI.Metrics = uilabel(cg,'Text','尚無測試結果', ...
                'FontWeight','bold','FontSize',14); app.UI.Metrics.Layout.Column = [1 2];
            app.UI.Export = uibutton(cg,'Text','匯出測試 CSV', ...
                'ButtonPushedFcn',@(~,~) app.run(@() app.exportResults()));
            app.UI.Results = uitable(cg,'ColumnName',{'影像路徑','實際異常','異常分數','預測異常'}, ...
                'ColumnEditable',false,'RowName',{});
            app.UI.Results.Layout.Column = [1 3];
            inspectTab = uitab(tabs,'Title','03  影像檢測');
            ig = uigridlayout(inspectTab,[5 2], ...
                'RowHeight',{38,38,'1x',44,42},'Padding',[18 16 18 16]);
            t = uilabel(ig,'Text','查看原始影像與異常熱區','FontSize',18,'FontWeight','bold');
            t.Layout.Column = [1 2];
            app.UI.OpenImage = uibutton(ig,'Text','載入檢測影像', ...
                'ButtonPushedFcn',@(~,~) app.run(@() app.openImage()));
            app.UI.Detect = uibutton(ig,'Text','執行異常檢測', ...
                'FontWeight','bold','ButtonPushedFcn',@(~,~) app.run(@() app.detect()));
            app.UI.Original = uiaxes(ig); app.emptyAxes(app.UI.Original,'原始影像');
            app.UI.Overlay = uiaxes(ig); app.emptyAxes(app.UI.Overlay,'異常熱圖');
            app.UI.Verdict = uilabel(ig,'Text','等待檢測影像', ...
                'FontWeight','bold','FontSize',18); app.UI.Verdict.Layout.Column = [1 2];
            uilabel(ig,'Text','熱圖透明度（每張影像各自正規化）');
            app.UI.Blend = uislider(ig,'Limits',[0 1],'Value',0.45, ...
                'MajorTicks',[0 0.25 0.5 0.75 1],'MinorTicks',[], ...
                'ValueChangedFcn',@(~,~) app.renderInspection());
            app.UI.Footer = uilabel(root,'Text','就緒','FontColor',[0.38 0.43 0.5]);
            app.UIFigure.Visible = 'on';
        end
        function closeApp(app)
            if app.Busy
                uialert(app.UIFigure,'請等待目前工作完成；批次預測可在進度視窗取消。','工作進行中');
                return
            end
            delete(app);
        end
        function run(app,action)
            if app.Busy, return; end
            app.Busy = true; app.refresh();
            cleanup = onCleanup(@() app.finish());
            try
                action();
            catch err
                app.log(['失敗：' err.message]);
                if strcmp(app.UIFigure.Visible,'on')
                    uialert(app.UIFigure,err.message,'無法完成操作','Interpreter','none');
                else
                    rethrow(err);
                end
            end
        end
        function finish(app)
            app.Busy = false; app.refresh();
        end
        function refresh(app)
            hasModel = ~isempty(app.Model);
            fcdd = startsWith(app.UI.ModelChoice.Value,'FCDD');
            patch = startsWith(app.UI.ModelChoice.Value,'PatchCore');
            app.UI.ModelHint.Text = '僅使用正常影像訓練；異常影像保留作評估。';
            if fcdd, app.UI.ModelHint.Text = 'FCDD 使用正常與異常影像共同訓練。'; end
            fields = fieldnames(app.UI);
            for k = 1:numel(fields)
                h = app.UI.(fields{k});
                if isprop(h,'Enable'), h.Enable = app.enabled(true); end
            end
            app.UI.Train.Enable = app.enabled(~isempty(app.Data.normal) && (~fcdd || ~isempty(app.Data.anomaly)));
            app.UI.Save.Enable = app.enabled(hasModel);
            app.UI.Threshold.Enable = app.enabled(hasModel);
            selected = ~isempty(app.Data.calibration) && ...
                ismember(string(app.UI.NormalClass.Value),string(categories(app.Data.calibration.Labels)));
            app.UI.Calibrate.Enable = app.enabled(hasModel && selected);
            app.UI.Evaluate.Enable = app.enabled(hasModel && app.Calibrated && ~isempty(app.Data.test) && strlength(app.NormalLabel)>0);
            app.UI.Detect.Enable = app.enabled(hasModel && ~isempty(app.InputImage));
            app.UI.Export.Enable = app.enabled(~isempty(app.Results));
            app.UI.Epochs.Enable = app.enabled(~patch);
            app.UI.Batch.Enable = app.enabled(true);
            app.UI.Rate.Enable = app.enabled(~patch);
            if hasModel, app.UI.ModelStatus.Text = char(app.ModelName); end
            if app.Busy
                app.UI.ReadyStatus.Text = '處理中…';
            elseif app.Calibrated
                app.UI.ReadyStatus.Text = '門檻已設定';
            elseif hasModel
                app.UI.ReadyStatus.Text = '請校準門檻';
            else
                app.UI.ReadyStatus.Text = '等待模型';
            end
        end
        function state = enabled(app,condition)
            state = 'off';
            if condition && ~app.Busy, state = 'on'; end
        end
        function log(app,message)
            app.LogLines{end+1} = [char(datetime('now','Format','HH:mm:ss')) '  ' char(message)];
            app.LogLines = app.LogLines(max(1,end-79):end);
            app.UI.Log.Value = app.LogLines;
            app.UI.Footer.Text = char(message);
        end
        function importData(app,role)
            folder = uigetdir(pwd,'選擇影像資料夾');
            if isequal(folder,0), return; end
            app.acceptData(role,folder);
        end
        function acceptData(app,role,folder)
            ds = imageDatastore(folder,'IncludeSubfolders',true,'LabelSource','foldernames');
            assert(~isempty(ds.Files),'資料夾沒有支援的影像。');
            % Reject overlap before replacing any active dataset.
            roles = fieldnames(app.Data);
            for k = 1:numel(roles)
                other = app.Data.(roles{k});
                if ~strcmp(role,roles{k}) && ~isempty(other)
                    assert(isempty(intersect(lower(string(ds.Files)),lower(string(other.Files)))), ...
                        'VIStudio:OverlappingData','資料與 %s 集重疊。訓練、校準、測試需使用不同影像。',roles{k});
                end
            end
            preview = VIStudioAnomalyApp.readImage(ds.Files{1},[224 224]);
            if strcmp(role,'calibration') || strcmp(role,'test')
                assert(numel(categories(ds.Labels)) >= 2, ...
                    'VIStudio:MissingClasses','校準與測試資料需至少兩個類別子資料夾，例如 good / defect。');
            end
            app.Data.(role) = ds;
            app.UI.(['Path_' role]).Text = folder;
            app.UI.(['Count_' role]).Text = sprintf('%d 張',numel(ds.Files));
            imshow(preview,'Parent',app.UI.Preview); title(app.UI.Preview,'最近匯入的影像');
            if strcmp(role,'calibration')
                app.UI.NormalClass.Items = [{'請選擇正常類別'}; categories(ds.Labels)];
                app.UI.NormalClass.Value = '請選擇正常類別';
            end
            if strcmp(role,'test'), app.clearResults(); end
            app.log(sprintf('已匯入 %s：%d 張影像。',role,numel(ds.Files)));
        end
        function ds = prepared(app,role)
            ds = imageDatastore(app.Data.(role).Files);
            target = app.ImageSize;
            ds.ReadFcn = @(file) VIStudioAnomalyApp.readImage(file,target);
        end
        function train(app)
            choice = string(app.UI.ModelChoice.Value);
            fcdd = startsWith(choice,'FCDD');
            patch = startsWith(choice,'PatchCore');
            assert(numel(app.Data.normal.Files)>=2,'請至少匯入兩張正常訓練影像。');
            targetSize = [app.UI.Size.Value app.UI.Size.Value];
            % Prepare locally so a failed retrain preserves the active model.
            normal = imageDatastore(app.Data.normal.Files,'ReadFcn', ...
                @(file) VIStudioAnomalyApp.readImage(file,targetSize));
            p = uiprogressdlg(app.UIFigure,'Title','訓練模型', ...
                'Message','正在訓練；首次使用可能需要下載預訓練權重。','Indeterminate','on');
            cleanup = onCleanup(@() delete(p));
            app.log('開始訓練 '+choice+'。'); drawnow;
            if patch
                app.require('patchCoreAnomalyDetector');
                backbone = "resnet18";
                if contains(choice,'50'), backbone = "resnet50"; end
                candidate = patchCoreAnomalyDetector('Backbone',backbone);
                candidate = trainPatchCoreAnomalyDetector(normal,candidate, ...
                    'CompressionRatio',0.1,'MiniBatchSize',app.UI.Batch.Value, ...
                    'ExecutionEnvironment',app.UI.Environment.Value);
            else
                opts = trainingOptions('adam','MaxEpochs',app.UI.Epochs.Value, ...
                    'MiniBatchSize',app.UI.Batch.Value,'InitialLearnRate',app.UI.Rate.Value, ...
                    'ExecutionEnvironment',app.UI.Environment.Value,'Verbose',false, ...
                    'Plots','none','Shuffle','every-epoch');
                if fcdd
                    app.require('fcddAnomalyDetector');
                    abnormal = imageDatastore(app.Data.anomaly.Files,'ReadFcn', ...
                        @(file) VIStudioAnomalyApp.readImage(file,targetSize));
                    backbone = pretrainedEncoderNetwork("resnet18",3);
                    candidate = fcddAnomalyDetector(backbone);
                    candidate = trainFCDDAnomalyDetector(normal,abnormal,candidate,opts);
                else
                    app.require('efficientADAnomalyDetector');
                    network = "pdn-small";
                    if contains(choice,'Medium'), network = "pdn-medium"; end
                    candidate = efficientADAnomalyDetector('Network',network);
                    candidate = trainEfficientADAnomalyDetector(normal,candidate,opts);
                end
            end
            app.Model = candidate; app.ModelName = choice; app.ImageSize = targetSize;
            app.Calibrated = false; app.NormalLabel = "";
            app.UI.Threshold.Value = 0;
            app.clearResults(); app.clearInspection();
            app.log('訓練完成。請使用獨立校準資料設定門檻。');
        end
        function scores = predictDataset(app,role)
            ds = app.prepared(role);
            scores = zeros(numel(ds.Files),1);
            p = uiprogressdlg(app.UIFigure,'Title','預測影像', ...
                'Message','處理中…','Cancelable','on');
            cleanup = onCleanup(@() delete(p));
            for k = 1:numel(ds.Files)
                drawnow;
                assert(~p.CancelRequested,'已取消預測；既有結果保留。');
                score = double(predict(app.Model,readimage(ds,k), ...
                    'ExecutionEnvironment',app.UI.Environment.Value));
                validateattributes(score,{'numeric'},{'scalar','real','finite','nonnegative'});
                scores(k) = score;
                p.Value = k/numel(ds.Files);
                p.Message = sprintf('%d / %d',k,numel(ds.Files));
            end
        end
        function calibrate(app)
            normal = string(app.UI.NormalClass.Value);
            labels = string(app.Data.calibration.Labels);
            assert(any(labels==normal) && any(labels~=normal),'請選擇校準資料中的正常類別。');
            scores = app.predictDataset('calibration');
            app.require('anomalyThreshold');
            threshold = anomalyThreshold(labels~=normal,scores,true);
            app.Model.Threshold = threshold;
            app.UI.Threshold.Value = threshold;
            app.Calibrated = true; app.NormalLabel = normal;
            app.clearResults();
            app.drawHistogram(scores,labels~=normal,'校準集分數分布');
            app.renderInspection();
            app.log(sprintf('校準完成：正常類別 %s，門檻 %.6g。',normal,threshold));
        end
        function setThreshold(app)
            app.Model.Threshold = app.UI.Threshold.Value;
            app.Calibrated = true;
            if ~isempty(app.Data.calibration) && ismember(string(app.UI.NormalClass.Value), ...
                    string(categories(app.Data.calibration.Labels)))
                selected = string(app.UI.NormalClass.Value);
                if selected ~= app.NormalLabel, app.clearResults(); end
                app.NormalLabel = selected;
            end
            if ~isempty(app.Scores)
                app.updateResults();
                app.drawHistogram(app.Scores,app.Targets,'獨立測試集分數分布');
            end
            app.renderInspection();
            app.log(sprintf('已手動設定門檻 %.6g。',app.UI.Threshold.Value));
        end
        function evaluate(app)
            labels = string(app.Data.test.Labels);
            assert(any(labels==app.NormalLabel) && any(labels~=app.NormalLabel), ...
                '測試資料需包含正常類別 %s 與至少一種異常類別。',app.NormalLabel);
            scores = app.predictDataset('test');
            app.Scores = scores; app.Targets = labels~=app.NormalLabel;
            app.updateResults();
            app.drawHistogram(scores,app.Targets,'獨立測試集分數分布');
            app.log(sprintf('已評估 %d 張獨立測試影像。',numel(scores)));
        end
        function updateResults(app)
            predicted = app.Scores >= app.UI.Threshold.Value;
            app.Results = table(string(app.Data.test.Files),app.Targets,app.Scores,predicted, ...
                'VariableNames',{'File','ActualAnomaly','Score','PredictedAnomaly'});
            app.UI.Results.Data = app.Results;
            m = VIStudioAnomalyApp.metrics(app.Targets,predicted);
            app.UI.Metrics.Text = sprintf('準確率 %.1f%%  ·  精確率 %.1f%%  ·  召回率 %.1f%%  ·  F1 %.3f', ...
                100*m.Accuracy,100*m.Precision,100*m.Recall,m.F1);
            app.UI.Metrics.Tooltip = sprintf('TN %d | FP %d | FN %d | TP %d',m.TN,m.FP,m.FN,m.TP);
        end
        function drawHistogram(app,scores,targets,caption)
            ax = app.UI.Histogram; cla(ax); hold(ax,'on');
            [~,edges] = histcounts(scores,20);
            histogram(ax,scores(~targets),edges,'FaceColor',[0.08 0.65 0.52],'DisplayName','正常');
            histogram(ax,scores(targets),edges,'FaceColor',[0.94 0.38 0.30],'DisplayName','異常');
            xline(ax,app.UI.Threshold.Value,'--','門檻','LineWidth',1.5,'DisplayName','門檻');
            hold(ax,'off'); legend(ax,'show'); title(ax,caption);
            ax.XTickMode = 'auto'; ax.YTickMode = 'auto'; ax.YGrid = 'on';
            xlabel(ax,'異常分數'); ylabel(ax,'影像數');
        end
        function clearResults(app)
            app.Results = table(); app.Scores = []; app.Targets = [];
            app.UI.Results.Data = []; app.UI.Metrics.Text = '尚無測試結果';
            cla(app.UI.Histogram); app.emptyAxes(app.UI.Histogram,'校準與測試分數分布');
        end
        function openImage(app)
            [file,folder] = uigetfile({'*.png;*.jpg;*.jpeg;*.bmp;*.tif;*.tiff','影像檔案'});
            if isequal(file,0), return; end
            app.acceptImage(fullfile(folder,file));
        end
        function acceptImage(app,file)
            image = VIStudioAnomalyApp.readImage(file,[]);
            app.InputImage = image;
            app.clearInspection();
            [~,name,extension] = fileparts(file);
            imshow(image,'Parent',app.UI.Original); title(app.UI.Original,[name extension],'Interpreter','none');
            app.log('已載入影像：'+string(file));
        end
        function clearInspection(app)
            app.ScoreMap = []; app.ImageScore = [];
            cla(app.UI.Overlay); app.emptyAxes(app.UI.Overlay,'異常熱圖');
            app.UI.Verdict.Text = '等待執行檢測';
            app.UI.Verdict.FontColor = [0.35 0.4 0.48];
        end
        function detect(app)
            p = uiprogressdlg(app.UIFigure,'Title','影像檢測','Message','計算異常分數與熱圖…','Indeterminate','on');
            cleanup = onCleanup(@() delete(p));
            image = imresize(app.InputImage,app.ImageSize);
            score = double(predict(app.Model,image,'ExecutionEnvironment',app.UI.Environment.Value));
            map = anomalyMap(app.Model,image,'ExecutionEnvironment',app.UI.Environment.Value);
            validateattributes(score,{'numeric'},{'scalar','real','finite','nonnegative'});
            validateattributes(map,{'numeric'},{'2d','real','finite','nonempty'});
            app.ImageScore = score; app.ScoreMap = map;
            app.renderInspection(); app.log('影像檢測完成。');
        end
        function renderInspection(app)
            if isempty(app.ScoreMap), return; end
            image = app.InputImage;
            map = imresize(rescale(app.ScoreMap),[size(image,1),size(image,2)]);
            colors = ind2rgb(uint8(255*map),turbo(256));
            alpha = app.UI.Blend.Value;
            overlay = (1-alpha)*im2double(image)+alpha*colors;
            imshow(overlay,'Parent',app.UI.Overlay); title(app.UI.Overlay,'異常熱圖 · 每張影像相對強度');
            if ~app.Calibrated
                app.UI.Verdict.Text = sprintf('分數 %.6g  ·  尚未設定門檻',app.ImageScore);
                return
            end
            verdict = '正常'; color = [0.04 0.55 0.40];
            if app.ImageScore>=app.UI.Threshold.Value
                verdict = '異常'; color = [0.85 0.23 0.20];
            end
            app.UI.Verdict.Text = sprintf('%s  ·  分數 %.6g  /  門檻 %.6g',verdict,app.ImageScore,app.UI.Threshold.Value);
            app.UI.Verdict.FontColor = color;
        end
        function saveModel(app)
            [file,folder] = uiputfile('*.mat','儲存已訓練模型','VIStudio_anomaly.mat');
            if isequal(file,0), return; end
            app.writeModel(fullfile(folder,file));
        end
        function writeModel(app,file)
            model = app.Model;
            metadata = struct('Version',1,'ModelName',app.ModelName,'ImageSize',app.ImageSize, ...
                'Calibrated',app.Calibrated,'NormalLabel',app.NormalLabel, ...
                'Threshold',app.UI.Threshold.Value);
            save(file,'model','metadata','-v7.3');
            app.log('模型與前處理設定已儲存。');
        end
        function loadModel(app)
            [file,folder] = uigetfile('*.mat','載入已訓練模型');
            if isequal(file,0), return; end
            app.acceptModel(fullfile(folder,file));
        end
        function acceptModel(app,file)
            loaded = load(file,'model','metadata');
            assert(isfield(loaded,'model'),'MAT 檔必須包含名為 model 的已訓練偵測器。');
            candidate = loaded.model;
            assert(ismember(string(class(candidate)), ...
                ["fcddAnomalyDetector","patchCoreAnomalyDetector","efficientADAnomalyDetector"]), ...
                '不支援此模型類型。請載入 FCDD、PatchCore 或 EfficientAD 偵測器。');
            target = [224 224]; calibrated = false; normal = "";
            threshold = 0; name = string(class(candidate));
            if isfield(loaded,'metadata')
                md = loaded.metadata;
                target = md.ImageSize; calibrated = md.Calibrated;
                normal = string(md.NormalLabel); threshold = md.Threshold; name = string(md.ModelName);
            elseif isprop(candidate,'ImageSize') && ~isempty(candidate.ImageSize)
                target = candidate.ImageSize(1:2);
            end
            validateattributes(target,{'numeric'},{'vector','numel',2,'integer','>=',32,'<=',4096});
            validateattributes(threshold,{'numeric'},{'scalar','real','finite','nonnegative'});
            validateattributes(calibrated,{'logical'},{'scalar'});
            assert(isscalar(normal) && isscalar(name),'模型中繼資料格式不正確。');
            % Probe before committing: reject untrained/incompatible detectors.
            predict(candidate,zeros([target 3],'uint8'),'ExecutionEnvironment','cpu');
            candidate.Threshold = threshold;
            app.Model = candidate; app.ImageSize = target; app.ModelName = name;
            app.NormalLabel = normal; app.Calibrated = calibrated; app.UI.Threshold.Value = threshold;
            app.clearResults(); app.clearInspection();
            app.log('模型已載入：'+string(file));
        end
        function exportResults(app)
            [file,folder] = uiputfile('*.csv','匯出獨立測試結果','VIStudio_results.csv');
            if isequal(file,0), return; end
            results = app.Results;
            results.Threshold = repmat(app.UI.Threshold.Value,height(results),1);
            results.NormalLabel = repmat(app.NormalLabel,height(results),1);
            writetable(results,fullfile(folder,file),'Encoding','UTF-8');
            app.log('測試結果已匯出。');
        end
        function checkEnvironment(app)
            functions = {'imageDatastore','trainingOptions','patchCoreAnomalyDetector', ...
                'fcddAnomalyDetector','efficientADAnomalyDetector','anomalyThreshold'};
            lines = {['MATLAB ' version('-release')]};
            for k = 1:numel(functions)
                state = '可使用';
                if isempty(which(functions{k})), state = '尚未安裝'; end
                lines{end+1} = [functions{k} '：' state]; %#ok<AGROW>
            end
            uialert(app.UIFigure,strjoin(lines,newline),'環境檢查','Icon','info');
        end
    end
    methods (Static)
        function image = readImage(file,targetSize)
            [image,map] = imread(file);
            if ~isempty(map), image = im2uint8(ind2rgb(image,map)); end
            if size(image,3)==1, image = repmat(image,1,1,3); end
            assert(size(image,3)==3,'影像必須是灰階或 RGB 格式：%s',file);
            image = im2uint8(image);
            if ~isempty(targetSize), image = imresize(image,targetSize); end
        end
        function m = metrics(actual,predicted)
            actual = logical(actual(:)); predicted = logical(predicted(:));
            assert(~isempty(actual) && numel(actual)==numel(predicted), ...
                'VIStudio:InvalidLabels','標籤不可為空且長度必須一致。');
            m.TP = sum(actual & predicted); m.TN = sum(~actual & ~predicted);
            m.FP = sum(~actual & predicted); m.FN = sum(actual & ~predicted);
            m.Accuracy = (m.TP+m.TN)/numel(actual);
            m.Precision = m.TP/max(1,m.TP+m.FP);
            m.Recall = m.TP/max(1,m.TP+m.FN);
            m.F1 = 2*m.TP/max(1,2*m.TP+m.FP+m.FN);
        end
    end
    methods (Static, Access = private)
        function emptyAxes(ax,caption)
            title(ax,caption); ax.XTick = []; ax.YTick = []; ax.Box = 'on';
            ax.Toolbar.Visible = 'off';
        end
        function require(name)
            assert(~isempty(which(name)), ...
                '找不到 %s。R2024b–R2026a 請安裝 Automated Visual Inspection Library；R2026b 請安裝 Visual Inspection Toolbox。',name);
        end
    end
end
