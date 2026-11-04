function [layerName,learnableNames] = networkHead(net)
%NETWORKHEAD Network head learnables
%   layerName = networkHead(net) returns the name of the last
%   convolution or fully connected layer in the network NET.
%   [layerName,learnableNames] = networkHead(net) also returns
%   the paths of the learnable parameters.

arguments
    net dlnetwork
end
outputName = string(net.OutputNames);
assert(isscalar(outputName),'VIStudio:MultipleOutputs', ...
    '分類模型必須只有一個輸出，請先選擇分類輸出。');

supportedLayers = [
    "FullyConnectedLayer" 
    "Convolution2DLayer"];

layerName = outputName;
while ~isempty(layerName)
    layer = getLayer(net,layerName);

    if contains(class(layer),supportedLayers)
        break
    end

    layerName = findSource(net,layerName);

    if ~isscalar(layerName)
        error('VIStudio:BranchedHead','Heads with branches are not supported.');
    end
end

if isempty(layerName)
    error('VIStudio:MissingHead','Network head not found.');
end

layerName = string(layer.Name);

learnables = net.Learnables(net.Learnables.Layer==layerName,:);
learnableNames = string(learnables.Layer)+"/"+string(learnables.Parameter);

end

function sourceNames = findSource(net,name)
%FINDSOURCE Find upstream layer
%   sourceNames = findSource(NET,name) returns the names of the layers
%   connected to the specified layer in NET.

connections = net.Connections;
destinations = regexprep(string(connections.Destination),'/.*$','');
idx = destinations == string(name);
sourceNames = unique(regexprep(string(connections.Source(idx)),'/.*$',''),'stable');

end
