classdef VIStudioModelIOV8
    methods (Static)
        function artifact=read(file,task,variable)
            if nargin<3, variable=""; end
            assert(isfile(file),'VIStudioV8:ExternalMissing','MAT file is missing.');
            loaded=load(file); names=string(fieldnames(loaded)); supported=strings(0,1);
            for k=1:numel(names)
                if VIStudioModelIOV8.matches(loaded.(names(k)),task), supported(end+1)=names(k); end %#ok<AGROW>
            end
            variable=string(variable);
            if strlength(variable)==0
                if ismember("model",supported), variable="model";
                else
                    candidates="(none)"; if ~isempty(supported), candidates=join(supported,', '); end
                    assert(isscalar(supported),'VIStudioV8:ExternalVariable', ...
                        '請指定唯一模型變數。 / Choose a model variable. Candidates: %s',candidates);
                    variable=supported;
                end
            end
            assert(isscalar(variable) && ismember(variable,supported),'VIStudioV8:ExternalType','Model type does not match the task.');
            model=loaded.(variable); metadata=struct();
            if isfield(loaded,'metadata'), metadata=loaded.metadata; end
            assert(isstruct(metadata) && isscalar(metadata),'VIStudioV8:ExternalMetadata','metadata must be a scalar struct.');
            if task=="classification" && ~isa(model,'dlnetwork')
                layers=model.Layers;
                indices=arrayfun(@(l) isa(l,'nnet.cnn.layer.ClassificationOutputLayer'),layers);
                if any(indices) && ~isfield(metadata,'ClassNames'), metadata.ClassNames=string(layers(find(indices,1,'last')).Classes); end
                graph=layerGraph(model); graph=removeLayers(graph,{layers(indices).Name}); model=dlnetwork(graph);
            end
            if task=="classification"
                input=getLayer(model,model.InputNames{1}).InputSize;
                if ~isfield(metadata,'ClassNames') && isfield(loaded,'classNames'), metadata.ClassNames=loaded.classNames; end
                if isfield(metadata,'ClassNames'), classes=string(metadata.ClassNames(:)); else, classes=strings(0,1); end
                assert(isscalar(model.InputNames) && isscalar(model.OutputNames) && numel(input)==3 && input(3)==3, ...
                    'VIStudioV8:ExternalInput','Training requires one RGB input and one output.');
            elseif task=="detection"
                input=model.InputSize; classes=string(model.ClassNames(:));
            else
                classes=["Normal";"Anomaly"]; input=[224 224 3];
                if (isa(model,'VIStudioTeacherStudentV8') || isa(model,'VIStudioTeacherStudentV6')), input=[model.ImageSize 3];
                elseif isprop(model,'ImageSize') && ~isempty(model.ImageSize), input=[model.ImageSize(1:2) 3]; end
                if isfield(metadata,'ImageSize'), input=[metadata.ImageSize(1:2) 3]; end
            end
            artifact=struct('Model',model,'Metadata',metadata,'Classes',classes,'InputSize',input, ...
                'File',VIStudioToolsV3.canonicalPath(file),'Digest',VIStudioToolsV3.fileHash(file),'Variable',variable);
        end
        function flag=matches(model,task)
            switch string(task)
                case "classification", flag=isa(model,'dlnetwork') || isa(model,'SeriesNetwork') || isa(model,'DAGNetwork');
                case "detection"
                    flag=ismember(string(class(model)),["yoloxObjectDetector","yolov4ObjectDetector","yolov3ObjectDetector", ...
                        "yolov2ObjectDetector","ssdObjectDetector","fasterRCNNObjectDetector"]);
                case "anomaly"
                    flag=ismember(string(class(model)),["patchCoreAnomalyDetector","fcddAnomalyDetector", ...
                        "efficientADAnomalyDetector","VIStudioTeacherStudentV8","VIStudioTeacherStudentV6"]);
                otherwise, flag=false;
            end
        end
        function name=detectorTrainer(model)
            types=["yoloxObjectDetector","yolov4ObjectDetector","yolov3ObjectDetector", ...
                "yolov2ObjectDetector","ssdObjectDetector","fasterRCNNObjectDetector"];
            trainers=["trainYOLOXObjectDetector","trainYOLOv4ObjectDetector","trainYOLOv3ObjectDetector", ...
                "trainYOLOv2ObjectDetector","trainSSDObjectDetector","trainFasterRCNNObjectDetector"];
            index=find(types==string(class(model)),1);
            assert(~isempty(index),'VIStudioV8:ExternalType','Unsupported detector.'); name=trainers(index);
        end
    end
end
