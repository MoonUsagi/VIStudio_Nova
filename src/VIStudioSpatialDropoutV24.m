classdef VIStudioSpatialDropoutV24 < nnet.layer.Layer & nnet.layer.Formattable
    % Drop complete feature channels independently per batch observation.
    properties
        Probability=.2
    end
    methods
        function layer=VIStudioSpatialDropoutV24(name)
            layer.Name=char(name); layer.Description='Channel-wise spatial dropout, p=0.2';
        end
        function y=predict(~,x), y=x; end
        function y=forward(layer,x)
            mask=rand(1,1,size(x,3),size(x,4),'like',extractdata(x))>=layer.Probability;
            y=x.*mask/(1-layer.Probability);
        end
    end
end
