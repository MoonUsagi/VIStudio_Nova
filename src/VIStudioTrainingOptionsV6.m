classdef VIStudioTrainingOptionsV6
    methods (Static)
        function o=defaults()
            o=struct('Solver',"adam",'L2',0.0001,'Momentum',0.9,'GradientThreshold',5, ...
                'Schedule',"none",'DropFactor',0.1,'DropPeriod',10,'Shuffle',"every-epoch", ...
                'ValidationFrequency',30,'Patience',0,'Seed',42,'FreezeBackbone',false, ...
                'CompressionRatio',0.1,'ReplaceHead',false,'AugmentCopies',0, ...
                'FlipLR',true,'FlipUD',false,'Rotation',10,'Translate',0.05, ...
                'ScaleMin',0.9,'ScaleMax',1.1,'Brightness',0.1,'Contrast',0.1,'Noise',0.01, ...
                'SynthMode',"none",'SynthCopies',0,'DefectFraction',0.12);
        end
        function o=merge(base,changes)
            assert(isstruct(changes) && isscalar(changes),'VIStudioV6:Options','Options must be a scalar struct.');
            fields=fieldnames(changes); assert(all(isfield(base,fields)),'VIStudioV6:Options','Unknown advanced option.');
            o=base; for k=1:numel(fields), o.(fields{k})=changes.(fields{k}); end
            for field={'Solver','Schedule','Shuffle','SynthMode'}, o.(field{1})=string(o.(field{1})); end
            o.Solver=string(validatestring(o.Solver,{'adam','sgdm','rmsprop'}));
            o.Schedule=string(validatestring(o.Schedule,{'none','piecewise'}));
            o.Shuffle=string(validatestring(o.Shuffle,{'every-epoch','once','never'}));
            o.SynthMode=string(validatestring(o.SynthMode,{'none','cutpaste','scratch','noise','copy-paste'}));
            ranges={'L2',0,1;'Momentum',0,0.999;'GradientThreshold',1e-6,1e6; ...
                'DropFactor',0.001,1;'DropPeriod',1,10000;'ValidationFrequency',1,100000; ...
                'Patience',0,10000;'Seed',0,1e9;'CompressionRatio',0.001,1; ...
                'AugmentCopies',0,20;'SynthCopies',0,20;'Rotation',0,90;'Translate',0,0.4; ...
                'ScaleMin',0.5,1;'ScaleMax',1,2;'Brightness',0,0.5;'Contrast',0,0.5; ...
                'Noise',0,0.2;'DefectFraction',0.01,0.4};
            for k=1:size(ranges,1)
                validateattributes(o.(ranges{k,1}),{'numeric'},{'scalar','real','finite','>=',ranges{k,2},'<=',ranges{k,3}});
            end
            for field={'DropPeriod','ValidationFrequency','Patience','Seed','AugmentCopies','SynthCopies'}
                validateattributes(o.(field{1}),{'numeric'},{'integer'});
            end
            for field={'FreezeBackbone','ReplaceHead','FlipLR','FlipUD'}
                validateattributes(o.(field{1}),{'logical'},{'scalar'});
            end
        end
        function opts=native(base,o,validationData)
            args={'MaxEpochs',base.Epochs,'MiniBatchSize',base.Batch,'InitialLearnRate',base.LearnRate, ...
                'ExecutionEnvironment',base.Environment,'Verbose',false,'Plots','none', ...
                'Shuffle',char(o.Shuffle),'L2Regularization',o.L2,'GradientThreshold',o.GradientThreshold, ...
                'LearnRateSchedule',char(o.Schedule),'LearnRateDropFactor',o.DropFactor,'LearnRateDropPeriod',o.DropPeriod};
            if o.Solver=="sgdm", args=[args {'Momentum',o.Momentum}]; end
            if ~isempty(validationData)
                patience=o.Patience; if patience==0, patience=Inf; end
                args=[args {'ValidationData',validationData,'ValidationFrequency',o.ValidationFrequency,'ValidationPatience',patience}];
            end
            opts=trainingOptions(char(o.Solver),args{:});
        end
    end
end
