classdef VIStudioChangeModelsV23
    % Original tiny CPU research networks, not paper/pretrained reproductions.
    methods (Static)
        function artifact=create(architecture,inputSize,seed)
            if nargin<2, inputSize=[64 64 3]; end; if nargin<3, seed=21; end
            architecture=string(validatestring(architecture,{'early-fusion','siamese-absdiff'})); validateattributes(inputSize,{'numeric'},{'size',[1 3],'integer','>=',1}); assert(inputSize(3)==3 && all(inputSize(1:2)>=16),'VIStudioV23:ChangeModelSize','Require RGB inputs of at least 16x16.');
            old=rng; rng(seed,'twister'); restore=onCleanup(@() rng(old));
            if architecture=="early-fusion"
                layers=[imageInputLayer([inputSize(1:2) 6],'Normalization','none');convolution2dLayer(3,8,'Padding','same');reluLayer;convolution2dLayer(3,8,'Padding','same');reluLayer;convolution2dLayer(1,1);sigmoidLayer]; net=dlnetwork(layers); encoder=[];
            else
                encoder=dlnetwork([imageInputLayer(inputSize,'Normalization','none');convolution2dLayer(3,8,'Padding','same');reluLayer;convolution2dLayer(3,8,'Padding','same');reluLayer]);
                net=dlnetwork([imageInputLayer([inputSize(1:2) 8],'Normalization','none');convolution2dLayer(1,1);sigmoidLayer]);
            end
            metadata=struct('Kind',"VIStudioChangeResearchModel",'Version',1,'Architecture',architecture,'InputSize',inputSize,'Preprocessing',"RGB im2single [0,1]; ordered reference,current",'TrainingDomain',"untrained original research architecture",'ValidatedForRealInspection',false,'ThresholdCalibrated',false);
            artifact=struct('Metadata',metadata,'Network',net,'Encoder',encoder);
        end
        function validate(a)
            if isstruct(a) && isfield(a,'Metadata') && isstruct(a.Metadata) && isfield(a.Metadata,'Kind') && isequal(string(a.Metadata.Kind),"VIStudioNativeFCSiam"), VIStudioFCSiamV23.validate(a); return; end
            assert(isstruct(a) && isscalar(a) && all(isfield(a,{'Metadata','Network','Encoder'})) && isa(a.Network,'dlnetwork'),'VIStudioV23:ChangeModel','Invalid research model artifact.'); m=a.Metadata;
            assert(all(isfield(m,{'Kind','Version','Architecture','InputSize','Preprocessing','TrainingDomain','ValidatedForRealInspection','ThresholdCalibrated'})) && m.Kind=="VIStudioChangeResearchModel" && m.Version==1 && ismember(string(m.Architecture),["early-fusion","siamese-absdiff"]),'VIStudioV23:ChangeModel','Unsupported paired-model contract.');
            validateattributes(m.InputSize,{'numeric'},{'size',[1 3],'integer','positive'}); assert(m.InputSize(3)==3 && string(m.Preprocessing)=="RGB im2single [0,1]; ordered reference,current",'VIStudioV23:ChangeModel','RGB preprocessing contract required.'); if m.Architecture=="siamese-absdiff", assert(isa(a.Encoder,'dlnetwork'),'VIStudioV23:ChangeModel','A shared encoder is required.'); end
        end
        function scores=predict(a,reference,current)
            if isstruct(a) && isfield(a,'Metadata') && isfield(a.Metadata,'Kind') && isequal(string(a.Metadata.Kind),"VIStudioNativeFCSiam"), scores=VIStudioFCSiamV23.predict(a,reference,current); return; end
            VIStudioChangeModelsV23.validate(a); sz=a.Metadata.InputSize;
            assert(isequal(size(reference),sz) && isequal(size(current),sz),'VIStudioV23:ChangeModelSize','Input size differs from the model contract; no silent resizing.');
            validateattributes(reference,{'numeric'},{'real','finite','>=',0,'<=',1}); validateattributes(current,{'numeric'},{'real','finite','>=',0,'<=',1});
            x=dlarray(single(reference),'SSCB'); y=dlarray(single(current),'SSCB');
            if a.Metadata.Architecture=="early-fusion", z=predict(a.Network,cat(3,x,y)); else, z=predict(a.Network,abs(predict(a.Encoder,x)-predict(a.Encoder,y))); end
            scores=single(gather(extractdata(z))); scores=reshape(scores,sz(1:2)); assert(all(isfinite(scores),'all') && all(scores>=0 & scores<=1,'all'),'VIStudioV23:ChangeModel','Invalid output scores.');
        end
        function [a,report]=trainSynthetic(architecture,steps)
            if nargin<2, steps=12; end; validateattributes(steps,{'numeric'},{'scalar','integer','>=',1,'<=',100});
            a=VIStudioChangeModelsV23.create(architecture); s=RandStream('mt19937ar','Seed',22); x=.25+.35*rand(s,64,64,3,4,'single'); y=x; truth=zeros(64,64,1,4,'single');
            for k=1:4, row=8+7*k; col=9+8*k; y(row:row+15,col:col+15,:,k)=.95; truth(row:row+15,col:col+15,1,k)=1; end
            x=dlarray(x,'SSCB'); y=dlarray(y,'SSCB'); t=dlarray(truth,'SSCB'); losses=zeros(steps+1,1); avg=[]; sq=[]; avgE=[]; sqE=[];
            for k=1:steps
                [loss,g,gE]=dlfeval(@VIStudioChangeModelsV23.gradients,a,x,y,t); losses(k)=double(gather(extractdata(loss))); [a.Network,avg,sq]=adamupdate(a.Network,g,avg,sq,k,.01);
                if a.Metadata.Architecture=="siamese-absdiff", [a.Encoder,avgE,sqE]=adamupdate(a.Encoder,gE,avgE,sqE,k,.01); end
            end
            loss=dlfeval(@VIStudioChangeModelsV23.loss,a,x,y,t); losses(end)=double(gather(extractdata(loss))); a.Metadata.TrainingDomain="four original synthetic training pairs only; no real-data validation";
            report=struct('Architecture',string(architecture),'Steps',steps,'Losses',losses,'InitialLoss',losses(1),'FinalLoss',losses(end),'Finite',all(isfinite(losses)),'RealDataValidated',false,'PretrainedWeights',false,'Meaning',"CPU training/inference feasibility only; not a benchmark or production model");
        end
        function [loss,g,gE]=gradients(a,x,y,t)
            loss=VIStudioChangeModelsV23.loss(a,x,y,t); gE=[];
            if a.Metadata.Architecture=="early-fusion", g=dlgradient(loss,a.Network.Learnables); else, [g,gE]=dlgradient(loss,a.Network.Learnables,a.Encoder.Learnables); end
        end
        function loss=loss(a,x,y,t)
            if a.Metadata.Architecture=="early-fusion", p=forward(a.Network,cat(3,x,y)); else, p=forward(a.Network,abs(forward(a.Encoder,x)-forward(a.Encoder,y))); end
            p=min(1-1e-6,max(1e-6,p)); loss=-mean(4*t.*log(p)+(1-t).*log(1-p),'all');
        end
    end
end
