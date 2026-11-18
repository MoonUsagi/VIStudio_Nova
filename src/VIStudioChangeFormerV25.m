classdef VIStudioChangeFormerV25
    % Native inference for Open-CD's Siamese SegFormer MiT-B0 variant.
    % Published upstream as ChangeFormer; NOT original ChangeFormer V6.
    % Shared 4-stage MiT, efficient attention, MixFFN and SegFormer decoder.
    methods (Static)
        function a=create(inputSize,seed)
            if nargin<1, inputSize=[256 256 3]; end; if nargin<2, seed=25; end; VIStudioChangeFormerV25.checkSize(inputSize); validateattributes(seed,{'numeric'},{'scalar','integer','>=',0,'<=',2^32-1}); schema=VIStudioChangeFormerV25.spec(); names=fieldnames(schema); stream=RandStream('mt19937ar','Seed',seed); weights=struct();
            for k=1:numel(names)
                key=names{k}; shape=schema.(key);
                if endsWith(key,'running_var') || (endsWith(key,'_weight') && numel(shape)==2 && shape(2)==1), weights.(key)=ones(shape,'single');
                elseif endsWith(key,'_weight'), weights.(key)=.02*randn(stream,shape,'single'); else, weights.(key)=zeros(shape,'single'); end
            end
            metadata=struct('Kind',"VIStudioNativeChangeFormer",'Version',1,'Architecture',"opencd-changeformer-b0",'InputSize',inputSize,'Preprocessing',"RGB [0,1]; ImageNet mean/std; normalized-zero pad32; crop original",'ClassNames',["unchanged","changed"],'WeightStatus',"RANDOM_INITIALIZATION",'ValidatedForRealInspection',false,'ThresholdCalibrated',false,'OriginalChangeFormerV6',false,'Implementation',"Open-CD Siamese SegFormer MiT-B0, not strict ChangeFormer V6; native inference only"); a=struct('Metadata',metadata,'Weights',weights);
        end
        function checkSize(sz)
            validateattributes(sz,{'numeric'},{'size',[1 3],'integer','positive'}); assert(sz(3)==3 && all(sz(1:2)>=16) && prod(ceil(sz(1:2)/32)*32)<=262144,'VIStudioV25:ChangeFormerSize','Require RGB >=16x16 and <=262144 padded pixels.');
        end
        function validate(a)
            assert(isstruct(a) && isscalar(a) && all(isfield(a,{'Metadata','Weights'})) && isstruct(a.Metadata) && isscalar(a.Metadata) && isstruct(a.Weights) && isscalar(a.Weights),'VIStudioV25:ChangeFormerArtifact','Invalid native Open-CD ChangeFormer artifact.'); m=a.Metadata;
            assert(all(isfield(m,{'Kind','Version','Architecture','InputSize','Preprocessing','ClassNames','WeightStatus','ValidatedForRealInspection','ThresholdCalibrated','OriginalChangeFormerV6','Implementation'})) && isequal(string(m.Kind),"VIStudioNativeChangeFormer") && isequal(m.Version,1) && isequal(string(m.Architecture),"opencd-changeformer-b0") && isequal(string(m.Preprocessing),"RGB [0,1]; ImageNet mean/std; normalized-zero pad32; crop original") && isequal(string(m.ClassNames),["unchanged","changed"]) && isequal(m.OriginalChangeFormerV6,false),'VIStudioV25:ChangeFormerArtifact','Unsupported architecture, preprocessing or original-model claim.'); VIStudioChangeFormerV25.checkSize(m.InputSize);
            schema=VIStudioChangeFormerV25.spec(); names=fieldnames(schema); assert(isequal(sort(names),sort(fieldnames(a.Weights))),'VIStudioV25:ChangeFormerWeights','Missing or extra tensors.');
            for k=1:numel(names), value=a.Weights.(names{k}); shape=schema.(names{k}); assert(isa(value,'single') && isreal(value) && isequal(size(value,1:numel(shape)),shape) && numel(value)==prod(shape) && all(isfinite(value),'all'),'VIStudioV25:ChangeFormerWeights','Invalid tensor %s',names{k}); if endsWith(names{k},'running_var'), assert(all(value>=0,'all'),'VIStudioV25:ChangeFormerWeights','Negative BN variance.'); end, end
        end
        function saveWeights(a,file)
            VIStudioChangeFormerV25.validate(a); assert(~isfile(file),'VIStudioV25:ChangeFormerOverwrite','Choose a new checkpoint path.'); checkpoint=struct('Kind',"VIStudioChangeFormerWeights",'Version',1,'Metadata',a.Metadata,'Weights',a.Weights); save(file,'checkpoint','-v7.3');
        end
        function a=loadWeights(file,inputSize)
            s=load(file,'checkpoint'); assert(isfield(s,'checkpoint'),'VIStudioV25:ChangeFormerWeights','Require native checkpoint.'); c=s.checkpoint; assert(isstruct(c) && isscalar(c) && all(isfield(c,{'Kind','Version','Metadata','Weights'})) && isequal(string(c.Kind),"VIStudioChangeFormerWeights") && isequal(c.Version,1),'VIStudioV25:ChangeFormerWeights','Unsupported checkpoint.'); a=struct('Metadata',c.Metadata,'Weights',c.Weights); if nargin>1, a.Metadata.InputSize=inputSize; end; VIStudioChangeFormerV25.validate(a);
        end
        function [score,probabilities,trace]=predict(a,reference,current)
            VIStudioChangeFormerV25.validate(a); sz=a.Metadata.InputSize; assert(isequal(size(reference),sz) && isequal(size(current),sz),'VIStudioV25:ChangeFormerSize','Pair must match native input shape.'); validateattributes(reference,{'numeric'},{'real','finite','>=',0,'<=',1}); validateattributes(current,{'numeric'},{'real','finite','>=',0,'<=',1});
            meanRGB=reshape(single([.485 .456 .406]),1,1,3); stdRGB=reshape(single([.229 .224 .225]),1,1,3); pad=mod(-sz(1:2),32); x=padarray((single(reference)-meanRGB)./stdRGB,pad,0,'post'); y=padarray((single(current)-meanRGB)./stdRGB,pad,0,'post'); weights=a.Weights;
            first=VIStudioChangeFormerV25.encode(weights,x); second=VIStudioChangeFormerV25.encode(weights,y); trace=struct('ReferenceStages',{first}); maps=cell(1,4);
            for stage=1:4
                p=sprintf('decode_head_convs_%d',stage-1); z=VIStudioBITV25.conv(weights,cat(3,first{stage},second{stage}),[p '_conv'],1,0); z=max(0,VIStudioBITV25.bn(weights,z,[p '_bn'])); maps{stage}=VIStudioBITV25.resize(z,2^(stage-1));
            end
            z=VIStudioBITV25.conv(weights,cat(3,maps{:}),'decode_head_fusion_conv_conv',1,0); z=max(0,VIStudioBITV25.bn(weights,z,'decode_head_fusion_conv_bn')); logits=VIStudioBITV25.conv(weights,z,'decode_head_conv_seg',1,0); logits=VIStudioBITV25.resize(logits,4); probabilities=VIStudioBITV25.softmax(logits,3); probabilities=probabilities(1:sz(1),1:sz(2),:); score=probabilities(:,:,2);
            assert(isequal(size(probabilities),[sz(1:2) 2]) && all(isfinite(probabilities),'all') && all(probabilities>=0 & probabilities<=1,'all') && max(abs(sum(probabilities,3)-1),[],'all')<1e-5,'VIStudioV25:ChangeFormerOutput','Invalid probabilities.');
        end
        function outputs=encode(weights,x)
            widths=[32 64 160 256]; heads=[1 2 5 8]; ratios=[8 4 2 1]; outputs=cell(1,4);
            for stage=1:4
                p=sprintf('backbone_layers_%d',stage-1); stride=2; kernel=3; if stage==1, stride=4; kernel=7; end
                x=VIStudioBITV25.conv(weights,x,[p '_0_projection'],stride,floor(kernel/2)); shape=size(x); channels=widths(stage); z=VIStudioChangeFormerV25.norm(weights,reshape(x,[],channels),[p '_0_norm']);
                for block=0:1
                    b=sprintf('%s_1_%d',p,block); n=VIStudioChangeFormerV25.norm(weights,z,[b '_norm1']); kv=n; sr=ratios(stage);
                    if sr>1, reduced=VIStudioBITV25.conv(weights,reshape(n,shape),[b '_attn_sr'],sr,0); kv=VIStudioChangeFormerV25.norm(weights,reshape(reduced,[],channels),[b '_attn_norm']); end
                    z=z+VIStudioChangeFormerV25.attention(weights,n,kv,[b '_attn_attn'],heads(stage)); f=reshape(VIStudioChangeFormerV25.norm(weights,z,[b '_norm2']),shape); f=VIStudioBITV25.conv(weights,f,[b '_ffn_layers_0'],1,0);
                    dw=weights.([b '_ffn_layers_1_weight']); dw=reshape(dw,3,3,1,1,channels*4); f=extractdata(dlconv(dlarray(f,'SSCB'),dw,weights.([b '_ffn_layers_1_bias']),'Padding',1)); f=.5*f.*(1+erf(f/single(sqrt(2)))); f=VIStudioBITV25.conv(weights,f,[b '_ffn_layers_4'],1,0); z=z+reshape(f,[],channels);
                end
                x=reshape(VIStudioChangeFormerV25.norm(weights,z,[p '_2']),shape); outputs{stage}=x;
            end
        end
        function y=norm(weights,x,p)
            meanValue=mean(x,2); variance=mean((x-meanValue).^2,2); y=(x-meanValue)./sqrt(variance+single(1e-6)); y=y.*reshape(weights.([p '_weight']),1,[])+reshape(weights.([p '_bias']),1,[]);
        end
        function y=attention(weights,x,reference,p,numHeads)
            width=size(x,2); w=weights.([p '_in_proj_weight']); b=weights.([p '_in_proj_bias']); q=x*w(1:width,:)'+reshape(b(1:width),1,[]); k=reference*w(width+(1:width),:)'+reshape(b(width+(1:width)),1,[]); v=reference*w(2*width+(1:width),:)'+reshape(b(2*width+(1:width)),1,[]); y=zeros(size(x),'single'); dim=width/numHeads;
            for head=1:numHeads, ids=(head-1)*dim+(1:dim); scores=VIStudioBITV25.softmax((q(:,ids)*k(:,ids)')*single(dim^-.5),2); y(:,ids)=scores*v(:,ids); end
            y=y*weights.([p '_out_proj_weight'])'+reshape(weights.([p '_out_proj_bias']),1,[]);
        end
        function s=spec()
            s=struct(); widths=[32 64 160 256]; ratios=[8 4 2 1]; previous=3;
            for stage=1:4
                channels=widths(stage); p=sprintf('backbone_layers_%d',stage-1); kernel=3; if stage==1, kernel=7; end
                s=VIStudioBITV25.convSpec(s,[p '_0_projection'],kernel,previous,channels,true); s=VIStudioChangeFormerV25.normSpec(s,[p '_0_norm'],channels); s=VIStudioChangeFormerV25.normSpec(s,[p '_2'],channels);
                for block=0:1
                    b=sprintf('%s_1_%d',p,block); s=VIStudioChangeFormerV25.normSpec(s,[b '_norm1'],channels); s=VIStudioChangeFormerV25.normSpec(s,[b '_norm2'],channels); s.([b '_attn_attn_in_proj_weight'])=[3*channels channels]; s.([b '_attn_attn_in_proj_bias'])=[3*channels 1]; s.([b '_attn_attn_out_proj_weight'])=[channels channels]; s.([b '_attn_attn_out_proj_bias'])=[channels 1];
                    if ratios(stage)>1, s=VIStudioBITV25.convSpec(s,[b '_attn_sr'],ratios(stage),channels,channels,true); s=VIStudioChangeFormerV25.normSpec(s,[b '_attn_norm'],channels); end
                    s=VIStudioBITV25.convSpec(s,[b '_ffn_layers_0'],1,channels,4*channels,true); s=VIStudioBITV25.convSpec(s,[b '_ffn_layers_1'],3,1,4*channels,true); s=VIStudioBITV25.convSpec(s,[b '_ffn_layers_4'],1,4*channels,channels,true);
                end
                d=sprintf('decode_head_convs_%d',stage-1); s=VIStudioBITV25.convSpec(s,[d '_conv'],1,channels*2,256,false); s=VIStudioBITV25.bnSpec(s,[d '_bn'],256); previous=channels;
            end
            s=VIStudioBITV25.convSpec(s,'decode_head_fusion_conv_conv',1,1024,256,false); s=VIStudioBITV25.bnSpec(s,'decode_head_fusion_conv_bn',256); s=VIStudioBITV25.convSpec(s,'decode_head_conv_seg',1,256,2,true);
        end
        function s=normSpec(s,p,channels), s.([p '_weight'])=[channels 1]; s.([p '_bias'])=[channels 1]; end
    end
end
