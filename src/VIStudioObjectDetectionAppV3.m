classdef VIStudioObjectDetectionAppV3 < VIStudioVisionAppV3
    methods
        function app=VIStudioObjectDetectionAppV3(varargin)
            app@VIStudioVisionAppV3('detection',varargin{:});
            if nargout==0, clear app; end
        end
    end
end
