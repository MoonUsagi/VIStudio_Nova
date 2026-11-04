classdef VIStudioSemanticV13
    methods (Static)
        function options=defaults()
            options=struct('Size',128,'Epochs',10,'Batch',4,'LearnRate',.001,'Environment','cpu','EncoderDepth',3,'Filters',16,'AugmentCopies',0,'Seed',42,'Loss',"crossentropy",'Architecture',"unet",'DataMode',"resize",'TileOverlap',.25,'WeightMode',"none",'ClassWeights',[],'WeightCap',20,'Solver',"adam",'Schedule',"none",'DropFactor',.1,'DropPeriod',10,'L2',.0001,'MaxPreparedImages',100000,'MaxBufferMB',512);
        end
        function o=options(value)
            o=VIStudioSemanticV13.defaults(); for f=fieldnames(value)', assert(isfield(o,f{1}),'VIStudioV13:SemanticOptions','Unknown training option.'); o.(f{1})=value.(f{1}); end
            for name={'Size','Epochs','Batch','EncoderDepth','Filters','Seed','AugmentCopies'}, validateattributes(o.(name{1}),{'numeric'},{'scalar','finite','integer','nonnegative'}); end
            assert(o.Size>=32 && o.Size<=1024 && o.Epochs>=1 && o.Batch>=1 && o.EncoderDepth>=1 && o.EncoderDepth<=5 && o.Filters>=2 && o.Filters<=128 && o.AugmentCopies<=20,'VIStudioV13:SemanticOptions','Training values outside supported range.');
            assert(string(o.Architecture)~="unet" || mod(o.Size,2^o.EncoderDepth)==0,'VIStudioV13:SemanticSize','Input size must be divisible by 2^EncoderDepth.');
            validateattributes(o.LearnRate,{'numeric'},{'scalar','positive','finite','<=',1}); o.Environment=string(validatestring(o.Environment,{'cpu','gpu','auto'}));
            o.Loss=string(validatestring(o.Loss,{'crossentropy','dice'}));
            o.Architecture=string(validatestring(o.Architecture,{'unet','deeplab-resnet18','bisenetv2'})); o.DataMode=string(validatestring(o.DataMode,{'resize','tiles'})); o.WeightMode=string(validatestring(o.WeightMode,{'none','inverse-frequency','manual'}));
            o.Solver=string(validatestring(o.Solver,{'adam','sgdm','rmsprop'})); o.Schedule=string(validatestring(o.Schedule,{'none','piecewise'}));
            if o.Architecture=="deeplab-resnet18", assert(o.Size>=224 && mod(o.Size,32)==0,'VIStudioV13:ModelInputSize','DeepLab ResNet-18 requires size >=224 and divisible by 32.'); end
            if o.Architecture=="bisenetv2", assert(o.Size>=64 && mod(o.Size,32)==0,'VIStudioV13:ModelInputSize','BiSeNet requires size >=64 and divisible by 32.'); end
            validateattributes(o.TileOverlap,{'numeric'},{'scalar','finite','>=',0,'<=',.75}); validateattributes(o.WeightCap,{'numeric'},{'scalar','finite','>=',1});
            validateattributes(o.DropFactor,{'numeric'},{'scalar','positive','<=',1,'finite'}); validateattributes(o.DropPeriod,{'numeric'},{'scalar','integer','positive','finite'}); validateattributes(o.L2,{'numeric'},{'scalar','>=',0,'<=',1,'finite'});
            validateattributes(o.MaxPreparedImages,{'numeric'},{'scalar','positive','integer','finite'}); validateattributes(o.MaxBufferMB,{'numeric'},{'scalar','positive','finite'});
            if ~isempty(o.ClassWeights), validateattributes(o.ClassWeights,{'numeric'},{'vector','positive','finite'}); end
        end
        function validateClasses(classes)
            assert(istable(classes) && all(ismember({'ID','Name','Color'},classes.Properties.VariableNames)) && height(classes)>=2,'VIStudioV13:SemanticClasses','Class map requires ID, Name and Color and at least two classes.');
            ids=double(classes.ID); names=string(classes.Name); validateattributes(ids,{'numeric'},{'column','integer','finite','>=',0,'<',65535});
            assert(numel(unique(ids))==numel(ids) && numel(unique(names))==numel(names) && all(strlength(names)>0) && sum(ids==0)==1 && names(ids==0)=="background",'VIStudioV13:SemanticClasses','Use unique IDs/names and background ID 0. ID 65535 is reserved for Ignore.');
            validateattributes(classes.Color,{'numeric'},{'size',[height(classes) 3],'finite','>=',0,'<=',1});
        end
        function output=exportAnnotations(doc,folder,conflict)
            conflict=string(validatestring(conflict,{'error','ignore','last'})); assert(~isfolder(folder) && ~isfile(folder),'VIStudioV13:FileExists','Choose a new dataset folder.');
            names=doc.Classes.Name; assert(~any(ismember(lower(names),["background","ignore"])),'VIStudioV13:SemanticReserved','background and ignore are reserved; use __ignore__ for ignored regions.');
            keep=names~="__ignore__"; names=names(keep); assert(~isempty(names),'VIStudioV13:SemanticClasses','Add at least one foreground class.');
            classes=table((0:numel(names))',["background";names],[.18 .18 .18;doc.Classes.Color(keep,:)],'VariableNames',{'ID','Name','Color'}); VIStudioSemanticV13.validateClasses(classes);
            files=doc.Files(doc.Reviewed); assert(~isempty(files),'VIStudioV13:UnreviewedImages','Review images before exporting.'); masks=cell(numel(files),1); conflicts=zeros(numel(files),1);
            for k=1:numel(files)
                image=VIStudioData.readImage(files(k),[]); pixels=zeros(size(image,[1 2]),'uint16'); occupied=false(size(pixels)); ignored=occupied;
                rows=doc.Annotations(doc.Annotations.File==files(k) & doc.Annotations.Reviewed,:); assert(~any(rows.Type=="image"),'VIStudioV13:SemanticRegions','Semantic export requires region annotations, not image labels.');
                for j=1:height(rows)
                    region=doc.rasterize(rows.Type(j),rows.Geometry{j},size(pixels)); if rows.Label(j)=="__ignore__", ignored=ignored | region; continue; end
                    id=uint16(classes.ID(classes.Name==rows.Label(j))); overlap=region & occupied & pixels~=id; conflicts(k)=conflicts(k)+nnz(overlap);
                    assert(conflict~="error" || ~any(overlap,'all'),'VIStudioV13:SemanticConflict','Different classes overlap; edit regions or explicitly choose Ignore/Last policy.');
                    if conflict=="ignore", ignored=ignored | overlap; end
                    pixels(region)=id; occupied=occupied | region;
                end
                pixels(ignored)=65535; masks{k}=pixels;
            end
            mkdir(folder); mkdir(fullfile(folder,'images')); mkdir(fullfile(folder,'labels')); outputFiles=strings(numel(files),1); labelFiles=outputFiles;
            for k=1:numel(files)
                outputFiles(k)=fullfile(folder,'images',sprintf('%06d.png',k)); labelFiles(k)=fullfile(folder,'labels',sprintf('%06d.png',k)); imwrite(VIStudioData.readImage(files(k),[]),outputFiles(k)); imwrite(masks{k},labelFiles(k));
            end
            manifest=table(outputFiles,labelFiles,repmat("train",numel(files),1),files,conflicts,'VariableNames',{'File','LabelFile','Split','SourceFile','ConflictPixels'});
            schema=struct('Version',12,'Task',"semantic",'IgnoreID',65535,'ConflictPolicy',conflict,'ReservedObjectFields',["InstanceID","Keypoints","Visibility"]);
            save(fullfile(folder,'dataset.mat'),'manifest','classes','schema'); writetable(manifest,fullfile(folder,'manifest.csv'),'Encoding','UTF-8'); writetable(classes(:,{'ID','Name'}),fullfile(folder,'classes.csv'),'Encoding','UTF-8');
            output=struct('Images',string(fullfile(folder,'images')),'Path',string(fullfile(folder,'dataset.mat')),'Manifest',manifest,'Classes',classes,'Schema',schema);
        end
        function [data,classes]=read(file)
            loaded=load(file); assert(all(isfield(loaded,{'manifest','classes'})),'VIStudioV13:SemanticManifest','MAT requires manifest and classes.'); data=loaded.manifest; classes=loaded.classes;
            assert(istable(data) && all(ismember({'File','LabelFile','Split'},data.Properties.VariableNames)),'VIStudioV13:SemanticManifest','Require File, LabelFile, Split.');
            data.File=string(data.File); data.LabelFile=string(data.LabelFile); data.Split=string(data.Split);
            for k=1:height(data)
                for f={'File','LabelFile'}
                    value=data.(f{1})(k); absolute=startsWith(value,"/") || startsWith(value,"\") || ~isempty(regexp(char(value),'^[A-Za-z]:[\\/]','once'));
                    if ~absolute, value=fullfile(fileparts(file),value); end
                    data.(f{1})(k)=VIStudioToolsV3.canonicalPath(value);
                end
            end
            VIStudioSemanticV13.validate(data,classes);
        end
        function snapshot=validate(data,classes)
            VIStudioSemanticV13.validateClasses(classes); assert(~isempty(data) && all(ismember(data.Split,["train","validation","test","calibration"])),'VIStudioV13:SemanticSplit','Invalid or empty dataset.');
            assert(numel(unique(lower(data.File)))==height(data),'VIStudioV13:SemanticDuplicate','Each image needs one record.'); source=strings(height(data),1); labels=source; pixels=source; decoded=source;
            for k=1:height(data)
                image=VIStudioData.readImage(data.File(k),[]); mask=VIStudioSemanticV13.label(data.LabelFile(k),classes); assert(isequal(size(mask),size(image,[1 2])),'VIStudioV13:SemanticLabelSize','Labels must match source resolution.');
                assert(any(mask~=65535,'all'),'VIStudioV13:SemanticEmpty','An image cannot contain only ignored pixels.');
                source(k)=VIStudioToolsV3.fileHash(data.File(k)); labels(k)=VIStudioToolsV3.fileHash(data.LabelFile(k)); pixels(k)=VIStudioDataHealthV8.pixelHash(image); decoded(k)=VIStudioDatasetV9.digest(jsonencode(mask));
            end
            for hash=unique(pixels)'
                rows=pixels==hash; assert(numel(unique(data.Split(rows)))==1,'VIStudioV13:SemanticLeak','Identical image content crosses roles.'); assert(numel(unique(decoded(rows)))==1,'VIStudioV13:SemanticTruthConflict','Identical images have conflicting labels.');
            end
            snapshot=data; snapshot.SourceHash=source; snapshot.LabelHash=labels; snapshot.PixelHash=pixels;
        end
        function labels=label(file,classes)
            [raw,map]=imread(file); assert(isempty(map) && ismatrix(raw) && isinteger(raw),'VIStudioV13:SemanticLabels','Use a single-channel integer label PNG.');
            labels=uint16(raw); assert(all(ismember(unique(labels),[uint16(classes.ID);uint16(65535)])),'VIStudioV13:SemanticLabelID','Unknown class ID in label image.');
        end
        function [model,metadata,run]=train(data,classes,options,folder,external,run)
            if nargin<5, external=[]; end; if nargin<6, run=VIStudioTrainingRunV9; end
            o=VIStudioSemanticV13.options(options); snapshot=VIStudioSemanticV13.validate(data,classes); train=data.Split=="train"; val=data.Split=="validation";
            assert(sum(train)>=2,'VIStudioV13:SemanticTraining','Use at least two training images.');
            if ~isempty(external)
                assert(external.Task=="semantic" && isequal(string(external.Metadata.SemanticClasses.Name),string(classes.Name)) && isequal(external.Metadata.SemanticClasses.ID,classes.ID),'VIStudioV13:SemanticParentClasses','External class map must match.');
                VIStudioSemanticV13.guard(external); VIStudioDatasetV9.assertParentIndependent(struct('Manifest',snapshot),external); assert(isequal(external.InputSize(1:2),[o.Size o.Size]),'VIStudioV13:SemanticParentSize','External input size differs.');
            end
            weights=VIStudioSemanticTilesV13.weights(data,classes,o); rngBefore=rng; rngCleanup=onCleanup(@() rng(rngBefore)); rng(o.Seed,'twister');
            assert(~isfolder(folder) && ~isfile(folder),'VIStudioV13:FileExists','Choose a new training folder.'); mkdir(folder);
            base=struct('Epochs',o.Epochs,'Batch',o.Batch,'LearnRate',o.LearnRate,'Environment',o.Environment); advanced=VIStudioTrainingOptionsV6.defaults(); advanced.Seed=o.Seed; advanced.Solver=o.Solver; advanced.Schedule=o.Schedule; advanced.DropFactor=o.DropFactor; advanced.DropPeriod=o.DropPeriod; advanced.L2=o.L2;
            run.begin('semantic',o.Architecture,base,advanced,fullfile(folder,'runs'));
            try
                [prepared,preparation]=VIStudioSemanticTilesV13.prepare(data,classes,o,folder,run,snapshot);
                represented=uint16([]); for k=find(prepared.Split=="train")', represented=union(represented,unique(imread(prepared.LabelFile(k)))); end
                assert(all(ismember(uint16(classes.ID),represented)),'VIStudioV13:SemanticMissingClass','Every class must occur in prepared training labels.');
                ds=VIStudioSemanticV13.datastore(prepared(prepared.Split=="train",:),classes); validation=[]; if any(val), validation=VIStudioSemanticV13.datastore(prepared(prepared.Split=="validation",:),classes); end
                if isempty(external), model=VIStudioSemanticV13.buildModel(o,height(classes)); else, model=external.Model; run.attachParent(external); end
                native=VIStudioTrainingOptionsV6.native(base,advanced,validation); native.OutputFcn=@(info) run.callback(info); native.BatchNormalizationStatistics='moving'; if ~isempty(validation), native.OutputNetwork='best-validation'; end
                run.stage('語意分割訓練 / Semantic training',true); [model,info]=trainnet(ds,model,@(Y,T) VIStudioSemanticV13.loss(Y,T,o.Loss,weights.Weight),native); run.ingest(info); status="complete"; if run.StopRequested, status="stopped"; end; run.finish(status);
                used=train | val; metadata=struct('Task',"semantic",'ModelName',o.Architecture+" / Semantic",'ClassNames',string(classes.Name),'SemanticClasses',classes,'ImageSize',[o.Size o.Size],'IgnoreID',65535,'Options',o,'TrainingClassWeights',weights,'Preparation',preparation,'SourceFiles',snapshot.File(used),'SourcePixelHashes',snapshot.PixelHash(used),'DatasetSnapshot',snapshot,'TrainingStatus',status,'RunFolder',run.RunFolder);
                if ~isempty(external)
                    metadata.ParentModel=external.File; metadata.ParentDigest=external.Digest; metadata.ModelName="External semantic network";
                    if isfield(external.Metadata,'SourceFiles'), metadata.SourceFiles=unique([metadata.SourceFiles;string(external.Metadata.SourceFiles(:))]); end
                    if isfield(external.Metadata,'SourcePixelHashes'), metadata.SourcePixelHashes=unique([metadata.SourcePixelHashes;string(external.Metadata.SourcePixelHashes(:))]); end
                end
                save(fullfile(folder,'model.mat'),'model','metadata','info','-v7.3'); save(fullfile(folder,'dataset.mat'),'snapshot','prepared','classes','o','weights','preparation'); writetable(prepared,fullfile(folder,'prepared.csv'),'Encoding','UTF-8'); run.attachCheckpoint(fullfile(folder,'model.mat'));
            catch err, status="failed"; if run.StopRequested, status="stopped"; end; run.finish(status,err.message); rethrow(err); end
        end
        function model=buildModel(o,classes)
            o=VIStudioSemanticV13.options(o);
            switch o.Architecture
                case "unet", model=unet([o.Size o.Size 3],classes,'EncoderDepth',o.EncoderDepth,'NumFirstEncoderFilters',o.Filters);
                case "deeplab-resnet18", model=deeplabv3plus([o.Size o.Size 3],classes,'resnet18');
                case "bisenetv2", model=bisenetv2([o.Size o.Size 3],classes,'ChannelRatio',4,'ChannelMultiplier',1,'DepthMultiplier',1);
            end
        end
        function ds=datastore(data,classes)
            ds=combine(imageDatastore(cellstr(data.File)),pixelLabelDatastore(cellstr(data.LabelFile),cellstr(classes.Name),classes.ID,'ReadFcn',@(file) categorical(imread(file),classes.ID,cellstr(classes.Name))));
            sample=preview(ds); assert(isequal(string(categories(sample{2})),string(classes.Name)),'VIStudioV13:SemanticClassOrder','Datastore class order differs.');
        end
        function loss=loss(Y,T,kind,weights)
            if nargin<4, weights=ones(size(T,3),1); end
            validateattributes(weights,{'numeric'},{'vector','numel',size(T,3),'positive','finite'}); weights=reshape(single(weights),1,1,[],1); T(isnan(T))=0; mask=sum(T,3)>0;
            if string(kind)=="crossentropy", weighted=T.*weights; loss=-sum(weighted.*log(max(Y,1e-7)),'all')/max(sum(weighted,'all'),1e-7);
            else
                Y=Y.*mask; intersection=sum(Y.*T,[1 2]); denominator=sum(Y+T,[1 2]); classLoss=1-(2*intersection+1e-6)./(denominator+1e-6); loss=sum(classLoss.*weights,'all')/(sum(weights,'all')*size(T,4));
            end
        end
        function a=load(file)
            loaded=load(file,'model','metadata'); assert(all(isfield(loaded,{'model','metadata'})) && isa(loaded.model,'dlnetwork') && isfield(loaded.metadata,'Task') && string(loaded.metadata.Task)=="semantic",'VIStudioV13:SemanticModel','MAT must contain a semantic dlnetwork and metadata.');
            md=loaded.metadata; VIStudioSemanticV13.validateClasses(md.SemanticClasses); input=getLayer(loaded.model,loaded.model.InputNames{1}).InputSize;
            assert(loaded.model.Initialized && numel(input)==3 && input(3)==3 && numel(loaded.model.InputNames)==1 && numel(loaded.model.OutputNames)==1,'VIStudioV13:SemanticInput','Use a single RGB input/output network.');
            a=struct('Model',loaded.model,'Metadata',md,'Classes',string(md.SemanticClasses.Name),'InputSize',input,'File',VIStudioToolsV3.canonicalPath(file),'Digest',VIStudioToolsV3.fileHash(file),'Variable',"model",'Task',"semantic");
        end
        function guard(a), assert(isfile(a.File) && VIStudioToolsV3.fileHash(a.File)==a.Digest,'VIStudioV13:ChangedModel','Model changed; reload it.'); end
        function scores=probabilities(a,image)
            scores=minibatchpredict(a.Model,image,'ExecutionEnvironment','cpu'); if isa(scores,'dlarray'), scores=extractdata(scores); end; scores=gather(scores);
            assert(size(scores,3)==numel(a.Classes) && all(isfinite(scores),'all'),'VIStudioV13:SemanticScores','Invalid probability map.');
            assert(all(scores>=0 & scores<=1,'all') && all(abs(sum(scores,3)-1)<1e-3,'all'),'VIStudioV13:SemanticScores','Network must output per-pixel softmax probabilities.');
        end
        function result=predict(a,image)
            VIStudioSemanticV13.guard(a); o=VIStudioSemanticV13.defaults();
            if isfield(a.Metadata,'Options'), fields=fieldnames(a.Metadata.Options); for k=1:numel(fields), if isfield(o,fields{k}), o.(fields{k})=a.Metadata.Options.(fields{k}); end, end, end
            if string(o.DataMode)=="tiles", result=VIStudioSemanticTilesV13.predict(a,image,o); return; end
            timer=tic; original=size(image,[1 2]); scores=VIStudioSemanticV13.probabilities(a,imresize(image,a.InputSize(1:2))); [confidence,index]=max(scores,[],3); ids=uint16(a.Metadata.SemanticClasses.ID); labels=imresize(reshape(ids(index),size(index)),original,'nearest'); confidence=imresize(confidence,original,'bilinear');
            result=struct('Labels',labels,'ConfidenceMap',confidence,'Classes',a.Metadata.SemanticClasses,'Milliseconds',1000*toc(timer),'ModelDigest',a.Digest,'InferenceMode',"resize",'TileCount',1,'ScoreBufferMB',numel(scores)*4/1024^2);
        end
        function [rows,confusion,summary]=metrics(predicted,truth,classes)
            VIStudioSemanticV13.validateClasses(classes); assert(isequal(size(predicted),size(truth)),'VIStudioV13:SemanticMetricSize','Prediction and truth sizes differ.');
            valid=truth~=65535; assert(any(valid,'all'),'VIStudioV13:SemanticEmpty','No valid truth pixels.'); [known,a]=ismember(truth(valid),classes.ID); [recognized,b]=ismember(predicted(valid),classes.ID); assert(all(known) && all(recognized),'VIStudioV13:SemanticLabelID','Unknown class ID.');
            confusion=accumarray([a(:) b(:)],1,[height(classes) height(classes)]); tp=diag(confusion); actual=sum(confusion,2); estimated=sum(confusion,1)'; fp=estimated-tp; fn=actual-tp; iou=tp./(tp+fp+fn); dice=2*tp./(2*tp+fp+fn);
            rows=table(classes.ID,string(classes.Name),tp,fp,fn,actual,iou,dice,'VariableNames',{'ID','Class','TP','FP','FN','Support','IoU','Dice'}); foreground=classes.ID~=0;
            summary=struct('Pixels',nnz(valid),'IgnoredPixels',nnz(~valid),'PixelAccuracy',sum(tp)/sum(confusion,'all'),'MeanIoU',mean(iou,'omitnan'),'MeanDice',mean(dice,'omitnan'),'ForegroundIoU',mean(iou(foreground),'omitnan'),'ForegroundDice',mean(dice(foreground),'omitnan'));
        end
        function evaluation=evaluate(a,data,classes)
            VIStudioSemanticV13.guard(a); snapshot=VIStudioSemanticV13.validate(data,classes); assert(all(ismember(data.Split,["validation","test"])),'VIStudioV13:SemanticEvaluationSplit','Evaluate reserved validation or test images only.');
            assert(isequal(string(classes.Name),a.Classes) && isequal(classes.ID,a.Metadata.SemanticClasses.ID),'VIStudioV13:SemanticParentClasses','Evaluation class map differs.'); VIStudioDatasetV9.assertParentIndependent(struct('Manifest',snapshot),a);
            confusion=zeros(height(classes)); images=table();
            for k=1:height(data)
                p=VIStudioSemanticV13.predict(a,VIStudioData.readImage(data.File(k),[])); truth=VIStudioSemanticV13.label(data.LabelFile(k),classes); [~,c,m]=VIStudioSemanticV13.metrics(p.Labels,truth,classes); confusion=confusion+c; entry=struct2table(m); entry.File=data.File(k); entry.Milliseconds=p.Milliseconds; entry.TileCount=p.TileCount; images=[images;entry];
            end
            tp=diag(confusion); fp=sum(confusion,1)'-tp; fn=sum(confusion,2)-tp; IoU=tp./(tp+fp+fn); Dice=2*tp./(2*tp+fp+fn); perClass=table(classes.ID,string(classes.Name),tp,fp,fn,IoU,Dice,'VariableNames',{'ID','Class','TP','FP','FN','IoU','Dice'});
            summary=struct('Images',height(data),'PixelAccuracy',sum(tp)/sum(confusion,'all'),'MeanIoU',mean(IoU,'omitnan'),'MeanDice',mean(Dice,'omitnan'),'ForegroundIoU',mean(IoU(classes.ID~=0),'omitnan'),'ForegroundDice',mean(Dice(classes.ID~=0),'omitnan'));
            evaluation=struct('PerClass',perClass,'Confusion',confusion,'Images',images,'Summary',summary,'Classes',classes,'DatasetSnapshot',snapshot,'ModelFile',a.File,'ModelDigest',a.Digest);
        end
        function image=overlay(image,result,opacity)
            if nargin<3, opacity=.45; end
            colors=zeros(size(image),'like',image); foreground=false(size(result.Labels));
            for k=1:height(result.Classes), rows=result.Labels==result.Classes.ID(k); if result.Classes.ID(k)==0, continue; end; foreground=foreground | rows; for channel=1:3, plane=colors(:,:,channel); plane(rows)=uint8(255*result.Classes.Color(k,channel)); colors(:,:,channel)=plane; end, end
            for channel=1:3, plane=image(:,:,channel); color=colors(:,:,channel); plane(foreground)=uint8((1-opacity)*double(plane(foreground))+opacity*double(color(foreground))); image(:,:,channel)=plane; end
        end
    end
end
