classdef VIStudioAnomalyAppV3 < VIStudioVisionAppV3
    methods
        function app=VIStudioAnomalyAppV3(varargin)
            app@VIStudioVisionAppV3('anomaly',varargin{:});
            if nargout==0, clear app; end
        end
    end
end
