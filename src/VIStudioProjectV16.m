classdef VIStudioProjectV16 < handle
    % Project metadata only. Source images, labels and models remain separate.
    properties (SetAccess=private)
        File=""
        Info
        FileDigest=""
    end
    methods
        function app=VIStudioProjectV16(file)
            if nargin<1, app.Info=VIStudioProjectV16.defaults('New project','classification'); return; end
            loaded=load(file,'project'); assert(isfield(loaded,'project'),'VIStudioV16:Project','Require a VIStudio project file.'); VIStudioProjectV16.validate(loaded.project); app.File=VIStudioToolsV3.canonicalPath(file); app.FileDigest=VIStudioToolsV3.fileHash(file); app.Info=loaded.project;
            base=fileparts(app.File); for role=VIStudioProjectV16.roles(), value=string(app.Info.(role)); if strlength(value)>0 && ~VIStudioProjectV16.isAbsolute(value), app.Info.(role)=string(fullfile(base,value)); end, end
        end
        function setName(app,name,note)
            assert(strlength(strtrim(string(name)))>0,'VIStudioV16:Name','Project name is required.'); app.Info.Name=string(name); if nargin>2, app.Info.Note=string(note); end
        end
        function attach(app,role,file)
            role=string(validatestring(role,cellstr(VIStudioProjectV16.roles()))); file=VIStudioToolsV3.canonicalPath(file);
            if role=="ImageFolder", assert(isfolder(file),'VIStudioV16:Resource','Image folder is missing.'); else, assert(isfile(file),'VIStudioV16:Resource','Resource file is missing.'); end
            previous=app.Info; app.Info.(role)=file;
            try
            if role=="DatasetFile"
                info=app.datasetInfo(); if strlength(info.Error)>0 || (strlength(info.Task)>0 && info.Task~=app.Info.Task), app.Info=previous; error('VIStudioV16:DatasetTask','Dataset is invalid or its task differs from this project. %s',info.Error); end
            elseif role=="SessionFile"
                try, loaded=load(file,'session'); assert(isfield(loaded,'session') && all(isfield(loaded.session,{'Files','Reviewed','Annotations'}))); catch, app.Info=previous; error('VIStudioV16:Session','Select an editable VIStudio annotation session.'); end
            elseif role=="ModelFile"
                names=who('-file',char(file)); if ~any(ismember(names,{'model','detector','net','trainedNet','trainedNetwork'})), app.Info=previous; error('VIStudioV16:Model','No supported model variable was found. Attaching does not execute or validate a model.'); end
            elseif role=="EvaluationFile"
                info=app.evaluationInfo(); if strlength(info.Error)>0, app.Info=previous; error('VIStudioV16:Evaluation','%s',info.Error); end
            end
            catch err, app.Info=previous; rethrow(err); end
        end
        function detach(app,role), role=string(validatestring(role,cellstr(VIStudioProjectV16.roles()))); app.Info.(role)=""; end
        function save(app,file)
            if nargin<2, file=app.File; end; assert(strlength(string(file))>0,'VIStudioV16:Project','Choose a project file.'); parent=fileparts(char(file)); if isempty(parent), parent=pwd; file=fullfile(parent,file); end; if ~isfolder(parent), mkdir(parent); end; file=VIStudioToolsV3.canonicalPath(file);
            if isfile(file)
                assert(strcmpi(file,app.File) && app.FileDigest==VIStudioToolsV3.fileHash(file),'VIStudioV16:ProjectChanged','Project file already exists or changed externally. Reload or save to a new file.');
            end
            app.Info.Updated=string(datetime('now','Format','yyyy-MM-dd HH:mm:ss')); VIStudioProjectV16.validate(app.Info); project=app.Info; base=string(fileparts(file));
            if ~isfolder(base), mkdir(base); end
            for role=VIStudioProjectV16.roles(), value=string(project.(role)); if startsWith(lower(value),lower(base+filesep)), project.(role)=extractAfter(value,strlength(base)+1); end, end
            temp=[tempname(base) '.mat']; cleanup=onCleanup(@() VIStudioProjectV16.cleanTemp(temp)); save(temp,'project','-v7.3'); movefile(temp,file,'f'); app.File=file; app.FileDigest=VIStudioToolsV3.fileHash(file);
        end
        function d=datasetInfo(app)
            d=struct('Images',0,'Classes',0,'Objects',0,'Train',0,'Validation',0,'Test',0,'Missing',0,'Task',"",'Error',"",'Format',"none"); file=app.Info.DatasetFile; if strlength(file)==0, return; end
            if ~isfile(file), d.Error="Dataset file is missing"; return; end
            try
                names=who('-file',char(file));
                if all(ismember({'manifest','classes'},names))
                    loaded=load(file,'manifest','classes','schema','objects'); m=loaded.manifest; d.Format="manifest"; if isfield(loaded,'schema') && isfield(loaded.schema,'Task'), d.Task=string(loaded.schema.Task); elseif isfield(loaded,'schema') && isfield(loaded.schema,'Type'), d.Task="semantic"; elseif ismember('LabelFile',m.Properties.VariableNames), d.Task="semantic"; end
                    assert(istable(m) && ismember('File',m.Properties.VariableNames),'Missing manifest File column'); d.Images=height(m); d.Classes=numel(loaded.classes); if istable(loaded.classes), d.Classes=height(loaded.classes); end
                    files=string(m.File); for k=1:numel(files), if ~VIStudioProjectV16.isAbsolute(files(k)), files(k)=fullfile(fileparts(file),files(k)); end, end; d.Missing=nnz(~isfile(files));
                    if ismember('LabelFile',m.Properties.VariableNames), labels=string(m.LabelFile); for k=1:numel(labels), if ~VIStudioProjectV16.isAbsolute(labels(k)), labels(k)=fullfile(fileparts(file),labels(k)); end, end; d.Missing=d.Missing+nnz(~isfile(labels)); end
                    if ismember('Split',m.Properties.VariableNames), splits=string(m.Split); assert(all(ismember(splits,["train","validation","test","calibration"])),'Invalid split'); d.Train=nnz(splits=="train"); d.Validation=nnz(splits=="validation"); d.Test=nnz(splits=="test"); end
                    if isfield(loaded,'objects'), d.Objects=height(loaded.objects); if ismember('MaskFile',loaded.objects.Properties.VariableNames), masks=string(loaded.objects.MaskFile); masks=masks(strlength(masks)>0); for k=1:numel(masks), if ~VIStudioProjectV16.isAbsolute(masks(k)), masks(k)=fullfile(fileparts(file),masks(k)); end, end; d.Missing=d.Missing+nnz(~isfile(masks)); end, end
                elseif any(ismember(names,{'exportROI','gTruth'}))
                    assert(app.Info.Task=="detection",'Detection data linked to another task'); d.Task="detection"; d.Format="detection"; loaded=load(file); if isfield(loaded,'exportROI'), data=loaded.exportROI; else, data=loaded.gTruth; end; data=VIStudioData.detectionTable(data,fileparts(file)); d.Images=height(data); d.Classes=width(data)-1; d.Missing=nnz(~isfile(string(data.imageFilename)));
                else, error('Unsupported dataset format; choose exported dataset.mat or detection annotations.'); end
            catch err, d.Error=string(err.message); end
        end
        function e=evaluationInfo(app)
            e=struct('Summary',table(),'Meaning',"",'ModelDigest',"",'Error',""); file=app.Info.EvaluationFile; if strlength(file)==0, return; end
            if ~isfile(file), e.Error="Evaluation file is missing"; return; end
            try
                loaded=load(file,'evaluation'); assert(isfield(loaded,'evaluation') && isstruct(loaded.evaluation) && isscalar(loaded.evaluation) && ~isempty(fieldnames(loaded.evaluation)),'Require a results MAT containing evaluation.'); result=loaded.evaluation;
                if isfield(result,'Task'), assert(string(result.Task)==app.Info.Task,'Evaluation task differs from project.'); end
                if isfield(result,'Detailed') && isfield(result.Detailed,'Summary'), e.Summary=struct2table(result.Detailed.Summary); elseif isfield(result,'Summary'), if istable(result.Summary), e.Summary=result.Summary; elseif isstruct(result.Summary), e.Summary=struct2table(result.Summary); end, end
                if isfield(result,'Meaning'), e.Meaning=string(result.Meaning); else, e.Meaning="Attached report; evaluation provenance is not verified by the homepage"; end
                if isfield(result,'ModelDigest'), e.ModelDigest=string(result.ModelDigest); end
            catch err, e.Error=string(err.message); end
        end
        function s=status(app)
            d=app.datasetInfo(); reviewed=0; total=0; pending=0; annotations=0; classCount=0; sessionError=""; missing=0;
            if strlength(app.Info.SessionFile)>0
                try
                    loaded=load(app.Info.SessionFile,'session'); a=loaded.session; assert(numel(a.Reviewed)==numel(a.Files),'Invalid review flags'); total=numel(a.Files); reviewed=nnz(a.Reviewed); annotations=height(a.Annotations); classCount=height(a.Classes); pending=nnz(~a.Annotations.Reviewed); missing=nnz(~isfile(string(a.Files)));
                catch err, sessionError=string(err.message); end
            end
            folderCount=0; folderError="";
            if strlength(app.Info.ImageFolder)>0
                try, ds=imageDatastore(app.Info.ImageFolder,'IncludeSubfolders',true); folderCount=numel(ds.Files); catch err, folderError=string(err.message); end
            end
            imageCount=folderCount; if total>0, imageCount=total; end; if d.Images>0, imageCount=d.Images; end; issues=strings(0,1); if strlength(d.Error)>0, issues(end+1)=d.Error; end; if strlength(sessionError)>0, issues(end+1)="Session: "+sessionError; end; if strlength(folderError)>0, issues(end+1)="Images: "+folderError; end; if missing+d.Missing>0, issues(end+1)="來源影像／遮罩缺失 / Missing source assets: "+string(missing+d.Missing); end
            states=["EMPTY";"NOT_STARTED";"NEEDS_DATA";"NEEDS_MODEL";"NEEDS_MODEL"];
            hints=["連結影像資料夾或匯出資料集 / Link images or dataset";"建立標記並完成候選覆核 / Annotate and review candidates";"準備 train 與獨立 validation/test / Prepare independent splits";"連結模型與保留資料，再執行評估 / Evaluate a model on held-out data";"載入模型後執行單張檢測 / Load a model and inspect an image"];
            if imageCount>0 && isempty(issues), states(1)="DATA_LINKED"; hints(1)="已讀取檔案清單；完整資料驗證於工作區執行 / File inventory read; workspace validates content"; end
            if total>0 && strlength(sessionError)==0
                states(2)="IN_PROGRESS"; if reviewed==total && pending==0 && missing==0, states(2)="REVIEWED"; end; hints(2)=sprintf('%d/%d 張已覆核，%d 候選待確認 / reviewed, pending candidates',reviewed,total,pending);
            elseif d.Images>0 && strlength(d.Error)==0, states(2)="DATASET_LINKED"; hints(2)="已連結匯出資料；首頁不推定人工覆核歷程 / Dataset linked; review history not inferred"; end
            if d.Images>0 && strlength(d.Error)==0 && d.Missing==0
                states(3)="NEEDS_SPLIT"; if d.Train>=2 && d.Test+d.Validation>0, states(3)="READY_TO_CONFIGURE"; end
                hints(3)=sprintf('train %d / validation %d / test %d；尚未執行訓練 / not trained',d.Train,d.Validation,d.Test);
            elseif folderCount>0, states(3)="FOLDER_LINKED"; hints(3)="到訓練頁設定標籤、模型與資料切分 / Configure labels, model and splits in training"; end
            if pending>0, states(3)="REVIEW_PENDING"; hints(3)="目前標記有未確認候選；先覆核再重新匯出資料 / Review candidates and re-export data"; end
            modelLinked=strlength(app.Info.ModelFile)>0 && isfile(app.Info.ModelFile); modelState="NOT_LINKED";
            if modelLinked
                modelState="LINKED_NOT_RUN"; states(5)="MODEL_LINKED_NOT_RUN"; hints(5)="模型檔已連結；未由首頁執行推論 / Model linked; inference not run";
                if d.Validation+d.Test>0 && d.Missing==0 && strlength(d.Error)==0, states(4)="READY_TO_EVALUATE"; end
            elseif strlength(app.Info.ModelFile)>0, issues(end+1)="模型檔案缺失 / Model file missing"; modelState="MISSING"; end
            e=app.evaluationInfo(); if strlength(app.Info.EvaluationFile)>0
                if strlength(e.Error)>0, issues(end+1)=e.Error; states(4)="REPORT_ERROR";
                else
                    states(4)="REPORT_LINKED_UNVERIFIED"; hints(4)="已連結報告；不代表通過驗收 / Attached report, not acceptance approval";
                    if modelLinked && strlength(e.ModelDigest)>0 && e.ModelDigest~=VIStudioToolsV3.fileHash(app.Info.ModelFile), states(4)="REPORT_MODEL_MISMATCH"; hints(4)="報告的模型雜湊與目前模型不符，請重新評估 / Model digest mismatch"; end
                end
            end
            if ~isempty(issues), states(1)="CHECK_LINKS"; end
            next="data"; if states(1)=="DATA_LINKED", next="label"; if any(states(2)==["REVIEWED","DATASET_LINKED"]), next="train"; if modelLinked, next="evaluate"; if states(4)=="REPORT_LINKED_UNVERIFIED", next="inspect"; end, end, end, end
            stages=["data";"label";"train";"evaluate";"inspect"]; titles=["1 資料 / Data";"2 標記 / Annotation";"3 訓練 / Training";"4 評估 / Evaluation";"5 檢測 / Inspection"];
            s=struct('Images',imageCount,'Reviewed',reviewed,'ReviewTotal',total,'Pending',pending,'Annotations',max(annotations,d.Objects),'Classes',max(classCount,d.Classes),'Train',d.Train,'Validation',d.Validation,'Test',d.Test,'ModelState',modelState,'Issues',issues,'Stages',table(stages,titles,states,hints,'VariableNames',{'Stage','Title','State','Hint'}),'Next',next,'Evaluation',e,'Dataset',d,'Meaning',"首頁顯示已保存檔案，未儲存的工作區內容需按同步 / Saved artifacts only; sync workspace changes");
        end
    end
    methods (Static)
        function roles=roles(), roles=["ImageFolder","SessionFile","DatasetFile","ModelFile","EvaluationFile"]; end
        function p=defaults(name,task)
            task=string(validatestring(task,{'classification','detection','anomaly','semantic','instance','keypoints'})); timestamp=string(datetime('now','Format','yyyy-MM-dd HH:mm:ss')); p=struct('Version',16,'Kind',"VIStudioProject",'Name',string(name),'Task',task,'Created',timestamp,'Updated',timestamp,'Note',"",'ImageFolder',"",'SessionFile',"",'DatasetFile',"",'ModelFile',"",'EvaluationFile',"");
        end
        function app=create(name,task,folder)
            file=fullfile(folder,'VIStudioProject.mat'); assert(~isfile(file),'VIStudioV16:FileExists','A project already exists here; open it or select a new folder.'); app=VIStudioProjectV16; app.Info=VIStudioProjectV16.defaults(name,task); assert(strlength(strtrim(app.Info.Name))>0,'VIStudioV16:Name','Project name is required.'); app.save(file);
        end
        function validate(p)
            expected=VIStudioProjectV16.defaults('check','classification'); assert(isstruct(p) && isscalar(p) && all(isfield(p,fieldnames(expected))) && p.Version==16 && string(p.Kind)=="VIStudioProject",'VIStudioV16:Project','Unsupported project metadata.'); validatestring(p.Task,{'classification','detection','anomaly','semantic','instance','keypoints'});
            for field=["Name","Note",VIStudioProjectV16.roles()], assert(isscalar(string(p.(field))),'VIStudioV16:Project','Project text fields must be scalar.'); end
        end
        function yes=isAbsolute(file), yes=startsWith(file,"/") || startsWith(file,"\") || ~isempty(regexp(char(file),'^[A-Za-z]:[\\/]','once')); end
        function cleanTemp(file), if isfile(file), delete(file); end, end
    end
end
