function net = freezeNetwork(net,args)
% netFrozen = freezeNetwork(net) sets the learning rate factors of all the
% learnable parameters of the specified network to zero.
%
% Use LayerNamesToIgnore for layer names and LayerTypesToIgnore for layer
% classes (full class names or short names such as FullyConnectedLayer).

arguments
    net dlnetwork
    args.LayerNamesToIgnore string = string.empty;
    args.LayerTypesToIgnore string = string.empty;
end

layerNamesToIgnore = args.LayerNamesToIgnore;
layerTypesToIgnore = args.LayerTypesToIgnore;

% Find names of layers to freeze.
layerNames = string({net.Layers.Name})';
layerClassNames = string(arrayfun(@class,net.Layers,UniformOutput=false));
shortClassNames = regexprep(layerClassNames,'^.*\.','');
assert(all(ismember(layerNamesToIgnore,layerNames)), ...
    'VIStudio:UnknownLayer','LayerNamesToIgnore 包含不存在的層名稱。');

idxLayersToFreeze = ...
    ~ismember(layerClassNames,layerTypesToIgnore) ...
    & ~ismember(shortClassNames,layerTypesToIgnore) ...
    & ~ismember(layerNames,layerNamesToIgnore);

layersToFreeze = {net.Layers(idxLayersToFreeze).Name}';

% Create table of layer and parameter name pairs.
idxParametersToFreeze = ismember(net.Learnables.Layer,layersToFreeze);
tbl = net.Learnables(idxParametersToFreeze,1:2);

% Loop over parameters to freeze.
for i = 1:size(tbl,1)
    layerName = tbl.Layer(i);
    parameterName = tbl.Parameter(i);
    net = setLearnRateFactor(net,layerName,parameterName,0);
end

end
