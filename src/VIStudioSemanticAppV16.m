classdef VIStudioSemanticAppV16 < handle
    properties (SetAccess=private)
        UIFigure
        Tools
    end
    properties (Dependent,SetAccess=private)
        Semantic
    end
    methods
        function app=VIStudioSemanticAppV16(visible)
            if nargin<1, visible='on'; end
            app.UIFigure=uifigure('Visible','off','Name','VIStudio V16 | 語意分割 Semantic Segmentation','Position',[60 60 1440 900],'CloseRequestFcn',@(~,~) delete(app));
            grid=uigridlayout(app.UIFigure,[1 1]); tabs=uitabgroup(grid); page=uitab(tabs,'Title','語意分割與產品檢測 / Semantic & Product Inspection');
            callbacks=struct('Source',@() app.Tools.SourceFile,'Busy',@(value) app.busy(value),'Activate',@(file) app.activateAnomaly(file),'DefectRules',@() VIStudioDefectsV11.defaults(),'Retrain',@(task,path) app.receive(task,path));
            app.Tools=VIStudioWorkbenchV16(page,'classification',callbacks); app.Tools.selectSemantic(); VIStudioThemeV16.install(app.UIFigure,'語意分割 / Semantic'); app.UIFigure.Visible=validatestring(visible,{'on','off'});
        end
        function pane=get.Semantic(app), pane=app.Tools.Semantic; end
        function delete(app)
            if ~isempty(app.Tools) && isvalid(app.Tools), delete(app.Tools); end
            if ~isempty(app.UIFigure) && isvalid(app.UIFigure), delete(app.UIFigure); end
        end
    end
    methods (Access=private)
        function activateAnomaly(~,file), other=VIStudioVisionAppV16('anomaly'); other.loadModel(file); end
        function busy(app,value), app.Tools.busy(value); end
        function receive(app,task,path)
            if string(task)=="semantic", app.Semantic.loadDataset(path); app.Tools.selectSemantic();
            else, other=VIStudioVisionAppV16(task); if string(task)=="detection", other.loadTrainingAnnotations(path); else, other.loadTrainingFolder(path); end, end
        end
    end
end
