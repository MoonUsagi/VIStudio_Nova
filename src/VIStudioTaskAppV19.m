classdef VIStudioTaskAppV19 < handle
    properties (SetAccess=private)
        UIFigure
        Pane
    end
    methods
        function app=VIStudioTaskAppV19(task,visible)
            if nargin<1, task='instance'; end; if nargin<2, visible='on'; end
            app.UIFigure=uifigure('Visible','off','Name','VIStudio V19 | 實例・關鍵點・AI・品質','Position',[70 60 1420 900],'CloseRequestFcn',@(~,~) delete(app)); grid=uigridlayout(app.UIFigure,[1 1]); app.Pane=VIStudioTaskPaneV19(grid,task); VIStudioThemeV19.install(app.UIFigure,string(task)); app.UIFigure.Visible=validatestring(visible,{'on','off'});
        end
        function delete(app), if ~isempty(app.Pane) && isvalid(app.Pane), delete(app.Pane); end; if ~isempty(app.UIFigure) && isvalid(app.UIFigure), delete(app.UIFigure); end, end
    end
end
