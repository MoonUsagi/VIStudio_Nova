classdef VIStudioToolsV3
    % Result operations shared by classification, detection and anomaly V3.
    methods (Static)
        function filter=defaultFilter()
            filter=struct('Query',"",'Class',"all",'Status',"all",'Review',"all", ...
                'MinConfidence',-Inf,'MaxConfidence',Inf);
        end
        function [view,indices]=filterResults(results,filter)
            if isempty(results), view=results; indices=[]; return; end
            keep=true(height(results),1);
            if strlength(filter.Query)>0
                text=lower(string(results.File)+" "+string(results.Prediction)+" "+string(results.ReviewNote));
                keep=keep & contains(text,lower(string(filter.Query)));
            end
            if filter.Class~="all", keep=keep & string(results.Prediction)==filter.Class; end
            if filter.Review~="all", keep=keep & string(results.ReviewState)==filter.Review; end
            if filter.Status~="all"
                terms=struct('review','Review','classified','Classified','objects','Objects found', ...
                    'empty','No objects','normal','Normal','anomaly','Anomaly','error','Error');
                assert(isfield(terms,char(filter.Status)),'VIStudioV3:InvalidFilter','Invalid status filter.');
                keep=keep & contains(string(results.Status),terms.(char(filter.Status)));
            end
            if isfinite(filter.MinConfidence), keep=keep & results.Confidence>=filter.MinConfidence; end
            if isfinite(filter.MaxConfidence), keep=keep & results.Confidence<=filter.MaxConfidence; end
            indices=find(keep); view=results(indices,:);
        end
        function [perClass,summary,matrix]=classificationMetrics(actual,predicted,classes)
            actual=string(actual(:)); predicted=string(predicted(:)); classes=string(classes(:));
            assert(~isempty(actual) && numel(actual)==numel(predicted),'VIStudioV3:MissingLabels', ...
                '請提供正確答案。 / Ground truth labels are required.');
            assert(all(ismember(actual,classes)) && all(ismember(predicted,classes)), ...
                'VIStudioV3:UnknownLabels','Labels must belong to model classes.');
            matrix=zeros(numel(classes));
            [~,a]=ismember(actual,classes); [~,p]=ismember(predicted,classes);
            for k=1:numel(a), matrix(a(k),p(k))=matrix(a(k),p(k))+1; end
            tp=diag(matrix); support=sum(matrix,2); predictedCount=sum(matrix,1)';
            precision=tp./max(1,predictedCount); recall=tp./max(1,support);
            f1=2*precision.*recall./max(eps,precision+recall);
            perClass=table(classes,support,precision,recall,f1, ...
                'VariableNames',{'Class','Support','Precision','Recall','F1'});
            observed=support>0;
            summary=struct('Images',numel(a),'Accuracy',sum(tp)/numel(a), ...
                'MacroPrecision',mean(precision(observed)),'MacroRecall',mean(recall(observed)), ...
                'MacroF1',mean(f1(observed)));
        end
        function json=encodeMask(mask)
            % Run-length encoding on column-major logical pixels.
            values=logical(mask(:)); changes=diff([false;values;false]);
            starts=find(changes==1); stops=find(changes==-1)-1;
            json=string(jsonencode([starts stops-starts+1]));
        end
        function mask=decodeMask(json,imageSize)
            validateattributes(imageSize,{'numeric'},{'vector','numel',2,'positive','integer','finite'});
            runs=jsondecode(char(json)); mask=false(imageSize);
            if isempty(runs), return; end
            if isvector(runs), runs=reshape(runs,1,[]); end
            validateattributes(runs,{'numeric'},{'2d','ncols',2,'positive','integer','finite'});
            assert(all(runs(:,1)+runs(:,2)-1<=numel(mask)),'VIStudioV3:InvalidMask','Mask run exceeds image size.');
            for k=1:size(runs,1), mask(runs(k,1)+(0:runs(k,2)-1))=true; end
        end
        function boxes=decodeBoxes(json,count)
            raw=jsondecode(char(json));
            if count==0, assert(isempty(raw),'VIStudioV3:InvalidBoxes','Expected no boxes.'); boxes=zeros(0,4); return; end
            if count==1, raw=reshape(raw,1,4); end
            validateattributes(raw,{'numeric'},{'size',[count 4],'real','finite'});
            assert(all(raw(:,3:4)>0,'all'),'VIStudioV3:InvalidBoxes','Box sizes must be positive.');
            boxes=double(raw);
        end
        function [crop,roi]=cropImage(image,requested)
            if isempty(requested), roi=[1 1 size(image,2) size(image,1)];
            else, roi=double(requested); end
            validateattributes(roi,{'numeric'},{'vector','numel',4,'real','finite','integer','positive'});
            assert(roi(1)+roi(3)-1<=size(image,2) && roi(2)+roi(4)-1<=size(image,1), ...
                'VIStudioV3:ROIOutsideImage','ROI 超出影像範圍。 / ROI lies outside the image.');
            crop=image(roi(2)+(0:roi(4)-1),roi(1)+(0:roi(3)-1),:);
        end
        function digest=fileHash(file)
            if ispc
                stream=System.IO.File.OpenRead(char(file));
                cleanup=onCleanup(@() stream.Dispose());
                algorithm=System.Security.Cryptography.SHA256.Create();
                algorithmCleanup=onCleanup(@() algorithm.Dispose());
                bytes=uint8(algorithm.ComputeHash(stream));
                digest=lower(string(reshape(dec2hex(bytes,2)',1,[])));
                return
            end
            fid=fopen(file,'rb'); assert(fid~=-1,'VIStudioV3:MissingFile','Cannot read %s',file);
            cleanup=onCleanup(@() fclose(fid));
            hash=java.security.MessageDigest.getInstance('SHA-256');
            while ~feof(fid)
                bytes=fread(fid,1024*1024,'*uint8'); hash.update(bytes);
            end
            digest=lower(string(reshape(dec2hex(typecast(hash.digest(),'uint8'),2)',1,[])));
        end
        function path=canonicalPath(file)
            [folder,name,extension]=fileparts(char(file));
            if isempty(folder), folder=pwd; end
            [ok,attributes]=fileattrib(folder);
            assert(ok,'VIStudioV3:MissingFolder','Folder does not exist.');
            path=string(fullfile(attributes.Name,[name extension]));
        end
        function text=translate(value,language)
            if strcmp(language,'bilingual'), text=value; return; end
            wasCell=iscell(value); wasChar=ischar(value); values=string(value);
            for k=1:numel(values)
                lines=splitlines(values(k));
                for j=1:numel(lines)
                    line=lines(j);
                    if contains(line,' / ')
                        parts=split(line,' / ');
                        if strcmp(language,'zh'), line=parts(1); else, line=parts(end); end
                    else
                        bilingual={ '01 資料 Data','02 結果 Results','03 檢測 Inspection', ...
                            '04 覆核 Review','05 評估 Evaluation'};
                        chinese={'01 資料','02 結果','03 檢測','04 覆核','05 評估'};
                        english={'01 Data','02 Results','03 Inspection','04 Review','05 Evaluation'};
                        idx=find(strcmp(line,bilingual),1);
                        if ~isempty(idx)
                            if strcmp(language,'zh'), line=string(chinese{idx}); else, line=string(english{idx}); end
                        end
                    end
                    lines(j)=line;
                end
                values(k)=join(lines,newline);
            end
            if wasCell, text=cellstr(values); elseif wasChar, text=char(values); else, text=values; end
        end
    end
end
