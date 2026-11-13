classdef VIStudioShapeMatchingAppV18 < handle
    properties (SetAccess=private)
        UIFigure
        Data
        Handles=struct()
        Reference=[]
    end
    properties (Access=private)
        Busy=false
    end
    methods
        function app=VIStudioShapeMatchingAppV18(visible)
            if nargin<1, visible='on'; end
            app.Data=VIStudioShapeMatchingV18; app.build(); app.UIFigure.Visible=validatestring(char(visible),{'on','off'}); app.refresh();
        end
        function delete(app), if ~isempty(app.UIFigure) && isvalid(app.UIFigure), delete(app.UIFigure); end, end
        function loadTemplate(app,input,roi)
            if nargin<3, roi=[]; end; reference=VIStudioShapeMatchingV18.readImage(input); app.Data.setTemplate(reference,roi); app.Reference=reference; app.refresh();
        end
        function loadSearch(app,input), app.Data.setSearch(input); app.refresh(); end
        function demo(app)
            [t,s]=VIStudioShapeMatchingV18.demo(); app.loadTemplate(t); app.loadSearch(s);
        end
        function results=run(app)
            app.Data.configure(app.options()); app.refresh();
            try, results=app.Data.run(); app.refresh(); catch err, app.refresh(); rethrow(err); end
        end
        function refresh(app)
            if ~isempty(app.Data.Template), imshow(app.Data.Template,'Parent',app.Handles.TemplateAxes); end
            if ~isempty(app.Data.SearchImage)
                ax=app.Handles.SearchAxes; imshow(app.Data.SearchImage,'Parent',ax); hold(ax,'on');
                [h,w,~]=size(app.Data.Template);
                if ~isempty(app.Data.Matches)
                    corners=[1 1;w 1;w h;1 h;1 1];
                    for k=1:numel(app.Data.Matches)
                        points=app.Data.templatePointsToSearch(corners,k); plot(ax,points(:,1),points(:,2),'Color',[.15 .9 .7],'LineWidth',2);
                        text(ax,points(1,1),points(1,2),sprintf('#%d %.3f',k,app.Data.Results.Score(k)),'Color','yellow','FontSize',12,'VerticalAlignment','bottom');
                    end
                end
                hold(ax,'off');
            end
            app.Handles.Results.Data=app.Data.Results;
            app.Handles.Status.Text="狀態 / State: "+app.Data.State+" | "+string(height(app.Data.Results))+" matches · px / deg · Score is not a probability";
        end
    end
    methods (Access=private)
        function build(app)
            p=VIStudioThemeV18.palette(); app.UIFigure=uifigure('Name','VIStudio V18 | 樣板／形狀匹配 Shape Matching','Position',[60 50 1460 920],'Visible','off','CloseRequestFcn',@(~,~) delete(app));
            root=uigridlayout(app.UIFigure,[4 1],'RowHeight',{44,105,'1x',42},'Padding',[10 8 10 8]);
            bar=uigridlayout(root,[1 7],'Padding',[0 0 0 0]);
            texts={'樣板影像 / Template','擷取樣板 / Crop ROI','搜尋影像 / Search','示例 / Demo','開啟設定 / Open','儲存設定 / Save','匯出 / Export'};
            callbacks={@() app.pickTemplate(),@() app.crop(),@() app.pickSearch(),@() app.demo(),@() app.open(),@() app.save(),@() app.export()};
            for k=1:numel(texts), cb=callbacks{k}; uibutton(bar,'Text',texts{k},'ButtonPushedFcn',@(~,~) app.action(cb)); end
            box=uigridlayout(root,[2 8],'RowHeight',{27,38},'ColumnWidth',{'1x','1x','1x','1x','1x','1x','1x',160},'Padding',[0 0 0 0]);
            names={'旋轉下限 / Min °','旋轉上限 / Max °','尺度下限 / Min scale','尺度上限 / Max scale','分數門檻 / Score','最大數量 / Max','邊緣極性 / Polarity','執行 / Run'};
            for k=1:8, label=uilabel(box,'Text',names{k},'WordWrap','on'); label.Layout.Row=1; label.Layout.Column=k; end
            fields={'MinRotation','MaxRotation','MinScale','MaxScale','Score','MaxMatches'}; values=[-180 180 1 1 .75 10];
            for k=1:6
                control=uieditfield(box,'numeric','Value',values(k),'ValueChangedFcn',@(~,~) app.action(@() app.changed())); control.Layout.Row=2; control.Layout.Column=k; app.Handles.(fields{k})=control;
            end
            app.Handles.Polarity=uidropdown(box,'Items',{'sensitive','globally-insensitive'},'ValueChangedFcn',@(~,~) app.action(@() app.changed())); app.Handles.Polarity.Layout.Row=2; app.Handles.Polarity.Layout.Column=7;
            run=uibutton(box,'Text','搜尋 / Match','ButtonPushedFcn',@(~,~) app.action(@() app.run())); run.Layout.Row=2; run.Layout.Column=8;
            content=uigridlayout(root,[2 2],'RowHeight',{'1x',185},'ColumnWidth',{'1x','2x'}); app.Handles.TemplateAxes=uiaxes(content); title(app.Handles.TemplateAxes,'樣板 / Template'); app.Handles.SearchAxes=uiaxes(content); title(app.Handles.SearchAxes,'搜尋結果 / Search results');
            app.Handles.Results=uitable(content,'RowName',{}); app.Handles.Results.Layout.Row=2; app.Handles.Results.Layout.Column=[1 2];
            app.Handles.Status=uilabel(root,'WordWrap','on'); h=VIStudioThemeV18.install(app.UIFigure,'樣板／形狀匹配 / Shape Matching');
            h.Guide.Text='R2026b Visual Inspection Toolbox · 單樣板定位，不需訓練；結果為像素座標，尚未自動套用量測配方 / One-template localization; pixel results; measurement recipes are not automatically aligned.';
        end
        function o=options(app)
            o=app.Data.Options; o.RotationRange=[app.Handles.MinRotation.Value app.Handles.MaxRotation.Value]; o.ScaleRange=[app.Handles.MinScale.Value app.Handles.MaxScale.Value]; o.ScoreThreshold=app.Handles.Score.Value; o.MaxMatches=app.Handles.MaxMatches.Value; o.EdgePolarity=string(app.Handles.Polarity.Value);
        end
        function syncControls(app)
            o=app.Data.Options; values=[o.RotationRange o.ScaleRange o.ScoreThreshold o.MaxMatches]; fields={'MinRotation','MaxRotation','MinScale','MaxScale','Score','MaxMatches'};
            for k=1:6, app.Handles.(fields{k}).Value=values(k); end; app.Handles.Polarity.Value=char(o.EdgePolarity);
        end
        function changed(app)
            try, app.Data.configure(app.options()); catch err, app.syncControls(); rethrow(err); end; app.refresh();
        end
        function pickTemplate(app)
            [f,p]=uigetfile({'*.png;*.jpg;*.jpeg;*.tif;*.bmp','Images'}); if ~isequal(f,0), app.loadTemplate(fullfile(p,f)); end
        end
        function pickSearch(app)
            [f,p]=uigetfile({'*.png;*.jpg;*.jpeg;*.tif;*.bmp','Images'}); if ~isequal(f,0), app.loadSearch(fullfile(p,f)); end
        end
        function crop(app)
            assert(~isempty(app.Reference),'VIStudioV18:Template','Load a reference image first.');
            fig=uifigure('Name','擷取樣板 / Crop template','Position',[180 120 850 650]); cleanup=onCleanup(@() delete(fig)); ax=uiaxes(fig,'Position',[10 10 830 630]); imshow(app.Reference,'Parent',ax); roi=drawrectangle(ax); wait(roi);
            assert(isvalid(roi),'VIStudioV18:ROI','Crop cancelled.'); pos=roi.Position; x=max(1,ceil(pos(1))); y=max(1,ceil(pos(2))); w=min(size(app.Reference,2),floor(pos(1)+pos(3)))-x+1; h=min(size(app.Reference,1),floor(pos(2)+pos(4)))-y+1; app.loadTemplate(app.Reference,[x y w h]);
        end
        function save(app), app.changed(); [f,p]=uiputfile('*.mat','Save shape definition','shape-definition.mat'); if ~isequal(f,0), app.Data.saveDefinition(fullfile(p,f)); end, end
        function open(app), [f,p]=uigetfile('*.mat'); if ~isequal(f,0), app.Data.loadDefinition(fullfile(p,f)); app.Reference=app.Data.Template; app.syncControls(); app.refresh(); end, end
        function export(app), parent=uigetdir(pwd); if ~isequal(parent,0), folder=app.Data.export(parent); app.Handles.Status.Text="已匯出 / Exported: "+string(folder); end, end
        function action(app,callback)
            if app.Busy, return; end; app.Busy=true; cleanup=onCleanup(@() app.finish());
            controls=findall(app.UIFigure,'-isa','matlab.ui.control.Button'); for k=1:numel(controls), controls(k).Enable='off'; end; drawnow;
            try, callback(); catch err, app.Handles.Status.Text=string(err.message); if strcmp(app.UIFigure.Visible,'off'), rethrow(err); end; uialert(app.UIFigure,err.message,'VIStudio V18','Interpreter','none'); end
        end
        function finish(app)
            app.Busy=false; if ~isvalid(app.UIFigure), return; end
            controls=findall(app.UIFigure,'-isa','matlab.ui.control.Button'); for k=1:numel(controls), controls(k).Enable='on'; end
            h=getappdata(app.UIFigure,'VIStudioThemeV18'); h.Sync.Enable='off';
        end
    end
end
