classdef VIStudioFCSiamV25
    % Independently implemented native MATLAB FC-Siam architectural family.
    % Architecture reference: Daudt, Le Saux & Boulch, ICIP 2018.
    % Separately licensed pretrained weights: VIStudio_Pretrained_V23.
    % Native inference does not invoke Python or upstream source code.
    methods (Static)
        function a=create(variant,inputSize,seed)
            if nargin<2, inputSize=[64 64 3]; end; if nargin<3, seed=22; end
            variant=string(validatestring(variant,{'fc-siam-diff','fc-siam-conc'}));
            validateattributes(inputSize,{'numeric'},{'size',[1 3],'integer','positive'}); assert(inputSize(3)==3 && all(inputSize(1:2)>=16) && prod(inputSize(1:2))<=262144,'VIStudioV25:FCSiamSize','Require RGB, at least 16x16 and at most 262144 pixels.');
            validateattributes(seed,{'numeric'},{'scalar','integer','>=',0,'<=',2^32-1}); old=rng; rng(seed,'twister'); cleanup=onCleanup(@() rng(old));
            channels=[16 32 64 128]; counts=[2 2 3 3]; layers=imageInputLayer(inputSize,'Normalization','none','Name','image'); outputs=strings(1,5);
            for level=1:4
                for j=1:counts(level)
                    id=sprintf('%d%d',level,j); layers=[layers;convolution2dLayer(3,channels(level),'Padding',1,'Name',['conv' id]);batchNormalizationLayer('Epsilon',1e-5,'MeanDecay',.9,'VarianceDecay',.9,'Name',['bn' id]);reluLayer('Name',['relu' id]);VIStudioSpatialDropoutV25(['drop' id])]; %#ok<AGROW>
                end
                outputs(level)="drop"+id; layers=[layers;maxPooling2dLayer(2,'Stride',2,'Name',sprintf('pool%d',level))]; %#ok<AGROW>
            end
            outputs(5)="pool4"; encoder=dlnetwork(layers,'OutputNames',outputs);
            up=cell(1,4); block=cell(1,4); upChannels=[16 32 64 128]; outChannels={[16 2],[32 16],[64 64 32],[128 128 64]}; factor=1+(variant=="fc-siam-conc");
            for level=4:-1:1
                pooled=floor(inputSize(1:2)/2^level); spatial=floor(inputSize(1:2)/2^(level-1)); width=upChannels(level);
                up{level}=dlnetwork([imageInputLayer([pooled width],'Normalization','none','Name',sprintf('up_input%d',level));transposedConv2dLayer(3,width,'Stride',2,'Cropping',[1 0 1 0],'Name',sprintf('upconv%d',level))]);
                sequence=imageInputLayer([spatial width+factor*channels(level)],'Normalization','none','Name',sprintf('joined%d',level)); widths=outChannels{level};
                for j=1:numel(widths)
                    name=sprintf('conv%d%dd',level,numel(widths)-j+1); sequence=[sequence;transposedConv2dLayer(3,widths(j),'Cropping',1,'Name',name)]; %#ok<AGROW>
                    if level==1 && j==numel(widths), sequence=[sequence;softmaxLayer('Name','class_probabilities')]; else, sequence=[sequence;batchNormalizationLayer('Epsilon',1e-5,'MeanDecay',.9,'VarianceDecay',.9,'Name',[name '_bn']);reluLayer('Name',[name '_relu']);VIStudioSpatialDropoutV25([name '_drop'])]; end %#ok<AGROW>
                end
                block{level}=dlnetwork(sequence);
            end
            metadata=struct('Kind',"VIStudioNativeFCSiam",'Version',1,'Architecture',variant,'InputSize',inputSize,'Preprocessing',"RGB im2single [0,1]; ordered reference,current",'ClassNames',["unchanged","changed"],'WeightStatus',"RANDOM_INITIALIZATION",'TrainingDomain',"none",'ValidatedForRealInspection',false,'ThresholdCalibrated',false,'Seed',seed,'Implementation',"VIStudio native MATLAB; shared 4-level encoder; current-image bottleneck");
            a=struct('Metadata',metadata,'Encoder',encoder,'Up',{up},'Block',{block});
        end
        function validate(a)
            assert(isstruct(a) && isscalar(a) && all(isfield(a,{'Metadata','Encoder','Up','Block'})),'VIStudioV25:FCSiamArtifact','Invalid FC-Siam artifact.'); m=a.Metadata;
            assert(isstruct(m) && isscalar(m) && all(isfield(m,{'Kind','Version','Architecture','InputSize','Preprocessing','ClassNames','WeightStatus','TrainingDomain','ValidatedForRealInspection','ThresholdCalibrated','Seed','Implementation'})),'VIStudioV25:FCSiamArtifact','Missing FC-Siam metadata.');
            assert(isequal(string(m.Kind),"VIStudioNativeFCSiam") && isequal(m.Version,1) && isscalar(string(m.Architecture)) && ismember(string(m.Architecture),["fc-siam-diff","fc-siam-conc"]) && ismember(string(m.Preprocessing),["RGB im2single [0,1]; ordered reference,current","RGB im2single [0,1]; ordered reference,current; ImageNet RGB normalization; pad32"]) && isequal(string(m.ClassNames),["unchanged","changed"]),'VIStudioV25:FCSiamArtifact','Unsupported architecture, class order or preprocessing.');
            if contains(string(m.Preprocessing),"ImageNet")
                assert(isfield(m,'Normalization') && isstruct(m.Normalization) && all(isfield(m.Normalization,{'Mean','Std','PadMultiple','PadValue'})),'VIStudioV25:FCSiamArtifact','Missing pretrained normalization contract.'); n=m.Normalization;
                assert(isequal(n.Mean,[.485 .456 .406]) && isequal(n.Std,[.229 .224 .225]) && isequal(n.PadMultiple,32) && isequal(n.PadValue,0),'VIStudioV25:FCSiamArtifact','Unexpected pretrained normalization or padding.');
            end
            validateattributes(m.InputSize,{'numeric'},{'size',[1 3],'integer','positive'}); assert(m.InputSize(3)==3 && all(m.InputSize(1:2)>=16) && prod(m.InputSize(1:2))<=262144,'VIStudioV25:FCSiamSize','Invalid input size.');
            assert(isa(a.Encoder,'dlnetwork') && iscell(a.Up) && iscell(a.Block) && numel(a.Up)==4 && numel(a.Block)==4 && all(cellfun(@(n) isa(n,'dlnetwork'),[a.Up a.Block])),'VIStudioV25:FCSiamArtifact','Require shared encoder and four complete decoder levels.');
        end
        function [score,probabilities]=predict(a,reference,current)
            VIStudioFCSiamV25.validate(a); sz=a.Metadata.InputSize;
            assert(isequal(size(reference),sz) && isequal(size(current),sz),'VIStudioV25:FCSiamSize','Pair must match the exact RGB model size; no automatic resizing.');
            validateattributes(reference,{'numeric'},{'real','finite','>=',0,'<=',1}); validateattributes(current,{'numeric'},{'real','finite','>=',0,'<=',1});
            [reference,current]=VIStudioFCSiamV25.preprocess(a.Metadata,reference,current);
            p=VIStudioFCSiamV25.compute(a,dlarray(reference,'SSCB'),dlarray(current,'SSCB'),false); probabilities=single(gather(extractdata(p))); probabilities=probabilities(1:sz(1),1:sz(2),:); score=probabilities(:,:,2);
            assert(isequal(size(probabilities),[sz(1:2) 2]) && all(isfinite(probabilities),'all') && all(probabilities>=0 & probabilities<=1,'all') && max(abs(sum(probabilities,3)-1),[],'all')<1e-5,'VIStudioV25:FCSiamOutput','Invalid two-class output.');
        end
        function [p,a]=compute(a,x,y,training)
            f=cell(1,5); g=cell(1,5);
            if training
                [f{:},state]=forward(a.Encoder,x); a.Encoder.State=VIStudioFCSiamV25.detachState(state);
                [g{:},state]=forward(a.Encoder,y); a.Encoder.State=VIStudioFCSiamV25.detachState(state);
            else
                [f{:}]=predict(a.Encoder,x); [g{:}]=predict(a.Encoder,y);
            end
            p=g{5}; % Published family uses the second branch's pooled bottleneck.
            for level=4:-1:1
                if training, [p,state]=forward(a.Up{level},p); a.Up{level}.State=VIStudioFCSiamV25.detachState(state); else, p=predict(a.Up{level},p); end
                h=size(p,1); w=size(p,2); dh=size(f{level},1)-h; dw=size(f{level},2)-w; assert(dh>=0 && dh<=1 && dw>=0 && dw<=1,'VIStudioV25:FCSiamJoin','Unexpected decoder spatial alignment.');
                p=p([1:h repmat(h,1,dh)],[1:w repmat(w,1,dw)],:,:);
                if a.Metadata.Architecture=="fc-siam-diff", p=cat(3,p,abs(f{level}-g{level})); else, p=cat(3,p,f{level},g{level}); end
                if training, [p,state]=forward(a.Block{level},p); a.Block{level}.State=VIStudioFCSiamV25.detachState(state); else, p=predict(a.Block{level},p); end
            end
        end
        function saveWeights(a,file)
            VIStudioFCSiamV25.validate(a); assert(~isfile(file),'VIStudioV25:FCSiamOverwrite','Choose a new checkpoint path.'); checkpoint=struct('Kind',"VIStudioFCSiamWeights",'Version',1,'Metadata',a.Metadata,'Encoder',VIStudioFCSiamV25.pack(a.Encoder),'Up',{cellfun(@VIStudioFCSiamV25.pack,a.Up,'UniformOutput',false)},'Block',{cellfun(@VIStudioFCSiamV25.pack,a.Block,'UniformOutput',false)}); save(file,'checkpoint','-v7.3');
        end
        function a=loadWeights(file,inputSize)
            loaded=load(file,'checkpoint'); assert(isfield(loaded,'checkpoint'),'VIStudioV25:FCSiamWeights','MAT requires a native checkpoint variable; .pth is not supported.'); c=loaded.checkpoint;
            assert(isstruct(c) && isscalar(c) && all(isfield(c,{'Kind','Version','Metadata','Encoder','Up','Block'})) && isequal(string(c.Kind),"VIStudioFCSiamWeights") && isequal(c.Version,1),'VIStudioV25:FCSiamWeights','Unsupported checkpoint.');
            m=c.Metadata; assert(isstruct(m) && all(isfield(m,{'Architecture','InputSize','Seed'})),'VIStudioV25:FCSiamWeights','Missing architecture metadata.'); if nargin>1, m.InputSize=inputSize; end; a=VIStudioFCSiamV25.create(m.Architecture,m.InputSize,m.Seed); a.Metadata=m; VIStudioFCSiamV25.validate(a);
            if contains(string(m.Preprocessing),"ImageNet"), padded=[ceil(m.InputSize(1:2)/32)*32 3]; a=VIStudioFCSiamV25.create(m.Architecture,padded,m.Seed); a.Metadata=m; end
            assert(iscell(c.Up) && iscell(c.Block) && numel(c.Up)==4 && numel(c.Block)==4,'VIStudioV25:FCSiamWeights','Incomplete decoder weights.');
            a.Encoder=VIStudioFCSiamV25.restore(a.Encoder,c.Encoder);
            for k=1:4, a.Up{k}=VIStudioFCSiamV25.restore(a.Up{k},c.Up{k}); a.Block{k}=VIStudioFCSiamV25.restore(a.Block{k},c.Block{k}); end
            % Dry-run validates all output dimensions after a full strict weight/state load.
            VIStudioFCSiamV25.predict(a,zeros(m.InputSize,'single'),zeros(m.InputSize,'single'));
        end
        function packed=pack(net)
            packed=struct('Learnables',net.Learnables,'State',net.State);
            for key={'Learnables','State'}, rows=packed.(key{1}); for k=1:height(rows), rows.Value{k}=gather(extractdata(rows.Value{k})); end; packed.(key{1})=rows; end
        end
        function state=detachState(state)
            for k=1:height(state), state.Value{k}=dlarray(extractdata(state.Value{k})); end
        end
        function [x,y]=preprocess(metadata,x,y)
            x=single(x); y=single(y);
            if contains(string(metadata.Preprocessing),"ImageNet")
                meanRGB=reshape(single(metadata.Normalization.Mean),1,1,3); stdRGB=reshape(single(metadata.Normalization.Std),1,1,3); x=(x-meanRGB)./stdRGB; y=(y-meanRGB)./stdRGB;
                pad=mod(-size(x,[1 2]),32); x=padarray(x,pad,0,'post'); y=padarray(y,pad,0,'post');
            end
        end
        function net=restore(net,packed)
            assert(isstruct(packed) && isscalar(packed) && all(isfield(packed,{'Learnables','State'})),'VIStudioV25:FCSiamWeights','Missing learnable weights or BN state.');
            for key={'Learnables','State'}
                name=key{1}; target=net.(name); source=packed.(name);
                assert(istable(source) && isequal(source.Properties.VariableNames,target.Properties.VariableNames) && isequal(source.Layer,target.Layer) && isequal(source.Parameter,target.Parameter),'VIStudioV25:FCSiamWeights','Layer/parameter names or ordering differ.');
                for k=1:height(target)
                    value=source.Value{k}; assert(isa(value,'single') && isreal(value) && isequal(size(value),size(target.Value{k})) && all(isfinite(value),'all'),'VIStudioV25:FCSiamWeights','Weight shape, precision or finite-value validation failed.');
                    if contains(string(source.Parameter(k)),"Variance"), assert(all(value>=0,'all'),'VIStudioV25:FCSiamWeights','BN variance must be nonnegative.'); end
                    target.Value{k}=dlarray(value);
                end
                net.(name)=target;
            end
        end
        function [a,report]=trainStep(a,reference,current,truth,rate)
            if nargin<5, rate=1e-3; end; VIStudioFCSiamV25.validate(a); sz=a.Metadata.InputSize; assert(isequal(size(reference),sz) && isequal(size(current),sz) && islogical(truth) && isequal(size(truth),sz(1:2)),'VIStudioV25:FCSiamSize','Training pair/truth dimensions differ.'); validateattributes(rate,{'numeric'},{'scalar','finite','positive','<=',.1});
            validateattributes(reference,{'numeric'},{'real','finite','>=',0,'<=',1}); validateattributes(current,{'numeric'},{'real','finite','>=',0,'<=',1});
            [reference,current]=VIStudioFCSiamV25.preprocess(a.Metadata,reference,current);
            [loss,grad,a]=dlfeval(@VIStudioFCSiamV25.gradients,a,dlarray(reference,'SSCB'),dlarray(current,'SSCB'),dlarray(single(truth),'SSCB'));
            a.Encoder=dlupdate(@(w,g) w-rate*g,a.Encoder,grad.Encoder); for k=1:4, a.Up{k}=dlupdate(@(w,g) w-rate*g,a.Up{k},grad.Up{k}); a.Block{k}=dlupdate(@(w,g) w-rate*g,a.Block{k},grad.Block{k}); end
            a.Metadata.WeightStatus="USER_TRAINED_UNVALIDATED"; a.Metadata.TrainingDomain="caller-supplied pair(s); independent validation required"; a.Metadata.ValidatedForRealInspection=false; a.Metadata.ThresholdCalibrated=false;
            norms=cellfun(@(v) sum(abs(gather(extractdata(v))),'all'),grad.Encoder.Value); report=struct('Loss',double(gather(extractdata(loss))),'EncoderGradientL1',sum(norms),'IndependentValidation',false);
        end
        function [loss,grad,a]=gradients(a,x,y,t)
            [p,a]=VIStudioFCSiamV25.compute(a,x,y,true); changed=min(1-1e-6,max(1e-6,p(1:size(t,1),1:size(t,2),2,:))); loss=-mean(t.*log(changed)+(1-t).*log(1-changed),'all');
            inputs=[{a.Encoder.Learnables} cellfun(@(n) n.Learnables,a.Up,'UniformOutput',false) cellfun(@(n) n.Learnables,a.Block,'UniformOutput',false)]; out=cell(1,9); [out{:}]=dlgradient(loss,inputs{:}); grad=struct('Encoder',out{1},'Up',{out(2:5)},'Block',{out(6:9)});
        end
    end
end
