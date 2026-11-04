classdef VIStudioTaskModelsV15
    methods (Static)
        function o=defaults(task)
            task=string(validatestring(task,{'instance','keypoints','assist'})); choice="maskrcnn"; if task=="keypoints", choice="hrnet-w32"; elseif task=="assist", choice="sam2-tiny"; end
            o=struct('Version',15,'Task',task,'Model',choice,'Epochs',10,'Batch',2,'LearnRate',.0001,'Environment',"cpu",'Threshold',.5,'ModelFile',"",'DatasetFile',"",'Template',VIStudioPoseV15.template(),'PCKThreshold',.05);
        end
        function saveSetup(o,file)
            VIStudioTaskModelsV15.validateSetup(o); assert(~isfile(file),'VIStudioV15:FileExists','Choose a new setup file.'); configuration=o; save(file,'configuration','-v7.3');
        end
        function o=loadSetup(file), loaded=load(file,'configuration'); assert(isfield(loaded,'configuration'),'VIStudioV15:Setup','MAT requires configuration.'); o=loaded.configuration; VIStudioTaskModelsV15.validateSetup(o); o.Version=15; end
        function validateSetup(o)
            expected=VIStudioTaskModelsV15.defaults(o.Task); assert(all(isfield(o,fieldnames(expected))) && ismember(o.Version,[14 15]),'VIStudioV15:Setup','Invalid V14/V15 configuration.');
            validateattributes([o.Epochs o.Batch],{'numeric'},{'integer','positive','finite'}); validateattributes(o.LearnRate,{'numeric'},{'scalar','positive','finite','<=',1}); validateattributes(o.Threshold,{'numeric'},{'scalar','>=',0,'<=',1}); validatestring(o.Environment,{'cpu','gpu','auto'});
            g=VIStudioPoseV15.geometry(o.Template,nan(numel(o.Template.Names),2),zeros(numel(o.Template.Names),1),[1 1 2 2]); VIStudioPoseV15.validate(g,[2 2]);
            choices=struct('instance',{{'maskrcnn','solov2'}},'keypoints',{{'hrnet-w32','hrnet-w48'}},'assist',{{'sam2-tiny','sam-base'}}); validatestring(o.Model,choices.(o.Task));
        end
        function [model,status]=create(o,classes)
            if nargin<2, classes=strings(0,1); end; VIStudioTaskModelsV15.validateSetup(o); model=[];
            try
                switch string(o.Model)
                    case "maskrcnn", if isempty(classes), model=maskrcnn('resnet50-coco'); else, model=maskrcnn('resnet50-coco',cellstr(classes)); end
                    case "solov2", if isempty(classes), model=solov2('resnet50-coco'); else, model=solov2('resnet50-coco',cellstr(classes)); end
                    case {"hrnet-w32","hrnet-w48"}, backbone='human-full-body-w32'; if o.Model=="hrnet-w48", backbone='human-full-body-w48'; end; if isempty(classes), model=hrnetObjectKeypointDetector(backbone); else, model=hrnetObjectKeypointDetector(backbone,string(classes),'KeypointConnections',o.Template.Edges); end
                    otherwise, model=segmentAnythingModel(char(o.Model));
                end
                status=struct('State',"CREATED_NOT_VERIFIED",'Message',"Model object created; inference/training not yet verified",'Class',string(class(model)));
            catch err, status=struct('State',"UNAVAILABLE",'Message',string(err.message),'Class',""); end
        end
        function a=load(file,task)
            loaded=load(file); assert(isfield(loaded,'model'),'VIStudioV15:TaskModel','MAT requires model.'); model=loaded.model; type=string(class(model)); supported=(task=="instance" && any(type==["maskrcnn","solov2"])) || (task=="keypoints" && isa(model,'hrnetObjectKeypointDetector')) || (task=="assist" && ismethod(model,'extractEmbeddings') && ismethod(model,'segmentObjectsFromEmbeddings'));
            assert(supported,'VIStudioV15:TaskModel','Model type does not match task.'); metadata=struct(); if isfield(loaded,'metadata'), metadata=loaded.metadata; end; a=struct('Model',model,'Metadata',metadata,'Task',string(task),'File',VIStudioToolsV3.canonicalPath(file),'Digest',VIStudioToolsV3.fileHash(file));
        end
        function result=predict(a,image,threshold,boxes)
            if nargin<3, threshold=.5; end; if nargin<4, boxes=[1 1 size(image,2) size(image,1)]; end
            assert(VIStudioToolsV3.fileHash(a.File)==a.Digest,'VIStudioV15:ChangedModel','Reload changed model.'); timer=tic;
            if a.Task=="instance"
                [masks,labels,scores,bounds]=segmentObjects(a.Model,image,'Threshold',threshold,'ExecutionEnvironment','cpu'); if isempty(labels), masks=false(size(image,1),size(image,2),0); scores=zeros(0,1); bounds=zeros(0,4); end; result=struct('Masks',logical(masks),'Labels',string(labels(:)),'Scores',double(scores(:)),'Boxes',double(bounds),'Milliseconds',1000*toc(timer));
            else
                [points,scores,valid]=detect(a.Model,image,boxes,'ExecutionEnvironment','cpu'); valid=valid & scores>=threshold; result=struct('Points',points,'Scores',scores,'Valid',valid,'Names',string(a.Model.KeyPointClasses),'Edges',a.Model.KeypointConnections,'Boxes',boxes,'Milliseconds',1000*toc(timer));
            end
        end
        function [mask,evidence]=assist(model,image,foreground,background,box)
            if nargin<4, background=zeros(0,2); end; if nargin<5, box=[]; end; imageSize=size(image,[1 2]);
            for points={foreground,background}, validateattributes(points{1},{'numeric'},{'2d','ncols',2,'real','finite'}); assert(all(points{1}(:,1)>=1 & points{1}(:,1)<=imageSize(2)) && all(points{1}(:,2)>=1 & points{1}(:,2)<=imageSize(1)),'VIStudioV15:PromptBounds','Prompt outside image.'); end
            assert(~isempty(foreground) || ~isempty(box),'VIStudioV15:Prompt','Provide a foreground point or box.'); args={}; if ~isempty(foreground), args=[args {'ForegroundPoints',foreground}]; end; if ~isempty(box), validateattributes(box,{'numeric'},{'numel',4,'finite','positive'}); assert(box(1)+box(3)-1<=imageSize(2) && box(2)+box(4)-1<=imageSize(1),'VIStudioV15:PromptBounds','Box outside image.'); args=[args {'BoundingBox',box}]; end; if ~isempty(background), args=[args {'BackgroundPoints',background}]; end
            embeddings=extractEmbeddings(model,image); [masks,scores]=segmentObjectsFromEmbeddings(model,embeddings,imageSize,args{:}); scores=double(gather(scores)); [score,index]=max(scores(:)); mask=logical(masks(:,:,index)); assert(isequal(size(mask),imageSize) && any(mask,'all'),'VIStudioV15:AssistMask','SAM returned an empty or invalid mask.'); evidence=struct('Source',"SAM",'Score',score,'Foreground',foreground,'Background',background,'Box',box,'Reviewed',false);
        end
        function [model,metadata,run]=train(data,o,folder,external,run)
            if nargin<4, external=[]; end; if nargin<5, run=VIStudioTrainingRunV9; end; VIStudioTaskModelsV15.validateSetup(o); snapshot=VIStudioStructuredV15.assertUnchanged(data); assert(data.schema.Task==o.Task && o.Task~="assist",'VIStudioV15:TaskMismatch','Dataset task differs.'); assert(sum(data.manifest.Split=="train")>=2,'VIStudioV15:TaskTrainingData','Use at least two independent training images.');
            if ~isempty(external), assert(VIStudioToolsV3.fileHash(external.File)==external.Digest,'VIStudioV15:ChangedModel','Reload external model.'); VIStudioDatasetV9.assertParentIndependent(struct('Manifest',snapshot),external); end
            assert(~isfolder(folder) && ~isfile(folder),'VIStudioV15:FileExists','Choose new training folder.'); mkdir(folder); advanced=VIStudioTrainingOptionsV6.defaults(); base=struct('Epochs',o.Epochs,'Batch',o.Batch,'LearnRate',o.LearnRate,'Environment',o.Environment); run.begin(o.Task,o.Model,base,advanced,fullfile(folder,'runs'));
            try
                if o.Task=="instance", classes=data.classes; ds=VIStudioStructuredV15.instanceDatastore(data,'train'); else, classes=string(data.schema.Template.Names); o.Template=data.schema.Template; o.Template.Name="dataset"; ds=VIStudioStructuredV15.poseDatastore(data,'train'); end
                if isempty(external), [model,status]=VIStudioTaskModelsV15.create(o,classes); assert(~isempty(model),'VIStudioV15:ModelUnavailable','%s',status.Message); else, model=external.Model; run.attachParent(external); end
                options=VIStudioTrainingOptionsV6.native(base,advanced,[]); options.BatchNormalizationStatistics='moving'; options.OutputFcn=@(info) run.callback(info); run.stage('原生訓練介面 / Native training adapter',true);
                if o.Task=="instance"
                    assert(isequal(sort(string(model.ClassNames(:))),sort(string(classes(:)))),'VIStudioV15:ModelClasses','Instance model classes differ.'); if isa(model,'maskrcnn'), [model,info]=trainMaskRCNN(ds,model,options); else, [model,info]=trainSOLOV2(ds,model,options); end
                else
                    assert(isequal(string(model.KeyPointClasses(:)),string(classes(:))),'VIStudioV15:ModelClasses','HRNet point order differs.'); [model,info]=trainHRNetObjectKeypointDetector(ds,model,options);
                end
                run.ingest(info); state="complete"; if run.StopRequested, state="stopped"; end; run.finish(state); used=data.manifest.Split=="train"; metadata=struct('Task',o.Task,'Options',o,'Classes',classes,'Template',data.schema.Template,'SourceFiles',snapshot.File(used),'SourcePixelHashes',snapshot.PixelHash(used),'DatasetSnapshot',snapshot,'TrainingStatus',state);
                if ~isempty(external), metadata.ParentDigest=external.Digest; if isfield(external.Metadata,'SourceFiles'), metadata.SourceFiles=unique([metadata.SourceFiles;string(external.Metadata.SourceFiles(:))]); end; if isfield(external.Metadata,'SourcePixelHashes'), metadata.SourcePixelHashes=unique([metadata.SourcePixelHashes;string(external.Metadata.SourcePixelHashes(:))]); end, end
                save(fullfile(folder,'model.mat'),'model','metadata','info','-v7.3'); save(fullfile(folder,'dataset_snapshot.mat'),'data','snapshot','o','-v7.3'); run.attachCheckpoint(fullfile(folder,'model.mat'));
            catch err, run.finish('failed',err.message); rethrow(err); end
        end
    end
end
