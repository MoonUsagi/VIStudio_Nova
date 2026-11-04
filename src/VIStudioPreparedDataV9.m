classdef VIStudioPreparedDataV9
    % Split original files first. All variants remain in the training split.
    methods (Static)
        function prepared=build(task,samples,gt,base,o,input,folder,assignedSplit)
            o=VIStudioTrainingOptionsV6.merge(VIStudioTrainingOptionsV6.defaults(),o);
            assert(~isempty(samples),'VIStudioV9:MissingData','Load training data first.');
            assert(~isfolder(folder),'VIStudioV9:PreparedExists','Choose a new prepared-data folder.');
            if task=="detection", assert(ismember(o.SynthMode,["none","noise","copy-paste"]),'VIStudioV9:SynthesisMode','Detection supports noise or annotated copy-paste.');
            else, assert(o.SynthMode~="copy-paste",'VIStudioV9:SynthesisMode','Object copy-paste requires box annotations.'); end
            if nargin<8 || isempty(assignedSplit)
                assignedSplit=repmat("train",height(samples),1);
                if task~="anomaly" && base.Validation>0
                    stream=RandStream('mt19937ar','Seed',o.Seed);
                    strata=unique(samples.Label); if task=="detection", strata="all"; end
                    for stratum=strata'
                        rows=find(samples.Label==stratum); if task=="detection", rows=(1:height(samples))'; end
                        assert(numel(rows)>=2,'VIStudioV9:Split','Each training stratum needs two images for validation.');
                        rows=rows(randperm(stream,numel(rows))); amount=max(1,min(numel(rows)-1,round(numel(rows)*base.Validation/100)));
                        assignedSplit(rows(1:amount))="validation";
                    end
                end
            end
            split=string(assignedSplit(:));
            assert(numel(split)==height(samples) && all(ismember(split,["train","validation","test","calibration"])) && any(split=="train"), ...
                'VIStudioV9:Split','Invalid dataset roles.');
            mkdir(folder); mkdir(fullfile(folder,'images')); mkdir(fullfile(folder,'masks'));
            manifest=table(); classes=strings(0,1); if ~isempty(gt), classes=string(gt.Properties.VariableNames(2:end))'; end
            for row=1:height(samples)
                original=VIStudioData.readImage(samples.File(row),[]);
                boxes=zeros(0,4); labels=strings(0,1);
                if ~isempty(gt)
                    for c=1:numel(classes)
                        current=gt.(classes(c)){row}; boxes=[boxes;current]; %#ok<AGROW>
                        labels=[labels;repmat(classes(c),size(current,1),1)]; %#ok<AGROW>
                    end
                end
                factor=input([2 1])./[size(original,2) size(original,1)];
                image=imresize(original,input(1:2)); boxes=boxes.*[factor factor];
                hash=VIStudioToolsV3.fileHash(samples.File(row));
                variants=0; if split(row)=="train", variants=o.AugmentCopies; end
                for k=0:variants
                    seed=mod(o.Seed+row*1000+k,2^32-1); kind="original"; current=image; b=boxes; l=labels;
                    if k>0
                        kind="augmentation"; [current,b,l]=VIStudioPreparedDataV9.augment(image,boxes,labels,o,seed);
                    end
                    manifest=[manifest;write(current,b,l,[],samples.Label(row),kind,seed,row,split(row),hash)]; %#ok<AGROW>
                end
                if split(row)=="train" && o.SynthMode~="none" && ...
                        (task~="anomaly" || samples.Label(row)==string(base.NormalClass)) && ...
                        (o.SynthMode~="copy-paste" || ~isempty(boxes))
                    for k=1:o.SynthCopies
                        seed=mod(o.Seed+row*1000+100+k,2^32-1);
                        [current,mask,b,l]=VIStudioPreparedDataV9.synthesize(image,boxes,labels,o,seed);
                        label=samples.Label(row); if task=="anomaly", label="__synthetic_anomaly__"; end
                        manifest=[manifest;write(current,b,l,mask,label,"synthetic",seed,row,"train",hash)]; %#ok<AGROW>
                    end
                end
            end
            writetable(manifest,fullfile(folder,'manifest.csv'),'Encoding','UTF-8');
            annotations=[];
            if task=="detection"
                imageFilename=cellstr(manifest.File); annotations=table(imageFilename);
                for c=1:numel(classes)
                    values=cell(height(manifest),1);
                    for k=1:height(manifest)
                        labels=string(jsondecode(manifest.LabelsJSON(k))); labels=labels(:);
                        boxes=VIStudioToolsV3.decodeBoxes(manifest.BoxesJSON(k),manifest.Objects(k));
                        values{k}=boxes(labels==classes(c),:);
                    end
                    annotations.(classes(c))=values;
                end
                exportROI=annotations; save(fullfile(folder,'annotations.mat'),'exportROI');
            end
            prepared=struct('Folder',string(folder),'Manifest',manifest,'Annotations',annotations,'InputSize',input);
            save(fullfile(folder,'preparation.mat'),'prepared','o','base','-v7.3');
            function record=write(im,b,l,mask,label,kind,seed,sourceRow,part,hash)
                index=height(manifest)+1; file=fullfile(folder,'images',sprintf('%06d.png',index)); imwrite(im,file);
                maskFile="";
                if ~isempty(mask), maskFile=string(fullfile(folder,'masks',sprintf('%06d.png',index))); imwrite(logical(mask),maskFile); end
                record=table(string(file),samples.File(sourceRow),string(label),string(part),string(kind),seed, ...
                    size(b,1),string(jsonencode(num2cell(b,2))),string(jsonencode(cellstr(l))),maskFile,string(hash), ...
                    'VariableNames',{'File','SourceFile','Label','Split','Kind','Seed','Objects','BoxesJSON','LabelsJSON','MaskFile','SourceHash'});
            end
        end
        function [image,boxes,labels]=augment(image,boxes,labels,o,seed)
            stream=RandStream('mt19937ar','Seed',seed); h=size(image,1); w=size(image,2);
            angle=(2*rand(stream)-1)*o.Rotation; scale=o.ScaleMin+rand(stream)*(o.ScaleMax-o.ScaleMin);
            signs=[1 1]; if o.FlipLR && rand(stream)<0.5, signs(1)=-1; end
            if o.FlipUD && rand(stream)<0.5, signs(2)=-1; end
            a=scale*[cosd(angle) -sind(angle);sind(angle) cosd(angle)]*diag(signs);
            center=[(w+1)/2 (h+1)/2]; delta=(2*rand(stream,1,2)-1).*o.Translate.*[w h];
            matrix=[a' zeros(2,1);center-center*a'+delta 1]; transform=affine2d(matrix);
            image=imwarp(image,transform,'OutputView',imref2d([h w]));
            if ~isempty(boxes)
                out=zeros(size(boxes)); visible=false(size(boxes,1),1);
                for k=1:size(boxes,1)
                    b=boxes(k,:); points=[b(1:2);b(1)+b(3) b(2);b(1)+b(3) b(2)+b(4);b(1) b(2)+b(4)];
                    points=transformPointsForward(transform,points); lo=min(points); hi=max(points); area=prod(hi-lo);
                    lo=max([1 1],lo); hi=min([w h],hi); sizeBox=max(0,hi-lo);
                    out(k,:)=[lo sizeBox]; visible(k)=all(sizeBox>=1) && prod(sizeBox)>=0.5*area;
                end
                boxes=out(visible,:); labels=labels(visible);
            end
            x=im2double(image); x=(x-0.5)*(1+(2*rand(stream)-1)*o.Contrast)+0.5+(2*rand(stream)-1)*o.Brightness;
            x=x+o.Noise*randn(stream,size(x)); image=im2uint8(min(1,max(0,x)));
        end
        function [image,mask,boxes,labels]=synthesize(image,boxes,labels,o,seed)
            stream=RandStream('mt19937ar','Seed',seed); h=size(image,1); w=size(image,2); mask=false(h,w);
            ph=max(2,round(h*sqrt(o.DefectFraction))); pw=max(2,round(w*sqrt(o.DefectFraction)));
            y=randi(stream,h-ph+1); x=randi(stream,w-pw+1);
            switch o.SynthMode
                case "noise"
                    mask(y:y+ph-1,x:x+pw-1)=true;
                    patch=uint8(randi(stream,256,[ph pw 3])-1); image(y:y+ph-1,x:x+pw-1,:)=patch;
                case "scratch"
                    x2=randi(stream,w); y2=randi(stream,h);
                    for t=linspace(0,1,max(h,w))
                        px=round(x+(x2-x)*t); py=round(y+(y2-y)*t);
                        mask(max(1,py-1):min(h,py+1),max(1,px-1):min(w,px+1))=true;
                    end
                    for c=1:3, layer=image(:,:,c); layer(mask)=uint8(randi(stream,256)-1); image(:,:,c)=layer; end
                case "cutpaste"
                    sourceY=randi(stream,h-ph+1); sourceX=randi(stream,w-pw+1);
                    patch=image(sourceY:sourceY+ph-1,sourceX:sourceX+pw-1,:);
                    patch=im2uint8(min(1,im2double(patch)*0.65+0.3));
                    image(y:y+ph-1,x:x+pw-1,:)=patch; mask(y:y+ph-1,x:x+pw-1)=true;
                case "copy-paste"
                    assert(~isempty(boxes),'VIStudioV9:CopyPaste','Object copy-paste requires a labeled box.');
                    index=randi(stream,size(boxes,1)); b=boxes(index,:);
                    lo=max([1 1],floor(b(1:2))); hi=min([w h],ceil(b(1:2)+b(3:4)));
                    pw=hi(1)-lo(1)+1; ph=hi(2)-lo(2)+1; found=false;
                    for attempt=1:200
                        x=randi(stream,w-pw+1); y=randi(stream,h-ph+1); proposed=[x y pw ph];
                        if all(bboxOverlapRatio(proposed,boxes)==0), found=true; break; end
                    end
                    assert(found,'VIStudioV9:CopyPaste','No empty location for this object. Reduce copies or choose noise synthesis.');
                    patch=image(lo(2):hi(2),lo(1):hi(1),:); image(y:y+ph-1,x:x+pw-1,:)=patch;
                    boxes=[boxes;proposed]; labels=[labels;labels(index)]; mask(y:y+ph-1,x:x+pw-1)=true;
                otherwise, error('VIStudioV9:SynthesisMode','Select a synthesis mode first.');
            end
        end
    end
end
