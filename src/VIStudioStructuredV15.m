classdef VIStudioStructuredV15
    methods (Static)
        function output=export(doc,folder,task)
            task=string(validatestring(task,{'instance','keypoints'})); assert(~isfolder(folder) && ~isfile(folder),'VIStudioV15:FileExists','Choose a new output folder.'); files=doc.Files(doc.Reviewed); assert(~isempty(files),'VIStudioV15:Unreviewed','Review at least one image.');
            rows=doc.Annotations(ismember(doc.Annotations.File,files) & doc.Annotations.Reviewed,:); if task=="instance", assert(~any(rows.Label=="__ignore__"),'VIStudioV15:InstanceIgnore','Instance training does not yet support ignore regions.'); rows=rows(ismember(rows.Type,["mask","rectangle","polygon"]),:); else, rows=rows(rows.Type=="keypoints",:); end
            assert(~isempty(rows),'VIStudioV15:StructuredEmpty','No reviewed annotations for this task.'); classes=unique(rows.Label,'stable'); mkdir(folder); mkdir(fullfile(folder,'images')); mkdir(fullfile(folder,'masks'));
            manifest=table(strings(numel(files),1),repmat("train",numel(files),1),files,'VariableNames',{'File','Split','SourceFile'}); objects=table(strings(0,1),strings(0,1),strings(0,1),strings(0,1),cell(0,1),cell(0,1),'VariableNames',{'File','ObjectID','Class','MaskFile','Box','Pose'});
            template=[];
            for k=1:numel(files)
                image=VIStudioData.readImage(files(k),[]); file=string(fullfile(folder,'images',sprintf('%06d.png',k))); imwrite(image,file); manifest.File(k)=file; current=rows(rows.File==files(k),:);
                for j=1:height(current)
                    maskFile=""; pose=[];
                    if task=="instance"
                        mask=doc.rasterize(current.Type(j),current.Geometry{j},size(image,[1 2])); [y,x]=find(mask); box=[min(x) min(y) max(x)-min(x)+1 max(y)-min(y)+1]; maskFile=string(fullfile(folder,'masks',sprintf('%06d_%04d.png',k,j))); imwrite(mask,maskFile);
                    else
                        pose=VIStudioPoseV15.validate(current.Geometry{j},size(image,[1 2])); box=pose.Box;
                        if isempty(template), template=struct('Names',pose.Names,'Edges',pose.Edges); else, assert(isequal(template.Names,pose.Names) && isequal(template.Edges,pose.Edges),'VIStudioV15:PoseTemplate','Use one keypoint template per exported dataset.'); end
                    end
                    objects(end+1,:)={file,current.InstanceID(j),current.Label(j),maskFile,{box},{pose}};
                end
            end
            schema=struct('Version',15,'Task',task,'Template',template,'VisibilityConvention',"0 unknown / 1 occluded / 2 visible"); save(fullfile(folder,'dataset.mat'),'manifest','objects','classes','schema','-v7.3'); writetable(manifest,fullfile(folder,'manifest.csv'),'Encoding','UTF-8'); output=struct('Task',task,'Path',string(fullfile(folder,'dataset.mat')),'Images',string(fullfile(folder,'images')));
        end
        function data=read(file)
            data=load(file); assert(all(isfield(data,{'manifest','objects','classes','schema'})) && ismember(data.schema.Version,[14 15]),'VIStudioV15:StructuredDataset','Require a V15 structured dataset.'); base=fileparts(file);
            for f={'File','SourceFile'}, if ~ismember(f{1},data.manifest.Properties.VariableNames), continue; end; data.manifest.(f{1})=string(data.manifest.(f{1})); end
            data.manifest.Split=string(data.manifest.Split); data.objects.File=string(data.objects.File); data.objects.MaskFile=string(data.objects.MaskFile); data.objects.Class=string(data.objects.Class); data.objects.ObjectID=string(data.objects.ObjectID); data.classes=string(data.classes(:));
            for k=1:height(data.manifest), data.manifest.File(k)=VIStudioStructuredV15.resolve(data.manifest.File(k),base); end
            for k=1:height(data.objects), data.objects.File(k)=VIStudioStructuredV15.resolve(data.objects.File(k),base); if strlength(data.objects.MaskFile(k))>0, data.objects.MaskFile(k)=VIStudioStructuredV15.resolve(data.objects.MaskFile(k),base); end, end
            data.snapshot=VIStudioStructuredV15.validate(data);
        end
        function snapshot=validate(data)
            task=string(validatestring(data.schema.Task,{'instance','keypoints'})); m=data.manifest; o=data.objects; assert(~isempty(m) && numel(unique(lower(string(m.File))))==height(m) && all(ismember(m.Split,["train","validation","test","calibration"])),'VIStudioV15:StructuredManifest','Invalid image roles or repeated source.');
            assert(numel(unique(o.ObjectID))==height(o) && all(ismember(o.File,m.File)) && all(ismember(o.Class,string(data.classes))),'VIStudioV15:StructuredObjects','Object identity, source or class is invalid.'); pixels=strings(height(m),1); hashes=pixels; labels=strings(height(o),1);
            for k=1:height(m), image=VIStudioData.readImage(m.File(k),[]); pixels(k)=VIStudioDataHealthV8.pixelHash(image); hashes(k)=VIStudioToolsV3.fileHash(m.File(k)); end
            for hash=unique(pixels)', assert(numel(unique(m.Split(pixels==hash)))==1,'VIStudioV15:StructuredLeak','Identical images cross dataset roles.'); end
            if ismember('SourceFile',m.Properties.VariableNames), for source=unique(string(m.SourceFile))', if strlength(source)>0, assert(numel(unique(m.Split(string(m.SourceFile)==source)))==1,'VIStudioV15:StructuredLeak','Derived images from one source cross roles.'); end, end, end
            for k=1:height(o)
                info=imfinfo(o.File(k)); box=o.Box{k}; VIStudioAnnotationDataV15.validateGeometry(o.File(k),'rectangle',box);
                if task=="instance", mask=VIStudioMasksV11.mask(o.MaskFile(k)); assert(isequal(size(mask),[info.Height info.Width]) && any(mask,'all'),'VIStudioV15:InstanceMask','Instance mask must be nonempty and match image size.'); [y,x]=find(mask); assert(isequal(double(box),[min(x) min(y) max(x)-min(x)+1 max(y)-min(y)+1]),'VIStudioV15:InstanceBox','Box must bound its instance mask.'); labels(k)=VIStudioToolsV3.fileHash(o.MaskFile(k));
                else, pose=VIStudioPoseV15.validate(o.Pose{k},[info.Height info.Width]); assert(isequal(pose.Names,string(data.schema.Template.Names(:))) && isequal(pose.Edges,data.schema.Template.Edges),'VIStudioV15:PoseTemplate','Dataset template mismatch.'); labels(k)=VIStudioDatasetV9.digest(jsonencode(pose)); end
            end
            snapshot=m; snapshot.SourceHash=hashes; snapshot.PixelHash=pixels; snapshot.ObjectFingerprint=repmat(VIStudioDatasetV9.digest(jsonencode(struct('Objects',o.ObjectID,'Classes',o.Class,'Boxes',{o.Box},'Labels',labels,'Schema',data.schema))),height(m),1);
        end
        function snapshot=assertUnchanged(data)
            snapshot=VIStudioStructuredV15.validate(data);
            if isfield(data,'snapshot'), assert(isequal(snapshot.SourceHash,data.snapshot.SourceHash) && isequal(snapshot.ObjectFingerprint,data.snapshot.ObjectFingerprint),'VIStudioV15:StructuredChanged','Images or labels changed after loading; reload the dataset.'); end
        end
        function value=resolve(value,base)
            value=string(value); absolute=startsWith(value,"/") || startsWith(value,"\") || ~isempty(regexp(char(value),'^[A-Za-z]:[\\/]','once')); if ~absolute, value=fullfile(base,value); end; assert(isfile(value),'VIStudioV15:StructuredMissing','Missing image or mask.'); value=VIStudioToolsV3.canonicalPath(value);
        end
        function ds=instanceDatastore(data,role)
            VIStudioStructuredV15.validate(data); m=data.manifest(data.manifest.Split==string(role),:); assert(~isempty(m),'VIStudioV15:StructuredRole','No images for requested role.'); array=arrayDatastore((1:height(m))','IterationDimension',1); ds=transform(array,@sample);
            function result=sample(index)
                if iscell(index), index=index{1}; end; file=m.File(index); image=VIStudioData.readImage(file,[]); objects=data.objects(data.objects.File==file,:); masks=false(size(image,1),size(image,2),height(objects)); boxes=zeros(height(objects),4); for n=1:height(objects), masks(:,:,n)=VIStudioMasksV11.mask(objects.MaskFile(n)); boxes(n,:)=objects.Box{n}; end
                result={image,boxes,categorical(objects.Class,data.classes,data.classes),masks};
            end
        end
        function ds=poseDatastore(data,role)
            VIStudioStructuredV15.validate(data); files=data.manifest.File(data.manifest.Split==string(role)); objects=data.objects(ismember(data.objects.File,files),:); assert(~isempty(objects),'VIStudioV15:StructuredRole','No poses for requested role.');
            for k=1:height(objects), assert(all(objects.Pose{k}.Visibility==2),'VIStudioV15:PoseNativeVisibility','Native HRNet training adapter currently requires fully visible points; retain other annotations for review/evaluation.'); end
            keypoints=cell(height(objects),1); boxes=keypoints; for k=1:height(objects), keypoints{k}=objects.Pose{k}.XY; boxes{k}=objects.Box{k}; end
            points=table(keypoints); bounds=table(boxes,'VariableNames',{'object'}); ds=combine(imageDatastore(cellstr(objects.File)),arrayDatastore(points),boxLabelDatastore(bounds));
        end
        function result=instanceMetrics(predicted,truth,threshold)
            if nargin<3, threshold=.5; end; validateattributes(threshold,{'numeric'},{'scalar','>',0,'<=',1}); n=numel(predicted); m=numel(truth); pairs=zeros(0,3);
            for i=1:n, for j=1:m, if string(predicted(i).Class)==string(truth(j).Class), p=predicted(i).Mask; t=truth(j).Mask; assert(isequal(size(p),size(t)),'VIStudioV15:InstanceMetricSize','Masks must match.'); union=nnz(p | t); overlap=0; if union>0, overlap=nnz(p & t)/union; end; pairs(end+1,:)=[i j overlap]; end, end, end
            if ~isempty(pairs), pairs=sortrows(pairs,-3); end; usedP=false(n,1); usedT=false(m,1); matched=zeros(0,3);
            for k=1:size(pairs,1), p=pairs(k,1); t=pairs(k,2); if pairs(k,3)>=threshold && ~usedP(p) && ~usedT(t), usedP(p)=true; usedT(t)=true; matched(end+1,:)=pairs(k,:); end, end
            tp=size(matched,1); precision=NaN; recall=NaN; if n>0, precision=tp/n; end; if m>0, recall=tp/m; end
            result=struct('Threshold',threshold,'TP',tp,'FP',n-tp,'FN',m-tp,'Precision',precision,'Recall',recall,'MeanMatchedIoU',mean(matched(:,3)),'CountError',n-m,'Matches',matched);
        end
    end
end
