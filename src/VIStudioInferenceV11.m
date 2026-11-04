classdef VIStudioInferenceV11
    methods (Static)
        function a=load(file,task)
            a=VIStudioModelIOV8.read(file,task); a.Task=string(task);
        end
        function p=run(a,image,environment,honorROI)
            if nargin<3, environment='cpu'; end; if nargin<4, honorROI=true; end
            assert(isfile(a.File) && VIStudioToolsV3.fileHash(a.File)==a.Digest,'VIStudioV11:ChangedModel','Model file changed; reload it.');
            timer=tic; originalSize=size(image,[1 2]); roi=[];
            if honorROI && isfield(a.Metadata,'InspectionROI'), roi=a.Metadata.InspectionROI; end
            [input,roi]=VIStudioToolsV3.cropImage(image,roi); md=a.Metadata;
            p=struct('Task',a.Task,'Label',"",'Confidence',NaN,'Scores',[],'Classes',a.Classes,'Boxes',zeros(0,4),'BoxLabels',strings(0,1), ...
                'Mask',[],'Map',[],'ROI',roi,'Decision',"REVIEW",'Calibrated',false,'ImageThreshold',NaN,'PixelThreshold',NaN,'Milliseconds',0,'ModelDigest',a.Digest);
            threshold=.5; if isfield(md,'Threshold') && ~isempty(md.Threshold), threshold=double(md.Threshold); end
            if a.Task=="classification"
                input=imresize(input,a.InputSize(1:2)); if a.InputSize(3)==1, input=rgb2gray(input); end
                scores=gather(extractdataIfNeeded(minibatchpredict(a.Model,input,'ExecutionEnvironment',environment))); scores=double(scores(:));
                assert(numel(scores)==numel(a.Classes) && all(isfinite(scores)),'VIStudioV11:Scores','Class score count is invalid.');
                if any(scores<0) || any(scores>1) || abs(sum(scores)-1)>1e-3, scores=exp(scores-max(scores)); end
                scores=scores/sum(scores); [p.Confidence,index]=max(scores); p.Label=a.Classes(index); p.Scores=scores;
                if p.Confidence>=threshold, p.Decision="CLASSIFIED"; end
            elseif a.Task=="detection"
                [boxes,scores,labels]=detect(a.Model,input,'Threshold',threshold,'ExecutionEnvironment',environment);
                scores=double(scores(:)); labels=string(labels(:)); boxes=double(boxes); keep=scores>=threshold;
                boxes=boxes(keep,:); scores=scores(keep); labels=labels(keep); boxes(:,1:2)=boxes(:,1:2)+roi(1:2)-1;
                p.Boxes=boxes; p.Scores=scores; p.BoxLabels=labels; p.Label=join(unique(labels),', '); p.Decision="DETECTED";
                if ~isempty(scores), p.Confidence=max(scores); end
            else
                input=imresize(input,a.InputSize(1:2)); p.Confidence=double(predict(a.Model,input,'ExecutionEnvironment',environment));
                map=anomalyMap(a.Model,input,'ExecutionEnvironment',environment); map=double(gather(extractdataIfNeeded(map))); validateattributes(map,{'numeric'},{'2d','finite','real'}); p.Map=map;
                if isprop(a.Model,'Threshold') && ~isempty(a.Model.Threshold), threshold=double(a.Model.Threshold); p.Calibrated=true; end
                if isfield(md,'Calibrated'), p.Calibrated=logical(md.Calibrated); end
                if p.Calibrated
                    p.ImageThreshold=threshold; p.Label="Normal"; p.Decision="OK";
                    if p.Confidence>=threshold, p.Label="Anomaly"; p.Decision="NG"; end
                else, p.Label="Uncalibrated"; end
                if isfield(md,'PixelThreshold') && ~isempty(md.PixelThreshold)
                    p.PixelThreshold=double(md.PixelThreshold); validateattributes(p.PixelThreshold,{'numeric'},{'scalar','finite','nonnegative'});
                    local=imresize(map>=p.PixelThreshold,roi([4 3]),'nearest'); p.Mask=false(originalSize); p.Mask(roi(2)+(0:roi(4)-1),roi(1)+(0:roi(3)-1))=local;
                end
            end
            p.Milliseconds=1000*toc(timer);
            function x=extractdataIfNeeded(x), if isa(x,'dlarray'), x=extractdata(x); end, end
        end
        function result=compare(a,b,image,environment)
            if nargin<4, environment='cpu'; end
            assert(a.Task==b.Task,'VIStudioV11:CompareTask','Compare models from the same task.');
            first=VIStudioInferenceV11.run(a,image,environment); second=VIStudioInferenceV11.run(b,image,environment);
            difference=first.Label~=second.Label; maskIoU=NaN; unmatched=NaN;
            if a.Task=="anomaly"
                difference=first.Decision~=second.Decision;
                if ~isempty(first.Mask) && ~isempty(second.Mask)
                    metrics=VIStudioMasksV11.metrics(first.Mask,second.Mask); maskIoU=metrics.IoU; difference=difference || maskIoU<.8;
                end
            elseif a.Task=="detection"
                used=false(size(second.Boxes,1),1); matched=0;
                for k=1:size(first.Boxes,1)
                    candidates=find(~used & second.BoxLabels==first.BoxLabels(k)); if isempty(candidates), continue; end
                    overlap=bboxOverlapRatio(first.Boxes(k,:),second.Boxes(candidates,:)); [best,j]=max(overlap);
                    if best>=.5, used(candidates(j))=true; matched=matched+1; end
                end
                unmatched=size(first.Boxes,1)+size(second.Boxes,1)-2*matched; difference=unmatched>0;
            end
            result=struct('First',first,'Second',second,'Disagree',difference,'MaskIoU',maskIoU,'UnmatchedDetections',unmatched, ...
                'Summary',table(["A";"B"],[first.Label;second.Label],[first.Confidence;second.Confidence], ...
                [first.Decision;second.Decision],[first.Milliseconds;second.Milliseconds], ...
                'VariableNames',{'Model','Label','Score','Decision','Milliseconds'}));
        end
        function image=overlay(image,p)
            if p.Task=="detection" && ~isempty(p.Boxes), image=insertObjectAnnotation(image,'rectangle',p.Boxes,cellstr(p.BoxLabels));
            elseif p.Task=="anomaly" && ~isempty(p.Mask), image=labeloverlay(image,p.Mask,'Transparency',.65); end
            image=insertText(image,[1 1],char(p.Label+" | "+p.Decision),'FontSize',12,'BoxOpacity',.6);
        end
    end
end
