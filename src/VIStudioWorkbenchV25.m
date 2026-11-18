classdef VIStudioWorkbenchV25 < handle
    properties (SetAccess=private)
        Structured=[]
        Semantic=[]
        Handles=struct()
        SourceFile=""
        SourceImage=[]
        ModelA=[]
        ModelB=[]
        LastComparison=[]
        LastQuality=[]
        LastPipeline=[]
        LastRotation=[]
        Queue
        MaskData=table()
        MaskArtifact=[]
        MaskEvaluation=[]
        Geometry=VIStudioGeometryV11.defaults()
        QualityOptions=VIStudioQualityV11.defaults()
        Recipe=VIStudioPipelineV13.defaults()
        TrainRun=[]
    end
    properties (Access=private)
        Callbacks
        SourceHash=""
        Busy=false
        Labeler=[]
        Controls=struct()
        Root
    end
    methods
        function app=VIStudioWorkbenchV25(tab,task,callbacks,root)
            if nargin<4, root=fileparts(mfilename('fullpath')); end
            app.Root=string(root); app.Callbacks=callbacks; app.Queue=VIStudioHardSamplesV11(fullfile(root,'V16_HardSamples')); app.TrainRun=VIStudioTrainingRunV9;
            grid=uigridlayout(tab,[2 1],'RowHeight',{38,'1x'});
            bar=uigridlayout(grid,[1 4],'ColumnWidth',{170,170,'1x',120},'Padding',[0 0 0 0]);
            uibutton(bar,'Text','載入影像 / Load image','ButtonPushedFcn',@(~,~) app.action(@() app.pickImage()));
            uibutton(bar,'Text','使用目前影像 / Current image','ButtonPushedFcn',@(~,~) app.action(@() app.setSource(callbacks.Source())));
            app.Handles.Source=uilabel(bar,'Text','未載入 / No image','Interpreter','none');
            app.Handles.Stop=uibutton(bar,'Text','停止 / Stop','Enable','off','ButtonPushedFcn',@(~,~) app.TrainRun.requestStop());
            app.Handles.Tabs=uitabgroup(grid); app.buildCompare(task); app.buildQuality(); app.buildQueue(); app.buildMasks(); app.buildGeometry(); app.buildRotation(); app.buildPipeline(); page=uitab(app.Handles.Tabs,'Title','語意分割 / Semantic'); app.Semantic=VIStudioSemanticPaneV25(page,callbacks); page=uitab(app.Handles.Tabs,'Title','實例與點位 / Instance & Pose'); app.Structured=VIStudioTaskPaneV25(page,'instance');
        end
        function selectSemantic(app), app.Handles.Tabs.SelectedTab=app.Semantic.Handles.Tabs.Parent; end
        function delete(app)
            if ~isempty(app.Structured) && isvalid(app.Structured), delete(app.Structured); end
            if ~isempty(app.Semantic) && isvalid(app.Semantic), delete(app.Semantic); end
            if ~isempty(app.Labeler) && isvalid(app.Labeler), delete(app.Labeler); end
        end
        function configureRecipe(app,recipe)
            recipe=VIStudioPipelineV13.validate(recipe,true); app.showRecipe(recipe);
        end
        function configureGeometry(app,geometry)
            VIStudioGeometryV11.validate(geometry); app.Geometry=geometry; app.LastComparison=[]; app.showGeometry();
        end
        function configureQuality(app,options)
            app.QualityOptions=VIStudioQualityV11.options(options);
            for f=fieldnames(app.Controls.Quality)', app.Controls.Quality.(f{1}).Value=app.QualityOptions.(f{1}); end
        end
        function loadMaskManifest(app,file)
            app.MaskData=VIStudioMasksV11.read(file); app.Handles.MaskTable.Data=app.MaskData;
        end
        function setSource(app,file)
            assert(isfile(file),'VIStudioV15:Source','Load a source image first.'); app.SourceImage=VIStudioData.readImage(file,[]); app.SourceFile=VIStudioToolsV3.canonicalPath(file); app.SourceHash=VIStudioToolsV3.fileHash(file);
            app.LastComparison=[]; app.LastRotation=[]; app.LastPipeline=[]; app.Handles.Source.Text=app.SourceFile;
            imshow(app.SourceImage,'Parent',app.Handles.CompareA); imshow(app.SourceImage,'Parent',app.Handles.CompareB); app.showGeometry();
        end
        function setModel(app,side,file,task)
            artifact=VIStudioInferenceV13.load(file,task); app.LastComparison=[]; if string(side)=="A", app.ModelA=artifact; app.Handles.PathA.Text=artifact.File; else, app.ModelB=artifact; app.Handles.PathB.Text=artifact.File; end
        end
        function result=compare(app)
            assert(~isempty(app.ModelA) && ~isempty(app.ModelB),'VIStudioV15:CompareModels','Load model A and B.'); [image,context]=app.prepared();
            quality=VIStudioQualityV11.check(image,app.quality()); app.LastQuality=quality; app.Handles.QualityTable.Data=quality.Metrics;
            assert(~quality.Blocked,'VIStudioV15:Retake','Image quality requires retaking; inference was not run.');
            result=VIStudioInferenceV13.compare(app.ModelA,app.ModelB,image); result.Geometry=context; result.Quality=quality; app.LastComparison=result;
            app.Handles.CompareTable.Data=result.Summary;
            detail="";
            if app.ModelA.Task=="anomaly", detail=sprintf(' | Mask IoU: %g',result.MaskIoU);
            elseif app.ModelA.Task=="detection", detail=sprintf(' | 未配對框 / Unmatched: %g',result.UnmatchedDetections); end
            app.Handles.CompareStatus.Text=sprintf('差異 / Disagree: %d',result.Disagree)+detail+" | 座標 / Coordinates: "+context.CoordinateSpace;
            imshow(VIStudioInferenceV13.overlay(image,result.First),'Parent',app.Handles.CompareA); imshow(VIStudioInferenceV13.overlay(image,result.Second),'Parent',app.Handles.CompareB);
        end
        function id=enqueue(app,reason)
            [image,context]=app.prepared(); task=string(app.Controls.CompareTask.Value); predicted=""; evidence=struct('CoordinateSpace',context.CoordinateSpace,'Geometry',rmfield(context,'ValidMask'));
            if ~isempty(app.LastComparison)
                predicted=app.LastComparison.First.Label; task=app.ModelA.Task; evidence.Comparison=app.LastComparison.Summary; evidence.Models=[app.ModelA.Digest app.ModelB.Digest];
            end
            id=app.Queue.add(app.SourceFile,task,reason,predicted,evidence,image); app.refreshQueue();
        end
        function count=mine(app,folder,maxItems)
            assert(~isempty(app.ModelA) && ~isempty(app.ModelB),'VIStudioV15:CompareModels','Load two models first.'); ds=imageDatastore(folder,'IncludeSubfolders',true); count=0; app.TrainRun=VIStudioTrainingRunV9;
            for k=1:numel(ds.Files)
                if app.TrainRun.StopRequested, break; end
                app.setSource(ds.Files{k});
                [im,~]=app.prepared(); q=VIStudioQualityV11.check(im,app.quality());
                if q.Blocked, app.Handles.CompareStatus.Text="需重拍，略過回訓 / RETAKE; excluded from retraining"; drawnow; continue; end
                result=app.compare(); low=false;
                if app.ModelA.Task=="anomaly", low=result.First.Decision=="REVIEW" || result.Second.Decision=="REVIEW";
                else, low=result.First.Confidence<app.Controls.LowConfidence.Value || result.Second.Confidence<app.Controls.LowConfidence.Value; end
                if result.Disagree || low, app.enqueue('模型分歧或低信心 / Disagreement or low confidence'); count=count+1; end
                if count>=maxItems, break; end; drawnow;
            end
        end
        function [image,context]=prepared(app)
            assert(~isempty(app.SourceImage) && isfile(app.SourceFile) && VIStudioToolsV3.fileHash(app.SourceFile)==app.SourceHash,'VIStudioV15:SourceChanged','Source changed or is missing; reload it.');
            [image,context]=VIStudioGeometryV11.apply(app.SourceImage,app.Geometry);
            assert(context.ValidFraction>=app.Geometry.MinValidFraction,'VIStudioV15:GeometryCoverage','Rectified image has too many invalid pixels.');
        end
        function o=quality(app)
            o=app.QualityOptions;
            fields=fieldnames(app.Controls.Quality);
            for k=1:numel(fields), o.(fields{k})=app.Controls.Quality.(fields{k}).Value; end
            o=VIStudioQualityV11.options(o); app.QualityOptions=o;
        end
        function report=checkQuality(app)
            [image,~]=app.prepared(); report=VIStudioQualityV11.check(image,app.quality()); app.LastQuality=report; app.Handles.QualityTable.Data=report.Metrics;
            reason="通過 / Passed"; if ~isempty(report.Reasons), reason=join(report.Reasons,'; '); end; app.Handles.QualityStatus.Text=report.Decision+" | "+reason; imshow(image,'Parent',app.Handles.QualityImage);
        end
        function trainMasks(app,folder)
            assert(~isempty(app.MaskData),'VIStudioV15:MaskData','Load a mask manifest.'); base=struct('Epochs',app.Controls.Epochs.Value,'Batch',app.Controls.Batch.Value,'LearnRate',app.Controls.Rate.Value,'Environment','cpu','Validation',0,'Size',app.Controls.Size.Value,'NormalClass','good');
            external=[]; if app.Controls.WarmStart.Value, external=app.ModelA; assert(~isempty(external),'VIStudioV15:MaskExternal','Load an FCDD as model A.'); end
            app.TrainRun=VIStudioTrainingRunV9;
            [~,~,run]=VIStudioMasksV11.train(app.MaskData,base,struct('Size',base.Size,'AugmentCopies',app.Controls.Copies.Value),folder,external,app.TrainRun);
            app.TrainRun=run; app.MaskArtifact=VIStudioInferenceV13.load(fullfile(folder,'model.mat'),'anomaly'); app.Handles.MaskStatus.Text="已訓練，須校準 / Trained; calibration required · "+app.MaskArtifact.File;
        end
        function evaluation=evaluateMasks(app)
            assert(~isempty(app.MaskArtifact),'VIStudioV15:MaskModel','Train or load an anomaly model first.'); rows=app.MaskData.Split=="test";
            if ~any(rows), rows=app.MaskData.Split=="validation"; end
            assert(any(rows),'VIStudioV15:EvaluationSplit','Reserve test or validation images first.');
            [data,summary]=VIStudioMasksV11.evaluate(app.MaskArtifact,app.MaskData(rows,:),app.Controls.PixelThreshold.Value);
            evaluation=struct('Images',data,'Summary',summary); app.MaskEvaluation=evaluation; app.Handles.MaskResults.Data=data; app.Handles.MaskStatus.Text=string(jsonencode(summary));
        end
        function r=rotate(app,mask)
            [image,geometry]=app.prepared();
            if nargin<2
                [file,path]=uigetfile({'*.png;*.tif;*.bmp','Binary mask'}); if isequal(file,0), r=[]; return; end
                mask=VIStudioMasksV11.mask(fullfile(path,file)); assert(isequal(size(mask),size(app.SourceImage,[1 2])),'VIStudioV15:MaskSize','Mask must match the raw source image.');
                mask=VIStudioGeometryV11.apply(mask,app.Geometry,true);
            end
            options=VIStudioDefectsV11.defaults(); options.Enabled=true; options.UseCount=false; options.UseLength=true; options.MaxLength=app.Controls.MaxLength.Value; options.UseShortWidth=true; options.MaxShortWidth=app.Controls.MaxShort.Value;
            options.ScaleEnabled=app.Controls.RotationMM.Value; options.MMPerPixelX=app.Controls.ScaleX.Value; options.MMPerPixelY=app.Controls.ScaleY.Value;
            if app.Geometry.Perspective
                options.ScaleEnabled=true; options.MMPerPixelX=geometry.ScaleX; options.MMPerPixelY=geometry.ScaleY;
                app.Controls.RotationMM.Value=true; app.Controls.ScaleX.Value=geometry.ScaleX; app.Controls.ScaleY.Value=geometry.ScaleY;
            end
            if options.ScaleEnabled, options.LimitUnit="mm"; end
            r=VIStudioDefectsV11.analyze(mask & geometry.ValidMask,[],options); r.CoordinateSpace=geometry.CoordinateSpace; app.LastRotation=r;
            imshow(VIStudioDefectsV10.overlay(image,r),'Parent',app.Handles.RotationImage); hold(app.Handles.RotationImage,'on');
            for k=1:height(r.Rotated), vertices=jsondecode(r.Rotated.VerticesJSON(k)); plot(app.Handles.RotationImage,[vertices(:,1);vertices(1,1)],[vertices(:,2);vertices(1,2)],'y-','LineWidth',2); end
            hold(app.Handles.RotationImage,'off'); app.Handles.RotationTable.Data=r.Rotated; reason="通過 / Passed"; if ~isempty(r.Reasons), reason=join(r.Reasons,'; '); end; app.Handles.RotationStatus.Text=r.Decision+" | 上限單位 / Limit unit: "+options.LimitUnit+" | 座標 / Coordinates: "+geometry.CoordinateSpace+" | "+reason;
        end
        function result=runRecipe(app)
            app.prepared(); recipe=app.recipeFromUI(); recipe=VIStudioPipelineV13.validate(recipe,false); app.Recipe=recipe;
            assert(~isempty(app.SourceImage),'VIStudioV15:Source','Load source image.'); result=VIStudioPipelineV13.run(recipe,app.SourceImage); app.LastPipeline=result;
            image=result.Image;
            for stage=1:numel(result.Outputs)
                for n=1:numel(result.Outputs{stage})
                    item=result.Outputs{stage}{n}; if item.Prediction.Task~="semantic", continue; end
                    b=item.Box; ys=b(2)+(0:b(4)-1); xs=b(1)+(0:b(3)-1); image(ys,xs,:)=VIStudioSemanticV13.overlay(image(ys,xs,:),item.Prediction.Semantic);
                end
            end
            for k=1:height(result.Stages)
                box=result.Stages{k,{'X','Y','Width','Height'}}; if all(isfinite(box)), image=insertObjectAnnotation(image,'rectangle',box,char(result.Stages.Stage(k)+": "+result.Stages.Decision(k))); end
            end
            imshow(image,'Parent',app.Handles.PipelineImage); app.Handles.PipelineResults.Data=result.Stages;
            app.Handles.PipelineStatus.Text=result.Decision+sprintf(' | %.1f ms | ',result.Milliseconds)+result.Geometry.CoordinateSpace;
        end
        function busy(app,value)
            objects=findall(app.Handles.Tabs.Parent); state='on'; if value, state='off'; end
            for h=reshape(objects,1,[]), if isprop(h,'Enable'), h.Enable=state; end, end
            app.Handles.Stop.Enable='off';
            if ~value && ~isempty(app.Semantic), app.Semantic.Run.Handles.Stop.Enable='off'; end
        end
    end
    methods (Access=private)
        function labelBar(~,bar,labels)
            controls=bar.Children; bar.RowHeight={20,38}; bar.RowSpacing=2;
            for k=1:numel(controls), controls(k).Layout.Row=2; controls(k).Layout.Column=k; end
            for k=1:numel(labels), label=uilabel(bar,'Text',labels{k}); label.Layout.Row=1; label.Layout.Column=k; end
        end
        function buildCompare(app,task)
            tab=uitab(app.Handles.Tabs,'Title','模型並排 / Compare'); grid=uigridlayout(tab,[5 2],'RowHeight',{38,30,30,'1x',110});
            bar=uigridlayout(grid,[1 8],'ColumnWidth',{'1x','1x','1x','1x','1x','1x',80,65},'Padding',[0 0 0 0]); bar.Layout.Column=[1 2];
            app.Controls.CompareTask=uidropdown(bar,'Items',{'classification','detection','anomaly'},'Value',char(task));
            uibutton(bar,'Text','載入 A / Load A','ButtonPushedFcn',@(~,~) app.action(@() app.pickModel('A')));
            uibutton(bar,'Text','載入 B / Load B','ButtonPushedFcn',@(~,~) app.action(@() app.pickModel('B')));
            uibutton(bar,'Text','並排檢測 / Compare','ButtonPushedFcn',@(~,~) app.action(@() app.compare()));
            uibutton(bar,'Text','加入困難樣本 / Queue','ButtonPushedFcn',@(~,~) app.action(@() app.enqueue('人工選入 / Manually selected')));
            uibutton(bar,'Text','批次挑選 / Mine folder','ButtonPushedFcn',@(~,~) app.action(@() app.pickMine()));
            app.Handles.PathA=uilabel(grid,'Text','A: 未載入 / Not loaded','Interpreter','none'); app.Handles.PathA.Layout.Column=[1 2];
            app.Handles.PathB=uilabel(grid,'Text','B: 未載入 / Not loaded','Interpreter','none');
            app.Handles.CompareStatus=uilabel(grid,'Text','同一校正影像，比較相同任務 / Same prepared image; same task','WordWrap','on');
            app.Handles.CompareA=uiaxes(grid); app.Handles.CompareA.Layout.Row=4; app.Handles.CompareB=uiaxes(grid); app.Handles.CompareB.Layout.Row=4; app.Handles.CompareB.Layout.Column=2;
            app.Handles.CompareTable=uitable(grid); app.Handles.CompareTable.Layout.Column=[1 2]; app.Handles.CompareTable.Layout.Row=5;
            uilabel(bar,'Text','低信心 / Low'); app.Controls.LowConfidence=uieditfield(bar,'numeric','Value',.7,'Limits',[0 1]);
        end
        function buildQuality(app)
            tab=uitab(app.Handles.Tabs,'Title','影像品質 / Quality'); grid=uigridlayout(tab,[1 2],'ColumnWidth',{330,'1x'}); left=uigridlayout(grid,[12 2],'RowHeight',repmat({34},1,12),'ColumnWidth',{230,'1x'});
            values=VIStudioQualityV11.defaults(); fields={'Enabled','MinBrightness','MaxBrightness','MinContrast','MinFocus','MaxDarkFraction','MaxBrightFraction','MaxShiftPixels'};
            labels={'啟用重拍攔截 / Gate enabled','最低亮度 / Min brightness','最高亮度 / Max brightness','最低對比 / Min contrast','最低清晰度 / Min focus','暗部比例上限 / Max dark','飽和比例上限 / Max bright','位移上限 px / Max shift'};
            app.Controls.Quality=struct();
            for k=1:numel(fields)
                label=uilabel(left,'Text',labels{k},'WordWrap','on'); label.Layout.Row=k;
                if islogical(values.(fields{k})), control=uicheckbox(left,'Text','','Value',values.(fields{k})); else, control=uieditfield(left,'numeric','Value',values.(fields{k}),'Limits',[0 realmax]); end
                control.Layout.Row=k; control.Layout.Column=2; app.Controls.Quality.(fields{k})=control;
            end
            button=uibutton(left,'Text','檢查目前影像 / Check','ButtonPushedFcn',@(~,~) app.action(@() app.checkQuality())); button.Layout.Row=9; button.Layout.Column=[1 2];
            button=uibutton(left,'Text','以目前影像為位置參考 / Reference','ButtonPushedFcn',@(~,~) app.action(@() app.setReference())); button.Layout.Row=10; button.Layout.Column=[1 2];
            right=uigridlayout(grid,[3 1],'RowHeight',{60,'1x',90}); app.Handles.QualityStatus=uilabel(right,'Text','指標需依拍攝條件調整 / Tune thresholds for your imaging setup','WordWrap','on'); app.Handles.QualityImage=uiaxes(right); app.Handles.QualityTable=uitable(right);
        end
        function buildQueue(app)
            tab=uitab(app.Handles.Tabs,'Title','困難樣本 / Hard samples'); grid=uigridlayout(tab,[3 1],'RowHeight',{38,'1x',45});
            bar=uigridlayout(grid,[1 5],'Padding',[0 0 0 0]); app.Controls.QueueTask=uidropdown(bar,'Items',{'classification','detection','anomaly'});
            app.Controls.Truth=uieditfield(bar,'text','Placeholder','人工類別 / Human label');
            uibutton(bar,'Text','確認選取標籤 / Confirm','ButtonPushedFcn',@(~,~) app.action(@() app.reviewQueue()));
            uibutton(bar,'Text','排除 / Exclude','ButtonPushedFcn',@(~,~) app.action(@() app.excludeQueue()));
            uibutton(bar,'Text','匯出覆核資料 / Export','ButtonPushedFcn',@(~,~) app.action(@() app.exportQueue()));
            app.Handles.QueueTable=uitable(grid,'SelectionType','row');
            bar=uigridlayout(grid,[1 4],'Padding',[0 0 0 0]);
            uibutton(bar,'Text','匯出並送回訓練 / Retrain','ButtonPushedFcn',@(~,~) app.exportAndRetrain());
            uibutton(bar,'Text','開啟標註與遮罩工具 / Labeler','ButtonPushedFcn',@(~,~) app.openQueueLabeler());
            uibutton(bar,'Text','匯入覆核框 MAT / Import boxes','ButtonPushedFcn',@(~,~) app.action(@() app.importQueueBoxes()));
            uilabel(bar,'Text','未經人工確認不進入回訓資料 / Human review is mandatory','WordWrap','on'); app.refreshQueue();
        end
        function buildMasks(app)
            tab=uitab(app.Handles.Tabs,'Title','遮罩訓練與評估 / Masks'); grid=uigridlayout(tab,[6 1],'RowHeight',{38,38,38,50,'1x',130});
            bar=uigridlayout(grid,[1 5],'Padding',[0 0 0 0]);
            uibutton(bar,'Text','載入標註清單 / Manifest','ButtonPushedFcn',@(~,~) app.action(@() app.pickManifest()));
            app.Controls.MaskSplit=uidropdown(bar,'Items',{'train','validation','test','calibration'});
            uibutton(bar,'Text','指定選取用途 / Assign split','ButtonPushedFcn',@(~,~) app.action(@() app.assignSplit()));
            uibutton(bar,'Text','載入異常模型 / Load model','ButtonPushedFcn',@(~,~) app.action(@() app.pickMaskModel()));
            uibutton(bar,'Text','在工作區啟用 / Activate','ButtonPushedFcn',@(~,~) app.activateMask());
            bar=uigridlayout(grid,[1 10],'Padding',[0 0 0 0]);
            uilabel(bar,'Text','Epochs'); app.Controls.Epochs=uieditfield(bar,'numeric','Value',1,'Limits',[1 10000]);
            uilabel(bar,'Text','Batch'); app.Controls.Batch=uieditfield(bar,'numeric','Value',2,'Limits',[1 128]);
            uilabel(bar,'Text','LR'); app.Controls.Rate=uieditfield(bar,'numeric','Value',.0001,'Limits',[eps 1]);
            uilabel(bar,'Text','Size'); app.Controls.Size=uieditfield(bar,'numeric','Value',224,'Limits',[32 1024]);
            uilabel(bar,'Text','Copies'); app.Controls.Copies=uieditfield(bar,'numeric','Value',0,'Limits',[0 20]);
            bar=uigridlayout(grid,[1 6],'Padding',[0 0 0 0]); app.Controls.WarmStart=uicheckbox(bar,'Text','沿用 A / Warm-start A');
            uibutton(bar,'Text','遮罩監督訓練 / Train','ButtonPushedFcn',@(~,~) app.action(@() app.pickTrainMasks()));
            app.Controls.PixelThreshold=uieditfield(bar,'numeric','Value',.5,'Limits',[0 realmax],'Tooltip','Raw anomaly-map threshold');
            uibutton(bar,'Text','正常校準集門檻 / Calibrate','ButtonPushedFcn',@(~,~) app.action(@() app.calibrateMasks()));
            uibutton(bar,'Text','IoU / Dice 評估','ButtonPushedFcn',@(~,~) app.action(@() app.evaluateMasks()));
            uibutton(bar,'Text','匯出評估 / Export','ButtonPushedFcn',@(~,~) app.action(@() app.exportMaskEvaluation()));
            app.Handles.MaskStatus=uilabel(grid,'Text','File, MaskFile, Label, Split；只擴充 train / Only train is augmented','WordWrap','on');
            app.Handles.MaskTable=uitable(grid,'SelectionType','row'); app.Handles.MaskResults=uitable(grid);
        end
        function buildGeometry(app)
            tab=uitab(app.Handles.Tabs,'Title','透視與鏡頭 / Geometry'); grid=uigridlayout(tab,[5 2],'RowHeight',{65,65,100,'1x',50});
            bar=uigridlayout(grid,[1 5],'Padding',[0 0 0 0]); bar.Layout.Column=[1 2];
            uibutton(bar,'Text','鏡頭參數 MAT / Lens MAT','ButtonPushedFcn',@(~,~) app.action(@() app.pickCamera()));
            app.Controls.Square=uieditfield(bar,'numeric','Value',20,'Limits',[eps realmax],'Tooltip','Checkerboard square size in mm');
            uibutton(bar,'Text','棋盤格校正 / Calibrate','ButtonPushedFcn',@(~,~) app.action(@() app.calibrateCamera()));
            uibutton(bar,'Text','清除幾何 / Reset','ButtonPushedFcn',@(~,~) app.action(@() app.resetGeometry()));
            uibutton(bar,'Text','儲存校正 / Save','ButtonPushedFcn',@(~,~) app.action(@() app.saveGeometry()));
            app.labelBar(bar,{'鏡頭設定 / Lens','方格邊長 mm / Square mm'});
            bar=uigridlayout(grid,[1 6],'Padding',[0 0 0 0]); bar.Layout.Column=[1 2];
            app.Controls.OutputW=uieditfield(bar,'numeric','Value',640,'Limits',[2 8192],'Tooltip','Rectified width in pixels'); app.Controls.OutputH=uieditfield(bar,'numeric','Value',480,'Limits',[2 8192],'Tooltip','Rectified height in pixels');
            app.Controls.WorldW=uieditfield(bar,'numeric','Value',100,'Limits',[eps realmax],'Tooltip','Reference rectangle width in mm'); app.Controls.WorldH=uieditfield(bar,'numeric','Value',75,'Limits',[eps realmax],'Tooltip','Reference rectangle height in mm');
            uibutton(bar,'Text','選四角 / Mark corners','ButtonPushedFcn',@(~,~) app.action(@() app.markCorners()));
            uibutton(bar,'Text','套用四點 / Apply points','ButtonPushedFcn',@(~,~) app.action(@() app.applyPoints()));
            app.labelBar(bar,{'輸出寬 px / Width px','輸出高 px / Height px','實體寬 mm / Width mm','實體高 mm / Height mm'});
            app.Handles.Points=uitable(grid,'Data',[1 1;640 1;640 480;1 480],'ColumnName',{'X','Y'},'ColumnEditable',[true true]); app.Handles.Points.Layout.Column=[1 2];
            app.Handles.GeometryRaw=uiaxes(grid); app.Handles.GeometryRaw.Layout.Row=4; app.Handles.GeometryResult=uiaxes(grid); app.Handles.GeometryResult.Layout.Row=4; app.Handles.GeometryResult.Layout.Column=2;
            app.Handles.GeometryStatus=uilabel(grid,'Text','角點在去畸變後影像；校正後座標不冒充原圖座標 / Corners use undistorted coordinates; results use rectified coordinates','WordWrap','on'); app.Handles.GeometryStatus.Layout.Column=[1 2];
        end
        function buildRotation(app)
            tab=uitab(app.Handles.Tabs,'Title','旋轉尺寸 / Rotated dimensions'); grid=uigridlayout(tab,[4 1],'RowHeight',{65,45,'1x',140});
            bar=uigridlayout(grid,[1 7],'Padding',[0 0 0 0]);
            app.Controls.RotationMM=uicheckbox(bar,'Text','mm'); app.Controls.ScaleX=uieditfield(bar,'numeric','Value',1,'Limits',[eps realmax],'Tooltip','X mm/px'); app.Controls.ScaleY=uieditfield(bar,'numeric','Value',1,'Limits',[eps realmax],'Tooltip','Y mm/px');
            app.Controls.MaxLength=uieditfield(bar,'numeric','Value',100,'Limits',[0 realmax],'Tooltip','Maximum rotated long side'); app.Controls.MaxShort=uieditfield(bar,'numeric','Value',100,'Limits',[0 realmax],'Tooltip','Maximum rotated short side');
            uibutton(bar,'Text','載入遮罩量測 / Mask','ButtonPushedFcn',@(~,~) app.action(@() app.rotate()));
            uibutton(bar,'Text','模型 A 遮罩 / A mask','ButtonPushedFcn',@(~,~) app.action(@() app.rotateFromModel()));
            app.labelBar(bar,{'單位 / Unit','X mm/px','Y mm/px','長邊上限 / Max length','短邊上限 / Max width'});
            app.Handles.RotationStatus=uilabel(grid,'Text','最小面積旋轉框；角度以影像 Y 向下為正 / Minimum-area rectangle; clockwise image angles','WordWrap','on'); app.Handles.RotationImage=uiaxes(grid); app.Handles.RotationTable=uitable(grid);
        end
        function buildPipeline(app)
            tab=uitab(app.Handles.Tabs,'Title','流程與產品配方 / Recipes'); grid=uigridlayout(tab,[6 1],'RowHeight',{38,38,140,45,'1x',130});
            bar=uigridlayout(grid,[1 6],'Padding',[0 0 0 0]); app.Controls.RecipeName=uieditfield(bar,'text','Value','New product');
            uibutton(bar,'Text','新增模型步驟 / Add stage','ButtonPushedFcn',@(~,~) app.action(@() app.addStage()));
            uibutton(bar,'Text','刪除步驟 / Remove','ButtonPushedFcn',@(~,~) app.action(@() app.removeStage()));
            uibutton(bar,'Text','載入配方 / Load','ButtonPushedFcn',@(~,~) app.action(@() app.loadRecipe()));
            uibutton(bar,'Text','另存配方 / Save','ButtonPushedFcn',@(~,~) app.action(@() app.saveRecipe()));
            uibutton(bar,'Text','執行流程 / Run','ButtonPushedFcn',@(~,~) app.action(@() app.runRecipe()));
            bar=uigridlayout(grid,[1 4],'Padding',[0 0 0 0]);
            app.Controls.StageTask=uidropdown(bar,'Items',{'classification','detection','anomaly','semantic'},'Tooltip','Task for the next model stage');
            uibutton(bar,'Text','套用目前量測規則 / Use active rules','ButtonPushedFcn',@(~,~) app.useActiveRules());
            uibutton(bar,'Text','套用旋轉量測規則 / Use rotated rules','ButtonPushedFcn',@(~,~) app.useRotatedRules());
            uibutton(bar,'Text','匯出流程報告 / Export report','ButtonPushedFcn',@(~,~) app.action(@() app.exportRecipeResult()));
            app.Handles.StageTable=uitable(grid,'ColumnName',{'ID','Task','ModelFile','Parent','ParentClass','AcceptLabels','MinTargets','MaxTargets','MinObjects','MaxObjects','MaxUnacceptedFraction','MinPixelConfidence'},'ColumnEditable',[true true false true true true true true true true true true]); app.Handles.StageTable.Data=cell(0,12);
            app.Handles.PipelineStatus=uilabel(grid,'Text','Parent 指向前一步 ID；分類需指定接受類別 / Parent references an earlier ID; classification requires accepted labels','WordWrap','on');
            app.Handles.PipelineImage=uiaxes(grid); app.Handles.PipelineResults=uitable(grid);
        end
        function exportRecipeResult(app)
            assert(~isempty(app.LastPipeline),'VIStudioV15:InspectionReport','Run a recipe first.'); parent=uigetdir(pwd); if isequal(parent,0), return; end
            [~,name]=fileparts(tempname(parent)); VIStudioPipelineV13.export(app.LastPipeline,fullfile(parent,['inspection_' name]));
        end
        function useActiveRules(app)
            app.Recipe.DefectRules=VIStudioDefectsV11.options(app.Callbacks.DefectRules());
            app.Handles.PipelineStatus.Text="已套用目前量測規則 / Active metrology rules copied";
        end
        function useRotatedRules(app)
            o=VIStudioDefectsV11.defaults(); o.Enabled=true; o.UseCount=false; o.UseLength=true; o.UseShortWidth=true;
            o.MaxLength=app.Controls.MaxLength.Value; o.MaxShortWidth=app.Controls.MaxShort.Value;
            o.ScaleEnabled=app.Controls.RotationMM.Value; o.MMPerPixelX=app.Controls.ScaleX.Value; o.MMPerPixelY=app.Controls.ScaleY.Value;
            if o.ScaleEnabled, o.LimitUnit="mm"; end
            if app.Geometry.Perspective
                o.ScaleEnabled=true; o.LimitUnit="mm"; o.MMPerPixelX=app.Geometry.WidthMM/app.Geometry.OutputSize(2); o.MMPerPixelY=app.Geometry.HeightMM/app.Geometry.OutputSize(1);
            end
            app.Recipe.DefectRules=VIStudioDefectsV11.options(o); app.Handles.PipelineStatus.Text="已套用旋轉長短邊規則 / Rotated length/width rules copied";
        end
        function recipe=recipeFromUI(app)
            recipe=app.Recipe; recipe.Name=string(app.Controls.RecipeName.Value); recipe.Geometry=app.Geometry; recipe.Quality=app.quality(); data=app.Handles.StageTable.Data; stages=repmat(VIStudioPipelineV13.stage('','',''),0,1);
            for k=1:size(data,1)
                s=VIStudioPipelineV13.stage(data{k,1},data{k,2},data{k,3},data{k,4}); s.ParentClass=string(data{k,5}); labels=split(string(data{k,6}),';'); s.AcceptLabels=labels(strlength(strtrim(labels))>0); s.AcceptLabels=strtrim(s.AcceptLabels);
                old=find(string({app.Recipe.Stages.ID})==s.ID,1);
                if ~isempty(old) && app.Recipe.Stages(old).ModelFile==s.ModelFile && app.Recipe.Stages(old).Task==s.Task
                    s.Digest=app.Recipe.Stages(old).Digest; s.ROI=app.Recipe.Stages(old).ROI;
                else, artifact=VIStudioInferenceV13.load(s.ModelFile,s.Task); s.Digest=artifact.Digest; end
                s.MinTargets=data{k,7}; s.MaxTargets=data{k,8}; s.MinObjects=data{k,9}; s.MaxObjects=data{k,10}; s.MaxUnacceptedFraction=data{k,11}; s.MinPixelConfidence=data{k,12}; stages(end+1)=s; %#ok<AGROW>
            end
            recipe.Stages=stages;
        end
        function showRecipe(app,recipe)
            app.Recipe=recipe; app.Geometry=recipe.Geometry; app.QualityOptions=recipe.Quality; app.configureQuality(recipe.Quality); app.Controls.RecipeName.Value=char(recipe.Name); data=cell(numel(recipe.Stages),12);
            for k=1:numel(recipe.Stages)
                s=recipe.Stages(k); data(k,:)={char(s.ID),char(s.Task),char(s.ModelFile),char(s.Parent),char(s.ParentClass),char(join(string(s.AcceptLabels),';')),s.MinTargets,s.MaxTargets,s.MinObjects,s.MaxObjects,s.MaxUnacceptedFraction,s.MinPixelConfidence};
            end
            app.Handles.StageTable.Data=data;
            for field=fieldnames(app.Controls.Quality)', app.Controls.Quality.(field{1}).Value=recipe.Quality.(field{1}); end
            if ~isempty(app.SourceImage), app.showGeometry(); end
        end
        function action(app,callback)
            if app.Busy, return; end
            app.Busy=true; app.Callbacks.Busy(true); cleanup=onCleanup(@() app.finish()); app.Handles.Stop.Enable='on';
            try, callback(); catch err, fig=ancestor(app.Handles.Tabs,'figure'); if strcmp(fig.Visible,'off'), rethrow(err); end; uialert(fig,err.message,'V25','Interpreter','none'); end
        end
        function finish(app), app.Busy=false; app.Callbacks.Busy(false); app.refreshQueue(); end
        function pickImage(app), [f,p]=uigetfile({'*.png;*.jpg;*.bmp;*.tif','Images'}); if ~isequal(f,0), app.setSource(fullfile(p,f)); end, end
        function pickModel(app,side), [f,p]=uigetfile('*.mat'); if ~isequal(f,0), app.setModel(side,fullfile(p,f),app.Controls.CompareTask.Value); end, end
        function pickMine(app), folder=uigetdir(pwd); if ~isequal(folder,0), app.mine(folder,50); end, end
        function setReference(app), [im,~]=app.prepared(); app.QualityOptions.Reference=im; app.checkQuality(); end
        function refreshQueue(app), app.Handles.QueueTable.Data=app.Queue.Rows(:,{'ID','Task','Reason','Prediction','ActualLabel','ReviewState','OriginalFile'}); end
        function ids=selectedQueue(app), rows=app.Handles.QueueTable.Selection; assert(~isempty(rows),'VIStudioV15:QueueSelection','Select queue rows.'); ids=app.Queue.Rows.ID(rows); end
        function reviewQueue(app), ids=app.selectedQueue(); for id=reshape(ids,1,[]), app.Queue.review(id,app.Controls.Truth.Value); end, app.refreshQueue(); end
        function excludeQueue(app), ids=app.selectedQueue(); for id=reshape(ids,1,[]), app.Queue.exclude(id); end, app.refreshQueue(); end
        function exportAndRetrain(app)
            parent=uigetdir(pwd); if isequal(parent,0), return; end
            [~,name]=fileparts(tempname(parent)); task=string(app.Controls.QueueTask.Value);
            output=app.Queue.export(fullfile(parent,['reviewed_' name]),task); app.Callbacks.Retrain(task,output.Path);
        end
        function exportQueue(app), parent=uigetdir(pwd); if isequal(parent,0), return; end; [~,name]=fileparts(tempname(parent)); app.Queue.export(fullfile(parent,['reviewed_' name]),app.Controls.QueueTask.Value); end
        function openQueueLabeler(app)
            ids=app.selectedQueue(); rows=ismember(app.Queue.Rows.ID,ids); app.Labeler=VIStudioLabelerV25('on'); app.Labeler.loadFiles(app.Queue.Rows.File(rows));
        end
        function importQueueBoxes(app), [f,p]=uigetfile('*.mat'); if ~isequal(f,0), app.Queue.importAnnotations(fullfile(p,f)); app.refreshQueue(); end, end
        function pickManifest(app), [f,p]=uigetfile({'*.mat;*.csv','Mask manifest'}); if ~isequal(f,0), app.loadMaskManifest(fullfile(p,f)); end, end
        function assignSplit(app), rows=app.Handles.MaskTable.Selection; assert(~isempty(rows),'VIStudioV15:MaskSelection','Select image rows.'); app.MaskData.Split(rows)=string(app.Controls.MaskSplit.Value); app.Handles.MaskTable.Data=app.MaskData; end
        function pickMaskModel(app), [f,p]=uigetfile('*.mat'); if ~isequal(f,0), app.MaskArtifact=VIStudioInferenceV13.load(fullfile(p,f),'anomaly'); app.Handles.MaskStatus.Text=app.MaskArtifact.File; end, end
        function activateMask(app), assert(~isempty(app.MaskArtifact),'VIStudioV15:MaskModel','Load a mask model.'); app.Callbacks.Activate(app.MaskArtifact.File); end
        function pickTrainMasks(app), parent=uigetdir(pwd); if isequal(parent,0), return; end; [~,name]=fileparts(tempname(parent)); app.trainMasks(fullfile(parent,['mask_training_' name])); end
        function calibrateMasks(app)
            assert(~isempty(app.MaskArtifact),'VIStudioV15:MaskModel','Load or train a model.'); rows=app.MaskData.Split=="calibration" & app.MaskData.Label=="good";
            [f,p]=uiputfile('calibrated_mask_model.mat'); if isequal(f,0), return; end
            app.MaskArtifact=VIStudioMasksV11.calibrateModel(app.MaskArtifact,app.MaskData(rows,:),99,fullfile(p,f));
            app.Controls.PixelThreshold.Value=app.MaskArtifact.Metadata.PixelThreshold;
            app.Handles.MaskStatus.Text="獨立正常集 99% 門檻已另存 / Independent-normal 99th-percentile thresholds saved · "+app.MaskArtifact.File;
        end
        function exportMaskEvaluation(app)
            assert(~isempty(app.MaskEvaluation),'VIStudioV15:Evaluation','Run evaluation first.'); [f,p]=uiputfile('*.csv'); if isequal(f,0), return; end
            path=fullfile(p,f); assert(~isfile(path),'VIStudioV15:FileExists','Choose a new filename.'); writetable(app.MaskEvaluation.Images,path,'Encoding','UTF-8');
        end
        function pickCamera(app)
            [f,p]=uigetfile('*.mat'); if isequal(f,0), return; end; loaded=load(fullfile(p,f)); candidate=app.Geometry;
            if isfield(loaded,'geometry'), candidate=loaded.geometry;
            else
                names=fieldnames(loaded); found=false;
                for k=1:numel(names), value=loaded.(names{k}); if isa(value,'cameraParameters') || isa(value,'cameraIntrinsics'), candidate.Camera=value; candidate.SourceSize=double(value.ImageSize); found=true; break; end, end
                assert(found,'VIStudioV15:Camera','MAT requires cameraParameters, cameraIntrinsics or geometry.');
            end
            VIStudioGeometryV11.validate(candidate); app.Geometry=candidate; app.showGeometry();
        end
        function calibrateCamera(app)
            folder=uigetdir(pwd); if isequal(folder,0), return; end; [camera,report]=VIStudioGeometryV11.calibrate(folder,app.Controls.Square.Value);
            app.Geometry.Perspective=false; app.Geometry.Camera=camera; app.Geometry.SourceSize=double(camera.ImageSize); app.Handles.GeometryStatus.Text=string(jsonencode(report)); if ~isempty(app.SourceImage), app.showGeometry(); end
        end
        function resetGeometry(app), app.Geometry=VIStudioGeometryV11.defaults(); if ~isempty(app.SourceImage), app.showGeometry(); end, end
        function saveGeometry(app), [f,p]=uiputfile('*.mat'); if isequal(f,0), return; end; file=fullfile(p,f); assert(~isfile(file),'VIStudioV15:FileExists','Choose new file.'); geometry=app.Geometry; save(file,'geometry','-v7.3'); end
        function showGeometry(app)
            if app.Geometry.Perspective
                app.Controls.OutputW.Value=app.Geometry.OutputSize(2); app.Controls.OutputH.Value=app.Geometry.OutputSize(1);
                app.Controls.WorldW.Value=app.Geometry.WidthMM; app.Controls.WorldH.Value=app.Geometry.HeightMM; app.Handles.Points.Data=app.Geometry.Points;
            end
            if isempty(app.SourceImage), return; end
            imshow(app.SourceImage,'Parent',app.Handles.GeometryRaw); [image,context]=VIStudioGeometryV11.apply(app.SourceImage,app.Geometry); imshow(image,'Parent',app.Handles.GeometryResult);
            app.Handles.GeometryStatus.Text=sprintf('%s | valid %.1f%% | %.6g / %.6g mm/px',context.CoordinateSpace,100*context.ValidFraction,context.ScaleX,context.ScaleY);
        end
        function markCorners(app)
            base=app.Geometry; base.Perspective=false; [image,~]=VIStudioGeometryV11.apply(app.SourceImage,base); imshow(image,'Parent',app.Handles.GeometryResult);
            polygon=drawpolygon(app.Handles.GeometryResult); cleanup=onCleanup(@() delete(polygon)); points=wait(polygon); assert(isequal(size(points),[4 2]),'VIStudioV15:Quad','Mark exactly four corners.'); app.Handles.Points.Data=points; app.applyPoints();
        end
        function applyPoints(app)
            app.Geometry=VIStudioGeometryV11.perspective(app.Handles.Points.Data,[app.Controls.OutputH.Value app.Controls.OutputW.Value], ...
                [app.Controls.WorldW.Value app.Controls.WorldH.Value],size(app.SourceImage,[1 2]),app.Geometry); app.showGeometry();
        end
        function rotateFromModel(app)
            [image,~]=app.prepared(); assert(~isempty(app.ModelA) && app.ModelA.Task=="anomaly",'VIStudioV15:MaskModel','Load anomaly model A.'); p=VIStudioInferenceV13.run(app.ModelA,image); assert(~isempty(p.Mask),'VIStudioV15:PixelThreshold','Model A requires a pixel threshold.'); app.rotate(p.Mask);
        end
        function addStage(app)
            [f,p]=uigetfile('*.mat'); if isequal(f,0), return; end
            task=string(app.Controls.StageTask.Value); VIStudioInferenceV13.load(fullfile(p,f),task); data=app.Handles.StageTable.Data;
            data(end+1,:)={sprintf('stage%d',size(data,1)+1),char(task),fullfile(p,f),'','','',1,9999,0,9999,0,.5}; app.Handles.StageTable.Data=data;
        end
        function removeStage(app), rows=app.Handles.StageTable.Selection; data=app.Handles.StageTable.Data; data(rows,:)=[]; app.Handles.StageTable.Data=data; end
        function saveRecipe(app), [f,p]=uiputfile('*.mat'); if ~isequal(f,0), recipe=app.recipeFromUI(); VIStudioPipelineV13.save(recipe,fullfile(p,f)); end, end
        function loadRecipe(app), [f,p]=uigetfile('*.mat'); if ~isequal(f,0), app.showRecipe(VIStudioPipelineV13.load(fullfile(p,f))); end, end
    end
end
