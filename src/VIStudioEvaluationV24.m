classdef VIStudioEvaluationV24
    % Score-ordered, 101-recall mask AP for reviewed, non-crowd instances.
    methods (Static)
        function report=official(predicted,truth,classes,files)
            categories=struct('id',{},'name',{}); for k=1:numel(classes), categories(k)=struct('id',k,'name',char(classes(k))); end
            images=struct('id',{},'file_name',{},'height',{},'width',{});
            for k=1:numel(files)
                sizeHint=[1 1]; ix=find(string({truth.Image})==files(k),1); if ~isempty(ix), sizeHint=size(truth(ix).Mask); else, ix=find(string({predicted.Image})==files(k),1); if ~isempty(ix), sizeHint=size(predicted(ix).Mask); end, end
                images(k)=struct('id',k,'file_name',char(files(k)),'height',sizeHint(1),'width',sizeHint(2));
            end
            annotations={}; results={};
            for k=1:numel(truth)
                t=truth(k); [y,x]=find(t.Mask); annotations{end+1}=struct('id',k,'image_id',find(files==string(t.Image),1),'category_id',find(classes==string(t.Class),1),'segmentation',VIStudioCocoV15.encodeRLE(logical(t.Mask)),'area',nnz(t.Mask),'iscrowd',0,'bbox',[min(x)-1 min(y)-1 max(x)-min(x)+1 max(y)-min(y)+1]);
            end
            for k=1:numel(predicted)
                p=predicted(k); results{end+1}=struct('image_id',find(files==string(p.Image),1),'category_id',find(classes==string(p.Class),1),'segmentation',VIStudioCocoV15.encodeRLE(logical(p.Mask)),'score',p.Score);
            end
            payload=struct('truth',struct('info',struct('description','VI Studio V24'),'images',{num2cell(images)},'categories',{num2cell(categories)},'annotations',{annotations}),'predictions',{results}); raw=VIStudioCocoV15.bridge('evaluate',payload);
            names=["AP50_95";"AP50";"AP75";"APSmall";"APMedium";"APLarge";"AR1";"AR10";"AR100";"ARSmall";"ARMedium";"ARLarge"]; report=struct('Summary',table(names,double(raw.Stats(:)),'VariableNames',{'Metric','Value'}),'Meaning',string(raw.Meaning));
        end
        function evaluation=batch(data,files,results,threshold)
            VIStudioStructuredV15.assertUnchanged(data); files=string(files(:)); assert(numel(unique(files))==numel(files) && numel(results)==numel(files) && ~isempty(files),'VIStudioV15:EvaluationFiles','Require one prediction per unique held-out image.');
            [valid,indices]=ismember(files,data.manifest.File); assert(all(valid) && all(ismember(data.manifest.Split(indices),["test","validation"])),'VIStudioV15:EvaluationSplit','Evaluation only accepts validation/test images.');
            predicted=struct('Image',{},'Class',{},'Mask',{},'Score',{}); truth=struct('Image',{},'Class',{},'Mask',{}); predictedPoses={}; truthPoses={}; images=table();
            for k=1:numel(files)
                file=files(k); r=results{k}; assert(isfield(r,'SourceHash') && string(r.SourceHash)==VIStudioToolsV3.fileHash(file),'VIStudioV15:PredictionSource','Prediction source hash is missing or mismatched.'); objects=data.objects(data.objects.File==file,:);
                if data.schema.Task=="instance"
                    assert(size(r.Masks,3)==numel(r.Labels) && numel(r.Scores)==numel(r.Labels),'VIStudioV15:PredictionCount','Instance output count mismatch.'); info=imfinfo(file); assert(size(r.Masks,1)==info.Height && size(r.Masks,2)==info.Width,'VIStudioV15:MetricSize','Prediction masks differ from source dimensions.');
                    for j=1:numel(r.Labels), assert(any(r.Masks(:,:,j),'all'),'VIStudioV15:PredictionMask','Predicted masks must not be empty.'); predicted(end+1)=struct('Image',file,'Class',string(r.Labels(j)),'Mask',logical(r.Masks(:,:,j)),'Score',double(r.Scores(j))); end
                    for j=1:height(objects), truth(end+1)=struct('Image',file,'Class',objects.Class(j),'Mask',VIStudioMasksV11.mask(objects.MaskFile(j))); end
                    images=[images;table(file,numel(r.Labels),height(objects),'VariableNames',{'File','Predicted','Truth'})];
                else
                    assert(isfield(r,'Poses') && numel(r.Poses)==height(objects),'VIStudioV15:PoseCount','Provide one pose per supplied truth box, including explicit unknown predictions.');
                    for j=1:height(objects), p=VIStudioPoseV15.validate(r.Poses{j},size(imread(file),[1 2])); assert(isequal(p.Box,objects.Box{j}),'VIStudioV15:PosePair','Pose must correspond to supplied object box.'); predictedPoses{end+1}=p; truthPoses{end+1}=objects.Pose{j}; end
                    images=[images;table(file,height(objects),'VariableNames',{'File','TruthObjects'})];
                end
            end
            if data.schema.Task=="instance", detail=VIStudioEvaluationV24.instances(predicted,truth,data.classes); else, detail=VIStudioEvaluationV24.poses(predictedPoses,truthPoses,threshold,false); end
            evaluation=struct('Task',data.schema.Task,'Images',images,'Detailed',detail,'Meaning',detail.Meaning,'Provenance',"Source hashes verified; external prediction training history not verified",'DatasetSnapshot',data.snapshot,'Predictions',{predicted},'Truth',{truth},'Files',files);
        end
        function fig=show(evaluation)
            d=evaluation.Detailed; fig=uifigure('Name','V24 完整評估 / Evaluation','Position',[120 80 1160 820]); grid=uigridlayout(fig,[2 1],'RowHeight',{60,'1x'}); uilabel(grid,'Text',evaluation.Meaning,'WordWrap','on'); tabs=uitabgroup(grid);
            p=uitab(tabs,'Title','總覽 / Summary'); g=uigridlayout(p,[2 1]); uitable(g,'Data',struct2table(d.Summary)); uitable(g,'Data',evaluation.Images);
            if evaluation.Task=="instance"
                p=uitab(tabs,'Title','逐類 / Classes'); g=uigridlayout(p,[1 1]); uitable(g,'Data',d.Classes);
                p=uitab(tabs,'Title','PR 曲線 / Precision–Recall'); g=uigridlayout(p,[1 1]); ax=uiaxes(g); hold(ax,'on');
                for k=1:height(d.Classes), c=d.Curves{k,1}; if ~isempty(c), plot(ax,c.Recall,c.Precision,'DisplayName',char(d.Classes.Class(k))); end, end; xlabel(ax,'Recall @ IoU .50'); ylabel(ax,'Precision'); xlim(ax,[0 1]); ylim(ax,[0 1]); legend(ax,'show');
                p=uitab(tabs,'Title','IoU 門檻 / Thresholds'); g=uigridlayout(p,[1 1]); ax=uiaxes(g); plot(ax,d.IoUThresholds,squeeze(mean(d.AP(:,:,1,3),1,'omitnan')),'-o'); xlabel(ax,'Mask IoU'); ylabel(ax,'Mean AP'); ylim(ax,[0 1]);
                if isfield(evaluation,'Official'), p=uitab(tabs,'Title','官方 COCO / Official'); g=uigridlayout(p,[1 1]); uitable(g,'Data',evaluation.Official.Summary); end
            else
                p=uitab(tabs,'Title','逐點 / Points'); g=uigridlayout(p,[1 1]); uitable(g,'Data',d.Points);
                p=uitab(tabs,'Title','誤差分布 / Error distribution'); g=uigridlayout(p,[1 2]); ax=uiaxes(g); values=[]; if ~isempty(d.Details), values=d.Details.ErrorPx(isfinite(d.Details.ErrorPx)); end; histogram(ax,values); xlabel(ax,'Detected error (pixels)'); ylabel(ax,'Count'); ax=uiaxes(g); plot(ax,d.PCKCurve.Threshold,d.PCKCurve.PCK,'-o'); xlabel(ax,'Normalized threshold'); ylabel(ax,'PCK'); ylim(ax,[0 1]);
                p=uitab(tabs,'Title','逐物件點位 / Details'); g=uigridlayout(p,[1 1]); uitable(g,'Data',d.Details);
            end
            VIStudioThemeV24.install(fig,'模型評估 / Evaluation');
        end
        function report=instances(predicted,truth,classes)
            % Records: Image, Class, Mask; predictions also require Score.
            classes=string(classes(:)); thresholds=.5:.05:.95;
            areas=[0 Inf;0 32^2;32^2 96^2;96^2 Inf]; limits=[1 10 100];
            ap=nan(numel(classes),10,4,3); ar=ap; curves=cell(numel(classes),10);
            for k=1:numel(predicted)
                validateattributes(predicted(k).Score,{'numeric'},{'scalar','finite','>=',0,'<=',1});
                assert(ismember(string(predicted(k).Class),classes),'VIStudioV15:MetricClass','Prediction class is outside the dataset.');
            end
            for c=1:numel(classes)
                p=predicted(string({predicted.Class})==classes(c)); g=truth(string({truth.Class})==classes(c));
                for a=1:4
                    for d=1:3
                        for t=1:10
                            [ap(c,t,a,d),ar(c,t,a,d),curve]=VIStudioEvaluationV24.averagePrecision(p,g,thresholds(t),areas(a,:),limits(d));
                            if a==1 && d==3, curves{c,t}=curve; end
                        end
                    end
                end
            end
            byClass=table(classes,reshape(mean(ap(:,:,1,3),2,'omitnan'),[],1),reshape(ap(:,1,1,3),[],1),reshape(ap(:,6,1,3),[],1),reshape(mean(ar(:,:,1,3),2,'omitnan'),[],1),'VariableNames',{'Class','AP50_95','AP50','AP75','AR100'});
            summary=struct('AP50_95',mean(ap(:,:,1,3),'all','omitnan'),'AP50',mean(ap(:,1,1,3),'omitnan'),'AP75',mean(ap(:,6,1,3),'omitnan'),'APSmall',mean(ap(:,:,2,3),'all','omitnan'),'APMedium',mean(ap(:,:,3,3),'all','omitnan'),'APLarge',mean(ap(:,:,4,3),'all','omitnan'),'AR1',mean(ar(:,:,1,1),'all','omitnan'),'AR10',mean(ar(:,:,1,2),'all','omitnan'),'AR100',mean(ar(:,:,1,3),'all','omitnan'));
            report=struct('Summary',summary,'Classes',byClass,'AP',ap,'AR',ar,'Curves',{curves},'IoUThresholds',thresholds,'RecallThresholds',0:.01:1,'MaxDetections',limits,'AreaRanges',areas,'Meaning',"COCO-style mask AP, non-crowd reviewed instances; not official COCO API certification. AP uses confidence order, 101 recall points, IoU .50:.05:.95, area ranges and maxDets 1/10/100.");
        end
        function [ap,recall,curve]=averagePrecision(p,g,threshold,areaRange,maxDet)
            images=unique([string({p.Image}) string({g.Image})],'stable'); scores=[]; tp=[]; fp=[]; positives=0;
            for image=images
                gi=find(string({g.Image})==image); pi=find(string({p.Image})==image);
                ga=arrayfun(@(x) nnz(x.Mask),g(gi)); ignored=ga<areaRange(1) | ga>areaRange(2);
                [ignored,order]=sort(ignored,'ascend'); gi=gi(order); used=false(numel(gi),1); positives=positives+nnz(~ignored);
                [~,order]=sort([p(pi).Score],'descend'); pi=pi(order(1:min(maxDet,numel(order))));
                for index=pi
                    best=0; overlap=threshold;
                    for j=1:numel(gi)
                        if used(j), continue; end
                        if best>0 && ~ignored(best) && ignored(j), break; end
                        pm=logical(p(index).Mask); gm=logical(g(gi(j)).Mask); assert(isequal(size(pm),size(gm)),'VIStudioV15:MetricSize','Mask sizes must match within an image.');
                        u=nnz(pm|gm); iou=0; if u>0, iou=nnz(pm&gm)/u; end
                        if iou>=overlap, overlap=iou; best=j; end
                    end
                    if best>0
                        used(best)=true; if ignored(best), continue; end
                        hit=true;
                    else
                        pa=nnz(p(index).Mask); if pa<areaRange(1) || pa>areaRange(2), continue; end
                        hit=false;
                    end
                    scores(end+1,1)=p(index).Score; tp(end+1,1)=double(hit); fp(end+1,1)=double(~hit);
                end
            end
            ap=NaN; recall=NaN; curve=table(zeros(0,1),zeros(0,1),zeros(0,1),'VariableNames',{'Score','Recall','Precision'});
            if positives==0, return; end
            if isempty(scores), ap=0; recall=0; return; end
            [scores,order]=sort(scores,'descend'); tp=cumsum(tp(order)); fp=cumsum(fp(order)); r=tp/positives; precision=tp./(tp+fp); envelope=precision;
            for j=numel(envelope)-1:-1:1, envelope(j)=max(envelope(j),envelope(j+1)); end
            sampled=zeros(101,1); levels=0:.01:1; for j=1:101, ix=find(r>=levels(j),1); if ~isempty(ix), sampled(j)=envelope(ix); end, end
            ap=mean(sampled); recall=r(end); curve=table(scores,r,precision,'VariableNames',{'Score','Recall','Precision'});
        end
        function report=poses(predicted,truth,threshold,includeOccluded)
            if nargin<3, threshold=.05; end; if nargin<4, includeOccluded=false; end
            assert(iscell(predicted) && iscell(truth) && numel(predicted)==numel(truth),'VIStudioV15:PosePairs','Provide paired poses; missing predictions must be explicit unknown poses.'); details=table();
            for k=1:numel(truth)
                [rows,~]=VIStudioPoseV15.metrics(predicted{k},truth{k},threshold,includeOccluded); rows.Object=repmat(k,height(rows),1); details=[details;rows];
            end
            points=strings(0,1); if ~isempty(details), points=unique(details.Point,'stable'); end
            perPoint=table();
            for name=points'
                r=details(details.Point==name & details.Evaluated,:); n=height(r); valid=isfinite(r.ErrorPx); pck=NaN; miss=NaN; if n>0, pck=nnz(r.Correct)/n; miss=nnz(~valid)/n; end
                perPoint=[perPoint;table(name,n,pck,miss,mean(r.ErrorPx,'omitnan'),VIStudioEvaluationV24.percentile(r.ErrorPx,50),VIStudioEvaluationV24.percentile(r.ErrorPx,95),'VariableNames',{'Point','Evaluated','PCK','MissRate','MeanDetectedErrorPx','MedianDetectedErrorPx','P95DetectedErrorPx'})];
            end
            evaluated=0; correct=0; errors=[]; if ~isempty(details), evaluated=nnz(details.Evaluated); correct=nnz(details.Correct); errors=details.ErrorPx(details.Evaluated); end
            pck=NaN; miss=NaN; if evaluated>0, pck=correct/evaluated; miss=nnz(~isfinite(errors))/evaluated; end
            levels=[.01 .025 .05 .075 .1 .2]'; values=nan(size(levels)); if evaluated>0, for j=1:numel(levels), values(j)=nnz(details.Evaluated & details.NormalizedError<=levels(j))/evaluated; end, end
            summary=struct('PCK',pck,'Threshold',threshold,'EvaluatedPoints',evaluated,'MissRate',miss,'MeanDetectedErrorPx',mean(errors,'omitnan'),'MedianDetectedErrorPx',VIStudioEvaluationV24.percentile(errors,50),'P95DetectedErrorPx',VIStudioEvaluationV24.percentile(errors,95));
            report=struct('Summary',summary,'Points',perPoint,'Details',details,'PCKCurve',table(levels,values,'VariableNames',{'Threshold','PCK'}),'IncludeOccluded',includeOccluded,'Meaning',"Conditional on paired object boxes; normalized by truth-box diagonal. Missing predictions remain in PCK denominator; error statistics describe detected points only. Not OKS AP.");
        end
        function value=percentile(values,p)
            values=sort(values(isfinite(values))); value=NaN; if isempty(values), return; end; x=1+(numel(values)-1)*p/100; lo=floor(x); hi=ceil(x); value=values(lo)+(x-lo)*(values(hi)-values(lo));
        end
    end
end
