classdef VIStudioTeacherStudentV6
    % Single frozen ResNet-18 teacher + compact trainable student.
    % Custom feature distillation baseline, trained on normal images only.
    properties
        Threshold=[]
    end
    properties (SetAccess=private)
        Teacher
        Student
        FeatureLayer="res3b_relu"
        ImageSize=[224 224]
        TrainingHistory=table()
        Updates=0
    end
    methods
        function model=VIStudioTeacherStudentV6(imageSize)
            if nargin<1, imageSize=[224 224]; end
            model.ImageSize=double(imageSize);
            model.Teacher=imagePretrainedNetwork("resnet18");
            assert(any(string({model.Teacher.Layers.Name})==model.FeatureLayer),'VIStudioV6:TeacherLayer','Teacher feature layer is missing.');
            probe=predict(model.Teacher,dlarray(zeros([imageSize 3 1],'single'),'SSCB'),'Outputs',model.FeatureLayer);
            channels=size(probe,3);
            layers=[imageInputLayer([imageSize 3],'Normalization','none','Name','input')
                convolution2dLayer(5,32,'Stride',2,'Padding','same','Name','conv1')
                reluLayer('Name','relu1')
                convolution2dLayer(3,64,'Stride',2,'Padding','same','Name','conv2')
                reluLayer('Name','relu2')
                convolution2dLayer(3,channels,'Stride',2,'Padding','same','Name','features')];
            model.Student=dlnetwork(layers);
        end
        function [model,history]=train(model,ds,base,o)
            teacher=model.Teacher; student=model.Student; useGPU=VIStudioTeacherStudentV6.useGPU(base.Environment);
            if useGPU, teacher=dlupdate(@gpuArray,teacher); student=dlupdate(@gpuArray,student); end
            average=[]; squared=[]; velocity=[]; iterations=0; lossValues=[]; epochs=[]; rates=[];
            files=string(ds.Files); stream=RandStream('mt19937ar','Seed',o.Seed);
            order=1:numel(files); if o.Shuffle=="once", order=randperm(stream,numel(files)); end
            for epoch=1:base.Epochs
                if o.Shuffle=="every-epoch", order=randperm(stream,numel(files)); end
                rate=base.LearnRate;
                if o.Schedule=="piecewise", rate=rate*o.DropFactor^floor((epoch-1)/o.DropPeriod); end
                for first=1:base.Batch:numel(files)
                    rows=order(first:min(numel(files),first+base.Batch-1));
                    batch=zeros([model.ImageSize 3 numel(rows)],'single');
                    for k=1:numel(rows), batch(:,:,:,k)=single(VIStudioData.readImage(files(rows(k)),model.ImageSize)); end
                    if useGPU, batch=gpuArray(batch); end
                    x=dlarray(batch,'SSCB'); target=predict(teacher,x,'Outputs',model.FeatureLayer);
                    % The target is evaluated outside dlfeval: teacher weights stay frozen.
                    target=VIStudioTeacherStudentV6.normalize(target);
                    [loss,gradients]=dlfeval(@VIStudioTeacherStudentV6.studentGradients,student,x/255,target,o.L2);
                    normSquared=0;
                    for k=1:height(gradients)
                        g=extractdata(gradients.Value{k}); normSquared=normSquared+double(gather(sum(g.^2,'all')));
                    end
                    factor=min(1,o.GradientThreshold/max(eps,sqrt(normSquared)));
                    for k=1:height(gradients), gradients.Value{k}=gradients.Value{k}*factor; end
                    iterations=iterations+1;
                    if o.Solver=="adam"
                        [student,average,squared]=adamupdate(student,gradients,average,squared,iterations,rate);
                    elseif o.Solver=="sgdm", [student,velocity]=sgdmupdate(student,gradients,velocity,rate,o.Momentum);
                    else, [student,squared]=rmspropupdate(student,gradients,squared,rate); end
                    value=double(gather(extractdata(loss))); assert(isfinite(value),'VIStudioV6:StudentLoss','Student loss is not finite.');
                    lossValues(end+1,1)=value; epochs(end+1,1)=epoch; rates(end+1,1)=rate; %#ok<AGROW>
                    drawnow limitrate;
                end
            end
            model.Student=dlupdate(@gather,student); model.Updates=model.Updates+iterations; model.Threshold=[];
            history=table((1:iterations)',epochs,lossValues,rates,'VariableNames',{'Iteration','Epoch','Loss','LearnRate'});
            model.TrainingHistory=[model.TrainingHistory;history];
        end
        function score=predict(model,image,varargin)
            map=anomalyMap(model,image,varargin{:}); sorted=sort(map(:),'descend');
            score=double(mean(sorted(1:max(1,ceil(numel(sorted)*0.05)))));
        end
        function map=anomalyMap(model,image,varargin)
            parser=inputParser; addParameter(parser,'ExecutionEnvironment','auto'); parse(parser,varargin{:});
            environment=validatestring(parser.Results.ExecutionEnvironment,{'auto','cpu','gpu'});
            image=imresize(image,model.ImageSize); if size(image,3)==1, image=repmat(image,1,1,3); end
            teacher=model.Teacher; student=model.Student; x=single(image);
            if VIStudioTeacherStudentV6.useGPU(environment)
                teacher=dlupdate(@gpuArray,teacher); student=dlupdate(@gpuArray,student); x=gpuArray(x);
            end
            x=dlarray(x,'SSCB'); target=predict(teacher,x,'Outputs',model.FeatureLayer); output=predict(student,x/255);
            difference=mean((VIStudioTeacherStudentV6.normalize(target)-VIStudioTeacherStudentV6.normalize(output)).^2,3);
            map=imresize(gather(extractdata(difference)),model.ImageSize,'bilinear');
            map=max(single(0),single(map));
        end
    end
    methods (Static,Access=private)
        function x=normalize(x), x=x./sqrt(sum(x.^2,3)+1e-8); end
        function [loss,gradients]=studentGradients(student,x,target,l2)
            output=VIStudioTeacherStudentV6.normalize(forward(student,x));
            loss=mean((output-target).^2,'all');
            if l2>0
                for k=1:height(student.Learnables), loss=loss+0.5*l2*sum(student.Learnables.Value{k}.^2,'all'); end
            end
            gradients=dlgradient(loss,student.Learnables);
        end
        function flag=useGPU(environment)
            available=canUseGPU;
            assert(~strcmp(environment,'gpu') || available,'VIStudioV6:GPUUnavailable','No supported GPU is available.');
            flag=strcmp(environment,'gpu') || (strcmp(environment,'auto') && available);
        end
    end
end
