classdef VIStudioData
    % Shared validation and data preparation for VIStudio's native apps.
    methods (Static)
        function image = readImage(file,targetSize)
            [image,map] = imread(file);
            if ~isempty(map), image = im2uint8(ind2rgb(image,map)); end
            if size(image,3)==1, image = repmat(image,1,1,3); end
            assert(size(image,3)==3,'VIStudio:InvalidImage','請使用灰階或 RGB 影像。');
            image = im2uint8(image);
            if nargin>1 && ~isempty(targetSize), image = imresize(image,targetSize(1:2)); end
        end
        function parts = splitIndices(count,percentages,seed)
            validateattributes(count,{'numeric'},{'scalar','integer','positive'});
            validateattributes(percentages,{'numeric'},{'vector','real','finite','nonnegative'});
            percentages = double(percentages(:)');
            assert(abs(sum(percentages)-100)<1e-6,'VIStudio:InvalidSplit','資料比例必須加總為 100%%。');
            active = percentages>0;
            assert(count>=nnz(active),'VIStudio:InsufficientData','影像數不足以分配給每個非零比例的資料集。');
            raw = count*percentages/100;
            sizes = max(double(active),floor(raw));
            while sum(sizes)>count
                excess=sizes-raw; excess(sizes<=double(active))=-Inf;
                [~,index]=max(excess); sizes(index)=sizes(index)-1;
            end
            while sum(sizes)<count
                deficit=raw-sizes; deficit(~active)=-Inf;
                [~,index]=max(deficit); sizes(index)=sizes(index)+1;
            end
            if nargin<3, seed=42; end
            stream = RandStream('mt19937ar','Seed',seed);
            indices = randperm(stream,count);
            parts = cell(1,numel(sizes)); offset=0;
            for k=1:numel(sizes)
                parts{k} = sort(indices(offset+(1:sizes(k))));
                offset = offset+sizes(k);
            end
        end
        function [train,val,test] = splitClassification(ds,percentages)
            assert(~isempty(ds) && ~isempty(ds.Files),'VIStudio:MissingData','請先匯入分類資料。');
            labels = categories(ds.Labels);
            assert(numel(labels)>=2,'VIStudio:MissingClasses','分類資料至少需要兩個類別子資料夾。');
            indices = {[],[],[]};
            for k=1:numel(labels)
                rows = find(ds.Labels==labels{k});
                parts = VIStudioData.splitIndices(numel(rows),percentages,42+k);
                for j=1:3, indices{j}=[indices{j};rows(parts{j}(:))]; end %#ok<AGROW>
            end
            train=subset(ds,sort(indices{1}));
            val=subset(ds,sort(indices{2}));
            test=subset(ds,sort(indices{3}));
        end
        function data = detectionTable(value,baseFolder)
            if nargin<2, baseFolder=pwd; end
            if isa(value,'groundTruth'), value=objectDetectorTrainingData(value); end
            assert(istable(value) && height(value)>0,'VIStudio:InvalidGroundTruth','標註資料必須是非空表格或 groundTruth 物件。');
            names = value.Properties.VariableNames;
            pathName = 'imageFilename';
            if ~ismember(pathName,names)
                if ismember('Files',names), pathName='Files'; else, pathName=names{1}; end
            end
            files = string(value.(pathName)); files = files(:);
            assert(numel(files)==height(value) && all(strlength(files)>0), ...
                'VIStudio:InvalidGroundTruth','標註資料的影像路徑格式不正確。');
            for k=1:numel(files)
                if ~isfile(files(k)) && isfile(fullfile(baseFolder,files(k)))
                    files(k)=fullfile(baseFolder,files(k));
                end
            end
            assert(all(isfile(files)),'VIStudio:MissingImages','部分標註影像不存在，請先修復影像路徑。');
            assert(numel(unique(lower(files)))==numel(files),'VIStudio:DuplicateImages','標註資料含重複影像路徑。');
            data=table(cellstr(files),'VariableNames',{'imageFilename'});
            for k=1:numel(names)
                name=names{k}; if strcmp(name,pathName), continue; end
                boxes=value.(name);
                if ~iscell(boxes), continue; end
                valid=cellfun(@(b) isnumeric(b) && (isempty(b) || (ismatrix(b) && size(b,2)==4)),boxes);
                if ~all(valid), continue; end
                for row=1:numel(boxes)
                    b=boxes{row};
                    if isempty(b), boxes{row}=zeros(0,4); continue; end
                    assert(all(isfinite(b),'all') && all(b(:,1:2)>=1,'all') && all(b(:,3:4)>0,'all'), ...
                        'VIStudio:InvalidBoxes','%s 第 %d 列包含無效的 [x y width height] 方框。',name,row);
                    boxes{row}=double(b);
                end
                data.(name)=boxes;
            end
            assert(width(data)>1,'VIStudio:MissingBoxes','資料中沒有有效的矩形標註欄位。');
        end
        function options = trainingOptionsFromUI(subapp,validationData)
            settings=struct('Solver','adam','MaxEpochs',10,'MiniBatchSize',8, ...
                'ValidationFrequency',10,'Verbose',false,'Plots','training-progress', ...
                'Shuffle','every-epoch','InitialLearnRate',1e-4,'LearnRateSchedule','none', ...
                'LearnRateDropPeriod',10,'LearnRateDropFactor',0.1);
            if ~isempty(subapp) && isvalid(subapp)
                fields=fieldnames(settings);
                controls={'SolverDropDown','MaxEpochsEditField','MiniBatchSizeEditField', ...
                    'ValidationFrequencyEditField','VerboseCheckBox','PlotsDropDown','ShuffleDropDown', ...
                    'InitialLearnRateEditField','LearnRateScheduleDropDown', ...
                    'LearnRateDropPeriodEditField','LearnRateDropFactorEditField'};
                for k=1:numel(fields), settings.(fields{k})=subapp.(controls{k}).Value; end
                if strcmp(subapp.ValidationDataDropDown.Value,'[]'), validationData=[]; end
            end
            validateattributes(settings.MaxEpochs,{'numeric'},{'scalar','integer','positive','finite'});
            validateattributes(settings.MiniBatchSize,{'numeric'},{'scalar','integer','positive','finite'});
            validateattributes(settings.ValidationFrequency,{'numeric'},{'scalar','integer','positive','finite'});
            validateattributes(settings.InitialLearnRate,{'numeric'},{'scalar','positive','finite'});
            validateattributes(settings.LearnRateDropPeriod,{'numeric'},{'scalar','integer','positive','finite'});
            validateattributes(settings.LearnRateDropFactor,{'numeric'},{'scalar','>',0,'<=',1,'finite'});
            solver=settings.Solver; settings=rmfield(settings,'Solver');
            args=namedargs2cell(settings);
            options=trainingOptions(solver,args{:},'ValidationData',validationData,'ExecutionEnvironment','auto');
        end
        function configureTrainingUI(app)
            controls={'MaxEpochsEditField','MiniBatchSizeEditField','ValidationFrequencyEditField','LearnRateDropPeriodEditField'};
            for k=1:numel(controls)
                h=app.(controls{k}); h.Value=max(1,round(h.Value));
                h.Limits=[1 100000]; h.RoundFractionalValues='on';
            end
            app.InitialLearnRateEditField.Value=max(1e-8,app.InitialLearnRateEditField.Value);
            app.InitialLearnRateEditField.Limits=[1e-8 1];
            app.LearnRateDropFactorEditField.Value=max(1e-6,app.LearnRateDropFactorEditField.Value);
            app.LearnRateDropFactorEditField.Limits=[1e-6 1];
        end
        function fig = appFigure(app)
            names={'UIFigure','VIStudio_ClassificationUIFigure','VIStudio_ObjectDetectionUIFigure','VIStudio_AnomalyDetectionUIFigure'};
            for k=1:numel(names)
                if isprop(app,names{k}), fig=app.(names{k}); return; end
            end
            error('VIStudio:MissingFigure','找不到主視窗。');
        end
    end
end
