classdef VIStudioModelVisualsV7
    % Read actual network graphs; perturbation explanations also support detectors.
    methods (Static)
        function components=components(model)
            components=struct('Name',{},'Network',{});
            if isa(model,'dlnetwork'), components(1)=struct('Name',"Network",'Network',model); return; end
            % R2026b YOLOX exposes readable, hidden component networks. Probe
            % their types rather than assuming that detector.Network exists.
            for name={'Backbone','Neck','Head','Network'}
                if isprop(model,name{1})
                    try
                        network=model.(name{1});
                        if isa(network,'DAGNetwork') || isa(network,'SeriesNetwork'), network=dlnetwork(network); end
                        if isa(network,'dlnetwork')
                            components(end+1)=struct('Name',string(name{1}),'Network',network); %#ok<AGROW>
                        end
                    catch
                        % Unsupported/private components are explicitly absent.
                    end
                end
            end
        end
        function [graph,layers]=networkGraph(net)
            names=string({net.Layers.Name})'; types=string(arrayfun(@class,net.Layers,'UniformOutput',false)); types=types(:);
            source=string(net.Connections.Source); target=string(net.Connections.Destination);
            for k=1:numel(source)
                if ~ismember(source(k),names), source(k)=regexprep(source(k),'/[^/]+$',''); end
                if ~ismember(target(k),names), target(k)=regexprep(target(k),'/[^/]+$',''); end
            end
            assert(all(ismember(source,names)) && all(ismember(target,names)),'VIStudioV7:NetworkGraph','Unknown connection endpoint.');
            graph=digraph(cellstr(source),cellstr(target),[],cellstr(names)); count=zeros(numel(names),1);
            values=net.Learnables;
            for k=1:height(values)
                index=find(names==string(values.Layer(k)),1); count(index)=count(index)+numel(values.Value{k});
            end
            layers=table(names,types,count,'VariableNames',{'Name','Type','Parameters'});
        end
        function result=explain(model,task,metadata,file,options,progress)
            if nargin<5, options=struct(); end
            if nargin<6, progress=@(~,~) false; end
            defaults=struct('Method',"occlusion",'Target',"auto",'DetectionIndex',1,'GridSize',4, ...
                'Threshold',.25,'Environment','cpu','FeatureLayer',"auto");
            assert(isstruct(options) && isscalar(options),'VIStudioV7:VisualOptions','Options must be a scalar struct.');
            fields=fieldnames(options); assert(all(isfield(defaults,fields),'all'),'VIStudioV7:VisualOptions','Unknown visualization option.');
            for k=1:numel(fields), defaults.(fields{k})=options.(fields{k}); end
            o=defaults; o.Method=string(validatestring(o.Method,{'gradcam','occlusion','features'}));
            validateattributes(o.GridSize,{'numeric'},{'scalar','integer','>=',2,'<=',12});
            validateattributes(o.DetectionIndex,{'numeric'},{'scalar','integer','positive'});
            validateattributes(o.Threshold,{'numeric'},{'scalar','finite','>=',0,'<=',1});
            o.Environment=validatestring(o.Environment,{'cpu','gpu','auto'});
            image=VIStudioData.readImage(file,[]); sizeOriginal=[size(image,1) size(image,2)];
            result=struct('Task',string(task),'File',VIStudioToolsV3.canonicalPath(file), ...
                'SourceHash',VIStudioToolsV3.fileHash(file),'Method',o.Method,'Options',o,'Map',[], ...
                'Target',"",'BaselineScore',NaN,'Scores',[],'Labels',strings(0,1),'Boxes',zeros(0,4), ...
                'FeatureLayer',"",'ReductionLayer',"",'Completed',false);
            result.ModelClass=string(class(model)); result.ModelName=""; result.ModelFile=""; result.ModelDigest="";
            for field={'ModelName','ModelFile','ModelDigest'}
                if isfield(metadata,field{1}), result.(field{1})=string(metadata.(field{1})); end
            end
            if task=="classification"
                classes=string(metadata.ClassNames(:)); inputSize=getLayer(model,model.InputNames{1}).InputSize;
                input=imresize(image,inputSize(1:2)); if inputSize(3)==1, input=rgb2gray(input); end
                scores=VIStudioModelVisualsV7.classScores(model,input,o.Environment,numel(classes));
                [~,index]=max(scores);
                if string(o.Target)~="auto"
                    index=find(classes==string(o.Target),1); assert(~isempty(index),'VIStudioV7:VisualTarget','Unknown class.');
                end
                result.Target=classes(index); result.BaselineScore=scores(index); result.Scores=scores; result.Labels=classes;
                if o.Method=="gradcam"
                    args={'ExecutionEnvironment',o.Environment};
                    if string(o.FeatureLayer)~="auto", args=[args {'FeatureLayer',char(o.FeatureLayer)}]; end
                    [map,feature,reduction]=gradCAM(model,input,index,args{:});
                    result.FeatureLayer=string(feature); result.ReductionLayer=string(reduction);
                elseif o.Method=="features"
                    feature=string(o.FeatureLayer);
                    if feature=="auto"
                        layers=model.Layers; conv=arrayfun(@(l) isa(l,'nnet.cnn.layer.Convolution2DLayer'),layers);
                        assert(any(conv),'VIStudioV7:FeatureLayer','Select a spatial feature layer.');
                        feature=string(layers(find(conv,1,'last')).Name);
                    end
                    features=minibatchpredict(model,input,'Outputs',char(feature),'ExecutionEnvironment',o.Environment);
                    if isa(features,'dlarray'), features=extractdata(features); end
                    features=gather(features); assert(ndims(features)<=3 && size(features,1)>1 && size(features,2)>1, ...
                        'VIStudioV7:FeatureLayer','Selected layer must have spatial features.');
                    map=mean(abs(single(features)),3); result.FeatureLayer=feature;
                    result.FeatureMaps=features(:,:,1:min(16,size(features,3)));
                else
                    objective=@(x) VIStudioModelVisualsV7.classObjective(model,x,o.Environment,numel(classes),index);
                    map=VIStudioModelVisualsV7.occlude(input,result.BaselineScore,objective,o.GridSize,progress);
                end
            else
                assert(task=="detection" && o.Method=="occlusion",'VIStudioV7:VisualMethod','Detection uses target-specific occlusion.');
                [boxes,scores,labels]=detect(model,image,'Threshold',o.Threshold,'ExecutionEnvironment',o.Environment);
                labels=string(labels(:)); scores=double(scores(:));
                keep=scores>=o.Threshold; boxes=double(boxes(keep,:)); scores=scores(keep); labels=labels(keep);
                assert(~isempty(scores),'VIStudioV7:NoVisualTarget','No detection at this threshold. Lower the threshold or choose another image.');
                [scores,order]=sort(scores,'descend'); boxes=boxes(order,:); labels=labels(order);
                index=o.DetectionIndex; assert(index<=numel(scores),'VIStudioV7:VisualTarget','Detection index exceeds the object count.');
                result.Boxes=boxes; result.Scores=scores; result.Labels=labels;
                result.Target=labels(index); result.TargetBox=boxes(index,:); result.BaselineScore=scores(index);
                objective=@(x) VIStudioModelVisualsV7.detectorObjective(model,x,result.TargetBox,result.Target,o);
                map=VIStudioModelVisualsV7.occlude(image,result.BaselineScore,objective,o.GridSize,progress);
            end
            if isa(map,'dlarray'), map=extractdata(map); end
            result.Map=single(imresize(gather(map),sizeOriginal,'nearest'));
            assert(all(isfinite(result.Map),'all'),'VIStudioV7:VisualMap','Non-finite visualization.');
            result.Completed=true;
        end
        function map=occlude(image,baseline,objective,n,progress)
            h=size(image,1); w=size(image,2); n=min([n h w]);
            ys=round(linspace(1,h+1,n+1)); xs=round(linspace(1,w+1,n+1)); map=zeros(h,w,'single');
            fill=mean(single(image),[1 2]); total=n*n;
            for row=1:n
                for col=1:n
                    step=(row-1)*n+col;
                    assert(~progress(step,total),'VIStudioV7:Cancelled','Visualization cancelled.');
                    y=ys(row):ys(row+1)-1; x=xs(col):xs(col+1)-1; changed=image;
                    changed(y,x,:)=cast(repmat(fill,numel(y),numel(x),1),'like',image);
                    map(y,x)=single(baseline-objective(changed));
                end
            end
        end
        function scores=classScores(model,input,environment,count)
            scores=minibatchpredict(model,input,'ExecutionEnvironment',environment);
            if isa(scores,'dlarray'), scores=extractdata(scores); end
            scores=double(gather(scores(:))); assert(numel(scores)==count && all(isfinite(scores)),'VIStudioV7:VisualClasses','Class metadata does not match model output.');
            if any(scores<0) || abs(sum(scores)-1)>1e-3
                scores=exp(scores-max(scores)); scores=scores/sum(scores);
            end
        end
        function value=classObjective(model,input,environment,count,index)
            scores=VIStudioModelVisualsV7.classScores(model,input,environment,count); value=scores(index);
        end
        function value=detectorObjective(model,image,box,label,o)
            [boxes,scores,labels]=detect(model,image,'Threshold',0.001,'ExecutionEnvironment',o.Environment);
            value=VIStudioModelVisualsV7.matchScore(box,label,boxes,scores,string(labels));
        end
        function value=matchScore(box,label,boxes,scores,labels)
            value=0; if isempty(boxes), return; end
            overlap=bboxOverlapRatio(box,double(boxes)); overlap=overlap(:); scores=double(scores(:)); labels=string(labels(:));
            keep=labels==string(label) & overlap>=.1;
            if any(keep), value=max(scores(keep).*overlap(keep)); end
        end
        function overlay=overlay(image,map,alpha)
            if nargin<3, alpha=.5; end
            map=imresize(max(single(map),0),[size(image,1) size(image,2)]); peak=max(map,[],'all');
            if peak>0, map=map/peak; end
            colors=ind2rgb(uint8(map*255),turbo(256)); weight=alpha*double(map);
            overlay=im2uint8(im2double(image).*(1-weight)+colors.*weight);
        end
    end
end
