classdef VIStudioMasksV11
    methods (Static)
        function data=read(file)
            if endsWith(lower(string(file)),'.csv'), data=readtable(file,'Delimiter',',','ReadVariableNames',true,'TextType','string','VariableNamingRule','preserve');
            else, loaded=load(file); assert(isfield(loaded,'manifest'),'VIStudioV11:MaskManifest','MAT requires manifest.'); data=loaded.manifest; end
            assert(istable(data) && all(ismember({'File','MaskFile','Label'},data.Properties.VariableNames)),'VIStudioV11:MaskManifest','Require File, MaskFile, Label columns.');
            for name={'File','MaskFile','Label'}, data.(name{1})=string(data.(name{1})); end
            if ~ismember('Split',data.Properties.VariableNames), data.Split=repmat("train",height(data),1); else, data.Split=string(data.Split); end
            data=data(:,{'File','MaskFile','Label','Split'});
            for k=1:height(data)
                for f={'File','MaskFile'}
                    path=data.(f{1})(k); absolute=startsWith(path,"/") || startsWith(path,"\") || ~isempty(regexp(char(path),'^[A-Za-z]:[\\/]','once'));
                    if ~absolute, path=string(fullfile(fileparts(file),path)); end
                    assert(isfile(path),'VIStudioV11:MaskMissing','Image or mask file is missing.'); data.(f{1})(k)=VIStudioToolsV3.canonicalPath(path);
                end
            end
            VIStudioMasksV11.validate(data);
        end
        function snapshot=validate(data,normal)
            if nargin<2, normal="good"; end
            assert(~isempty(data) && all(ismember(data.Split,["train","validation","test","calibration"])),'VIStudioV11:MaskSplit','Invalid or empty mask dataset.');
            assert(numel(unique(lower(data.File)))==height(data),'VIStudioV11:MaskDuplicate','Each source image must have one mask record.');
            pixels=strings(height(data),1); maskHash=pixels; sourceHash=pixels;
            for k=1:height(data)
                image=VIStudioData.readImage(data.File(k),[]); mask=VIStudioMasksV11.mask(data.MaskFile(k));
                assert(isequal(size(image,[1 2]),size(mask)),'VIStudioV11:MaskSize','Source image and truth mask resolutions differ.');
                assert((data.Label(k)==normal)==~any(mask,'all'),'VIStudioV11:MaskLabel','Normal images need empty masks; abnormal images need nonempty masks.');
                pixels(k)=VIStudioDataHealthV8.pixelHash(image); sourceHash(k)=VIStudioToolsV3.fileHash(data.File(k)); maskHash(k)=VIStudioToolsV3.fileHash(data.MaskFile(k));
            end
            for hash=unique(pixels)'
                rows=pixels==hash; assert(numel(unique(data.Split(rows)))==1,'VIStudioV11:MaskLeak','Identical image content crosses dataset roles.');
                if sum(rows)>1
                    decoded=cellfun(@(f) VIStudioMasksV11.mask(f),cellstr(data.MaskFile(rows)),'UniformOutput',false);
                    assert(all(cellfun(@(x) isequal(x,decoded{1}),decoded)),'VIStudioV11:MaskConflict','Identical images have different truth masks.');
                end
            end
            snapshot=data; snapshot.SourceHash=sourceHash; snapshot.MaskHash=maskHash; snapshot.PixelHash=pixels;
        end
        function mask=mask(file,target)
            [raw,map]=imread(file); assert(isempty(map) && ismatrix(raw),'VIStudioV11:BinaryMask','Use a single-channel binary mask.');
            values=unique(raw); assert(all(ismember(double(values),[0 1 255])),'VIStudioV11:BinaryMask','Mask values must be 0/1 or 0/255.'); mask=raw>0;
            if nargin>1, mask=imresize(mask,target(1:2),'nearest'); end
        end
        function [model,metadata,run]=train(data,base,options,folder,external,run)
            if nargin<5, external=[]; end; if nargin<6, run=VIStudioTrainingRunV9; end
            defaults=struct('NormalLabel',"good",'Size',224,'AugmentCopies',0,'Seed',42);
            for f=fieldnames(options)', assert(isfield(defaults,f{1}),'VIStudioV11:MaskOptions','Unknown mask training option.'); defaults.(f{1})=options.(f{1}); end; o=defaults;
            validateattributes(o.Size,{'numeric'},{'scalar','integer','>=',32,'<=',1024}); validateattributes(o.AugmentCopies,{'numeric'},{'scalar','integer','>=',0,'<=',20});
            snapshot=VIStudioMasksV11.validate(data,o.NormalLabel); train=data.Split=="train";
            assert(sum(train & data.Label==o.NormalLabel)>=2 && any(train & data.Label~=o.NormalLabel),'VIStudioV11:MaskTrainingData','Require two normal training images and masked anomaly training images.');
            if ~isempty(external)
                assert(isa(external.Model,'fcddAnomalyDetector'),'VIStudioV11:MaskExternal','Mask warm-start requires an FCDD model.');
                plan=struct('Manifest',table(snapshot.File,snapshot.Split,snapshot.PixelHash,'VariableNames',{'File','Split','PixelHash'})); VIStudioDatasetV9.assertParentIndependent(plan,external);
                assert(VIStudioToolsV3.fileHash(external.File)==external.Digest,'VIStudioV11:ChangedModel','External model changed.');
            end
            assert(~isfolder(folder) && ~isfile(folder),'VIStudioV11:FileExists','Choose a new training output folder.'); mkdir(folder); mkdir(fullfile(folder,'images')); mkdir(fullfile(folder,'masks'));
            prepared=table(strings(0,1),strings(0,1),strings(0,1),strings(0,1),'VariableNames',{'File','MaskFile','Label','SourceFile'});
            advanced=VIStudioTrainingOptionsV6.defaults(); run.begin('anomaly','FCDD / mask supervised',base,advanced,fullfile(folder,'runs'));
            try
                for row=find(train)'
                    image=VIStudioData.readImage(data.File(row),[o.Size o.Size]); mask=VIStudioMasksV11.mask(data.MaskFile(row),[o.Size o.Size]);
                    for copy=0:o.AugmentCopies
                        im=image; truth=mask;
                        if copy>0
                            stream=RandStream('mt19937ar','Seed',o.Seed+row*1000+copy); turns=randi(stream,4)-1; im=rot90(im,turns); truth=rot90(truth,turns);
                            if rand(stream)>.5, im=fliplr(im); truth=fliplr(truth); end
                        end
                        id=height(prepared)+1; imFile=string(fullfile(folder,'images',sprintf('%06d.png',id))); maskFile=string(fullfile(folder,'masks',sprintf('%06d.png',id)));
                        imwrite(im,imFile); imwrite(truth,maskFile); prepared(end+1,:)={imFile,maskFile,data.Label(row),data.File(row)}; %#ok<AGROW>
                    end
                end
                normal=prepared.Label==o.NormalLabel; normalDS=imageDatastore(cellstr(prepared.File(normal)));
                abnormal=combine(imageDatastore(cellstr(prepared.File(~normal))),imageDatastore(cellstr(prepared.MaskFile(~normal)),'ReadFcn',@(f) VIStudioMasksV11.mask(f)));
                if isempty(external), model=fcddAnomalyDetector(pretrainedEncoderNetwork("resnet18",3)); else, model=external.Model; end
                native=VIStudioTrainingOptionsV6.native(base,advanced,[]); native.OutputFcn=@(info) run.callback(info); native.BatchNormalizationStatistics='moving';
                run.stage('像素監督訓練 / Mask-supervised training',true);
                [model,info]=trainFCDDAnomalyDetector(normalDS,abnormal,model,native,'UseMaskData',true);
                run.ingest(info); status="complete"; if run.StopRequested, status="stopped"; end; run.finish(status); model.Threshold=[];
                metadata=struct('Task',"anomaly",'ModelName',"FCDD / mask supervised",'ClassNames',["Normal";"Anomaly"], ...
                    'ImageSize',[o.Size o.Size],'NormalLabel',o.NormalLabel,'Calibrated',false,'MaskSupervised',true, ...
                    'SourceFiles',snapshot.File(train),'SourcePixelHashes',snapshot.PixelHash(train),'MaskSnapshot',snapshot,'MaskOptions',o, ...
                    'TrainingOptions',base,'TrainingStatus',status,'RunFolder',run.RunFolder);
                if ~isempty(external)
                    metadata.ParentModel=external.File; metadata.ParentDigest=external.Digest;
                    if isfield(external.Metadata,'SourceFiles'), metadata.SourceFiles=unique([metadata.SourceFiles;string(external.Metadata.SourceFiles(:))]); end
                    if isfield(external.Metadata,'SourcePixelHashes'), metadata.SourcePixelHashes=unique([metadata.SourcePixelHashes;string(external.Metadata.SourcePixelHashes(:))]); end
                end
                save(fullfile(folder,'model.mat'),'model','metadata','info','-v7.3'); save(fullfile(folder,'dataset.mat'),'snapshot','prepared','o');
                writetable(prepared,fullfile(folder,'prepared.csv'),'Encoding','UTF-8'); run.attachCheckpoint(fullfile(folder,'model.mat'));
            catch err, run.finish('failed',err.message); rethrow(err); end
        end
        function r=metrics(predicted,truth,valid)
            assert(islogical(predicted) && islogical(truth) && isequal(size(predicted),size(truth)),'VIStudioV11:MaskMetricSize','Masks must be logical and have matching resolutions.');
            if nargin<3, valid=true(size(truth)); end; assert(islogical(valid) && isequal(size(valid),size(truth)) && any(valid,'all'),'VIStudioV11:MetricCoverage','No valid evaluation pixels.');
            a=predicted(valid); b=truth(valid); tp=sum(a & b); fp=sum(a & ~b); fn=sum(~a & b); tn=sum(~a & ~b);
            iou=1; dice=1; if tp+fp+fn>0, iou=tp/(tp+fp+fn); dice=2*tp/(2*tp+fp+fn); end
            precision=1; recall=1; if tp+fp>0, precision=tp/(tp+fp); end; if tp+fn>0, recall=tp/(tp+fn); end
            r=struct('TP',tp,'FP',fp,'FN',fn,'TN',tn,'IoU',iou,'Dice',dice,'Precision',precision,'Recall',recall);
        end
        function [rows,summary]=evaluate(artifact,data,threshold)
            assert(VIStudioToolsV3.fileHash(artifact.File)==artifact.Digest,'VIStudioV11:ChangedModel','Model changed; reload it.');
            validateattributes(threshold,{'numeric'},{'scalar','real','finite','nonnegative'}); VIStudioMasksV11.validate(data);
            assert(all(ismember(data.Split,["test","validation"])),'VIStudioV11:EvaluationSplit','Evaluate only reserved validation or test rows.');
            plan=struct('Manifest',table(data.File,data.Split,strings(height(data),1),'VariableNames',{'File','Split','PixelHash'}));
            for k=1:height(data), plan.Manifest.PixelHash(k)=VIStudioDataHealthV8.pixelHash(VIStudioData.readImage(data.File(k),[])); end
            VIStudioDatasetV9.assertParentIndependent(plan,artifact);
            rows=table(); totals=zeros(1,4);
            for k=1:height(data)
                image=VIStudioData.readImage(data.File(k),[]); map=anomalyMap(artifact.Model,imresize(image,artifact.InputSize(1:2)),'ExecutionEnvironment','cpu'); map=gather(extract(map));
                predicted=imresize(map>=threshold,size(image,[1 2]),'nearest'); truth=VIStudioMasksV11.mask(data.MaskFile(k)); m=VIStudioMasksV11.metrics(predicted,truth);
                record=struct2table(m); record.File=data.File(k); record.Defect=any(truth,'all'); rows=[rows;record]; totals=totals+[m.TP m.FP m.FN m.TN]; %#ok<AGROW>
            end
            denominator=sum(totals(1:3)); iou=1; dice=1; if denominator>0, iou=totals(1)/denominator; dice=2*totals(1)/(2*totals(1)+totals(2)+totals(3)); end
            summary=struct('Images',height(rows),'Threshold',threshold,'MicroIoU',iou,'MicroDice',dice,'MeanIoU',mean(rows.IoU),'MeanDice',mean(rows.Dice),'DefectOnlyIoU',mean(rows.IoU(rows.Defect)),'DefectOnlyDice',mean(rows.Dice(rows.Defect)),'Totals',totals);
            function x=extract(x), if isa(x,'dlarray'), x=extractdata(x); end, end
        end
        function artifact=calibrateModel(artifact,data,percentile,file)
            assert(~isfile(file),'VIStudioV11:FileExists','Choose a new calibrated model filename.');
            [pixel,image]=VIStudioMasksV11.calibrate(artifact,data,percentile);
            loaded=load(artifact.File); model=artifact.Model; metadata=artifact.Metadata;
            metadata.Threshold=image; metadata.PixelThreshold=pixel; metadata.Calibrated=true;
            metadata.CalibrationMethod="Independent normal percentile"; metadata.CalibrationPercentile=percentile;
            metadata.CalibrationSnapshot=VIStudioMasksV11.validate(data); metadata.ParentDigest=artifact.Digest;
            files=strings(0,1); hashes=files;
            if isfield(metadata,'SourceFiles'), files=string(metadata.SourceFiles(:)); end
            if isfield(metadata,'SourcePixelHashes'), hashes=string(metadata.SourcePixelHashes(:)); end
            metadata.SourceFiles=unique([files;data.File]); metadata.SourcePixelHashes=unique([hashes;metadata.CalibrationSnapshot.PixelHash]);
            if isprop(model,'Threshold'), model.Threshold=image; end
            if isfield(loaded,'info'), info=loaded.info; save(file,'model','metadata','info','-v7.3'); else, save(file,'model','metadata','-v7.3'); end
            artifact=VIStudioInferenceV11.load(file,'anomaly');
        end
        function [threshold,imageThreshold]=calibrate(artifact,data,percentile)
            validateattributes(percentile,{'numeric'},{'scalar','>=',50,'<',100});
            assert(~isempty(data) && all(data.Split=="calibration"),'VIStudioV11:CalibrationSplit','Use an independent calibration partition.'); VIStudioMasksV11.validate(data);
            plan=struct('Manifest',table(data.File,data.Split,strings(height(data),1),'VariableNames',{'File','Split','PixelHash'}));
            assert(VIStudioToolsV3.fileHash(artifact.File)==artifact.Digest,'VIStudioV11:ChangedModel','Model changed; reload it.');
            pool=[]; scores=zeros(height(data),1);
            for k=1:height(data)
                image=VIStudioData.readImage(data.File(k),[]); plan.Manifest.PixelHash(k)=VIStudioDataHealthV8.pixelHash(image);
                assert(~any(VIStudioMasksV11.mask(data.MaskFile(k)),'all'),'VIStudioV11:NormalCalibration','Pixel calibration uses normal masks only.');
                scores(k)=double(predict(artifact.Model,imresize(image,artifact.InputSize(1:2)),'ExecutionEnvironment','cpu'));
                map=anomalyMap(artifact.Model,imresize(image,artifact.InputSize(1:2)),'ExecutionEnvironment','cpu'); if isa(map,'dlarray'), map=extractdata(map); end; map=gather(map); pool=[pool;double(map(:))]; %#ok<AGROW>
            end
            VIStudioDatasetV9.assertParentIndependent(plan,artifact); threshold=prctile(pool,percentile); imageThreshold=prctile(scores,percentile);
        end
    end
end
