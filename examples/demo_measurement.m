function app=demo_measurement
root=fileparts(fileparts(mfilename('fullpath'))); addpath(fullfile(root,'src')); app=VIStudioMeasurementAppV17; app.demo();
end
