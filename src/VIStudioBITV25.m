classdef VIStudioBITV25
    % Independent native MATLAB inference: Open-CD improved BIT-R18 variant.
    % Shared ResNetV1c (3 stages), 4 tokens/view, encoder1, cross-decoder8.
    % Native dlconv/maxpool and MATLAB matrix operations. No Python runtime.
    methods (Static)
        function a=create(inputSize,seed)
            if nargin<1, inputSize=[256 256 3]; end; if nargin<2, seed=24; end
            VIStudioBITV25.checkSize(inputSize); validateattributes(seed,{'numeric'},{'scalar','integer','>=',0,'<=',2^32-1}); spec=VIStudioBITV25.spec(); names=fieldnames(spec); stream=RandStream('mt19937ar','Seed',seed); weights=struct();
            for k=1:numel(names)
                key=names{k}; sz=spec.(key);
                if endsWith(key,'running_var') || (endsWith(key,'_weight') && numel(sz)==2 && sz(2)==1), value=ones(sz,'single');
                elseif endsWith(key,'_weight') || endsWith(key,'embedding'), value=.02*randn(stream,sz,'single');
                else, value=zeros(sz,'single'); end
                weights.(key)=value;
            end
            metadata=struct('Kind',"VIStudioNativeBIT",'Version',1,'Architecture',"bit-r18",'InputSize',inputSize,'Preprocessing',"RGB [0,1]; ImageNet mean/std; normalized-zero pad32; crop original",'ClassNames',["unchanged","changed"],'WeightStatus',"RANDOM_INITIALIZATION",'ValidatedForRealInspection',false,'ThresholdCalibrated',false,'Implementation',"Open-CD improved BITHead; shared ResNetV1c18 3-stage; 4 tokens/view; encoder1 decoder8; native inference only");
            a=struct('Metadata',metadata,'Weights',weights);
        end
        function checkSize(sz)
            validateattributes(sz,{'numeric'},{'size',[1 3],'integer','positive'}); assert(sz(3)==3 && all(sz(1:2)>=16) && prod(ceil(sz(1:2)/32)*32)<=262144,'VIStudioV25:BITSize','BIT requires RGB >=16x16 and at most 262144 padded pixels.');
        end
        function validate(a)
            assert(isstruct(a) && isscalar(a) && all(isfield(a,{'Metadata','Weights'})) && isstruct(a.Metadata) && isscalar(a.Metadata) && isstruct(a.Weights) && isscalar(a.Weights),'VIStudioV25:BITArtifact','Invalid native BIT artifact.'); m=a.Metadata;
            assert(all(isfield(m,{'Kind','Version','Architecture','InputSize','Preprocessing','ClassNames','WeightStatus','ValidatedForRealInspection','ThresholdCalibrated','Implementation'})) && isequal(string(m.Kind),"VIStudioNativeBIT") && isequal(m.Version,1) && isequal(string(m.Architecture),"bit-r18") && isequal(string(m.Preprocessing),"RGB [0,1]; ImageNet mean/std; normalized-zero pad32; crop original") && isequal(string(m.ClassNames),["unchanged","changed"]),'VIStudioV25:BITArtifact','Unsupported BIT architecture/preprocessing/class contract.'); VIStudioBITV25.checkSize(m.InputSize);
            spec=VIStudioBITV25.spec(); names=fieldnames(spec); assert(isequal(sort(names),sort(fieldnames(a.Weights))),'VIStudioV25:BITWeights','Missing or unexpected BIT parameters.');
            for k=1:numel(names)
                v=a.Weights.(names{k}); shape=spec.(names{k}); assert(isa(v,'single') && isreal(v) && numel(v)==prod(shape) && isequal(size(v,1:numel(shape)),shape) && all(isfinite(v),'all'),'VIStudioV25:BITWeights','Invalid tensor: %s',names{k});
                if endsWith(names{k},'running_var'), assert(all(v>=0,'all'),'VIStudioV25:BITWeights','Negative BN variance.'); end
            end
        end
        function saveWeights(a,file)
            VIStudioBITV25.validate(a); assert(~isfile(file),'VIStudioV25:BITOverwrite','Choose a new checkpoint path.'); checkpoint=struct('Kind',"VIStudioBITWeights",'Version',1,'Metadata',a.Metadata,'Weights',a.Weights); save(file,'checkpoint','-v7.3');
        end
        function a=loadWeights(file,inputSize)
            loaded=load(file,'checkpoint'); assert(isfield(loaded,'checkpoint'),'VIStudioV25:BITWeights','Require a native BIT checkpoint.'); c=loaded.checkpoint; assert(isstruct(c) && isscalar(c) && all(isfield(c,{'Kind','Version','Metadata','Weights'})) && isequal(string(c.Kind),"VIStudioBITWeights") && isequal(c.Version,1),'VIStudioV25:BITWeights','Unsupported BIT checkpoint.'); a=struct('Metadata',c.Metadata,'Weights',c.Weights); if nargin>1, a.Metadata.InputSize=inputSize; end; VIStudioBITV25.validate(a);
        end
        function [score,probabilities,trace]=predict(a,reference,current)
            VIStudioBITV25.validate(a); sz=a.Metadata.InputSize; assert(isequal(size(reference),sz) && isequal(size(current),sz),'VIStudioV25:BITSize','Pair must match the exact native BIT input shape.'); validateattributes(reference,{'numeric'},{'real','finite','>=',0,'<=',1}); validateattributes(current,{'numeric'},{'real','finite','>=',0,'<=',1});
            meanRGB=reshape(single([.485 .456 .406]),1,1,3); stdRGB=reshape(single([.229 .224 .225]),1,1,3); pad=mod(-sz(1:2),32); x=padarray((single(reference)-meanRGB)./stdRGB,pad,0,'post'); y=padarray((single(current)-meanRGB)./stdRGB,pad,0,'post'); w=a.Weights;
            x=VIStudioBITV25.backbone(w,x); y=VIStudioBITV25.backbone(w,y); trace=struct('ReferenceBackbone',x);
            x=max(0,VIStudioBITV25.conv(w,VIStudioBITV25.resize(x,2),'decode_head_pre_process_1_conv',1,1)); y=max(0,VIStudioBITV25.conv(w,VIStudioBITV25.resize(y,2),'decode_head_pre_process_1_conv',1,1));
            t1=VIStudioBITV25.tokens(w,x); t2=VIStudioBITV25.tokens(w,y); t=[t1;t2]+reshape(w.decode_head_enc_pos_embedding,8,32); p='decode_head_encoder_0'; n=VIStudioBITV25.norm(w,t,[p '_norm1']); t=t+VIStudioBITV25.attention(w,n,n,[p '_attn']); t=t+VIStudioBITV25.feed(w,VIStudioBITV25.norm(w,t,[p '_norm2']),p);
            t1=t(1:4,:); t2=t(5:8,:); shape=size(x); x=reshape(x,[],32); y=reshape(y,[],32);
            for k=0:7
                p=sprintf('decode_head_decoder_%d',k); x=VIStudioBITV25.decode(w,x,t1,p); y=VIStudioBITV25.decode(w,y,t2,p);
            end
            features=VIStudioBITV25.resize(reshape(abs(x-y),shape),4); logits=VIStudioBITV25.conv(w,features,'decode_head_conv_seg',1,0); probabilities=VIStudioBITV25.softmax(logits,3); probabilities=probabilities(1:sz(1),1:sz(2),:); score=probabilities(:,:,2);
            assert(isequal(size(probabilities),[sz(1:2) 2]) && all(isfinite(probabilities),'all') && all(probabilities>=0 & probabilities<=1,'all') && max(abs(sum(probabilities,3)-1),[],'all')<1e-5,'VIStudioV25:BITOutput','Invalid BIT probabilities.');
        end
        function x=backbone(w,x)
            pairs=[0 1;3 4;6 7];
            for k=1:3, x=max(0,VIStudioBITV25.bn(w,VIStudioBITV25.conv(w,x,sprintf('backbone_stem_%d',pairs(k,1)),1+(k==1),1),sprintf('backbone_stem_%d',pairs(k,2)))); end
            x=extractdata(maxpool(dlarray(x,'SSCB'),[3 3],'Stride',2,'Padding',1));
            for stage=1:3
                for block=0:1
                    p=sprintf('backbone_layer%d_%d',stage,block); stride=1+(stage==2 && block==0); skip=x;
                    z=max(0,VIStudioBITV25.bn(w,VIStudioBITV25.conv(w,x,[p '_conv1'],stride,1),[p '_bn1'])); z=VIStudioBITV25.bn(w,VIStudioBITV25.conv(w,z,[p '_conv2'],1,1),[p '_bn2']);
                    if isfield(w,[p '_downsample_0_weight']), skip=VIStudioBITV25.bn(w,VIStudioBITV25.conv(w,skip,[p '_downsample_0'],stride,0),[p '_downsample_1']); end
                    x=max(0,z+skip);
                end
            end
        end
        function x=conv(w,x,p,stride,padding)
            weights=w.([p '_weight']); bias=zeros(size(weights,4),1,'single'); if isfield(w,[p '_bias']), bias=reshape(w.([p '_bias']),[],1); end; x=extractdata(dlconv(dlarray(x,'SSCB'),weights,bias,'Stride',stride,'Padding',padding));
        end
        function x=bn(w,x,p)
            x=(x-reshape(w.([p '_running_mean']),1,1,[]))./sqrt(reshape(w.([p '_running_var']),1,1,[])+single(1e-5)); x=x.*reshape(w.([p '_weight']),1,1,[])+reshape(w.([p '_bias']),1,1,[]);
        end
        function tokens=tokens(w,x)
            att=max(0,VIStudioBITV25.conv(w,x,'decode_head_conv_att_conv',1,0)); att=VIStudioBITV25.softmax(reshape(att,[],4),1); tokens=att'*reshape(x,[],32);
        end
        function y=norm(w,x,p)
            meanValue=mean(x,2); variance=mean((x-meanValue).^2,2); y=(x-meanValue)./sqrt(variance+single(1e-5)); y=y.*reshape(w.([p '_weight']),1,[])+reshape(w.([p '_bias']),1,[]);
        end
        function y=linear(w,x,p)
            y=x*w.([p '_weight'])'; if isfield(w,[p '_bias']), y=y+reshape(w.([p '_bias']),1,[]); end
        end
        function y=attention(w,x,reference,p)
            q=VIStudioBITV25.linear(w,x,[p '_to_q']); k=VIStudioBITV25.linear(w,reference,[p '_to_k']); v=VIStudioBITV25.linear(w,reference,[p '_to_v']); y=zeros(size(x,1),64,'single');
            for head=1:8, ids=(head-1)*8+(1:8); scores=(q(:,ids)*k(:,ids)')*single(32^-.5); scores=VIStudioBITV25.softmax(scores,2); y(:,ids)=scores*v(:,ids); end
            y=VIStudioBITV25.linear(w,y,[p '_fc_out_0']);
        end
        function x=decode(w,x,reference,p)
            x=x+VIStudioBITV25.attention(w,VIStudioBITV25.norm(w,x,[p '_norm1']),VIStudioBITV25.norm(w,reference,[p '_norm1_']),[p '_attn']); x=x+VIStudioBITV25.feed(w,VIStudioBITV25.norm(w,x,[p '_norm2']),p);
        end
        function y=feed(w,x,p), y=VIStudioBITV25.linear(w,max(0,VIStudioBITV25.linear(w,x,[p '_ff_0'])),[p '_ff_3']); end
        function y=softmax(x,dim), x=exp(x-max(x,[],dim)); y=x./sum(x,dim); end
        function y=resize(x,scale)
            h=size(x,1); width=size(x,2); yy=min(h,max(1,((1:h*scale)-.5)/scale+.5)); xx=min(width,max(1,((1:width*scale)-.5)/scale+.5)); y0=floor(yy); y1=min(h,y0+1); x0=floor(xx); x1=min(width,x0+1); wy=reshape(single(yy-y0),[],1,1); wx=reshape(single(xx-x0),1,[],1);
            y=(x(y0,x0,:).*(1-wx)+x(y0,x1,:).*wx).*(1-wy)+(x(y1,x0,:).*(1-wx)+x(y1,x1,:).*wx).*wy;
        end
        function s=spec()
            s=struct(); pairs=[0 1 3 32;3 4 32 32;6 7 32 64];
            for k=1:3, s=VIStudioBITV25.convSpec(s,sprintf('backbone_stem_%d',pairs(k,1)),3,pairs(k,3),pairs(k,4),false); s=VIStudioBITV25.bnSpec(s,sprintf('backbone_stem_%d',pairs(k,2)),pairs(k,4)); end
            previous=64;
            for stage=1:3
                channels=64*2^(stage-1);
                for block=0:1
                    p=sprintf('backbone_layer%d_%d',stage,block); s=VIStudioBITV25.convSpec(s,[p '_conv1'],3,previous,channels,false); s=VIStudioBITV25.bnSpec(s,[p '_bn1'],channels); s=VIStudioBITV25.convSpec(s,[p '_conv2'],3,channels,channels,false); s=VIStudioBITV25.bnSpec(s,[p '_bn2'],channels);
                    if previous~=channels, s=VIStudioBITV25.convSpec(s,[p '_downsample_0'],1,previous,channels,false); s=VIStudioBITV25.bnSpec(s,[p '_downsample_1'],channels); end
                    previous=channels;
                end
            end
            s=VIStudioBITV25.convSpec(s,'decode_head_pre_process_1_conv',3,256,32,true); s=VIStudioBITV25.convSpec(s,'decode_head_conv_att_conv',1,32,4,true); s=VIStudioBITV25.convSpec(s,'decode_head_conv_seg',1,32,2,true); s.decode_head_enc_pos_embedding=[1 8 32];
            for block=-1:7
                if block==-1, p='decode_head_encoder_0'; norms={'norm1','norm2'}; else, p=sprintf('decode_head_decoder_%d',block); norms={'norm1','norm1_','norm2'}; end
                for key={'to_q','to_k','to_v'}, s.([p '_attn_' key{1} '_weight'])=[64 32]; end
                s.([p '_attn_fc_out_0_weight'])=[32 64]; s.([p '_attn_fc_out_0_bias'])=[32 1]; s.([p '_ff_0_weight'])=[64 32]; s.([p '_ff_0_bias'])=[64 1]; s.([p '_ff_3_weight'])=[32 64]; s.([p '_ff_3_bias'])=[32 1];
                for n=norms, s.([p '_' n{1} '_weight'])=[32 1]; s.([p '_' n{1} '_bias'])=[32 1]; end
            end
        end
        function s=convSpec(s,p,k,inc,outc,bias)
            s.([p '_weight'])=[k k inc outc]; if bias, s.([p '_bias'])=[outc 1]; end
        end
        function s=bnSpec(s,p,c)
            for suffix={'weight','bias','running_mean','running_var'}, s.([p '_' suffix{1}])=[c 1]; end
        end
    end
end
