classdef VIStudioModelViewerV7 < handle
    properties (SetAccess=private)
        Result=[]
        Handles=struct()
        Components=struct('Name',{},'Network',{})
    end
    properties (Access=private)
        Model=[]
        Metadata=struct()
        Task
        Cancelled=false
        Plot=[]
        Graph=[]
    end
    methods
        function viewer=VIStudioModelViewerV7(tab,task,callbacks)
            viewer.Task=string(task);
            root=uigridlayout(tab,[3 1],'RowHeight',{36,34,'1x'});
            bar=uigridlayout(root,[1 5],'Padding',[0 0 0 0],'ColumnWidth',{'1x',105,85,150,150});
            viewer.Handles.Info=uilabel(bar,'Text','請先訓練或載入模型 / Train or load a model','WordWrap','on');
            uilabel(bar,'Text','解釋門檻 / Viz cutoff','WordWrap','on');
            viewer.Handles.Threshold=uieditfield(bar,'numeric','Value',.25,'Limits',[0 1],'Enable',viewer.enabled(task=="detection"));
            viewer.Handles.Component=uidropdown(bar,'Items',{'Network'},'ValueChangedFcn',@(~,~) viewer.drawGraph());
            uibutton(bar,'Text','網路分析器 / Analyzer','ButtonPushedFcn',@(~,~) viewer.action(@() viewer.analyze()));
            note=uilabel(root,'Text','完整影像解釋，與檢測 ROI 獨立。熱圖僅代表模型反應。 / Full-image explanations, independent of inspection ROI. Heatmaps show model responses.','WordWrap','on');
            tabs=uitabgroup(root); structure=uitab(tabs,'Title','結構與參數 / Structure & Parameters');
            grid=uigridlayout(structure,[1 2],'ColumnWidth',{'1x',390}); viewer.Handles.Graph=uiaxes(grid);
            viewer.Handles.Layers=uitable(grid,'CellSelectionCallback',@(~,e) viewer.selectLayer(e));
            explanation=uitab(tabs,'Title','影像解釋 / Image Explanation'); grid=uigridlayout(explanation,[4 2],'RowHeight',{68,'1x',38,95});
            viewer.Handles.SubTabs=tabs; viewer.Handles.ExplainTab=explanation;
            controls=uigridlayout(grid,[2 6],'Padding',[0 0 0 0],'ColumnWidth',{115,'1x',105,'1x',90,'1x'}); controls.Layout.Column=[1 2];
            uilabel(controls,'Text','方法 / Method'); methods={'gradcam','occlusion','features'};
            if task=="detection", methods={'occlusion'}; end
            viewer.Handles.Method=uidropdown(controls,'Items',methods);
            uilabel(controls,'Text','目標類別 / Class'); viewer.Handles.Target=uidropdown(controls,'Items',{'auto'});
            uilabel(controls,'Text','物件 / Object'); viewer.Handles.Object=uieditfield(controls,'numeric','Value',1,'Limits',[1 Inf],'RoundFractionalValues','on');
            uilabel(controls,'Text','遮蔽網格 / Grid'); viewer.Handles.Grid=uieditfield(controls,'numeric','Value',4,'Limits',[2 12],'RoundFractionalValues','on');
            uilabel(controls,'Text','特徵層 / Layer'); viewer.Handles.Feature=uidropdown(controls,'Items',{'auto'});
            viewer.Handles.Run=uibutton(controls,'Text','解釋 / Explain','ButtonPushedFcn',@(~,~) callbacks.Explain());
            viewer.Handles.Cancel=uibutton(controls,'Text','取消 / Cancel','Enable','off','ButtonPushedFcn',@(~,~) viewer.cancel());
            viewer.Handles.Original=uiaxes(grid); viewer.Handles.Original.Layout.Row=2; viewer.Handles.Original.Layout.Column=1;
            viewer.Handles.Map=uiaxes(grid); viewer.Handles.Map.Layout.Row=2; viewer.Handles.Map.Layout.Column=2;
            viewer.Handles.Status=uilabel(grid,'Text','Grad-CAM：類別梯度；Features：非類別特定的特徵強度；Occlusion：遮蔽後分數下降。 / Grad-CAM: class gradients; Features: activation magnitude; Occlusion: score drop.','WordWrap','on');
            viewer.Handles.Status.Layout.Row=3; viewer.Handles.Status.Layout.Column=[1 2];
            viewer.Handles.Scores=uitable(grid); viewer.Handles.Scores.Layout.Row=4; viewer.Handles.Scores.Layout.Column=1;
            buttons=uigridlayout(grid,[3 1],'RowHeight',{34,34,'1x'}); buttons.Layout.Row=4; buttons.Layout.Column=2;
            uibutton(buttons,'Text','匯出熱圖與結果 / Export heatmap & result','ButtonPushedFcn',@(~,~) viewer.action(@() viewer.pickExport()));
            text='熱圖各自正規化；匯出包含原始數值。 / Display maps are normalized separately; export retains raw values.';
            if task=="detection", text='序號依分數排序；以類別與 IoU 追蹤同一物件。 / IDs follow score order; class and IoU track the target.'; end
            uilabel(buttons,'Text',text,'WordWrap','on');
            viewer.Handles.Target.Enable=viewer.enabled(task=="classification");
            viewer.Handles.Feature.Enable=viewer.enabled(task=="classification"); viewer.Handles.Object.Enable=viewer.enabled(task=="detection");
        end
        function setModel(viewer,model,metadata)
            viewer.Model=model; viewer.Metadata=metadata; viewer.Result=[];
            viewer.Components=VIStudioModelVisualsV7.components(model); names=string({viewer.Components.Name});
            if isempty(names), names="(unavailable)"; end
            viewer.Handles.Component.Items=cellstr(names); viewer.Handles.Component.Value=char(names(1));
            parameters=0; layers=0;
            for k=1:numel(viewer.Components)
                [~,layerTable]=VIStudioModelVisualsV7.networkGraph(viewer.Components(k).Network);
                parameters=parameters+sum(layerTable.Parameters); layers=layers+height(layerTable);
            end
            if isempty(viewer.Components)
                viewer.Handles.Info.Text=string(class(model))+" · 結構無法讀取 / Structure unavailable";
            else
                viewer.Handles.Info.Text=sprintf('%s · %d layers · %s parameters',class(model),layers,string(parameters));
            end
            if viewer.Task=="classification"
                viewer.Handles.Target.Items=cellstr(["auto";string(metadata.ClassNames(:))]); viewer.Handles.Target.Value='auto';
                allLayers=model.Layers; spatial=arrayfun(@(l) isa(l,'nnet.cnn.layer.Convolution2DLayer'),allLayers);
                viewer.Handles.Feature.Items=cellstr(["auto";string({allLayers(spatial).Name})']); viewer.Handles.Feature.Value='auto';
            end
            viewer.Handles.Scores.Data=table(); cla(viewer.Handles.Original); cla(viewer.Handles.Map); viewer.drawGraph();
        end
        function result=explain(viewer,file,options)
            assert(~isempty(viewer.Model),'VIStudioV7:MissingModel','Load a model first.');
            if nargin<3
                options=struct('Method',string(viewer.Handles.Method.Value),'Target',string(viewer.Handles.Target.Value), ...
                    'DetectionIndex',viewer.Handles.Object.Value,'GridSize',viewer.Handles.Grid.Value, ...
                    'FeatureLayer',string(viewer.Handles.Feature.Value),'Threshold',viewer.Handles.Threshold.Value);
            end
            viewer.Cancelled=false; viewer.Handles.Run.Enable='off'; viewer.Handles.Cancel.Enable='on';
            cleanup=onCleanup(@() viewer.finish());
            % Only replace the previous result once every perturbation succeeds.
            result=VIStudioModelVisualsV7.explain(viewer.Model,viewer.Task,viewer.Metadata,file,options,@(a,b) viewer.progress(a,b));
            viewer.Result=result; image=VIStudioData.readImage(file,[]); shown=image;
            viewer.Handles.Method.Value=char(result.Method); viewer.Handles.Grid.Value=result.Options.GridSize;
            viewer.Handles.Object.Value=result.Options.DetectionIndex; viewer.Handles.Threshold.Value=result.Options.Threshold;
            if ismember(string(result.Options.Target),string(viewer.Handles.Target.Items)), viewer.Handles.Target.Value=char(result.Options.Target); end
            if ismember(string(result.Options.FeatureLayer),string(viewer.Handles.Feature.Items)), viewer.Handles.Feature.Value=char(result.Options.FeatureLayer); end
            if viewer.Task=="detection"
                labels=string((1:numel(result.Scores))')+": "+result.Labels+" "+compose('%.3f',result.Scores);
                shown=insertObjectAnnotation(image,'rectangle',result.Boxes,cellstr(labels));
                viewer.Handles.Scores.Data=table((1:numel(result.Scores))',result.Labels,result.Scores,result.Boxes, ...
                    'VariableNames',{'Object','Class','Score','Box'});
            else
                viewer.Handles.Scores.Data=sortrows(table(result.Labels,result.Scores,'VariableNames',{'Class','Score'}),'Score','descend');
            end
            imshow(shown,'Parent',viewer.Handles.Original); title(viewer.Handles.Original,'模型結果 / Prediction');
            overlay=VIStudioModelVisualsV7.overlay(image,result.Map); imshow(overlay,'Parent',viewer.Handles.Map);
            title(viewer.Handles.Map,result.Method+" · "+result.Target,'Interpreter','none');
            viewer.Handles.Status.Text=sprintf('%s | score %.5g | raw map [%.5g, %.5g] · 紅色顯示正向強度 / Positive intensity overlay', ...
                result.Target,result.BaselineScore,min(result.Map,[],'all'),max(result.Map,[],'all'));
            viewer.Handles.Original.Toolbar.Visible='off'; viewer.Handles.Map.Toolbar.Visible='off';
            viewer.Handles.SubTabs.SelectedTab=viewer.Handles.ExplainTab;
        end
        function export(viewer,file)
            assert(~isempty(viewer.Result),'VIStudioV7:MissingVisualization','Compute a visualization first.');
            [folder,name,ext]=fileparts(file); if isempty(folder), folder=pwd; end
            assert(strcmpi(ext,'.mat'),'VIStudioV7:VisualExport','Use a .mat filename.');
            png=fullfile(folder,[char(name) '_heatmap.png']);
            assert(~isfile(file) && ~isfile(png),'VIStudioV7:FileExists','Choose a new export filename.');
            result=viewer.Result;
            assert(isfile(result.File) && VIStudioToolsV3.fileHash(result.File)==result.SourceHash,'VIStudioV7:ImageChanged','Source image changed; recompute the explanation.');
            image=VIStudioData.readImage(result.File,[]); overlay=VIStudioModelVisualsV7.overlay(image,result.Map);
            save(file,'result','-v7.3'); imwrite(overlay,png);
        end
    end
    methods (Access=private)
        function drawGraph(viewer)
            ax=viewer.Handles.Graph; cla(ax); viewer.Plot=[]; viewer.Graph=[]; viewer.Handles.Layers.Data=table();
            if isempty(viewer.Components)
                title(ax,'此模型未提供可讀取的網路元件 / Network components are unavailable'); return;
            end
            index=find(string({viewer.Components.Name})==string(viewer.Handles.Component.Value),1);
            [graph,layers]=VIStudioModelVisualsV7.networkGraph(viewer.Components(index).Network); viewer.Graph=graph;
            labels=graph.Nodes.Name; if numnodes(graph)>40, labels={}; end
            viewer.Plot=plot(ax,graph,'Layout','layered','NodeLabel',labels,'MarkerSize',3);
            title(ax,viewer.Components(index).Name+" · "+numnodes(graph)+" layers",'Interpreter','none');
            viewer.Handles.Layers.Data=layers; ax.Toolbar.Visible='on';
        end
        function selectLayer(viewer,event)
            if isempty(event.Indices) || isempty(viewer.Plot), return; end
            table=viewer.Handles.Layers.Data; name=table.Name(event.Indices(1,1));
            index=findnode(viewer.Graph,char(name)); highlight(viewer.Plot,1:numnodes(viewer.Graph),'NodeColor',[0 .45 .74]);
            highlight(viewer.Plot,index,'NodeColor',[.9 .2 .1],'MarkerSize',8); title(viewer.Handles.Graph,name,'Interpreter','none');
        end
        function analyze(viewer)
            assert(~isempty(viewer.Components),'VIStudioV7:NetworkUnavailable','This detector does not expose a readable component network.');
            index=find(string({viewer.Components.Name})==string(viewer.Handles.Component.Value),1); analyzeNetwork(viewer.Components(index).Network);
        end
        function stop=progress(viewer,current,total)
            viewer.Handles.Status.Text=sprintf('計算遮蔽 / Occlusion: %d / %d',current,total); drawnow; stop=viewer.Cancelled;
        end
        function cancel(viewer), viewer.Cancelled=true; end
        function finish(viewer), viewer.Handles.Run.Enable='on'; viewer.Handles.Cancel.Enable='off'; end
        function pickExport(viewer)
            [file,path]=uiputfile('*.mat','Export visualization','V7_explanation.mat'); if isequal(file,0), return; end
            viewer.export(fullfile(path,file));
        end
        function action(viewer,callback)
            try, callback(); catch err, uialert(ancestor(viewer.Handles.Graph,'figure'),err.message,'模型視覺化 / Model visualization'); end
        end
        function value=enabled(~,yes), value='off'; if yes, value='on'; end, end
    end
end
