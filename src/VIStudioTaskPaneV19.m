classdef VIStudioTaskPaneV19 < handle
    properties (SetAccess=private)
        Handles=struct()
        Dataset=[]
        DatasetFile=""
        SourceFile=""
        Artifact=[]
        Result=[]
        Evaluation=[]
        Configuration=VIStudioTaskModelsV15.defaults('instance')
        Run
        Editor=[]
    end
    properties (Access=private)
        Busy=false
    end
    methods
        function app=VIStudioTaskPaneV19(parent,task)
            if nargin<2, task='instance'; end
            grid=uigridlayout(parent,[3 1],'RowHeight',{40,60,'1x'}); app.Handles.Root=grid; bar=uigridlayout(grid,[1 6],'Padding',[0 0 0 0]);
            app.Handles.Task=uidropdown(bar,'Items',{'實例分割 / Instance','關鍵點／肢節 / Keypoints'},'ItemsData',{'instance','keypoints'},'ValueChangedFcn',@(~,~) app.changeTask());
            uibutton(bar,'Text','載入資料 / Dataset','ButtonPushedFcn',@(~,~) app.action(@() app.pickDataset())); uibutton(bar,'Text','載入影像 / Image','ButtonPushedFcn',@(~,~) app.action(@() app.pickImage())); uibutton(bar,'Text','標記工作室 / Labeler','ButtonPushedFcn',@(~,~) app.openEditor(app.Handles.Task.Value)); uibutton(bar,'Text','另存設定 / Save setup','ButtonPushedFcn',@(~,~) app.action(@() app.pickSave())); uibutton(bar,'Text','載入設定 / Load setup','ButtonPushedFcn',@(~,~) app.action(@() app.pickSetup()));
            app.Handles.Status=uilabel(grid,'Text','NOT_CHECKED / 先建立設定與標記資料；模型執行需本機資源','WordWrap','on'); tabs=uitabgroup(grid); app.Handles.Tabs=tabs;
            page=uitab(tabs,'Title','資料與模型 / Data & Model'); g=uigridlayout(page,[5 1],'RowHeight',{64,64,40,40,'1x'}); bar=uigridlayout(g,[2 4],'RowHeight',{22,32},'Padding',[0 0 0 0],'RowSpacing',3);
            labels={'模型 / Model','Epochs','Batch','LearnRate'}; for k=1:4, h=uilabel(bar,'Text',labels{k}); h.Layout.Row=1; h.Layout.Column=k; end
            app.Handles.Model=uidropdown(bar,'Items',{'maskrcnn','solov2'}); app.Handles.Epochs=uieditfield(bar,'numeric','Value',10,'Limits',[1 Inf]); app.Handles.Batch=uieditfield(bar,'numeric','Value',2,'Limits',[1 Inf]); app.Handles.Rate=uieditfield(bar,'numeric','Value',.0001,'Limits',[eps 1]); values={'Model','Epochs','Batch','Rate'}; for k=1:4, app.Handles.(values{k}).Layout.Row=2; app.Handles.(values{k}).Layout.Column=k; end
            bar=uigridlayout(g,[2 4],'RowHeight',{22,32},'Padding',[0 0 0 0],'RowSpacing',3); labels={'環境 / Environment','門檻 / Threshold','影像用途 / Split','點位範本 / Template'}; for k=1:4, h=uilabel(bar,'Text',labels{k}); h.Layout.Row=1; h.Layout.Column=k; end
            app.Handles.Environment=uidropdown(bar,'Items',{'cpu','gpu','auto'}); app.Handles.Threshold=uieditfield(bar,'numeric','Value',.5,'Limits',[0 1]); app.Handles.Split=uidropdown(bar,'Items',{'train','validation','test','calibration'}); app.Handles.Template=uidropdown(bar,'Items',{'industrial','human'}); values={'Environment','Threshold','Split','Template'}; for k=1:4, app.Handles.(values{k}).Layout.Row=2; app.Handles.(values{k}).Layout.Column=k; end
            bar=uigridlayout(g,[1 4],'Padding',[0 0 0 0]); uibutton(bar,'Text','檢查模型資源 / Check resources','ButtonPushedFcn',@(~,~) app.action(@() app.initialize())); uibutton(bar,'Text','載入模型 MAT / Load model','ButtonPushedFcn',@(~,~) app.action(@() app.pickModel())); uibutton(bar,'Text','指定影像用途 / Assign split','ButtonPushedFcn',@(~,~) app.action(@() app.assignSplit())); uibutton(bar,'Text','開始訓練 / Train','ButtonPushedFcn',@(~,~) app.action(@() app.pickTrain()));
            app.Handles.Hint=uilabel(g,'Text','本機新模型尚未驗證；可先完成標記與保存設定 / Models not verified; labeling and setup available','WordWrap','on'); app.Handles.Manifest=uitable(g,'SelectionType','row');
            page=uitab(tabs,'Title','檢測與評估 / Inspect & Evaluate'); g=uigridlayout(page,[5 2],'RowHeight',{38,38,'1x',110,60}); bar=uigridlayout(g,[1 3],'Padding',[0 0 0 0]); bar.Layout.Column=[1 2]; uibutton(bar,'Text','執行檢測 / Infer','ButtonPushedFcn',@(~,~) app.action(@() app.infer())); uibutton(bar,'Text','保留集評估 / Evaluate','ButtonPushedFcn',@(~,~) app.action(@() app.evaluate())); uibutton(bar,'Text','匯出結果 / Export','ButtonPushedFcn',@(~,~) app.action(@() app.exportResults()));
            bar=uigridlayout(g,[1 4],'Padding',[0 0 0 0]); bar.Layout.Column=[1 2]; uibutton(bar,'Text','詳細圖表 / Details','ButtonPushedFcn',@(~,~) app.action(@() app.showEvaluation())); uibutton(bar,'Text','官方 COCO / Official','ButtonPushedFcn',@(~,~) app.action(@() app.officialEvaluation())); uibutton(bar,'Text','匯入預測 / Predictions','ButtonPushedFcn',@(~,~) app.action(@() app.pickPredictions())); uibutton(bar,'Text','Python 環境 / Python','ButtonPushedFcn',@(~,~) app.action(@() app.pickPython()));
            app.Handles.Raw=uiaxes(g); app.Handles.Overlay=uiaxes(g); app.Handles.Results=uitable(g); app.Handles.Results.Layout.Column=[1 2]; app.Handles.EvalNote=uilabel(g,'Text','關鍵點使用提供的物件框，非端到端人體偵測 / Keypoints are conditional on supplied object boxes','WordWrap','on'); app.Handles.EvalNote.Layout.Column=[1 2];
            page=uitab(tabs,'Title','AI 輔助標記 / AI Assist'); g=uigridlayout(page,[3 1],'RowHeight',{100,48,'1x'}); uilabel(g,'Text','SAM 前景／背景點與框提示 → 待覆核遮罩 → 人工確認。未安裝模型時仍可標記與保存設定。 / SAM prompts → candidates → human review.','WordWrap','on'); uibutton(g,'Text','開啟 AI 提示與候選工具 / Open AI labeling','ButtonPushedFcn',@(~,~) app.openEditor('assist')); uilabel(g,'Text','使用原生 SAM 物件或本機 SAM MAT。不以一般閾值結果冒充 AI。 / Native SAM only; unavailable models stay unavailable.','WordWrap','on');
            page=uitab(tabs,'Title','標記品質 / Annotation QA'); g=uigridlayout(page,[3 1],'RowHeight',{100,48,'1x'}); uilabel(g,'Text','檢查疑似重複、微小區域、缺點、零長度連線與類別統計；另可比較兩份人工工作階段。 / Review annotation consistency.','WordWrap','on'); uibutton(g,'Text','開啟標記品質工具 / Open annotation QA','ButtonPushedFcn',@(~,~) app.openEditor('quality')); uilabel(g,'Text','提示不等於錯標；遮擋、重疊與截斷可能合理。報告不會自動修改真值。 / Findings require human review.','WordWrap','on');
            page=uitab(tabs,'Title','訓練紀錄 / Monitor'); app.Run=VIStudioTrainingRunV9(page); if ismember(string(task),["assist","quality"]), app.Handles.Task.Value='instance'; app.changeTask(); children=tabs.Children; index=contains(string({children.Title}),'AI'); if string(task)=="quality", index=contains(string({children.Title}),'品質'); end; tabs.SelectedTab=children(find(index,1)); else, app.Handles.Task.Value=char(task); app.changeTask(); end
        end
        function delete(app), if ~isempty(app.Editor) && isvalid(app.Editor), delete(app.Editor); end, end
        function o=options(app)
            o=app.Configuration; o.Task=string(app.Handles.Task.Value); o.Model=string(app.Handles.Model.Value); o.Epochs=app.Handles.Epochs.Value; o.Batch=app.Handles.Batch.Value; o.LearnRate=app.Handles.Rate.Value; o.Environment=string(app.Handles.Environment.Value); o.Threshold=app.Handles.Threshold.Value; o.DatasetFile=app.DatasetFile; o.Template=VIStudioPoseV15.template(app.Handles.Template.Value); if ~isempty(app.Dataset) && app.Dataset.schema.Task=="keypoints", o.Template=app.Dataset.schema.Template; o.Template.Name="dataset"; end; VIStudioTaskModelsV15.validateSetup(o);
        end
        function loadDataset(app,file)
            dataset=VIStudioStructuredV15.read(file); VIStudioHomeStateV16.remember('dataset',file); app.Dataset=dataset; app.DatasetFile=string(file); app.Handles.Task.Value=char(dataset.schema.Task); app.changeTask(); app.Handles.Manifest.Data=dataset.manifest; app.Result=[]; app.Evaluation=[]; app.setSource(dataset.manifest.File(1));
        end
        function setSource(app,file), image=VIStudioData.readImage(file,[]); app.SourceFile=VIStudioToolsV3.canonicalPath(file); imshow(image,'Parent',app.Handles.Raw); imshow(image,'Parent',app.Handles.Overlay); app.Result=[]; end
        function saveSetup(app,file), o=app.options(); o.Dataset=app.Dataset; VIStudioTaskModelsV15.saveSetup(o,file); VIStudioHomeStateV16.remember('setup',file); end
        function loadSetup(app,file)
            o=VIStudioTaskModelsV15.loadSetup(file); VIStudioHomeStateV16.remember('setup',file); app.Configuration=o; app.Handles.Task.Value=char(o.Task); app.changeTask(); app.Handles.Model.Value=char(o.Model); app.Handles.Epochs.Value=o.Epochs; app.Handles.Batch.Value=o.Batch; app.Handles.Rate.Value=o.LearnRate; app.Handles.Environment.Value=char(o.Environment); app.Handles.Threshold.Value=o.Threshold; if ismember(o.Template.Name,["industrial","human"]), app.Handles.Template.Value=char(o.Template.Name); end
            if isfield(o,'Dataset') && ~isempty(o.Dataset), VIStudioStructuredV15.assertUnchanged(o.Dataset); app.Dataset=o.Dataset; app.DatasetFile=o.DatasetFile; app.Handles.Manifest.Data=o.Dataset.manifest; app.setSource(o.Dataset.manifest.File(1)); elseif strlength(o.DatasetFile)>0 && isfile(o.DatasetFile), app.loadDataset(o.DatasetFile); end; app.Handles.Model.Value=char(o.Model); app.Handles.Status.Text='SETUP_LOADED_NOT_VERIFIED / 設定已載入，未驗證模型';
        end
        function status=initialize(app)
            o=app.options(); classes=strings(0,1); if ~isempty(app.Dataset) && app.Dataset.schema.Task==o.Task, if o.Task=="instance", classes=app.Dataset.classes; else, classes=string(app.Dataset.schema.Template.Names); end, end
            [~,status]=VIStudioTaskModelsV15.create(o,classes); app.Handles.Status.Text=status.State+" · "+status.Message;
        end
        function loadModel(app,file), app.Artifact=VIStudioTaskModelsV15.load(file,string(app.Handles.Task.Value)); app.Configuration.ModelFile=string(file); app.Result=[]; app.Evaluation=[]; app.Handles.Status.Text="LOADED_NOT_RUN · "+app.Artifact.File; end
        function train(app,folder)
            assert(~isempty(app.Dataset),'VIStudioV15:TaskDataset','Load a reviewed dataset.'); o=app.options(); assert(app.Dataset.schema.Task==o.Task,'VIStudioV15:TaskMismatch','Select matching dataset.'); VIStudioTaskModelsV15.train(app.Dataset,o,folder,app.Artifact,app.Run); app.loadModel(fullfile(folder,'model.mat'));
        end
        function result=infer(app)
            assert(~isempty(app.Artifact) && isfile(app.SourceFile),'VIStudioV15:TaskModel','Load image and a matching model.'); image=VIStudioData.readImage(app.SourceFile,[]); boxes=app.sourceBoxes(); result=VIStudioTaskModelsV15.predict(app.Artifact,image,app.Handles.Threshold.Value,boxes); result.SourceFile=app.SourceFile; result.SourceHash=VIStudioToolsV3.fileHash(app.SourceFile); result.ModelFile=app.Artifact.File; result.ModelDigest=app.Artifact.Digest; app.Result=result; imshow(image,'Parent',app.Handles.Raw);
            if app.Artifact.Task=="instance"
                for k=1:numel(result.Labels), image=labeloverlay(image,result.Masks(:,:,k),'Transparency',.55); end; if ~isempty(result.Boxes), image=insertObjectAnnotation(image,'rectangle',result.Boxes,cellstr(result.Labels)); end; app.Handles.Results.Data=table(result.Labels,result.Scores,'VariableNames',{'Class','Score'});
            else
                poses=app.poses(result,size(image,[1 2])); for k=1:numel(poses), image=VIStudioPoseV15.overlay(image,poses{k}); end; app.Handles.Results.Data=table(result.Names,'VariableNames',{'Point'});
            end
            imshow(image,'Parent',app.Handles.Overlay); app.Handles.Status.Text='INFERENCE_VERIFIED / 本次推論完成';
        end
        function evaluation=evaluate(app)
            assert(~isempty(app.Dataset) && ~isempty(app.Artifact),'VIStudioV15:TaskDataset','Load dataset and model.'); data=app.Dataset; snapshot=VIStudioStructuredV15.assertUnchanged(data); rows=data.manifest.Split=="test"; if ~any(rows), rows=data.manifest.Split=="validation"; end; assert(any(rows),'VIStudioV15:EvaluationSplit','Reserve test or validation images.');
            assert(app.Artifact.Task==data.schema.Task,'VIStudioV15:TaskMismatch','Model task differs from dataset.'); VIStudioDatasetV9.assertParentIndependent(struct('Manifest',snapshot),app.Artifact); files=data.manifest.File(rows); results=cell(numel(files),1);
            for k=1:numel(files)
                file=files(k); image=VIStudioData.readImage(file,[]); objects=data.objects(data.objects.File==file,:); boxes=zeros(height(objects),4); for n=1:height(objects), boxes(n,:)=objects.Box{n}; end
                threshold=0; if data.schema.Task=="keypoints", threshold=app.Handles.Threshold.Value; end
                if data.schema.Task=="keypoints" && isempty(boxes), prediction=struct('Poses',{{}}); else
                    prediction=VIStudioTaskModelsV15.predict(app.Artifact,image,threshold,boxes);
                    if data.schema.Task=="keypoints", prediction.Poses=app.poses(prediction,size(image,[1 2])); end
                end
                prediction.SourceHash=VIStudioToolsV3.fileHash(file); results{k}=prediction;
            end
            evaluation=app.evaluateOffline(files,results); evaluation.ModelFile=app.Artifact.File; evaluation.ModelDigest=app.Artifact.Digest; evaluation.APScoreCutoff=0; app.Evaluation=evaluation;
        end
        function evaluation=evaluateOffline(app,files,results)
            assert(~isempty(app.Dataset),'VIStudioV15:TaskDataset','Load a reviewed dataset.'); evaluation=VIStudioEvaluationV19.batch(app.Dataset,files,results,app.Configuration.PCKThreshold); app.Evaluation=evaluation; app.Handles.Results.Data=struct2table(evaluation.Detailed.Summary); app.Handles.EvalNote.Text=evaluation.Meaning;
        end
        function official=officialEvaluation(app)
            assert(~isempty(app.Evaluation) && app.Evaluation.Task=="instance",'VIStudioV15:Evaluation','Run instance evaluation first.'); e=app.Evaluation; official=VIStudioEvaluationV19.official(e.Predictions,e.Truth,app.Dataset.classes,e.Files); app.Evaluation.Official=official; app.Handles.EvalNote.Text=official.Meaning;
        end
        function editor=openEditor(app,kind)
            if ~isempty(app.Editor) && isvalid(app.Editor), app.Editor.UIFigure.Visible='on'; else, app.Editor=VIStudioLabelerV19('on',@(output) app.loadDataset(output.Path)); if ~isempty(app.Dataset), app.Editor.importStructured(app.DatasetFile); elseif strlength(app.SourceFile)>0, app.Editor.loadFiles(app.SourceFile); end, end
            app.Editor.openAdvanced(kind); editor=app.Editor;
        end
    end
    methods (Access=private)
        function showEvaluation(app), assert(~isempty(app.Evaluation),'VIStudioV15:Evaluation','Evaluate first.'); VIStudioEvaluationV19.show(app.Evaluation); end
        function pickPredictions(app)
            [f,p]=uigetfile('*.mat'); if isequal(f,0), return; end; loaded=load(fullfile(p,f),'files','results'); assert(all(isfield(loaded,{'files','results'})),'VIStudioV15:PredictionFile','Require files and results; each result requires SourceHash.'); app.evaluateOffline(loaded.files,loaded.results); app.showEvaluation();
        end
        function pickPython(app)
            [f,p]=uigetfile('*.exe','Python executable (optional official COCO bridge)'); if isequal(f,0), return; end; env=pyenv; assert(env.Status=="NotLoaded",'VIStudioV15:PythonLoaded','Python is already loaded; restart MATLAB before changing the executable.'); pyenv('Version',fullfile(p,f),'ExecutionMode','OutOfProcess'); app.Handles.Status.Text='PYTHON_CONFIGURED_NOT_RUN / Python 已設定，尚未執行';
        end
        function changeTask(app)
            task=string(app.Handles.Task.Value); app.Configuration.Task=task; choices={'maskrcnn','solov2'}; if task=="keypoints", choices={'hrnet-w32','hrnet-w48'}; end; app.Handles.Model.Items=choices; app.Handles.Model.Value=choices{1}; app.Artifact=[]; app.Result=[]; app.Evaluation=[];
        end
        function boxes=sourceBoxes(app)
            image=imfinfo(app.SourceFile); boxes=[1 1 image.Width image.Height]; if ~isempty(app.Dataset), objects=app.Dataset.objects(app.Dataset.objects.File==app.SourceFile,:); if ~isempty(objects), boxes=zeros(height(objects),4); for k=1:height(objects), boxes(k,:)=objects.Box{k}; end, end, end
        end
        function poses=poses(~,result,imageSize)
            poses=cell(size(result.Boxes,1),1); template=struct('Names',result.Names,'Edges',result.Edges);
            for k=1:numel(poses)
                xy=double(result.Points(:,:,k)); visible=result.Valid(:,k) & all(isfinite(xy),2) & xy(:,1)>=1 & xy(:,1)<=imageSize(2) & xy(:,2)>=1 & xy(:,2)<=imageSize(1); box=result.Boxes(k,:); visible=visible & xy(:,1)>=box(1) & xy(:,1)<=box(1)+box(3)-1 & xy(:,2)>=box(2) & xy(:,2)<=box(2)+box(4)-1; xy(~visible,:)=NaN; poses{k}=VIStudioPoseV15.geometry(template,xy,2*double(visible),box);
            end
        end
        function action(app,callback)
            if app.Busy, return; end; app.Busy=true; controls=findall(app.Handles.Root); for h=reshape(controls,1,[]), if isprop(h,'Enable'), h.Enable='off'; end, end; cleanup=onCleanup(@() app.finish()); try, callback(); catch err, app.Handles.Status.Text="ERROR / "+string(err.message); fig=ancestor(app.Handles.Task,'figure'); if strcmp(fig.Visible,'off'), rethrow(err); end; uialert(fig,err.message,'V19'); end
        end
        function finish(app), app.Busy=false; controls=findall(app.Handles.Root); for h=reshape(controls,1,[]), if isprop(h,'Enable'), h.Enable='on'; end, end; app.Run.Handles.Stop.Enable='off'; end
        function pickDataset(app), [f,p]=uigetfile('*.mat'); if ~isequal(f,0), app.loadDataset(fullfile(p,f)); end, end
        function pickImage(app), [f,p]=uigetfile({'*.png;*.jpg;*.bmp','Images'}); if ~isequal(f,0), app.setSource(fullfile(p,f)); end, end
        function pickModel(app), [f,p]=uigetfile('*.mat'); if ~isequal(f,0), app.loadModel(fullfile(p,f)); end, end
        function pickSave(app), [f,p]=uiputfile('*.mat'); if ~isequal(f,0), app.saveSetup(fullfile(p,f)); end, end
        function pickSetup(app), [f,p]=uigetfile('*.mat'); if ~isequal(f,0), app.loadSetup(fullfile(p,f)); end, end
        function assignSplit(app)
            assert(~isempty(app.Dataset),'VIStudioV15:TaskDataset','Load dataset.'); rows=app.Handles.Manifest.Selection; assert(~isempty(rows),'VIStudioV15:Selection','Select source rows.'); candidate=app.Dataset; candidate.manifest.Split(rows)=string(app.Handles.Split.Value); VIStudioStructuredV15.validate(candidate); app.Dataset=candidate; app.Handles.Manifest.Data=candidate.manifest; app.Evaluation=[];
        end
        function pickTrain(app), parent=uigetdir(pwd); if ~isequal(parent,0), app.train(tempname(parent)); end, end
        function exportResults(app)
            assert(~isempty(app.Evaluation) || ~isempty(app.Result),'VIStudioV15:TaskResult','Run inference or evaluation.'); parent=uigetdir(pwd); if isequal(parent,0), return; end; folder=tempname(parent); mkdir(folder); result=app.Result; evaluation=app.Evaluation; configuration=app.options(); save(fullfile(folder,'results.mat'),'result','evaluation','configuration','-v7.3'); if ~isempty(evaluation)
                writetable(evaluation.Images,fullfile(folder,'images.csv'),'Encoding','UTF-8'); writetable(struct2table(evaluation.Detailed.Summary),fullfile(folder,'summary.csv'),'Encoding','UTF-8');
                if evaluation.Task=="instance", writetable(evaluation.Detailed.Classes,fullfile(folder,'classes.csv'),'Encoding','UTF-8'); else, writetable(evaluation.Detailed.Points,fullfile(folder,'points.csv'),'Encoding','UTF-8'); writetable(evaluation.Detailed.Details,fullfile(folder,'point_details.csv'),'Encoding','UTF-8'); writetable(evaluation.Detailed.PCKCurve,fullfile(folder,'pck_curve.csv'),'Encoding','UTF-8'); end
                if isfield(evaluation,'Official'), writetable(evaluation.Official.Summary,fullfile(folder,'official_coco.csv'),'Encoding','UTF-8'); end
            end
        end
    end
end
