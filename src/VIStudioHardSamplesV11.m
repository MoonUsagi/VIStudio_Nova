classdef VIStudioHardSamplesV11 < handle
    properties (SetAccess=private)
        Root
        Rows
    end
    methods
        function queue=VIStudioHardSamplesV11(root)
            queue.Root=string(root); queue.Rows=table('Size',[0 11],'VariableTypes', ...
                {'string','string','string','string','string','string','string','string','string','string','string'}, ...
                'VariableNames',{'ID','File','OriginalFile','PixelHash','Task','Reason','Prediction','ActualLabel','ReviewState','BoxesJSON','EvidenceJSON'});
            if isfile(fullfile(root,'queue.mat'))
                loaded=load(fullfile(root,'queue.mat'),'rows'); assert(istable(loaded.rows) && all(ismember(queue.Rows.Properties.VariableNames,loaded.rows.Properties.VariableNames)),'VIStudioV11:Queue','Invalid queue journal.'); queue.Rows=loaded.rows;
            end
        end
        function id=add(queue,file,task,reason,prediction,evidence,image)
            if nargin<5, prediction=""; end; if nargin<6, evidence=struct(); end
            task=string(validatestring(task,{'classification','detection','anomaly'})); if nargin<7, image=VIStudioData.readImage(file,[]); end; hash=VIStudioDataHealthV8.pixelHash(image);
            row=find(queue.Rows.PixelHash==hash & queue.Rows.Task==task,1);
            if ~isempty(row), id=queue.Rows.ID(row); queue.Rows.Reason(row)=join(unique([queue.Rows.Reason(row);string(reason)]),'; '); queue.persist(); return; end
            if ~isfolder(queue.Root), mkdir(queue.Root); end
            images=fullfile(queue.Root,'images'); if ~isfolder(images), mkdir(images); end
            [~,name]=fileparts(tempname(images)); id=string(name); target=string(fullfile(images,name+".png")); imwrite(image,target);
            queue.Rows(end+1,:)={id,target,VIStudioToolsV3.canonicalPath(file),hash,task,string(reason),string(prediction),"","queued","",string(jsonencode(evidence))}; queue.persist();
        end
        function review(queue,id,label)
            row=queue.index(id); assert(queue.Rows.Task(row)~="detection",'VIStudioV11:QueueBoxes','Review detector samples in Labeler, then import reviewed annotations.');
            label=string(label); assert(isscalar(label) && ~ismissing(label) && strlength(strtrim(label))>0,'VIStudioV11:ReviewLabel','Enter a human-confirmed class.');
            queue.Rows.ActualLabel(row)=label; queue.Rows.ReviewState(row)="reviewed"; queue.persist();
        end
        function exclude(queue,id), row=queue.index(id); queue.Rows.ReviewState(row)="excluded"; queue.persist(); end
        function importAnnotations(queue,file)
            [~,~,gt]=VIStudioTrainingDataV4.groundTruth(file); updates=queue.Rows;
            for k=1:height(gt)
                path=VIStudioToolsV3.canonicalPath(gt.imageFilename{k}); row=find(updates.File==path & updates.Task=="detection",1);
                if isempty(row), continue; end
                boxes=zeros(0,4); labels=strings(0,1);
                for c=2:width(gt), current=gt.(gt.Properties.VariableNames{c}){k}; boxes=[boxes;current]; labels=[labels;repmat(string(gt.Properties.VariableNames{c}),size(current,1),1)]; end %#ok<AGROW>
                image=VIStudioData.readImage(path,[]);
                assert(isempty(boxes) || (all(boxes(:,1:2)>=1,'all') && all(boxes(:,3:4)>0,'all') && all(boxes(:,1:2)+boxes(:,3:4)<=[size(image,2)+1 size(image,1)+1],'all')),'VIStudioV11:QueueGeometry','Reviewed boxes exceed the source image.');
                updates.BoxesJSON(row)=string(jsonencode(struct('Boxes',boxes,'Labels',labels))); updates.ActualLabel(row)=join(unique(labels),';'); updates.ReviewState(row)="reviewed";
            end
            queue.Rows=updates; queue.persist();
        end
        function result=export(queue,folder,task)
            task=string(validatestring(task,{'classification','detection','anomaly'})); rows=queue.Rows(queue.Rows.Task==task & queue.Rows.ReviewState=="reviewed",:);
            assert(~isempty(rows),'VIStudioV11:Unreviewed','Human review is required before exporting training data.');
            assert(~isfolder(folder) && ~isfile(folder),'VIStudioV11:FileExists','Choose a new dataset folder.');
            for k=1:height(rows), assert(VIStudioDataHealthV8.pixelHash(VIStudioData.readImage(rows.File(k),[]))==rows.PixelHash(k),'VIStudioV11:QueueChanged','Queued image changed.'); end
            mkdir(folder); mkdir(fullfile(folder,'images')); manifest=rows; outputFiles=strings(height(rows),1);
            if task=="detection"
                names=strings(0,1); parsed=cell(height(rows),1);
                for k=1:height(rows)
                    assert(strlength(rows.BoxesJSON(k))>0,'VIStudioV11:QueueBoxes','Import reviewed bounding boxes first.'); parsed{k}=jsondecode(rows.BoxesJSON(k)); names=union(names,string(parsed{k}.Labels));
                end
                validNames=string(matlab.lang.makeValidName(cellstr(names))); assert(numel(unique(validNames))==numel(names),'VIStudioV11:LabelCollision','Object class names collide after MATLAB variable-name conversion.');
                assert(~isempty(names),'VIStudioV11:QueueBoxes','At least one positive object annotation is required.'); exportROI=table(cell(height(rows),1),'VariableNames',{'imageFilename'});
                for name=names', exportROI.(matlab.lang.makeValidName(char(name)))=repmat({zeros(0,4)},height(rows),1); end
                for k=1:height(rows)
                    file=string(fullfile(folder,'images',sprintf('%06d.png',k))); copyfile(rows.File(k),file); outputFiles(k)=file; exportROI.imageFilename{k}=char(file);
                    boxes=double(parsed{k}.Boxes); if isempty(boxes), boxes=zeros(0,4); elseif isvector(boxes), boxes=reshape(boxes,1,4); end
                    labels=string(parsed{k}.Labels); labels=labels(:);
                    for name=names', exportROI.(matlab.lang.makeValidName(char(name))){k}=boxes(labels==name,:); end
                end
                path=fullfile(folder,'annotations.mat'); save(path,'exportROI'); result=struct('Task',task,'Path',string(path));
            else
                labels=unique(rows.ActualLabel); folders=strings(numel(labels),1);
                for k=1:numel(labels)
                    label=labels(k); safe=~isempty(regexp(char(label),'^[^<>:"/\\|?*.][^<>:"/\\|?*]*$','once')) && ~endsWith(label,' ') && ~endsWith(label,'.');
                    if safe && ~any(strcmpi(label,["CON","PRN","AUX","NUL","COM1","LPT1"])), folders(k)=label; else, folders(k)="label_"+k; end
                end
                assert(numel(unique(lower(folders)))==numel(folders),'VIStudioV11:LabelFolders','Class folder names collide.'); labelMap=table(labels,folders,'VariableNames',{'OriginalName','Folder'});
                for k=1:height(rows)
                    target=fullfile(folder,'images',folders(labels==rows.ActualLabel(k))); if ~isfolder(target), mkdir(target); end
                    file=string(fullfile(target,sprintf('%06d.png',k))); copyfile(rows.File(k),file); outputFiles(k)=file;
                end
                save(fullfile(folder,'label_map.mat'),'labelMap'); result=struct('Task',task,'Path',string(fullfile(folder,'images')));
            end
            manifest.File=outputFiles; manifest.Split=repmat("train",height(manifest),1); writetable(manifest,fullfile(folder,'reviewed_manifest.csv'),'Encoding','UTF-8');
        end
    end
    methods (Access=private)
        function row=index(queue,id), row=find(queue.Rows.ID==string(id),1); assert(~isempty(row),'VIStudioV11:QueueID','Unknown sample ID.'); end
        function persist(queue)
            rows=queue.Rows; if ~isfolder(queue.Root), mkdir(queue.Root); end %#ok<NASGU>
            temporary=fullfile(queue.Root,'queue_pending.mat'); save(temporary,'rows','-v7.3'); movefile(temporary,fullfile(queue.Root,'queue.mat'),'f');
        end
    end
end
