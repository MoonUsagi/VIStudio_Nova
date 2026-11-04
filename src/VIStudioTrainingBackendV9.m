classdef VIStudioTrainingBackendV9
    methods (Static)
        function input=inputSize(task,choice,base,external)
            if ~isempty(external), input=external.InputSize; return; end
            if task=="classification"
                size=224; if ismember(choice,["xception","inceptionv3"]), size=299; end
                input=[size size 3];
            else, input=[base.Size base.Size 3]; end
        end
        function [model,metadata,info,prepared]=train(task,choice,samples,gt,base,o,external,folder,monitor,plan)
            if nargin<9 || isempty(monitor), monitor=VIStudioTrainingRunV9; end
            if monitor.Summary.Status~="running", monitor.begin(task,choice,base,o); end
            if nargin<10, plan=[]; end
            try
            if ~isempty(plan)
                assert(string(plan.Task)==string(task),'VIStudioV9:DatasetTask','Dataset task mismatch.');
                VIStudioDatasetV9.assertUnchanged(plan); samples=plan.Samples; gt=plan.Annotations;
                monitor.attachDataset(plan);
                VIStudioDatasetV9.assertParentIndependent(plan,external);
            end
            monitor.stage('資料準備 / Preparing data',true);
            assert(~isempty(samples),'VIStudioV9:MissingData','Load training data first.');
            o=VIStudioTrainingOptionsV6.merge(VIStudioTrainingOptionsV6.defaults(),o);
            saved=rng; cleanup=onCleanup(@() rng(saved)); rng(o.Seed,'twister');
            input=VIStudioTrainingBackendV9.inputSize(task,choice,base,external);
            classes=unique(samples.Label); if ~isempty(plan), classes=unique(samples.Label(plan.Manifest.Split=="train")); end; model=[]; info=[]; mode="new";
            if ~isempty(external)
                assert(isfile(external.File) && VIStudioToolsV3.fileHash(external.File)==external.Digest, ...
                    'VIStudioV9:ExternalChanged','External MAT contents changed; reload the model.');
                model=external.Model; mode="warm-start"; monitor.attachParent(external);
            end
            if task=="classification"
                assert(numel(classes)>=2,'VIStudioV9:MissingClasses','Classification requires at least two classes.');
                if isempty(model), model=imagePretrainedNetwork(string(choice),'NumClasses',numel(classes));
                elseif o.ReplaceHead
                    head=networkHead(model); layer=getLayer(model,head);
                    if isa(layer,'nnet.cnn.layer.FullyConnectedLayer'), replacement=fullyConnectedLayer(numel(classes),'Name',char(head));
                    else, replacement=convolution2dLayer(layer.FilterSize,numel(classes),'Name',char(head), ...
                            'Padding',layer.PaddingSize,'Stride',layer.Stride); end
                    model=replaceLayer(model,head,replacement); model=initialize(model);
                else
                    assert(numel(external.Classes)==numel(classes) && all(ismember(classes,external.Classes)), ...
                        'VIStudioV9:ClassMismatch','External class names must match, or enable Replace head.');
                    classes=external.Classes;
                end
                input=getLayer(model,model.InputNames{1}).InputSize;
                if o.FreezeBackbone, model=freezeNetwork(model,LayerNamesToIgnore=networkHead(model)); end
            elseif task=="detection"
                classes=string(gt.Properties.VariableNames(2:end))';
                if isempty(model)
                    architecture=lower(extractAfter(choice,"YOLOX-"))+"-coco";
                    model=yoloxObjectDetector(architecture,classes,'InputSize',input);
                else
                    assert(numel(external.Classes)==numel(classes) && all(ismember(classes,external.Classes)), ...
                        'VIStudioV9:ClassMismatch','External detection classes must match box annotations.');
                end
            end
            if isa(model,'VIStudioTeacherStudentV6'), model=VIStudioTeacherStudentV8.fromV6(model); end
            assigned=[]; if ~isempty(plan), assigned=plan.Manifest.Split; end
            prepared=VIStudioPreparedDataV9.build(task,samples,gt,base,o,input,folder,assigned); m=prepared.Manifest;
            assert(~monitor.StopRequested,'VIStudioV9:Cancelled','Training stopped before optimization.');
            monitor.stage('模型訓練 / Training model',true);
            train=m.Split=="train"; validation=m.Split=="validation";
            if task=="classification"
                ds=VIStudioTrainingBackendV9.classData(m(train,:),classes,input); val=[];
                if any(validation), val=VIStudioTrainingBackendV9.classData(m(validation,:),classes,input); end
                options=VIStudioTrainingBackendV9.monitoredOptions(base,o,val,monitor);
                [model,info]=trainnet(ds,model,"crossentropy",options);
            elseif task=="detection"
                ds=VIStudioTrainingBackendV9.boxData(prepared.Annotations(train,:)); val=[];
                if any(validation), val=VIStudioTrainingBackendV9.boxData(prepared.Annotations(validation,:)); end
                trainer=VIStudioModelIOV8.detectorTrainer(model);
                assert(~isempty(which(char(trainer))),'VIStudioV9:ModelUnavailable','Training API unavailable: %s',trainer);
                options=VIStudioTrainingBackendV9.monitoredOptions(base,o,val,monitor);
                if isa(model,'yoloxObjectDetector'), [model,info]=trainYOLOXObjectDetector(ds,model,options,'FreezeSubNetwork','none');
                else, [model,info]=feval(char(trainer),ds,model,options); end
            else
                normal=string(base.NormalClass); files=m.File(train & m.Label==normal);
                assert(numel(files)>=2,'VIStudioV9:MissingNormal','At least two normal training images are required.');
                ds=imageDatastore(cellstr(files),'ReadFcn',@(f) VIStudioData.readImage(f,input));
                if isempty(model)
                    if startsWith(choice,'Teacher–Student')
                        model=VIStudioTeacherStudentV8(input(1:2));
                    elseif startsWith(choice,'PatchCore')
                        backbone="resnet18"; if contains(choice,'50'), backbone="resnet50"; end
                        model=patchCoreAnomalyDetector('Backbone',backbone);
                    elseif startsWith(choice,'FCDD'), model=fcddAnomalyDetector(pretrainedEncoderNetwork("resnet18",3));
                    else, error('VIStudioV9:ModelUnavailable','The selected anomaly training API is unavailable.'); end
                end
                if isa(model,'VIStudioTeacherStudentV8')
                    [model,info]=model.train(ds,base,o,monitor);
                elseif isa(model,'patchCoreAnomalyDetector')
                    % Refitting a memory bank is not an optimizer-state resume.
                    if ~isempty(external), model=patchCoreAnomalyDetector('Backbone',model.Backbone); mode="refit-memory"; end
                    assert(~monitor.StopRequested,'VIStudioV9:Cancelled','Training stopped before memory-bank fitting.');
                    monitor.stage('PatchCore 建立記憶庫（此階段無逐步損失，完成後可停止） / Building memory bank; no per-step loss or interruption',false);
                    model=trainPatchCoreAnomalyDetector(ds,model,'CompressionRatio',o.CompressionRatio, ...
                        'MiniBatchSize',base.Batch,'ExecutionEnvironment',base.Environment);
                elseif isa(model,'fcddAnomalyDetector')
                    abnormal=m.File(train & m.Label~=normal);
                    assert(~isempty(abnormal),'VIStudioV9:MissingAnomaly','FCDD needs real or synthetic anomaly training images.');
                    abnormal=imageDatastore(cellstr(abnormal),'ReadFcn',@(f) VIStudioData.readImage(f,input));
                    [model,info]=trainFCDDAnomalyDetector(ds,abnormal,model,VIStudioTrainingBackendV9.monitoredOptions(base,o,[],monitor));
                else, error('VIStudioV9:ExternalType','This anomaly model has no supported retraining path.'); end
                model.Threshold=[]; classes=["Normal";"Anomaly"];
            end
            if ~isa(model,'VIStudioTeacherStudentV8'), monitor.ingest(info); end
            metadata=struct('ClassNames',classes,'ImageSize',input(1:2),'ModelName',string(choice), ...
                'Task',string(task),'NormalLabel',string(base.NormalClass),'Calibrated',false, ...
                'SourceFiles',unique(m.SourceFile(ismember(m.Split,["train","validation"]))),'PreparedFolder',prepared.Folder,'TrainingOptions',base, ...
                'AdvancedOptions',o,'TrainingMode',mode,'ExecutionEnvironment',base.Environment);
            if ~isempty(plan)
                metadata.DatasetFingerprint=plan.Fingerprint;
                metadata.DatasetCounts=plan.Counts;
                metadata.SourcePixelHashes=unique(plan.Manifest.PixelHash(ismember(plan.Manifest.Split,["train","validation"])));
            end
            status="complete"; if monitor.StopRequested, status="stopped"; end
            monitor.finish(status);
            metadata.RunFolder=monitor.RunFolder; metadata.TrainingStatus=status;
            if task=="classification" && any(validation), metadata.OutputNetwork="best-validation";
            else, metadata.OutputNetwork="trainer-default"; end
            if ~isempty(external)
                if isfield(external.Metadata,'SourcePixelHashes') && isfield(metadata,'SourcePixelHashes')
                    metadata.SourcePixelHashes=unique([metadata.SourcePixelHashes;string(external.Metadata.SourcePixelHashes(:))]);
                end
                metadata.ParentModel=external.File; metadata.ParentDigest=external.Digest;
                metadata.ParentVariable=external.Variable;
                metadata.ModelName="External / "+string(class(model));
                if isfield(external.Metadata,'SourceFiles')
                    metadata.SourceFiles=unique([string(external.Metadata.SourceFiles(:));string(metadata.SourceFiles(:))],'stable');
                end
            end
            catch err
                status="failed"; if strcmp(err.identifier,'VIStudioV9:Cancelled') || monitor.StopRequested, status="stopped"; end
                monitor.finish(status,err.message); rethrow(err);
            end
        end
        function options=monitoredOptions(base,o,val,monitor)
            options=VIStudioTrainingOptionsV6.native(base,o,val);
            options.OutputFcn=@(info) monitor.callback(info);
            if ~isempty(val), options.OutputNetwork='best-validation'; end
        end
        function ds=classData(m,classes,input)
            ds=imageDatastore(cellstr(m.File),'ReadFcn',@(f) VIStudioData.readImage(f,input));
            ds.Labels=categorical(m.Label,classes,classes);
            ds=augmentedImageDatastore(input(1:2),ds,'ColorPreprocessing','gray2rgb');
        end
        function ds=boxData(data)
            images=imageDatastore(data.imageFilename,'ReadFcn',@(f) VIStudioData.readImage(f,[]));
            ds=combine(images,boxLabelDatastore(data(:,2:end)));
        end
    end
end
