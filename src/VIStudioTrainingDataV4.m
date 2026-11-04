classdef VIStudioTrainingDataV4
    % Data summaries and model catalogue for the separate V4 training UI.
    methods (Static)
        function names=models(task)
            switch string(task)
                case "classification"
                    names=["resnet18","resnet50","mobilenetv2","inceptionv3","xception","densenet201"];
                case "detection"
                    names=["YOLOX-nano","YOLOX-tiny","YOLOX-small","YOLOX-medium","YOLOX-large"];
                case "anomaly"
                    names=["PatchCore / ResNet-18","PatchCore / ResNet-50","FCDD / ResNet-18", ...
                        "EfficientAD / Small","EfficientAD / Medium"];
                otherwise, error('VIStudioV4:InvalidTask','Unknown task.');
            end
        end
        function [samples,summary]=folder(folder)
            ds=imageDatastore(folder,'IncludeSubfolders',true,'LabelSource','foldernames');
            assert(~isempty(ds.Files),'VIStudioV4:EmptyData','資料夾沒有影像。 / No images found.');
            labels=string(ds.Labels); files=string(ds.Files);
            samples=table(files(:),labels(:),zeros(numel(files),1), ...
                'VariableNames',{'File','Label','Objects'});
            classes=unique(labels,'stable'); count=zeros(numel(classes),1);
            for k=1:numel(classes), count(k)=sum(labels==classes(k)); end
            summary=table(classes,count,'VariableNames',{'Class','Count'});
        end
        function [samples,summary,gt]=groundTruth(file)
            loaded=load(file);
            if isfield(loaded,'gTruth'), value=loaded.gTruth;
            elseif isfield(loaded,'exportROI'), value=loaded.exportROI;
            else, error('VIStudioV4:MissingGroundTruth','MAT 需要 gTruth 或 exportROI。 / Missing ground truth.'); end
            gt=VIStudioData.detectionTable(value,fileparts(file));
            files=string(gt.imageFilename); labels=strings(height(gt),1); objects=zeros(height(gt),1);
            classes=string(gt.Properties.VariableNames(2:end))'; count=zeros(numel(classes),1);
            for k=1:height(gt)
                present=strings(0,1);
                for c=1:numel(classes)
                    boxes=gt.(classes(c)){k}; n=size(boxes,1);
                    count(c)=count(c)+n; objects(k)=objects(k)+n;
                    if n>0, present(end+1)=classes(c); end %#ok<AGROW>
                end
                labels(k)=join(present,", ");
            end
            samples=table(files,labels,objects,'VariableNames',{'File','Label','Objects'});
            summary=table(classes,count,'VariableNames',{'Class','Count'});
        end
        function rows=filter(samples,query,label,gt)
            keep=contains(lower(samples.File),lower(string(query)));
            if string(label)~="all"
                if isempty(gt), keep=keep & samples.Label==string(label);
                else
                    column=gt.(string(label)); keep=keep & cellfun(@(b) ~isempty(b),column);
                end
            end
            rows=find(keep);
        end
        function data=prepareDetection(data,target)
            image=data{1}; original=size(image);
            if size(image,3)==1, image=repmat(image,1,1,3); end
            data{1}=imresize(image,target(1:2));
            boxes=data{2}; scale=target([2 1])./original([2 1]);
            data{2}=boxes.*[scale scale];
        end
    end
end
