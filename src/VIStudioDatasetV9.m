classdef VIStudioDatasetV9 < handle
    % Explicit roles, deterministic group splitting and immutable run snapshots.
    properties (SetAccess=private)
        Task
        Config
        Plan=[]
    end
    methods
        function data=VIStudioDatasetV9(task)
            data.Task=string(task);
            data.Config=struct('Mode',"automatic",'Sources',struct('train',"",'validation',"",'test',"",'calibration',""), ...
                'TestPercent',0,'CalibrationPercent',0,'GroupFile',"");
        end
        function configure(data,value)
            candidate=data.Config; names=fieldnames(value);
            for k=1:numel(names)
                assert(isfield(candidate,names{k}),'VIStudioV9:DatasetConfig','Unknown dataset option: %s',names{k});
                candidate.(names{k})=value.(names{k});
            end
            data.validateConfig(candidate);
            for role=["train","validation","test","calibration"]
                path=string(candidate.Sources.(role)); if strlength(path)>0, candidate.Sources.(role)=VIStudioToolsV3.canonicalPath(path); end
            end
            if strlength(string(candidate.GroupFile))>0, candidate.GroupFile=VIStudioToolsV3.canonicalPath(candidate.GroupFile); end
            data.Config=candidate; data.Plan=[];
        end
        function setSource(data,role,path)
            role=string(validatestring(role,{'train','validation','test','calibration'}));
            sources=data.Config.Sources; sources.(role)=string(path); data.configure(struct('Sources',sources));
        end
        function restore(data,config), data.validateConfig(config); data.configure(config); end
        function plan=build(data,validationPercent,seed)
            config=data.Config; data.validateConfig(config);
            validateattributes(validationPercent,{'numeric'},{'scalar','finite','>=',0,'<=',50});
            validateattributes(seed,{'numeric'},{'scalar','integer','nonnegative'});
            samples=table(); gt=[]; splits=strings(0,1); sourceRecords=struct();
            roles="train"; if config.Mode=="explicit", roles=["train","validation","test","calibration"]; end
            for role=roles
                path=string(config.Sources.(role)); if strlength(path)==0, continue; end
                if data.Task=="detection"
                    [current,~,boxes]=VIStudioTrainingDataV4.groundTruth(path);
                    if isempty(gt), gt=boxes;
                    else
                        expected=string(gt.Properties.VariableNames(2:end)); incoming=string(boxes.Properties.VariableNames(2:end));
                        assert(all(ismember(incoming,expected)),'VIStudioV9:DatasetClasses','Holdout annotations contain classes absent from training.');
                        normalized=table(boxes.imageFilename,'VariableNames',{'imageFilename'});
                        for name=expected
                            if ismember(name,incoming), normalized.(name)=boxes.(name);
                            else, normalized.(name)=repmat({zeros(0,4)},height(boxes),1); end
                        end
                        gt=[gt;normalized];
                    end
                else, [current,~]=VIStudioTrainingDataV4.folder(path); end
                for k=1:height(current), current.File(k)=VIStudioToolsV3.canonicalPath(current.File(k)); end
                samples=[samples;current]; splits=[splits;repmat(role,height(current),1)]; %#ok<AGROW>
                sourceRecords.(role)=struct('Path',VIStudioToolsV3.canonicalPath(path),'Images',height(current));
            end
            assert(~isempty(samples) && any(splits=="train"),'VIStudioV9:MissingData','Load training data first.');
            if ~isempty(gt), gt.imageFilename=cellstr(samples.File); end
            health=VIStudioDataHealthV8.scan(samples.File,samples.Label,data.Task,gt);
            groups="pixel:"+health.Images.PixelHash;
            if strlength(string(config.GroupFile))>0
                mapping=readtable(config.GroupFile,'Delimiter',',','ReadVariableNames',true,'TextType','string','VariableNamingRule','preserve');
                mapping.Properties.VariableNames=cellstr(strtrim(string(mapping.Properties.VariableNames)));
                assert(all(ismember({'File','Group'},mapping.Properties.VariableNames)),'VIStudioV9:GroupManifest','CSV requires File and Group columns.');
                mapping.File=string(mapping.File); mapping.Group=strtrim(string(mapping.Group));
                for k=1:height(mapping)
                    path=mapping.File(k);
                    if ~isfile(path), path=string(fullfile(fileparts(config.GroupFile),path)); end
                    mapping.File(k)=VIStudioToolsV3.canonicalPath(path);
                end
                assert(numel(unique(lower(mapping.File)))==height(mapping) && all(~ismissing(mapping.Group) & strlength(strtrim(mapping.Group))>0), ...
                    'VIStudioV9:GroupManifest','Group mappings need unique paths and nonempty group IDs.');
                [found,rows]=ismember(lower(samples.File),lower(mapping.File));
                assert(all(found),'VIStudioV9:GroupManifest','Every selected image must have a group mapping.'); groups=mapping.Group(rows);
            end
            if config.Mode=="automatic"
                percentages=[validationPercent config.TestPercent config.CalibrationPercent];
                if data.Task=="anomaly", percentages(1)=0; end % no anomaly validation selection is implemented
                assert(sum(percentages)<100,'VIStudioV9:SplitPercent','Holdout percentages must total less than 100.');
                splits(:)="train"; uniqueGroups=unique(groups); strata=strings(numel(uniqueGroups),1);
                for k=1:numel(uniqueGroups)
                    if data.Task=="detection", strata(k)="objects";
                    else, strata(k)=join(sort(unique(samples.Label(groups==uniqueGroups(k)))),"|"); end
                end
                stream=RandStream('mt19937ar','Seed',seed);
                for stratum=unique(strata)'
                    indices=find(strata==stratum); indices=indices(randperm(stream,numel(indices))); available=numel(indices); cursor=1;
                    for k=1:3
                        amount=0; if percentages(k)>0, amount=min(available-1,max(1,round(numel(indices)*percentages(k)/100))); end
                        if amount>0
                            selected=uniqueGroups(indices(cursor:cursor+amount-1)); splits(ismember(groups,selected))=rolesForHoldout(k);
                            cursor=cursor+amount; available=available-amount;
                        end
                    end
                end
                for k=1:3
                    if percentages(k)>0 && ~any(splits==rolesForHoldout(k))
                        health=issue(health,'INSUFFICIENT_GROUPS',"","",'群組不足以配置指定保留集 / Not enough independent groups for requested holdouts');
                    end
                end
            end
            if data.Task=="classification"
                trainClasses=unique(samples.Label(splits=="train"));
                if any(~ismember(samples.Label,trainClasses)), health=issue(health,'UNKNOWN_HOLDOUT_CLASS',"","",'保留集含訓練集未見類別 / Holdout contains a class absent from training'); end
            end
            if data.Task=="detection" && sum(samples.Objects(splits=="train"))==0
                health=issue(health,'NO_TRAIN_BOXES',"","",'訓練集沒有正樣本框 / Training split has no positive boxes');
            end
            for field={groups,health.Images.PixelHash}
                values=field{1};
                for value=unique(values)'
                    rows=find(values==value & strlength(value)>0);
                    if numel(unique(splits(rows)))>1
                        code='GROUP_LEAK'; if isequal(values,health.Images.PixelHash), code='SPLIT_PIXEL_LEAK'; end
                        health=issue(health,code,samples.File(rows(1)),samples.File(rows(end)), ...
                            '相同群組或像素跨越不同用途 / Same group or decoded content appears across dataset roles');
                    end
                end
            end
            manifest=table(samples.File,samples.Label,splits,groups,health.Images.FileHash,health.Images.PixelHash, ...
                'VariableNames',{'File','Label','Split','Group','SourceHash','PixelHash'});
            content=struct('Task',data.Task,'Config',config,'Manifest',table2struct(manifest),'Annotations',[]);
            if ~isempty(gt), content.Annotations=table2struct(gt); end
            fingerprint=VIStudioDatasetV9.digest(jsonencode(content));
            counts=table(["train";"validation";"test";"calibration"],zeros(4,1),zeros(4,1),'VariableNames',{'Split','Images','Groups'});
            for k=1:4, rows=splits==counts.Split(k); counts.Images(k)=sum(rows); counts.Groups(k)=numel(unique(groups(rows))); end
            plan=struct('Task',data.Task,'Config',config,'Samples',samples,'Annotations',gt,'Manifest',manifest,'Counts',counts, ...
                'Health',health,'Fingerprint',fingerprint,'Sources',sourceRecords,'Seed',seed,'ValidationPercent',validationPercent);
            data.Plan=plan;
            function name=rolesForHoldout(k), all=["validation","test","calibration"]; name=all(k); end
            function report=issue(report,code,file,related,message)
                report.Issues(end+1,:)={"error",string(code),string(file),string(related),string(message)};
                report.Errors=report.Errors+1;
            end
        end
    end
    methods (Static)
        function assertParentIndependent(plan,external)
            if isempty(external), return; end
            files=strings(0,1); pixels=strings(0,1); metadata=external.Metadata;
            if isfield(metadata,'SourceFiles'), files=string(metadata.SourceFiles(:)); end
            if isfield(metadata,'SourcePixelHashes'), pixels=string(metadata.SourcePixelHashes(:)); end
            for k=1:numel(files)
                if isfile(files(k)), pixels(end+1,1)=VIStudioDataHealthV8.pixelHash(VIStudioData.readImage(files(k),[])); end
            end
            heldout=plan.Manifest(plan.Manifest.Split~="train",:);
            assert(~any(ismember(lower(heldout.File),lower(files))) && ~any(ismember(heldout.PixelHash,pixels)), ...
                'VIStudioV9:ParentDatasetOverlap','外部模型曾使用保留集影像；請重新分配獨立資料 / External model provenance overlaps a held-out dataset.');
        end
        function validateConfig(config)
            assert(isstruct(config) && isscalar(config) && all(isfield(config,{'Mode','Sources','TestPercent','CalibrationPercent','GroupFile'})), ...
                'VIStudioV9:DatasetConfig','Invalid dataset configuration.');
            validatestring(config.Mode,{'automatic','explicit'});
            assert(isstruct(config.Sources) && isscalar(config.Sources) && all(isfield(config.Sources,{'train','validation','test','calibration'})), ...
                'VIStudioV9:DatasetConfig','Dataset sources require all four roles.');
            for role=["train","validation","test","calibration"]
                path=string(config.Sources.(role)); assert(isscalar(path) && ~ismissing(path),'VIStudioV9:DatasetConfig','Invalid source path.');
                assert(strlength(path)==0 || isfolder(path) || isfile(path),'VIStudioV9:DatasetSource','Dataset source is missing: %s',path);
            end
            for name={'TestPercent','CalibrationPercent'}, validateattributes(config.(name{1}),{'numeric'},{'scalar','finite','>=',0,'<=',50}); end
            path=string(config.GroupFile); assert(isscalar(path) && (strlength(path)==0 || isfile(path)),'VIStudioV9:GroupManifest','Group CSV is missing.');
        end
        function assertUnchanged(plan)
            assert(plan.Health.Errors==0,'VIStudioV9:DataHealth','Resolve dataset health errors before training.');
            for k=1:height(plan.Manifest)
                assert(isfile(plan.Manifest.File(k)) && VIStudioToolsV3.fileHash(plan.Manifest.File(k))==plan.Manifest.SourceHash(k), ...
                    'VIStudioV9:DatasetChanged','An image changed after the dataset snapshot was created. Rebuild the plan.');
            end
        end
        function value=digest(text)
            payload=unicode2native(char(text),'UTF-8'); algorithm=System.Security.Cryptography.SHA256.Create(); cleanup=onCleanup(@() algorithm.Dispose());
            bytes=uint8(algorithm.ComputeHash(payload)); value=lower(string(reshape(dec2hex(bytes,2)',1,[])));
        end
    end
end
