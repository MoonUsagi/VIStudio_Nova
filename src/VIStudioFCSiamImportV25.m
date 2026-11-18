classdef VIStudioFCSiamImportV25
    % One-time import of reviewed Open-CD numeric tensor exports, no Python calls.
    methods (Static)
        function a=convert(tensorFile,provenance,inputSize)
            if nargin<3, inputSize=[256 256 3]; end; s=load(tensorFile,'tensors'); assert(isfield(s,'tensors'),'VIStudioV25:ImportTensors','Missing tensors.'); t=s.tensors;
            a=VIStudioFCSiamV25.create(provenance.Variant,inputSize,23);
            % Fold the source's final 16-channel linear transpose-convolution
            % and its linear 1x1 segmentation head into the native 2-class head.
            w=t.conv11d_weight; h=reshape(t.head_weight,2,16); folded=zeros(16,2,3,3,'single');
            for i=1:16, for c=1:2, for k=1:16, folded(i,c,:,:)=folded(i,c,:,:)+reshape(h(c,k)*w(i,k,:,:),1,1,3,3); end, end, end
            t.conv11d_weight=folded; t.conv11d_bias=h*reshape(t.conv11d_bias,[],1)+reshape(t.head_bias,[],1);
            a.Encoder=VIStudioFCSiamImportV25.assign(a.Encoder,t);
            for k=1:4, a.Up{k}=VIStudioFCSiamImportV25.assign(a.Up{k},t); a.Block{k}=VIStudioFCSiamImportV25.assign(a.Block{k},t); end
            a.Metadata.Preprocessing="RGB im2single [0,1]; ordered reference,current; ImageNet RGB normalization; pad32";
            a.Metadata.Normalization=struct('Mean',[.485 .456 .406],'Std',[.229 .224 .225],'PadMultiple',32,'PadValue',0);
            a.Metadata.WeightStatus="PRETRAINED_REMOTE_SENSING_UNVALIDATED_INDUSTRIAL"; a.Metadata.TrainingDomain="Open-CD publisher checkpoint; LEVIR-CD building changes"; a.Metadata.Provenance=provenance; VIStudioFCSiamV25.validate(a);
        end
        function net=assign(net,tensors)
            p=VIStudioFCSiamV25.pack(net);
            for key={'Learnables','State'}
                rows=p.(key{1});
                for k=1:height(rows)
                    layer=string(rows.Layer(k)); parameter=string(rows.Parameter(k)); base=layer; if endsWith(base,'_bn'), base="bn"+extractBetween(base,5,strlength(base)-3); end
                    switch parameter
                        case "Weights", suffix="weight";
                        case "Bias", suffix="bias";
                        case "Scale", suffix="weight";
                        case "Offset", suffix="bias";
                        case "TrainedMean", suffix="running_mean";
                        case "TrainedVariance", suffix="running_var";
                        otherwise, error('VIStudioV25:ImportParameter','Unsupported parameter %s',parameter);
                    end
                    name=char(base+"_"+suffix); assert(isfield(tensors,name),'VIStudioV25:ImportParameter','Missing %s',name); value=tensors.(name);
                    if parameter=="Weights", value=permute(value,[3 4 2 1]); end
                    assert(numel(value)==numel(rows.Value{k}),'VIStudioV25:ImportShape','Tensor size mismatch: %s',name); rows.Value{k}=reshape(single(value),size(rows.Value{k}));
                end
                p.(key{1})=rows;
            end
            net=VIStudioFCSiamV25.restore(net,p);
        end
    end
end
