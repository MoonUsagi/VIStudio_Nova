classdef VIStudioAnnotationQualityV15
    methods (Static)
        function report=analyze(doc,minArea,duplicateIoU)
            if nargin<2, minArea=4; end; if nargin<3, duplicateIoU=.95; end; validateattributes(minArea,{'numeric'},{'scalar','nonnegative','finite'}); validateattributes(duplicateIoU,{'numeric'},{'scalar','>',0,'<=',1});
            issues=table(strings(0,1),strings(0,1),strings(0,1),strings(0,1),strings(0,1),'VariableNames',{'File','AnnotationID','Severity','Code','Detail'}); counts=zeros(height(doc.Classes),1); pending=counts; area=counts;
            for f=doc.Files'
                image=VIStudioData.readImage(f,[]); rows=doc.current(f); masks=cell(height(rows),1);
                if ~doc.Reviewed(doc.Files==f), issues(end+1,:)={f,"","info","IMAGE_PENDING","Image is not reviewed"}; end
                for k=1:height(rows)
                    c=find(doc.Classes.Name==rows.Label(k),1); counts(c)=counts(c)+1; pending(c)=pending(c)+~rows.Reviewed(k);
                    if ismember(rows.Type(k),["mask","polygon","rectangle"])
                        mask=doc.rasterize(rows.Type(k),rows.Geometry{k},size(image,[1 2])); masks{k}=mask; sizeValue=nnz(mask); area(c)=area(c)+sizeValue;
                        if sizeValue<minArea, issues(end+1,:)={f,rows.ID(k),"warning","TINY_REGION","Area "+sizeValue+" px"}; end
                        if any(mask([1 end],:),'all') || any(mask(:,[1 end]),'all'), issues(end+1,:)={f,rows.ID(k),"info","BORDER_REGION","May be truncated; inspect manually"}; end
                    elseif rows.Type(k)=="keypoints"
                        g=rows.Geometry{k}; missing=sum(g.Visibility==0); if missing>0, issues(end+1,:)={f,rows.ID(k),"info","MISSING_POINTS",string(missing)+" unknown points; may be intentional"}; end
                        edges=VIStudioPoseV15.measure(g); if any(edges.Distance==0), issues(end+1,:)={f,rows.ID(k),"warning","ZERO_LENGTH_EDGE","Connected points coincide"}; end
                    end
                end
                for a=1:height(rows), if isempty(masks{a}), continue; end
                    for b=a+1:height(rows), if isempty(masks{b}), continue; end; intersection=nnz(masks{a} & masks{b}); union=nnz(masks{a} | masks{b}); overlap=intersection/max(1,union);
                        if rows.Label(a)==rows.Label(b) && overlap>=duplicateIoU, issues(end+1,:)={f,rows.ID(a),"warning","POSSIBLE_DUPLICATE","Overlaps "+rows.ID(b)+"; IoU="+overlap};
                        elseif rows.Label(a)~=rows.Label(b) && intersection>0, issues(end+1,:)={f,rows.ID(a),"info","CROSS_CLASS_OVERLAP","With "+rows.ID(b)+"; valid for some instance scenes"}; end
                    end
                end
            end
            classes=table(doc.Classes.Name,counts,pending,area,'VariableNames',{'Class','Annotations','Pending','SummedRegionPixels'}); summary=struct('Images',numel(doc.Files),'ReviewedImages',sum(doc.Reviewed),'Annotations',height(doc.Annotations),'Warnings',sum(issues.Severity=="warning"),'PendingAnnotations',sum(pending),'UnusedClasses',sum(counts==0)); report=struct('Summary',summary,'Issues',issues,'Classes',classes,'Revision',doc.Revision);
        end
        function report=compare(a,b)
            rows=table(strings(0,1),strings(0,1),zeros(0,1),zeros(0,1),zeros(0,1),zeros(0,1),'VariableNames',{'File','Class','IoU','Dice','ObjectsA','ObjectsB'}); hashesA=strings(numel(a.Files),1); hashesB=strings(numel(b.Files),1);
            for k=1:numel(a.Files), hashesA(k)=VIStudioDataHealthV8.pixelHash(VIStudioData.readImage(a.Files(k),[])); end; for k=1:numel(b.Files), hashesB(k)=VIStudioDataHealthV8.pixelHash(VIStudioData.readImage(b.Files(k),[])); end
            assert(numel(unique(hashesA))==numel(hashesA) && numel(unique(hashesB))==numel(hashesB),'VIStudioV15:QualityAmbiguous','Duplicate image content makes reviewer pairing ambiguous.');
            for k=1:numel(a.Files)
                match=find(hashesB==hashesA(k),1); if isempty(match), continue; end; image=VIStudioData.readImage(a.Files(k),[]); first=a.current(a.Files(k)); second=b.current(b.Files(match)); names=union(first.Label,second.Label);
                for name=names'
                    regionA=false(size(image,[1 2])); regionB=regionA; objects=zeros(1,2); groups={first,second}; masks={regionA,regionB};
                    for reviewer=1:2, group=groups{reviewer}; for n=1:height(group), if group.Label(n)==name && ismember(group.Type(n),["mask","polygon","rectangle"]), masks{reviewer}=masks{reviewer} | a.rasterize(group.Type(n),group.Geometry{n},size(regionA)); objects(reviewer)=objects(reviewer)+1; end, end, end
                    if sum(objects)==0, continue; end; metrics=VIStudioMasksV11.metrics(masks{1},masks{2}); rows(end+1,:)={a.Files(k),name,metrics.IoU,metrics.Dice,objects(1),objects(2)};
                end
            end
            report=struct('Regions',rows,'MatchedImages',sum(ismember(hashesA,hashesB)),'MeanIoU',mean(rows.IoU),'MeanDice',mean(rows.Dice),'Meaning',"Reviewer agreement, not model accuracy; keypoints need point-wise evaluation");
        end
        function export(report,folder)
            assert(~isfolder(folder) && ~isfile(folder),'VIStudioV15:FileExists','Choose a new report folder.'); mkdir(folder); save(fullfile(folder,'quality.mat'),'report','-v7.3'); if isfield(report,'Issues'), writetable(report.Issues,fullfile(folder,'issues.csv'),'Encoding','UTF-8'); writetable(report.Classes,fullfile(folder,'classes.csv'),'Encoding','UTF-8'); else, writetable(report.Regions,fullfile(folder,'reviewer_agreement.csv'),'Encoding','UTF-8'); end
        end
    end
end
