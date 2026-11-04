classdef VIStudioAnnotationDataV15 < handle
    properties (SetAccess=private)
        Files=strings(0,1)
        Classes=table(strings(0,1),zeros(0,3),strings(0,1),'VariableNames',{'Name','Color','Description'})
        Annotations=table(strings(0,1),strings(0,1),strings(0,1),strings(0,1),cell(0,1),strings(0,1),zeros(0,1),false(0,1),strings(0,1), ...
            'VariableNames',{'ID','File','Label','Type','Geometry','Source','Score','Reviewed','ModelDigest'})
        Reviewed=false(0,1)
        Dirty=false
        Revision=0
    end
    properties (Access=private)
        UndoStack={}
        RedoStack={}
    end
    methods
        function doc=VIStudioAnnotationDataV15
            doc.Annotations=VIStudioAnnotationDataV15.upgrade(doc.Annotations);
        end
        function output=exportSemantic(doc,folder,conflict)
            if nargin<3, conflict='error'; end
            rows=doc.Annotations(ismember(doc.Annotations.File,doc.Files(doc.Reviewed)),:); assert(~any(rows.Type=="keypoints"),'VIStudioV15:PoseExportTask','Export keypoints separately; do not silently discard them in semantic export.');
            output=VIStudioSemanticV12.exportAnnotations(doc,folder,conflict);
        end
        function ids=splitInstance(doc,id)
            row=doc.row(id); r=doc.Annotations(row,:); assert(ismember(r.Type,["mask","polygon","rectangle"]),'VIStudioV15:InstanceType','Select a region.'); info=imfinfo(r.File); mask=doc.rasterize(r.Type,r.Geometry{1},[info.Height info.Width]); cc=bwconncomp(mask,8); assert(cc.NumObjects>1,'VIStudioV15:InstanceSplit','Erase a separating gap first; select a region with disconnected components.');
            doc.remember(); doc.Annotations(row,:)=[]; ids=strings(cc.NumObjects,1);
            for k=1:cc.NumObjects, current=false(size(mask)); current(cc.PixelIdxList{k})=true; entry=r; entry.ID=doc.newID(); entry.InstanceID=entry.ID; entry.Type="mask"; entry.Geometry={current}; entry.Source="manual-split"; entry.Reviewed=true; doc.Annotations=[doc.Annotations;entry]; ids(k)=entry.ID; end
            doc.Reviewed(doc.Files==r.File)=false;
        end
        function id=mergeInstances(doc,ids)
            ids=string(ids); assert(numel(ids)>=2 && numel(unique(ids))==numel(ids),'VIStudioV15:InstanceSelection','Select at least two different instances.'); indices=zeros(numel(ids),1); for k=1:numel(ids), indices(k)=doc.row(ids(k)); end
            rows=doc.Annotations(indices,:); assert(numel(unique(rows.File))==1 && numel(unique(rows.Label))==1 && all(ismember(rows.Type,["mask","polygon","rectangle"])),'VIStudioV15:InstanceMerge','Merge only regions with the same image and class.'); info=imfinfo(rows.File(1)); mask=false(info.Height,info.Width); for k=1:height(rows), mask=mask | doc.rasterize(rows.Type(k),rows.Geometry{k},size(mask)); end
            doc.remember(); entry=rows(1,:); entry.ID=doc.newID(); entry.InstanceID=entry.ID; entry.Type="mask"; entry.Geometry={mask}; entry.Source="manual-merge"; entry.Reviewed=true; doc.Annotations(indices,:)=[]; doc.Annotations=[doc.Annotations;entry]; doc.Reviewed(doc.Files==entry.File)=false; id=entry.ID;
        end
        function id=addKeypoints(doc,file,label,geometry,source,score,digest)
            if nargin<5, source="manual"; end; if nargin<6, score=NaN; end; if nargin<7, digest=""; end
            id=doc.add(file,label,'keypoints',geometry,source,score,digest); row=doc.row(id); doc.Annotations.Keypoints{row}=geometry.XY; doc.Annotations.Visibility{row}=geometry.Visibility;
        end
        function output=exportStructured(doc,folder,task), output=VIStudioStructuredV15.export(doc,folder,task); end
        function importStructured(doc,file)
            data=VIStudioStructuredV15.read(file); doc.remember(); doc.Files=data.manifest.File; names=string(data.classes(:)); doc.Classes=table(names,lines(numel(names)),repmat("",numel(names),1),'VariableNames',{'Name','Color','Description'}); doc.Annotations=doc.Annotations([],:); doc.Reviewed=true(numel(doc.Files),1);
            for k=1:height(data.objects)
                object=data.objects(k,:); geometry=object.Pose{1}; type="keypoints"; if data.schema.Task=="instance", geometry=VIStudioMasksV11.mask(object.MaskFile); type="mask"; end
                id=doc.newID(); entry=table(id,object.File,object.Class,type,{geometry},"imported-reviewed",NaN,true,"",'VariableNames',doc.Annotations.Properties.VariableNames(1:9)); entry=doc.upgrade(entry); entry.InstanceID=object.ObjectID; if type=="keypoints", entry.Keypoints={geometry.XY}; entry.Visibility={geometry.Visibility}; end; doc.Annotations=[doc.Annotations;entry];
            end
            doc.validateState(); doc.Dirty=true;
        end
        function loadFiles(doc,files)
            files=string(files); files=unique(files(:),'stable'); assert(~isempty(files) && all(isfile(files)),'VIStudioV15:LabelImages','Images are missing.');
            for k=1:numel(files), files(k)=VIStudioToolsV3.canonicalPath(files(k)); VIStudioData.readImage(files(k),[]); end
            doc.remember(); doc.Files=files; doc.Annotations=doc.Annotations([],:); doc.Reviewed=false(numel(files),1); doc.Dirty=true;
        end
        function addClass(doc,name,color,description)
            if nargin<3, color=[.1 .7 .4]; end
            if nargin<4, description=""; end
            name=doc.checkName(name); assert(~ismember(name,doc.Classes.Name),'VIStudioV15:LabelClass','Class already exists.');
            validateattributes(color,{'numeric'},{'size',[1 3],'finite','>=',0,'<=',1});
            doc.remember(); doc.Classes=[doc.Classes;table(name,double(color),string(description),'VariableNames',doc.Classes.Properties.VariableNames)];
        end
        function mergeClasses(doc,names)
            names=unique(string(names(:)),'stable');
            for k=1:numel(names), doc.checkName(names(k)); end
            names=names(~ismember(names,doc.Classes.Name)); if isempty(names), return; end
            colors=lines(height(doc.Classes)+numel(names)); colors=colors(height(doc.Classes)+1:end,:);
            doc.remember(); doc.Classes=[doc.Classes;table(names,colors,repmat("",numel(names),1),'VariableNames',doc.Classes.Properties.VariableNames)];
        end
        function renameClass(doc,old,new)
            new=doc.checkName(new); index=find(doc.Classes.Name==string(old),1);
            assert(~isempty(index) && ~ismember(new,doc.Classes.Name),'VIStudioV15:LabelClass','Class is missing or the new name already exists.');
            doc.remember(); doc.Classes.Name(index)=new; doc.Annotations.Label(doc.Annotations.Label==string(old))=new;
        end
        function deleteClass(doc,name,removeAnnotations)
            if nargin<3, removeAnnotations=false; end
            name=string(name); assert(ismember(name,doc.Classes.Name),'VIStudioV15:LabelClass','Unknown class.');
            rows=doc.Annotations.Label==name;
            assert(~any(rows) || removeAnnotations,'VIStudioV15:ClassInUse','Class has annotations; confirm their removal or rename the class.');
            doc.remember(); doc.Reviewed(ismember(doc.Files,doc.Annotations.File(rows)))=false;
            doc.Annotations(rows,:)=[]; doc.Classes(doc.Classes.Name==name,:)=[];
        end
        function id=add(doc,file,label,type,geometry,source,score,digest)
            if nargin<6, source="manual"; end
            if nargin<7, score=NaN; end
            if nargin<8, digest=""; end
            file=VIStudioToolsV3.canonicalPath(file); label=string(label); type=string(type);
            assert(ismember(file,doc.Files) && ismember(label,doc.Classes.Name),'VIStudioV15:Annotation','Unknown image or class.');
            geometry=doc.validateGeometry(file,type,geometry);
            validateattributes(score,{'numeric'},{'scalar','real'}); assert(isnan(score) || isfinite(score),'VIStudioV15:Annotation','Invalid score.');
            doc.remember();
            if type=="image", doc.Annotations(doc.Annotations.File==file & doc.Annotations.Type=="image",:)=[]; end
            id=doc.newID(); reviewed=string(source)~="model";
            entry=table(id,file,label,type,{geometry},string(source),double(score),reviewed,string(digest), ...
                'VariableNames',doc.Annotations.Properties.VariableNames(1:9)); entry=VIStudioAnnotationDataV15.upgrade(entry); doc.Annotations=[doc.Annotations;entry]; doc.Reviewed(doc.Files==file)=false;
        end
        function update(doc,id,geometry,label)
            row=doc.row(id); if nargin<4, label=doc.Annotations.Label(row); end
            assert(ismember(string(label),doc.Classes.Name),'VIStudioV15:LabelClass','Unknown class.');
            geometry=doc.validateGeometry(doc.Annotations.File(row),doc.Annotations.Type(row),geometry);
            doc.remember(); doc.Annotations.Geometry{row}=geometry; doc.Annotations.Label(row)=string(label);
            if doc.Annotations.Type(row)=="keypoints", doc.Annotations.Keypoints{row}=geometry.XY; doc.Annotations.Visibility{row}=geometry.Visibility; end
            doc.Annotations.Reviewed(row)=true; doc.Reviewed(doc.Files==doc.Annotations.File(row))=false;
            if doc.Annotations.Source(row)=="model", doc.Annotations.Source(row)="model-edited"; end
        end
        function remove(doc,id)
            row=doc.row(id); doc.remember(); doc.Reviewed(doc.Files==doc.Annotations.File(row))=false; doc.Annotations(row,:)=[];
        end
        function accept(doc,file,id)
            file=VIStudioToolsV3.canonicalPath(file); rows=doc.Annotations.File==file & ~doc.Annotations.Reviewed;
            if nargin>2 && strlength(string(id))>0, rows=rows & doc.Annotations.ID==string(id); end
            if any(rows), doc.remember(); doc.Annotations.Reviewed(rows)=true; end
        end
        function reviewCandidates(doc,files,decision,ids)
            files=string(files(:)); assert(all(ismember(files,doc.Files)),'VIStudioV15:ReviewFiles','Choose loaded images.'); decision=string(validatestring(decision,{'accept','reject'})); rows=ismember(doc.Annotations.File,files) & ~doc.Annotations.Reviewed & doc.Annotations.Source=="model";
            if nargin>3, ids=string(ids); assert(all(ismember(ids,doc.Annotations.ID(rows))),'VIStudioV15:Candidates','Only pending AI candidates can be selected.'); rows=rows & ismember(doc.Annotations.ID,ids); end
            if ~any(rows), return; end; doc.remember(); doc.Reviewed(ismember(doc.Files,doc.Annotations.File(rows)))=false;
            if decision=="accept", doc.Annotations.Reviewed(rows)=true; else, doc.Annotations(rows,:)=[]; end
        end
        function reject(doc,file)
            rows=doc.Annotations.File==VIStudioToolsV3.canonicalPath(file) & ~doc.Annotations.Reviewed & doc.Annotations.Source=="model";
            if any(rows), doc.remember(); doc.Annotations(rows,:)=[]; end
        end
        function markReviewed(doc,file,value)
            if nargin<3, value=true; end
            file=VIStudioToolsV3.canonicalPath(file); index=find(doc.Files==file,1);
            assert(~isempty(index),'VIStudioV15:LabelImages','Unknown image.'); validateattributes(value,{'logical'},{'scalar'});
            assert(~value || ~any(doc.Annotations.File==file & ~doc.Annotations.Reviewed), ...
                'VIStudioV15:PendingAnnotations','Accept, correct or reject pending predictions before marking this image reviewed.');
            doc.remember(); doc.Reviewed(index)=value;
        end
        function applyPredictions(doc,file,labels,types,geometries,scores,digest)
            file=VIStudioToolsV3.canonicalPath(file); labels=string(labels(:)); types=string(types(:)); scores=double(scores(:));
            assert(ismember(file,doc.Files) && numel(labels)==numel(types) && numel(types)==numel(geometries) && ...
                numel(scores)==numel(labels) && all(isfinite(scores)),'VIStudioV15:Predictions','Prediction lengths or scores are invalid.');
            assert(sum(types=="image")<=1,'VIStudioV15:Predictions','Only one image-level class prediction is allowed.');
            for k=1:numel(labels), doc.checkName(labels(k)); geometries{k}=doc.validateGeometry(file,types(k),geometries{k}); end
            % One snapshot for an entire prediction pass, including new classes.
            doc.remember(); remove=doc.Annotations.File==file & doc.Annotations.Source=="model" & ~doc.Annotations.Reviewed;
            doc.Annotations(remove,:)=[]; palette=lines(max(7,height(doc.Classes)+numel(labels)));
            for k=1:numel(labels)
                if ~ismember(labels(k),doc.Classes.Name)
                    doc.Classes=[doc.Classes;table(labels(k),palette(height(doc.Classes)+1,:),"",'VariableNames',doc.Classes.Properties.VariableNames)];
                end
                existing=doc.Annotations(doc.Annotations.File==file & doc.Annotations.Label==labels(k) & doc.Annotations.Reviewed,:);
                duplicate=false;
                if types(k)=="rectangle"
                    for j=1:height(existing)
                        if existing.Type(j)=="rectangle" && bboxOverlapRatio(geometries{k},existing.Geometry{j})>.8, duplicate=true; break; end
                    end
                elseif types(k)=="image"
                    duplicate=any(doc.Annotations.File==file & doc.Annotations.Type=="image" & doc.Annotations.Reviewed);
                end
                if duplicate, continue; end
                id=doc.newID();
                entry=table(id,file,labels(k),types(k),{geometries{k}},"model",scores(k),false,string(digest), ...
                    'VariableNames',doc.Annotations.Properties.VariableNames(1:9)); doc.Annotations=[doc.Annotations;VIStudioAnnotationDataV15.upgrade(entry)];
            end
            doc.Reviewed(doc.Files==file)=false;
        end
        function undo(doc)
            if isempty(doc.UndoStack), return; end
            doc.RedoStack{end+1}=doc.snapshot(); value=doc.UndoStack{end}; doc.UndoStack(end)=[]; doc.restore(value); doc.Dirty=true; doc.Revision=doc.Revision+1;
        end
        function redo(doc)
            if isempty(doc.RedoStack), return; end
            doc.UndoStack{end+1}=doc.snapshot(); value=doc.RedoStack{end}; doc.RedoStack(end)=[]; doc.restore(value); doc.Dirty=true; doc.Revision=doc.Revision+1;
        end
        function [undo,redo]=history(doc), undo=numel(doc.UndoStack); redo=numel(doc.RedoStack); end
        function state=recoveryState(doc), state=doc.snapshot(); state.Version=15; end
        function restoreRecovery(doc,state)
            assert(isstruct(state) && isfield(state,'Version') && ismember(state.Version,[7 12 14 15]) && ...
                all(isfield(state,{'Files','Classes','Annotations','Reviewed'})), ...
                'VIStudioV15:LabelSession','Invalid recovery state.');
            candidate=VIStudioAnnotationDataV15; candidate.restore(state); candidate.validateState();
            doc.remember(); doc.restore(candidate.snapshot()); doc.Dirty=true;
        end
        function saveSession(doc,file)
            assert(~isfile(file),'VIStudioV15:FileExists','Choose a new session filename.');
            session=doc.snapshot(); session.Version=15; %#ok<NASGU>
            save(file,'session','-v7.3'); doc.Dirty=false;
        end
        function loadSession(doc,file)
            loaded=load(file); candidate=VIStudioAnnotationDataV15;
            if isfield(loaded,'session')
                state=loaded.session;
                assert(isstruct(state) && isfield(state,'Version') && ismember(state.Version,[7 12 14 15]) && ...
                    all(isfield(state,{'Files','Classes','Annotations','Reviewed'})), 'VIStudioV15:LabelSession','Invalid V7 session.');
                candidate.Files=string(state.Files(:)); candidate.Classes=state.Classes; candidate.Annotations=VIStudioAnnotationDataV15.upgrade(state.Annotations); candidate.Reviewed=state.Reviewed;
                candidate.validateState();
            else
                assert(isfield(loaded,'exportROI') || isfield(loaded,'gTruth'),'VIStudioV15:LabelSession','MAT needs session, exportROI or gTruth.');
                if isfield(loaded,'exportROI'), data=loaded.exportROI; else, data=loaded.gTruth; end
                data=VIStudioData.detectionTable(data,fileparts(file)); candidate.Files=string(data.imageFilename);
                for k=1:numel(candidate.Files), candidate.Files(k)=VIStudioToolsV3.canonicalPath(candidate.Files(k)); end
                candidate.Reviewed=true(height(data),1);
                classes=string(data.Properties.VariableNames(2:end))'; palette=lines(numel(classes));
                map=table(); if isfield(loaded,'labelMap'), map=loaded.labelMap; end
                for c=1:numel(classes)
                    name=classes(c);
                    if ~isempty(map) && all(ismember({'OriginalName','ExportName'},map.Properties.VariableNames))
                        match=find(string(map.ExportName)==name,1); if ~isempty(match), name=string(map.OriginalName(match)); end
                    end
                    color=palette(c,:);
                    if isfield(loaded,'exportLabel') && istable(loaded.exportLabel) && all(ismember({'Name','Color'},loaded.exportLabel.Properties.VariableNames))
                        match=find(string(loaded.exportLabel.Name)==classes(c),1);
                        if ~isempty(match), color=loaded.exportLabel.Color(match,:); end
                    end
                    candidate.addClass(name,color);
                    for k=1:height(data)
                        boxes=data.(classes(c)){k};
                        for j=1:size(boxes,1), candidate.add(candidate.Files(k),name,'rectangle',boxes(j,:),'legacy'); end
                    end
                end
                candidate.Reviewed=true(height(data),1); candidate.validateState();
            end
            doc.remember(); doc.restore(candidate.snapshot()); doc.Dirty=false;
        end
        function [data,labelMap]=exportDetection(doc,file,convertShapes)
            if nargin<3, convertShapes=false; end
            assert(~isfile(file),'VIStudioV15:FileExists','Choose a new annotation filename.');
            files=doc.Files(doc.Reviewed); assert(~isempty(files),'VIStudioV15:UnreviewedImages','Mark at least one image reviewed before export.');
            rows=doc.Annotations(ismember(doc.Annotations.File,files) & doc.Annotations.Reviewed,:);
            assert(~any(rows.Type=="keypoints"),'VIStudioV15:PoseExportTask','Export keypoints separately.');
            assert(~any(rows.Type=="image"),'VIStudioV15:DetectionExport','Image class labels are not detection annotations.');
            assert(convertShapes || all(rows.Type=="rectangle"),'VIStudioV15:ShapeConversion', ...
                'Polygon/mask annotations require explicit Convert shapes to boxes. Native shapes stay in the V7 session.');
            assert(~isempty(doc.Classes),'VIStudioV15:LabelClass','Add a class first.');
            labelMap=doc.labelMap(false); imageFilename=cellstr(files); data=table(imageFilename);
            for c=1:height(labelMap)
                values=cell(numel(files),1);
                for k=1:numel(files)
                    records=rows(rows.File==files(k) & rows.Label==labelMap.OriginalName(c),:); boxes=zeros(0,4);
                    for j=1:height(records)
                        geometry=records.Geometry{j};
                        if records.Type(j)=="rectangle", box=geometry;
                        elseif records.Type(j)=="polygon", lo=min(geometry,[],1); hi=max(geometry,[],1); box=[lo max(1,hi-lo)];
                        else
                            [y,x]=find(geometry); if isempty(x), continue; end
                            box=[min(x) min(y) max(x)-min(x)+1 max(y)-min(y)+1];
                        end
                        boxes(end+1,:)=box; %#ok<AGROW>
                    end
                    values{k}=boxes;
                end
                data.(labelMap.ExportName(c))=values;
            end
            exportROI=data; Name=cellstr(labelMap.ExportName); Color=doc.Classes.Color; Type=repmat({'Rectangle'},height(doc.Classes),1);
            Description=cellstr(doc.Classes.Description); exportLabel=table(Name,Color,Type,Description); %#ok<NASGU>
            save(file,'exportROI','exportLabel','labelMap','-v7.3');
        end
        function output=exportDataset(doc,folder,task)
            task=string(validatestring(task,{'classification','anomaly'}));
            assert(~isfolder(folder) && ~isfile(folder),'VIStudioV15:FileExists','Choose a new dataset folder.');
            files=doc.Files(doc.Reviewed); assert(~isempty(files),'VIStudioV15:UnreviewedImages','Mark images reviewed before export.');
            labelMap=doc.labelMap(); labels=strings(numel(files),1); masks=cell(numel(files),1);
            for k=1:numel(files)
                rows=doc.Annotations(doc.Annotations.File==files(k) & doc.Annotations.Reviewed,:);
                if task=="classification"
                    imageLabels=rows(rows.Type=="image",:); assert(height(imageLabels)==1,'VIStudioV15:ImageClass','Each exported classification image needs exactly one image-level label.');
                    labels(k)=labelMap.ExportName(labelMap.OriginalName==imageLabels.Label);
                else
                    assert(~any(rows.Type=="keypoints"),'VIStudioV15:PoseExportTask','Export keypoints separately.');
                    assert(~any(rows.Type=="image"),'VIStudioV15:AnomalyExport','Anomaly export uses region annotations; remove image-level classification labels.');
                    image=VIStudioData.readImage(files(k),[]); mask=false(size(image,1),size(image,2));
                    for j=1:height(rows), mask=mask | doc.rasterize(rows.Type(j),rows.Geometry{j},size(mask)); end
                    masks{k}=mask; labels(k)="good"; if any(mask,'all'), labels(k)="defect"; end
                end
            end
            mkdir(folder); images=fullfile(folder,'images'); mkdir(images); mkdir(fullfile(folder,'masks'));
            imageFiles=strings(numel(files),1); maskFiles=strings(numel(files),1);
            for k=1:numel(files)
                target=fullfile(images,labels(k)); if ~isfolder(target), mkdir(target); end
                imageFiles(k)=string(fullfile(target,sprintf('%06d.png',k))); imwrite(VIStudioData.readImage(files(k),[]),imageFiles(k));
                if task=="anomaly"
                    maskFiles(k)=string(fullfile(folder,'masks',sprintf('%06d.png',k))); imwrite(masks{k},maskFiles(k));
                end
            end
            manifest=table(files,imageFiles,labels,maskFiles,'VariableNames',{'SourceFile','File','Label','MaskFile'});
            writetable(manifest,fullfile(folder,'manifest.csv'),'Encoding','UTF-8');
            save(fullfile(folder,'dataset.mat'),'manifest','labelMap','task'); output=struct('Images',string(images),'Manifest',manifest);
        end
        function rows=current(doc,file), rows=doc.Annotations(doc.Annotations.File==VIStudioToolsV3.canonicalPath(file),:); end
        function validateState(doc)
            assert(isstring(doc.Files) && numel(unique(doc.Files))==numel(doc.Files) && all(isfile(doc.Files)), 'VIStudioV15:LabelSession','Session images are missing or repeated.');
            assert(istable(doc.Classes) && all(ismember({'Name','Color','Description'},doc.Classes.Properties.VariableNames)) && ...
                numel(unique(doc.Classes.Name))==height(doc.Classes),'VIStudioV15:LabelSession','Invalid class table.');
            validateattributes(doc.Classes.Color,{'numeric'},{'ncols',3,'finite','>=',0,'<=',1});
            assert(islogical(doc.Reviewed) && iscolumn(doc.Reviewed) && numel(doc.Reviewed)==numel(doc.Files),'VIStudioV15:LabelSession','Invalid review flags.');
            expected=VIStudioAnnotationDataV15; required=expected.Annotations.Properties.VariableNames;
            assert(istable(doc.Annotations) && all(ismember(required,doc.Annotations.Properties.VariableNames)) && ...
                numel(unique(doc.Annotations.ID))==height(doc.Annotations) && ...
                all(ismember(doc.Annotations.File,doc.Files)) && all(ismember(doc.Annotations.Label,doc.Classes.Name)) && ...
                islogical(doc.Annotations.Reviewed),'VIStudioV15:LabelSession','Invalid annotations.');
            for k=1:height(doc.Classes), doc.checkName(doc.Classes.Name(k)); end
            for k=1:height(doc.Annotations), doc.validateGeometry(doc.Annotations.File(k),doc.Annotations.Type(k),doc.Annotations.Geometry{k}); end
            for k=1:numel(doc.Files)
                assert(sum(doc.Annotations.File==doc.Files(k) & doc.Annotations.Type=="image")<=1,'VIStudioV15:LabelSession','Repeated image-level labels.');
            end
            assert(~any(ismember(doc.Annotations.File(~doc.Annotations.Reviewed),doc.Files(doc.Reviewed))), ...
                'VIStudioV15:LabelSession','Reviewed images cannot contain pending annotations.');
        end
    end
    methods (Static)
        function rows=upgrade(rows)
            if ~ismember('InstanceID',rows.Properties.VariableNames), rows.InstanceID=rows.ID; end
            if ~ismember('Keypoints',rows.Properties.VariableNames), rows.Keypoints=repmat({zeros(0,2)},height(rows),1); end
            if ~ismember('Visibility',rows.Properties.VariableNames), rows.Visibility=repmat({zeros(0,1)},height(rows),1); end
        end
        function geometry=validateGeometry(file,type,geometry)
            info=imfinfo(file); h=info(1).Height; w=info(1).Width;
            switch string(type)
                case "keypoints", geometry=VIStudioPoseV15.validate(geometry,[h w]);
                case "rectangle"
                    validateattributes(geometry,{'numeric'},{'size',[1 4],'finite','real'});
                    assert(all(geometry(1:2)>=1) && all(geometry(3:4)>0) && ...
                        geometry(1)+geometry(3)<=w+1 && geometry(2)+geometry(4)<=h+1,'VIStudioV15:Geometry','Box lies outside the image.');
                    geometry=double(geometry);
                case "polygon"
                    validateattributes(geometry,{'numeric'},{'2d','ncols',2,'finite','real'});
                    assert(size(geometry,1)>=3 && all(geometry(:,1)>=1 & geometry(:,1)<=w) && ...
                        all(geometry(:,2)>=1 & geometry(:,2)<=h) && polyarea(geometry(:,1),geometry(:,2))>0, ...
                        'VIStudioV15:Geometry','Polygon needs at least three non-collinear vertices inside the image.'); geometry=double(geometry);
                case "mask"
                    validateattributes(geometry,{'logical'},{'size',[h w]});
                    assert(any(geometry,'all'),'VIStudioV15:Geometry','Mask is empty.');
                case "image", assert(isempty(geometry),'VIStudioV15:Geometry','Image labels have no region geometry.');
                otherwise, error('VIStudioV15:Geometry','Unsupported annotation type.');
            end
        end
        function mask=rasterize(type,geometry,imageSize)
            h=imageSize(1); w=imageSize(2);
            if type=="mask", mask=logical(geometry);
            elseif type=="polygon", mask=poly2mask(geometry(:,1),geometry(:,2),h,w);
            elseif type=="rectangle"
                mask=false(h,w); lo=max([1 1],floor(geometry(1:2))); hi=min([w h],ceil(geometry(1:2)+geometry(3:4))-1);
                mask(lo(2):hi(2),lo(1):hi(1))=true;
            else, mask=false(h,w); end
        end
        function mask=stroke(vertices,radius,imageSize)
            validateattributes(radius,{'numeric'},{'scalar','positive','finite'});
            validateattributes(vertices,{'numeric'},{'2d','ncols',2,'finite','real','nonempty'});
            h=imageSize(1); w=imageSize(2); mask=false(h,w);
            for k=1:max(1,size(vertices,1)-1)
                a=vertices(k,:); b=vertices(min(k+1,size(vertices,1)),:); count=max(1,ceil(norm(b-a)*2));
                for t=linspace(0,1,count+1)
                    p=a+(b-a)*t; xs=max(1,floor(p(1)-radius)):min(w,ceil(p(1)+radius)); ys=max(1,floor(p(2)-radius)):min(h,ceil(p(2)+radius));
                    [x,y]=meshgrid(xs,ys); mask(ys,xs)=mask(ys,xs) | (x-p(1)).^2+(y-p(2)).^2<=radius^2;
                end
            end
        end
    end
    methods (Access=private)
        function id=newID(doc)
            [~,name]=fileparts(tempname); id="ann_"+string(name);
            while ismember(id,doc.Annotations.ID), [~,name]=fileparts(tempname); id="ann_"+string(name); end
        end
        function name=checkName(~,name)
            name=strip(string(name)); assert(isscalar(name) && ~ismissing(name) && strlength(name)>0 && strlength(name)<=100, ...
                'VIStudioV15:LabelClass','Class names must contain 1–100 characters.');
        end
        function index=row(doc,id)
            index=find(doc.Annotations.ID==string(id),1); assert(~isempty(index),'VIStudioV15:Annotation','Annotation no longer exists.');
        end
        function remember(doc)
            doc.Revision=doc.Revision+1;
            doc.UndoStack{end+1}=doc.snapshot(); if numel(doc.UndoStack)>40, doc.UndoStack(1)=[]; end
            doc.RedoStack={}; doc.Dirty=true;
        end
        function value=snapshot(doc)
            value=struct('Files',doc.Files,'Classes',doc.Classes,'Annotations',doc.Annotations,'Reviewed',doc.Reviewed);
        end
        function restore(doc,state)
            doc.Files=state.Files; doc.Classes=state.Classes; doc.Annotations=VIStudioAnnotationDataV15.upgrade(state.Annotations); doc.Reviewed=state.Reviewed;
        end
        function map=labelMap(doc,safeFolders)
            if nargin<2, safeFolders=true; end
            if safeFolders
                names=string(matlab.lang.makeValidName(cellstr(doc.Classes.Name)));
                names=string(matlab.lang.makeUniqueStrings(cellstr(names)));
            else
                % Modern MATLAB tables support spaces and Unicode. Preserve
                % detector class names so external-model warm-start can match.
                names=string(matlab.lang.makeUniqueStrings(cellstr(doc.Classes.Name),{'imageFilename'}));
            end
            map=table(doc.Classes.Name,names(:),'VariableNames',{'OriginalName','ExportName'});
        end
    end
end
