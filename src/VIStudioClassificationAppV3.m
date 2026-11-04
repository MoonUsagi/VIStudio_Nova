classdef VIStudioClassificationAppV3 < VIStudioVisionAppV3
    methods
        function app=VIStudioClassificationAppV3(varargin)
            app@VIStudioVisionAppV3('classification',varargin{:});
            if nargout==0, clear app; end
        end
    end
end
