classdef VIStudioCocoV15
    % Lossless binary RLE exchange; MATLAB coordinates are one-based.
    methods (Static)
        function preview=inspect(file)
            c=jsondecode(fileread(file)); assert(all(isfield(c,{'images','annotations','categories'})),'VIStudioV15:COCO','Require images, annotations and categories.');
            categories=c.categories; names=string({categories.name})'; ids=[categories.id]'; assert(numel(unique(ids))==numel(ids) && numel(unique(names))==numel(names),'VIStudioV15:COCO','Duplicate categories.');
            points=strings(numel(ids),1); for k=1:numel(ids), if isfield(categories(k),'keypoints'), points(k)=strjoin(string(categories(k).keypoints),', '); end, end
            preview=struct('Categories',table(ids,names,names,points,'VariableNames',{'ID','SourceClass','TargetClass','Keypoints'}),'Images',numel(c.images),'Annotations',numel(c.annotations),'Data',c);
        end
        function output=export(data,folder)
            VIStudioStructuredV15.assertUnchanged(data); assert(~isfolder(folder) && ~isfile(folder),'VIStudioV15:FileExists','Choose a new folder.'); mkdir(folder); mkdir(fullfile(folder,'images'));
            images=struct('id',{},'file_name',{},'width',{},'height',{},'vi_split',{},'vi_source',{}); categories=struct('id',{},'name',{},'supercategory',{},'keypoints',{},'skeleton',{});
            for k=1:numel(data.classes)
                names={}; edges=zeros(0,2); if data.schema.Task=="keypoints", names=cellstr(data.schema.Template.Names); edges=data.schema.Template.Edges; end
                edgeCells=cell(size(edges,1),1); for e=1:size(edges,1), edgeCells{e}=edges(e,:); end
                categories(k)=struct('id',k,'name',char(data.classes(k)),'supercategory','object','keypoints',{names},'skeleton',{edgeCells});
            end
            annotations={};
            for k=1:height(data.manifest)
                image=VIStudioData.readImage(data.manifest.File(k),[]); name=sprintf('images/%06d.png',k); imwrite(image,fullfile(folder,name)); images(k)=struct('id',k,'file_name',name,'width',size(image,2),'height',size(image,1),'vi_split',char(data.manifest.Split(k)),'vi_source',char(data.manifest.SourceFile(k)));
                o=data.objects(data.objects.File==data.manifest.File(k),:);
                for j=1:height(o)
                    box=double(o.Box{j}); box(1:2)=box(1:2)-1; a=struct('id',numel(annotations)+1,'image_id',k,'category_id',find(data.classes==o.Class(j),1),'bbox',box,'iscrowd',0,'vi_object_id',char(o.ObjectID(j)));
                    if data.schema.Task=="instance"
                        mask=VIStudioMasksV11.mask(o.MaskFile(j)); a.segmentation=VIStudioCocoV15.encodeRLE(mask); a.area=nnz(mask);
                    else
                        p=o.Pose{j}; xy=p.XY-1; xy(p.Visibility==0,:)=0; a.keypoints=reshape([xy p.Visibility]',1,[]); a.num_keypoints=nnz(p.Visibility>0); a.area=prod(box(3:4));
                    end
                    annotations{end+1}=a;
                end
            end
            c=struct('info',struct('description','VI Studio V15 reviewed dataset','version','15','task',char(data.schema.Task)),'images',{num2cell(images)},'annotations',{annotations},'categories',{num2cell(categories)});
            file=fullfile(folder,'annotations.json'); fid=fopen(file,'w','n','UTF-8'); assert(fid>0); close=onCleanup(@() fclose(fid)); fprintf(fid,'%s',jsonencode(c)); output=string(file);
        end
        function output=import(file,imageRoot,folder,task,mapping)
            preview=VIStudioCocoV15.inspect(file); c=preview.Data; task=string(validatestring(task,{'instance','keypoints'}));
            if nargin<5, mapping=preview.Categories; end
            assert(istable(mapping) && isequal(mapping.ID,preview.Categories.ID) && all(strlength(string(mapping.TargetClass))>0) && numel(unique(string(mapping.TargetClass)))==height(mapping),'VIStudioV15:COCOMapping','Provide one unique nonempty target class per source category.');
            assert(~isfolder(folder) && ~isfile(folder),'VIStudioV15:FileExists','Choose a new folder.');
            assert(isfolder(imageRoot),'VIStudioV15:COCORoot','Image root does not exist.');
            ids=[c.images.id]; assert(numel(unique(ids))==numel(ids),'VIStudioV15:COCO','Duplicate image IDs.');
            if ~isempty(c.annotations), assert(numel(unique([c.annotations.id]))==numel(c.annotations),'VIStudioV15:COCO','Duplicate annotation IDs.'); end
            % Validate all inputs before writing any output.
            files=strings(numel(ids),1); geometries=cell(numel(c.annotations),1); template=[];
            for k=1:numel(ids)
                relative=string(c.images(k).file_name); assert(~startsWith(relative,["/","\"]) && isempty(regexp(char(relative),'(^|[\\/])\.\.([\\/]|$)|^[A-Za-z]:','once')),'VIStudioV15:COCOPath','Image names must be safe relative paths.');
                files(k)=VIStudioToolsV3.canonicalPath(fullfile(imageRoot,relative)); root=VIStudioToolsV3.canonicalPath(imageRoot); assert(startsWith(lower(files(k)),lower(root+filesep)),'VIStudioV15:COCOPath','Image path escapes root.'); info=imfinfo(files(k)); assert(info.Height==c.images(k).height && info.Width==c.images(k).width,'VIStudioV15:COCOSize','Image dimensions differ from COCO metadata.');
            end
            for j=1:numel(c.annotations)
                a=c.annotations(j); k=find(ids==a.image_id,1); category=find(mapping.ID==a.category_id,1); assert(~isempty(k) && ~isempty(category),'VIStudioV15:COCOReference','Unknown image/category ID.');
                assert(~isfield(a,'iscrowd') || a.iscrowd==0,'VIStudioV15:COCOCrowd','Crowd regions are not supported by editable instance truth; split or exclude them explicitly before import.'); assert(~isfield(a,'ignore') || a.ignore==0,'VIStudioV15:COCOIgnore','Ignore annotations cannot be silently converted to ordinary truth.');
                imageSize=[c.images(k).height c.images(k).width];
                if task=="instance"
                    assert(isfield(a,'segmentation'),'VIStudioV15:COCOMask','Segmentation is missing.'); seg=a.segmentation;
                    if isstruct(seg), mask=VIStudioCocoV15.decodeRLE(seg); else
                        % Official rasterization prevents half-pixel boundary drift.
                        if isnumeric(seg), polygons=cell(size(seg,1),1); for z=1:size(seg,1), polygons{z}=seg(z,:); end; seg=polygons; end
                        converted=VIStudioCocoV15.bridge('polygon',struct('segmentation',{seg},'size',imageSize)); mask=VIStudioCocoV15.decodeRLE(converted);
                    end
                    assert(isequal(size(mask),imageSize) && any(mask,'all'),'VIStudioV15:COCOMask','Mask must be nonempty and match image dimensions.'); geometries{j}=mask;
                else
                    names=string(c.categories(category).keypoints(:)); edges=double(c.categories(category).skeleton); if isempty(edges), edges=zeros(0,2); elseif isvector(edges), edges=reshape(edges,1,2); end
                    t=struct('Names',names,'Edges',edges); if isempty(template), template=t; else, assert(isequal(template,t),'VIStudioV15:COCOTemplate','Use a common point template across categories.'); end
                    values=double(a.keypoints(:)); assert(numel(values)==3*numel(names),'VIStudioV15:COCOKeypoints','Point count mismatch.'); values=reshape(values,3,[])'; xy=values(:,1:2)+1; v=values(:,3); xy(v==0,:)=NaN; box=double(a.bbox(:)'); box(1:2)=box(1:2)+1;
                    geometries{j}=VIStudioPoseV15.validate(VIStudioPoseV15.geometry(t,xy,v,box),imageSize);
                end
            end
            doc=VIStudioAnnotationDataV15; doc.loadFiles(files); for k=1:height(mapping), doc.addClass(string(mapping.TargetClass(k))); end
            for j=1:numel(c.annotations)
                a=c.annotations(j); k=find(ids==a.image_id,1); category=find(mapping.ID==a.category_id,1); type='mask'; if task=="keypoints", type='keypoints'; end; doc.add(files(k),string(mapping.TargetClass(category)),type,geometries{j},'imported-reviewed');
            end
            for k=1:numel(files), doc.markReviewed(files(k),true); end
            output=VIStudioStructuredV15.export(doc,folder,task); data=load(output.Path);
            for k=1:numel(files)
                if isfield(c.images(k),'vi_split'), data.manifest.Split(k)=string(c.images(k).vi_split); end
                if isfield(c.images(k),'vi_source'), data.manifest.SourceFile(k)=string(c.images(k).vi_source); end
            end
            for j=1:numel(c.annotations)
                % Export groups records by image; locate the matching row by image-local order.
                a=c.annotations(j); if isfield(a,'vi_object_id'), k=find(ids==a.image_id,1); original=find([c.annotations.image_id]==a.image_id); local=find(original==j); rows=find(data.objects.File==data.manifest.File(k)); data.objects.ObjectID(rows(local))=string(a.vi_object_id); end
            end
            VIStudioStructuredV15.validate(data); manifest=data.manifest; objects=data.objects; classes=data.classes; schema=data.schema; save(output.Path,'manifest','objects','classes','schema','-v7.3'); writetable(manifest,fullfile(folder,'manifest.csv'),'Encoding','UTF-8');
        end
        function rle=encodeRLE(mask)
            assert(islogical(mask) && ismatrix(mask),'VIStudioV15:RLE','Require a logical 2D mask.'); pixels=mask(:); cuts=[1;find(diff(pixels)~=0)+1;numel(pixels)+1]; counts=diff(cuts)'; if ~isempty(pixels) && pixels(1), counts=[0 counts]; end; rle=struct('size',size(mask),'counts',counts);
        end
        function output=bridge(operation,input)
            root=fileparts(mfilename('fullpath')); script=fullfile(root,'tools','vi_coco_bridge_v15.py'); deps=fullfile(root,'V15_Python');
            if ~isfolder(deps), deps=''; end
            try
                raw=pyrunfile(script,'output_json',operation=char(operation),input_json=jsonencode(input),deps_path=deps); output=jsondecode(char(raw));
            catch err
                error('VIStudioV15:COCOPython','Official COCO bridge unavailable. Configure MATLAB pyenv with Python, numpy and pycocotools; native RLE exchange and native AP remain available. Details: %s',err.message);
            end
        end
        function mask=decodeRLE(rle)
            sz=double(rle.size(:)'); validateattributes(sz,{'numeric'},{'numel',2,'integer','positive','finite'}); counts=rle.counts;
            if ischar(counts) || isstring(counts)
                s=double(char(counts))-48; counts=[]; position=1;
                while position<=numel(s)
                    x=0; shift=0;
                    while true
                        assert(position<=numel(s),'VIStudioV15:RLE','Truncated compressed RLE.'); code=s(position); position=position+1; assert(code>=0 && code<=63 && shift<55,'VIStudioV15:RLE','Invalid compressed RLE.'); x=x+bitand(code,31)*2^shift; shift=shift+5;
                        if bitand(code,32)==0, if bitand(code,16)~=0, x=x-2^shift; end; break; end
                    end
                    if numel(counts)>=3, x=x+counts(end-1); end; counts(end+1)=x;
                end
            end
            counts=double(counts(:)); validateattributes(counts,{'numeric'},{'integer','nonnegative','finite'}); assert(sum(counts)==prod(sz),'VIStudioV15:RLE','RLE counts do not match dimensions.'); mask=false(prod(sz),1); cursor=1;
            for k=1:numel(counts), if mod(k,2)==0, mask(cursor:cursor+counts(k)-1)=true; end; cursor=cursor+counts(k); end; mask=reshape(mask,sz);
        end
    end
end
