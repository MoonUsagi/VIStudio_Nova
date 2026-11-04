classdef VIStudioDataHealthV8
    methods (Static)
        function report=folder(folder,task)
            assert(isfolder(folder),'VIStudioV8:HealthSource','Folder is missing.');
            entries=dir(fullfile(folder,'**','*')); entries=entries(~[entries.isdir]);
            formats=imformats; extensions={}; for k=1:numel(formats), extensions=[extensions formats(k).ext]; end %#ok<AGROW>
            files=strings(0,1); labels=strings(0,1);
            for k=1:numel(entries)
                [~,~,ext]=fileparts(entries(k).name);
                if ismember(lower(erase(string(ext),'.')),string(extensions))
                    files(end+1,1)=string(fullfile(entries(k).folder,entries(k).name)); %#ok<AGROW>
                    [~,label]=fileparts(entries(k).folder); labels(end+1,1)=string(label); %#ok<AGROW>
                end
            end
            report=VIStudioDataHealthV8.scan(files,labels,task,[]); report.Source=string(folder);
        end
        function report=annotations(file)
            loaded=load(file);
            if isfield(loaded,'exportROI'), data=loaded.exportROI;
            elseif isfield(loaded,'gTruth'), data=loaded.gTruth;
            else, error('VIStudioV8:HealthAnnotations','MAT requires exportROI or gTruth.'); end
            if isa(data,'groundTruth'), data=objectDetectorTrainingData(data); end
            assert(istable(data) && width(data)>=1,'VIStudioV8:HealthAnnotations','Annotations must be a table.');
            files=string(data{:,1}); files=files(:); labels=repmat("(detection)",numel(files),1);
            for k=1:numel(files)
                if ~isfile(files(k)) && ~isAbsolute(files(k)), files(k)=string(fullfile(fileparts(file),files(k))); end
            end
            data.Properties.VariableNames{1}='imageFilename'; data.imageFilename=cellstr(files);
            report=VIStudioDataHealthV8.scan(files,labels,'detection',data); report.Source=string(file);
            function yes=isAbsolute(path), yes=startsWith(path,filesep) || ~isempty(regexp(char(path),'^[A-Za-z]:[\\/]','once')); end
        end
        function report=scan(files,labels,task,gt)
            files=string(files); files=files(:); labels=string(labels); labels=labels(:); task=string(task);
            assert(numel(files)==numel(labels),'VIStudioV8:HealthInput','File and label lengths differ.');
            n=numel(files); readable=false(n,1); widths=zeros(n,1); heights=widths; channels=widths; bytes=widths; objects=widths;
            hashes=strings(n,1); pixels=hashes;
            issues=table(strings(0,1),strings(0,1),strings(0,1),strings(0,1),strings(0,1), ...
                'VariableNames',{'Severity','Code','File','RelatedFile','Message'});
            if n==0, add('error','EMPTY_DATA',"","",'沒有影像 / No images found'); end
            for row=1:n
                try
                    if ~isfile(files(row)), error('Health:Missing','Image is missing.'); end
                    files(row)=VIStudioToolsV3.canonicalPath(files(row));
                    info=imfinfo(files(row)); image=VIStudioData.readImage(files(row),[]);
                    readable(row)=true; widths(row)=size(image,2); heights(row)=size(image,1); channels(row)=3;
                    details=dir(files(row)); bytes(row)=details.bytes;
                    if isfield(info,'ColorType') && strcmp(info(1).ColorType,'grayscale'), channels(row)=1; end
                    hashes(row)=VIStudioToolsV3.fileHash(files(row)); pixels(row)=VIStudioDataHealthV8.pixelHash(image);
                    if min(widths(row),heights(row))<32, add('warning','SMALL_IMAGE',files(row),"",'短邊小於 32 像素 / Short side below 32 pixels'); end
                    if max(widths(row),heights(row))/min(widths(row),heights(row))>5
                        add('warning','EXTREME_ASPECT',files(row),"",'影像長寬比大於 5 / Aspect ratio exceeds 5');
                    end
                    if ~isempty(regexp(char(files(row)),'[\\/](masks?)[\\/]','once'))
                        add('warning','MASK_DIRECTORY',files(row),"",'疑似遮罩混入影像目錄 / Possible mask inside the selected image tree');
                    end
                catch err
                    add('error','UNREADABLE_IMAGE',files(row),"",'無法讀取影像 / Cannot read image: '+string(err.message));
                end
            end
            [~,~,groups]=unique(lower(files));
            for row=1:n
                first=find(groups==groups(row),1);
                if first<row, add('error','DUPLICATE_PATH',files(row),files(first),'同一影像重複列出 / Image path appears more than once'); end
            end
            valid=find(readable & strlength(pixels)>0);
            for k=1:numel(valid)
                row=valid(k); previous=valid(1:k-1); same=previous(pixels(previous)==pixels(row));
                if isempty(same), continue; end
                first=same(1); severity='warning'; code='DUPLICATE_PIXELS'; message='像素內容重複 / Identical decoded image content';
                if task~="detection" && any(labels(same)~=labels(row))
                    severity='error'; code='LABEL_CONFLICT'; message='相同影像分配到不同類別 / Identical image has conflicting class labels';
                end
                add(severity,code,files(row),files(first),message);
            end
            if task=="detection"
                if isempty(gt) || width(gt)<2, add('error','MISSING_BOX_CLASSES',"","",'缺少標註類別欄位 / No box class columns');
                else
                    for row=1:n
                        for col=2:width(gt)
                            column=gt.(gt.Properties.VariableNames{col});
                            if ~iscell(column), add('error','INVALID_BOX_COLUMN',files(row),"",'標註欄位必須為 cell / Box column must contain cells'); continue; end
                            b=column{row};
                            if isempty(b), continue; end
                            if ~isnumeric(b) || ~isreal(b) || ~ismatrix(b) || size(b,2)~=4 || any(~isfinite(b),'all') || any(b(:,1:2)<1,'all') || any(b(:,3:4)<=0,'all')
                                add('error','INVALID_BOX',files(row),"",'無效 [x y width height] / Invalid box geometry'); continue;
                            end
                            objects(row)=objects(row)+size(b,1);
                            if readable(row) && any(b(:,1:2)+b(:,3:4)>[widths(row)+1 heights(row)+1],'all')
                                add('error','BOX_OUTSIDE_IMAGE',files(row),"",'標註框超出影像 / Box extends outside image');
                            end
                        end
                        if objects(row)==0, add('info','NEGATIVE_IMAGE',files(row),"",'無物件標註，可作負樣本 / No boxes; potential negative sample'); end
                    end
                end
                if sum(objects)==0, add('error','NO_POSITIVE_BOXES',"","",'沒有有效的正樣本框 / No positive object annotations'); end
            end
            classes=unique(labels,'stable'); count=zeros(numel(classes),1);
            for k=1:numel(classes), count(k)=sum(labels==classes(k) & readable); end
            if task=="classification" && numel(classes)<2, add('error','SINGLE_CLASS',"","",'分類至少需要兩個類別 / Classification requires two classes'); end
            if task~="detection" && ~isempty(count)
                if any(count<2), add('warning','LOW_CLASS_COUNT',"","",'部份類別少於兩張；驗證切分可能失敗 / Some classes have fewer than two images'); end
                if min(count)>0 && max(count)/min(count)>5, add('warning','CLASS_IMBALANCE',"","",'最大與最小類別數量超過五倍 / Class count ratio exceeds 5'); end
            end
            images=table(files,labels,readable,widths,heights,channels,bytes,hashes,pixels,objects, ...
                'VariableNames',{'File','Label','Readable','Width','Height','Channels','Bytes','FileHash','PixelHash','Objects'});
            report=struct('Task',task,'Source',"",'Images',images,'Issues',issues, ...
                'Classes',table(classes,count,'VariableNames',{'Class','Count'}),'CheckedAtUTC',string(datetime('now','TimeZone','UTC')), ...
                'Errors',sum(issues.Severity=="error"),'Warnings',sum(issues.Severity=="warning"));
            function add(severity,code,file,related,message)
                issues=[issues;table(string(severity),string(code),string(file),string(related),string(message),'VariableNames',issues.Properties.VariableNames)];
            end
        end
        function digest=pixelHash(image)
            shape=typecast(uint64(size(image)),'uint8'); payload=[shape(:);image(:)];
            if ispc
                algorithm=System.Security.Cryptography.SHA256.Create(); c=onCleanup(@() algorithm.Dispose()); bytes=uint8(algorithm.ComputeHash(payload));
            else
                algorithm=java.security.MessageDigest.getInstance('SHA-256'); algorithm.update(payload); bytes=typecast(algorithm.digest(),'uint8');
            end
            digest=lower(string(reshape(dec2hex(bytes,2)',1,[])));
        end
        function export(report,folder)
            assert(~isfolder(folder) && ~isfile(folder),'VIStudioV8:FileExists','Choose a new report folder.'); mkdir(folder);
            writetable(report.Images,fullfile(folder,'images.csv'),'Encoding','UTF-8');
            writetable(report.Issues,fullfile(folder,'issues.csv'),'Encoding','UTF-8');
            writetable(report.Classes,fullfile(folder,'classes.csv'),'Encoding','UTF-8'); save(fullfile(folder,'report.mat'),'report','-v7.3');
        end
    end
end
