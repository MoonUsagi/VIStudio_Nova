classdef VIStudioSemanticPaneV18 < handle
    properties (SetAccess=private)
        Handles=struct()
        Data=table()
        Classes=table()
        Artifact=[]
        Evaluation=[]
        Prediction=[]
        Comparison=[]
        Run
        Controls=struct()
    end
    properties (Access=private)
        Callbacks
        Labeler=[]
        Busy=false
        OptionsBase=VIStudioSemanticV13.defaults()
        CompareB=[]
    end
    methods
        function pane=VIStudioSemanticPaneV18(parent,callbacks)
            pane.Callbacks=callbacks; pane.Handles.Tabs=uitabgroup(parent); page=uitab(pane.Handles.Tabs,'Title','資料與訓練 / Data & Training'); grid=uigridlayout(page,[5 1],'RowHeight',{38,64,225,40,'1x'});
            bar=uigridlayout(grid,[1 5],'Padding',[0 0 0 0]);
            uibutton(bar,'Text','開啟標記工具 / Labeler','ButtonPushedFcn',@(~,~) pane.openLabeler());
            uibutton(bar,'Text','載入資料 MAT / Dataset','ButtonPushedFcn',@(~,~) pane.action(@() pane.pickData())); pane.Handles.Split=uidropdown(bar,'Items',{'train','validation','test','calibration'});
            uibutton(bar,'Text','指定用途 / Assign split','ButtonPushedFcn',@(~,~) pane.action(@() pane.assignSplit())); uibutton(bar,'Text','載入模型 MAT / Model','ButtonPushedFcn',@(~,~) pane.action(@() pane.pickModel()));
            bar=uigridlayout(grid,[2 4],'RowHeight',{22,34},'RowSpacing',4,'Padding',[0 0 0 0]); labels={'模型 / Architecture','環境 / Environment','損失 / Loss','外部模型 / Warm-start'};
            for k=1:4, h=uilabel(bar,'Text',labels{k}); h.Layout.Row=1; h.Layout.Column=k; end
            pane.Controls.Architecture=uidropdown(bar,'Items',{'U-Net','DeepLab v3+ / ResNet-18','BiSeNet v2 (from scratch)'},'ItemsData',{'unet','deeplab-resnet18','bisenetv2'},'ValueChangedFcn',@(~,~) pane.architectureChanged()); pane.Controls.Environment=uidropdown(bar,'Items',{'cpu','gpu','auto'}); pane.Controls.Loss=uidropdown(bar,'Items',{'crossentropy','dice'}); pane.Controls.WarmStart=uicheckbox(bar,'Text','沿用載入模型 / Use loaded model');
            fields={'Architecture','Environment','Loss','WarmStart'}; for k=1:4, pane.Controls.(fields{k}).Layout.Row=2; pane.Controls.(fields{k}).Layout.Column=k; end
            tabs=uitabgroup(grid); pane.Handles.ParameterTabs=tabs; page=uitab(tabs,'Title','模型參數 / Model'); params=uigridlayout(page,[2 7],'RowHeight',{24,34},'Padding',[6 8 6 8]); specs={'Size','Epochs','Batch','LearnRate','EncoderDepth','Filters','AugmentCopies'}; defaults=VIStudioSemanticV13.defaults();
            for k=1:numel(specs), f=specs{k}; label=uilabel(params,'Text',f); label.Layout.Row=1; label.Layout.Column=k; field=uieditfield(params,'numeric','Value',defaults.(f)); field.Layout.Row=2; field.Layout.Column=k; pane.Controls.(f)=field; end
            page=uitab(tabs,'Title','切塊與權重 / Tiles & Weights'); g=uigridlayout(page,[2 1],'RowHeight',{64,'1x'}); bar=uigridlayout(g,[2 4],'RowHeight',{22,34},'RowSpacing',4,'Padding',[0 0 0 0]); labels={'影像方式 / Data mode','重疊比例 / Overlap','類別權重 / Weights','自動權重上限 / Cap'};
            for k=1:4, label=uilabel(bar,'Text',labels{k}); label.Layout.Row=1; label.Layout.Column=k; end
            pane.Controls.DataMode=uidropdown(bar,'Items',{'整張縮放 / Resize','原尺寸切塊 / Tiles'},'ItemsData',{'resize','tiles'}); pane.Controls.TileOverlap=uieditfield(bar,'numeric','Value',.25,'Limits',[0 .75]); pane.Controls.WeightMode=uidropdown(bar,'Items',{'不加權 / None','逆頻率 / Inverse frequency','手動 / Manual'},'ItemsData',{'none','inverse-frequency','manual'},'ValueChangedFcn',@(~,~) pane.action(@() pane.refreshWeights())); pane.Controls.WeightCap=uieditfield(bar,'numeric','Value',20,'Limits',[1 realmax],'ValueChangedFcn',@(~,~) pane.action(@() pane.refreshWeights()));
            fields={'DataMode','TileOverlap','WeightMode','WeightCap'}; for k=1:4, pane.Controls.(fields{k}).Layout.Row=2; pane.Controls.(fields{k}).Layout.Column=k; end
            pane.Handles.Weights=uitable(g,'ColumnEditable',[false false false true]);
            page=uitab(tabs,'Title','最佳化 / Optimization'); params=uigridlayout(page,[2 6],'RowHeight',{24,34}); specs={'Seed','Solver','Schedule','DropFactor','DropPeriod','L2'};
            for k=1:6
                f=specs{k}; label=uilabel(params,'Text',f); label.Layout.Row=1; label.Layout.Column=k;
                if strcmp(f,'Solver'), field=uidropdown(params,'Items',{'adam','sgdm','rmsprop'}); elseif strcmp(f,'Schedule'), field=uidropdown(params,'Items',{'none','piecewise'}); else, field=uieditfield(params,'numeric','Value',defaults.(f)); end
                field.Layout.Row=2; field.Layout.Column=k; pane.Controls.(f)=field;
            end
            bar=uigridlayout(grid,[1 4],'Padding',[0 0 0 0]); uibutton(bar,'Text','檢查模型 / Check model','ButtonPushedFcn',@(~,~) pane.action(@() pane.verifyModel())); uibutton(bar,'Text','訓練所選模型 / Train selected','ButtonPushedFcn',@(~,~) pane.action(@() pane.pickTrain())); uibutton(bar,'Text','另存用途與參數 / Save setup','ButtonPushedFcn',@(~,~) pane.action(@() pane.saveDataset())); pane.Handles.Status=uilabel(bar,'Text','先分配原圖用途，再切塊 / Assign source roles before tiling','WordWrap','on'); pane.Handles.Data=uitable(grid,'SelectionType','row');
            page=uitab(pane.Handles.Tabs,'Title','推論 / Inspect'); grid=uigridlayout(page,[3 2],'RowHeight',{38,'1x',120}); bar=uigridlayout(grid,[1 2],'Padding',[0 0 0 0]); bar.Layout.Column=[1 2];
            uibutton(bar,'Text','載入影像推論 / Inspect image','ButtonPushedFcn',@(~,~) pane.action(@() pane.pickImage())); uibutton(bar,'Text','匯出類別圖 / Export labels','ButtonPushedFcn',@(~,~) pane.action(@() pane.exportPrediction()));
            pane.Handles.Raw=uiaxes(grid); pane.Handles.Overlay=uiaxes(grid); pane.Handles.Counts=uitable(grid); pane.Handles.Counts.Layout.Column=[1 2];
            page=uitab(pane.Handles.Tabs,'Title','評估 / Evaluate'); grid=uigridlayout(page,[5 1],'RowHeight',{38,45,'1x','1x',100}); bar=uigridlayout(grid,[1 2],'Padding',[0 0 0 0]);
            uibutton(bar,'Text','評估保留集 / Evaluate','ButtonPushedFcn',@(~,~) pane.action(@() pane.evaluate())); uibutton(bar,'Text','匯出報告 / Export','ButtonPushedFcn',@(~,~) pane.action(@() pane.exportEvaluation())); pane.Handles.Summary=uilabel(grid,'Text','test 優先，無 test 時用 validation / Prefer test, otherwise validation','WordWrap','on'); pane.Handles.Metrics=uitable(grid); pane.Handles.Confusion=uitable(grid); pane.Handles.Images=uitable(grid);
            page=uitab(pane.Handles.Tabs,'Title','模型比較 / Compare'); grid=uigridlayout(page,[4 1],'RowHeight',{38,45,100,'1x'}); bar=uigridlayout(grid,[1 3],'Padding',[0 0 0 0]);
            uibutton(bar,'Text','載入模型 B / Load B','ButtonPushedFcn',@(~,~) pane.action(@() pane.pickCompareB())); uibutton(bar,'Text','相同保留集比較 / Compare heldout','ButtonPushedFcn',@(~,~) pane.action(@() pane.compareModels())); uibutton(bar,'Text','匯出比較 / Export comparison','ButtonPushedFcn',@(~,~) pane.action(@() pane.exportComparison()));
            pane.Handles.CompareStatus=uilabel(grid,'Text','A 使用目前模型；B 另行載入 / A is the active model; load B separately','WordWrap','on'); pane.Handles.CompareSummary=uitable(grid); pane.Handles.CompareClasses=uitable(grid);
            page=uitab(pane.Handles.Tabs,'Title','訓練紀錄 / Monitor'); pane.Run=VIStudioTrainingRunV9(page);
        end
        function delete(pane), if ~isempty(pane.Labeler) && isvalid(pane.Labeler), delete(pane.Labeler); end, end
        function loadDataset(pane,file)
            names=who('-file',char(file)); if ismember('configuration',names), pane.loadSetup(file); return; end
            [data,classes]=VIStudioSemanticV13.read(file); pane.Data=data; pane.Classes=classes; pane.Handles.Data.Data=data; pane.clearEvaluation(); pane.refreshWeights(); if ismember('trainingOptions',names), loaded=load(file,'trainingOptions'); pane.setOptions(loaded.trainingOptions); end
        end
        function saveSetup(pane,file)
            assert(~isfile(file),'VIStudioV15:FileExists','Choose a new setup filename.');
            if ~isempty(pane.Data), VIStudioSemanticV13.validate(pane.Data,pane.Classes); end
            configuration=struct('Version',13,'Options',pane.options(),'Manifest',pane.Data,'Classes',pane.Classes); save(file,'configuration','-v7.3');
        end
        function loadSetup(pane,file)
            loaded=load(file,'configuration'); assert(isfield(loaded,'configuration') && isstruct(loaded.configuration) && all(isfield(loaded.configuration,{'Version','Options','Manifest','Classes'})) && loaded.configuration.Version==13,'VIStudioV15:Setup','Invalid V18 setup.'); c=loaded.configuration;
            VIStudioSemanticV13.options(c.Options); if ~isempty(c.Manifest), VIStudioSemanticV13.validate(c.Manifest,c.Classes); end
            pane.Data=c.Manifest; pane.Classes=c.Classes; pane.Handles.Data.Data=c.Manifest; pane.clearEvaluation(); pane.Handles.Weights.Data=table(); pane.setOptions(c.Options); pane.Handles.Status.Text='已載入設定，模型尚未檢查 / Setup loaded; model not checked';
        end
        function setSplit(pane,rows,role)
            role=string(validatestring(role,{'train','validation','test','calibration'})); candidate=pane.Data; candidate.Split(rows)=role; VIStudioSemanticV13.validate(candidate,pane.Classes); pane.Data=candidate; pane.Handles.Data.Data=candidate; pane.clearEvaluation(); pane.refreshWeights();
        end
        function setOptions(pane,options)
            o=VIStudioSemanticV13.options(options); pane.OptionsBase=o; for f=fieldnames(o)', if isfield(pane.Controls,f{1}), pane.Controls.(f{1}).Value=o.(f{1}); end, end;
            if o.WeightMode=="manual" && ~isempty(o.ClassWeights) && ~isempty(pane.Data), stats=VIStudioSemanticTilesV13.weights(pane.Data,pane.Classes,o); pane.Handles.Weights.Data=stats; end
            pane.refreshWeights(); pane.architectureChanged();
        end
        function o=options(pane)
            o=pane.OptionsBase; for f=fieldnames(o)', if isfield(pane.Controls,f{1}), o.(f{1})=pane.Controls.(f{1}).Value; end, end
            if string(o.WeightMode)=="manual" && istable(pane.Handles.Weights.Data) && ~isempty(pane.Handles.Weights.Data), o.ClassWeights=pane.Handles.Weights.Data.Weight; end
            o=VIStudioSemanticV13.options(o);
        end
        function status=verifyModel(pane)
            o=pane.options(); classes=2; if ~isempty(pane.Classes), classes=height(pane.Classes); end
            before=rng; cleanup=onCleanup(@() rng(before));
            try
                model=VIStudioSemanticV13.buildModel(o,classes); input=getLayer(model,model.InputNames{1}).InputSize; minibatchpredict(model,zeros([input 1],'single'),'ExecutionEnvironment','cpu');
                status=struct('Available',true,'Architecture',o.Architecture,'Layers',numel(model.Layers),'Message',"Build and CPU forward verified; training and accuracy are separate"); pane.Handles.Status.Text='可建立與前向 / Build + forward OK';
            catch err
                status=struct('Available',false,'Architecture',o.Architecture,'Layers',0,'Message',string(err.message)); pane.Handles.Status.Text="無法執行，設定仍可保存 / Unavailable; setup can be saved · "+string(err.message);
            end
        end
        function setCompareModel(pane,file), pane.CompareB=VIStudioSemanticV13.load(file); pane.Comparison=[]; pane.Handles.CompareStatus.Text=pane.CompareB.File; end
        function comparison=compareModels(pane)
            assert(~isempty(pane.Artifact) && ~isempty(pane.CompareB),'VIStudioV15:CompareModels','Load model A and B.'); rows=pane.Data.Split=="test"; if ~any(rows), rows=pane.Data.Split=="validation"; end; assert(any(rows),'VIStudioV15:SemanticEvaluationSplit','Reserve validation or test images.');
            a=VIStudioSemanticV13.evaluate(pane.Artifact,pane.Data(rows,:),pane.Classes); b=VIStudioSemanticV13.evaluate(pane.CompareB,pane.Data(rows,:),pane.Classes);
            summary=table(["A";"B"],[pane.Artifact.File;pane.CompareB.File],[a.Summary.MeanIoU;b.Summary.MeanIoU],[a.Summary.ForegroundIoU;b.Summary.ForegroundIoU],[a.Summary.MeanDice;b.Summary.MeanDice],[mean(a.Images.Milliseconds);mean(b.Images.Milliseconds)],'VariableNames',{'Model','File','MeanIoU','ForegroundIoU','MeanDice','MeanMilliseconds'});
            delta=table(a.PerClass.Class,a.PerClass.IoU,b.PerClass.IoU,b.PerClass.IoU-a.PerClass.IoU,a.PerClass.Dice,b.PerClass.Dice,'VariableNames',{'Class','A_IoU','B_IoU','DeltaIoU','A_Dice','B_Dice'});
            comparison=struct('A',a,'B',b,'Summary',summary,'PerClass',delta); pane.Comparison=comparison; pane.Handles.CompareSummary.Data=summary; pane.Handles.CompareClasses.Data=delta; pane.Handles.CompareStatus.Text='相同原圖與真值；各自沿用模型推論方式 / Same sources/truth; each model uses its saved inference settings';
        end
        function loadModel(pane,file)
            artifact=VIStudioSemanticV13.load(file); pane.Artifact=artifact; pane.Handles.Status.Text=artifact.File; pane.Prediction=[]; pane.clearEvaluation(); pane.Handles.Counts.Data=table(); cla(pane.Handles.Raw); cla(pane.Handles.Overlay);
        end
        function train(pane,folder)
            external=[]; if pane.Controls.WarmStart.Value, external=pane.Artifact; assert(~isempty(external),'VIStudioV15:SemanticModel','Load an external semantic model first.'); end
            VIStudioSemanticV13.train(pane.Data,pane.Classes,pane.options(),folder,external,pane.Run); pane.loadModel(fullfile(folder,'model.mat')); pane.Evaluation=[];
        end
        function p=inspect(pane,file)
            assert(~isempty(pane.Artifact),'VIStudioV15:SemanticModel','Load or train a model.'); image=VIStudioData.readImage(file,[]); p=VIStudioSemanticV13.predict(pane.Artifact,image); pane.Prediction=p;
            imshow(image,'Parent',pane.Handles.Raw); imshow(VIStudioSemanticV13.overlay(image,p),'Parent',pane.Handles.Overlay); pixels=zeros(height(p.Classes),1); for k=1:numel(pixels), pixels(k)=nnz(p.Labels==p.Classes.ID(k)); end
            pane.Handles.Counts.Data=table(p.Classes.Name,pixels,100*pixels/numel(p.Labels),'VariableNames',{'Class','Pixels','Percent'});
        end
        function e=evaluate(pane)
            assert(~isempty(pane.Artifact),'VIStudioV15:SemanticModel','Load or train a model.'); rows=pane.Data.Split=="test"; if ~any(rows), rows=pane.Data.Split=="validation"; end; assert(any(rows),'VIStudioV15:SemanticEvaluationSplit','Reserve test or validation rows.');
            e=VIStudioSemanticV13.evaluate(pane.Artifact,pane.Data(rows,:),pane.Classes); pane.Evaluation=e; pane.Handles.Metrics.Data=e.PerClass; pane.Handles.Confusion.Data=e.Confusion; pane.Handles.Confusion.RowName=cellstr(pane.Classes.Name); pane.Handles.Confusion.ColumnName=cellstr(pane.Classes.Name); pane.Handles.Images.Data=e.Images; pane.Handles.Summary.Text=string(jsonencode(e.Summary));
        end
    end
    methods (Access=private)
        function clearEvaluation(pane)
            pane.Comparison=[]; pane.Handles.CompareSummary.Data=table(); pane.Handles.CompareClasses.Data=table();
            pane.Evaluation=[]; pane.Handles.Metrics.Data=table(); pane.Handles.Confusion.Data=[]; pane.Handles.Confusion.RowName={}; pane.Handles.Confusion.ColumnName={}; pane.Handles.Images.Data=table(); pane.Handles.Summary.Text='尚未評估 / Not evaluated';
        end
        function architectureChanged(pane)
            architecture=string(pane.Controls.Architecture.Value); minimum=32; if architecture=="deeplab-resnet18", minimum=224; elseif architecture=="bisenetv2", minimum=64; end
            if pane.Controls.Size.Value<minimum, pane.Controls.Size.Value=minimum; end
            state='off'; if architecture=="unet", state='on'; end; pane.Controls.EncoderDepth.Enable=state; pane.Controls.Filters.Enable=state;
        end
        function refreshWeights(pane)
            if isempty(pane.Data), pane.Handles.Weights.Data=table(); return; end; o=pane.OptionsBase; o.WeightMode=string(pane.Controls.WeightMode.Value); o.WeightCap=pane.Controls.WeightCap.Value;
            if o.WeightMode=="manual"
                if istable(pane.Handles.Weights.Data) && height(pane.Handles.Weights.Data)==height(pane.Classes) && isequal(pane.Handles.Weights.Data.Class,string(pane.Classes.Name)), o.ClassWeights=pane.Handles.Weights.Data.Weight;
                elseif isempty(o.ClassWeights), o.ClassWeights=ones(height(pane.Classes),1); end
            end
            try, stats=VIStudioSemanticTilesV13.weights(pane.Data,pane.Classes,o);
            catch err
                if strcmp(err.identifier,'VIStudioV15:MissingWeightClass'), temporary=o; temporary.WeightMode="none"; stats=VIStudioSemanticTilesV13.weights(pane.Data,pane.Classes,temporary); stats.Weight(:)=NaN; pane.Handles.Status.Text='train 尚未涵蓋各類 / Assign train images for every class'; else, rethrow(err); end
            end
            pane.Handles.Weights.Data=stats; pane.Handles.Weights.ColumnEditable=[false false false o.WeightMode=="manual"];
        end
        function pickCompareB(pane), [f,p]=uigetfile('*.mat'); if ~isequal(f,0), pane.setCompareModel(fullfile(p,f)); end, end
        function exportComparison(pane)
            assert(~isempty(pane.Comparison),'VIStudioV15:Comparison','Compare models first.'); parent=uigetdir(pwd); if isequal(parent,0), return; end; folder=tempname(parent); mkdir(folder); comparison=pane.Comparison; save(fullfile(folder,'comparison.mat'),'comparison'); writetable(comparison.Summary,fullfile(folder,'summary.csv'),'Encoding','UTF-8'); writetable(comparison.PerClass,fullfile(folder,'classes.csv'),'Encoding','UTF-8');
        end
        function action(pane,callback)
            if pane.Busy, return; end; pane.Busy=true; pane.Callbacks.Busy(true); cleanup=onCleanup(@() pane.finish());
            try, callback(); catch err, fig=ancestor(pane.Handles.Tabs,'figure'); if strcmp(fig.Visible,'off'), rethrow(err); end; uialert(fig,err.message,'Semantic','Interpreter','none'); end
        end
        function finish(pane), pane.Busy=false; pane.Callbacks.Busy(false); pane.Run.Handles.Stop.Enable='off'; pane.architectureChanged(); end
        function pickData(pane), [f,p]=uigetfile('*.mat'); if ~isequal(f,0), pane.loadDataset(fullfile(p,f)); end, end
        function pickModel(pane), [f,p]=uigetfile('*.mat'); if ~isequal(f,0), pane.loadModel(fullfile(p,f)); end, end
        function pickImage(pane), [f,p]=uigetfile({'*.png;*.jpg;*.bmp;*.tif','Images'}); if ~isequal(f,0), pane.inspect(fullfile(p,f)); end, end
        function assignSplit(pane), rows=pane.Handles.Data.Selection; assert(~isempty(rows),'VIStudioV15:Selection','Select image rows.'); pane.setSplit(rows,pane.Handles.Split.Value); end
        function pickTrain(pane), parent=uigetdir(pwd); if isequal(parent,0), return; end; [~,name]=fileparts(tempname(parent)); pane.train(fullfile(parent,['semantic_run_' name])); end
        function saveDataset(pane)
            [f,p]=uiputfile('*.mat'); if isequal(f,0), return; end; pane.saveSetup(fullfile(p,f));
        end
        function openLabeler(pane), pane.Labeler=VIStudioLabelerV18('on',@(output) pane.receive(output)); pane.Labeler.openAdvanced('semantic'); end
        function receive(pane,output), assert(output.Task=="semantic",'VIStudioV15:SemanticTask','Export a semantic dataset.'); pane.loadDataset(output.Path); end
        function exportPrediction(pane)
            assert(~isempty(pane.Prediction),'VIStudioV15:SemanticPrediction','Inspect an image first.'); [f,p]=uiputfile('*.png'); if isequal(f,0), return; end; file=fullfile(p,f); assert(~isfile(file),'VIStudioV15:FileExists','Choose a new PNG.'); mapFile=[file '.classes.mat']; assert(~isfile(mapFile),'VIStudioV15:FileExists','Class-map sidecar exists.'); classes=pane.Prediction.Classes; imwrite(pane.Prediction.Labels,file); save(mapFile,'classes');
        end
        function exportEvaluation(pane)
            assert(~isempty(pane.Evaluation),'VIStudioV15:SemanticEvaluation','Evaluate a model first.'); parent=uigetdir(pwd); if isequal(parent,0), return; end; folder=tempname(parent); mkdir(folder); evaluation=pane.Evaluation; save(fullfile(folder,'evaluation.mat'),'evaluation'); writetable(evaluation.PerClass,fullfile(folder,'classes.csv')); writetable(evaluation.Images,fullfile(folder,'images.csv')); writematrix(evaluation.Confusion,fullfile(folder,'confusion.csv'));
        end
    end
end
