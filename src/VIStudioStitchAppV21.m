classdef VIStudioStitchAppV21 < handle
    properties (SetAccess=private)
        UIFigure
        Data
        Handles=struct()
    end
    properties (Access=private)
        Busy=false
    end
    methods
        function app=VIStudioStitchAppV21(visible)
            if nargin<1, visible='on'; end; app.Data=VIStudioStitchV21; app.build(); app.UIFigure.Visible=validatestring(visible,{'on','off'});
        end
        function delete(app), if ~isempty(app.UIFigure) && isvalid(app.UIFigure), delete(app.UIFigure); end, end
        function loadFiles(app,files)
            app.Data.setFiles(files); app.Handles.Files.Data=table((1:numel(app.Data.Sources))',string({app.Data.Sources.File})','VariableNames',{'Order','File'}); app.Handles.Files.Selection=1; app.refresh();
        end
        function image=run(app)
            o=app.Data.Options; o.Model=string(app.Handles.Model.Value); o.Blend=string(app.Handles.Blend.Value); o.MinInliers=app.Handles.Inliers.Value; o.MaxError=app.Handles.Error.Value; o.MaxCanvasPixels=app.Handles.Pixels.Value*1e6; app.Data.configure(o);
            try, image=app.Data.run(); app.refresh(); catch err, app.refresh(); rethrow(err); end
        end
        function demo(app), folder=tempname; files=VIStudioStitchV21.demo(folder); app.loadFiles(files); app.run(); end
        function refresh(app)
            cla(app.Handles.Result); if ~isempty(app.Data.Panorama), imshow(app.Data.Panorama,'Parent',app.Handles.Result); end
            if ~isempty(app.Data.Sources), imshow(VIStudioStitchV21.read(app.Data.Sources(1).File),'Parent',app.Handles.Source); end
            app.Handles.Quality.Data=app.Data.Quality; app.Handles.Status.Text=app.Data.State+" · "+app.Data.Message;
        end
    end
    methods (Access=private)
        function build(app)
            app.UIFigure=uifigure('Name','VIStudio V21 | 影像拼接 Image Stitching','Position',[60 50 1440 820],'Visible','off','CloseRequestFcn',@(~,~) app.close());
            g=uigridlayout(app.UIFigure,[4 1],'RowHeight',{42,65,'1x',40},'Scrollable','on'); bar=uigridlayout(g,[1 5],'Padding',[0 0 0 0]); labels={'載入多張 / Load images','上移 / Move up','下移 / Move down','示例 / Demo','匯出 / Export'}; calls={@() app.pick(),@() app.move(-1),@() app.move(1),@() app.demo(),@() app.export()};
            for k=1:5, cb=calls{k}; uibutton(bar,'Text',labels{k},'ButtonPushedFcn',@(~,~) app.action(cb)); end
            options=uigridlayout(g,[2 6],'RowHeight',{24,32},'RowSpacing',4,'Padding',[0 0 0 0]); names={'幾何 / Transform','接縫 / Blend','最少內點 / Inliers','最大誤差 px / Error','畫布上限 MP / Limit','執行 / Run'};
            for k=1:6, h=uilabel(options,'Text',names{k}); h.Layout.Row=1; h.Layout.Column=k; end
            app.Handles.Model=uidropdown(options,'Items',{'translation','similarity','affine','projective'},'Value','similarity'); app.Handles.Model.Layout.Row=2; app.Handles.Model.Layout.Column=1;
            app.Handles.Blend=uidropdown(options,'Items',{'feather','mean'}); app.Handles.Blend.Layout.Row=2; app.Handles.Blend.Layout.Column=2;
            fields={'Inliers','Error','Pixels'}; values=[12 3 8]; for k=1:3, h=uieditfield(options,'numeric','Value',values(k)); h.Layout.Row=2; h.Layout.Column=k+2; app.Handles.(fields{k})=h; end
            h=uibutton(options,'Text','配準並拼接 / Stitch','ButtonPushedFcn',@(~,~) app.action(@() app.run())); h.Layout.Row=2; h.Layout.Column=6;
            body=uigridlayout(g,[2 3],'ColumnWidth',{260,'1x','2x'},'RowHeight',{'1x',160}); app.Handles.Files=uitable(body,'SelectionType','row'); app.Handles.Source=uiaxes(body); title(app.Handles.Source,'首張參考 / Reference'); app.Handles.Result=uiaxes(body); title(app.Handles.Result,'拼接結果 / Mosaic'); app.Handles.Quality=uitable(body,'RowName',{}); app.Handles.Quality.Layout.Row=2; app.Handles.Quality.Layout.Column=[1 3];
            app.Handles.Status=uilabel(g,'Text','請依相鄰重疊順序載入 / Load images in adjacent-overlap order','WordWrap','on','Interpreter','none'); h=VIStudioThemeV21.install(app.UIFigure,'影像拼接 / Image Stitching'); h.Guide.Text='特徵配準 → 品質檢查 → 接縫融合 / Registration → Quality gates → Blending. Requires overlapping planar views; no physical calibration is transferred.';
        end
        function move(app,delta)
            ix=app.Handles.Files.Selection; if isempty(ix), return; end; ix=ix(1); target=ix+delta; if target<1 || target>numel(app.Data.Sources), return; end
            files=string({app.Data.Sources.File}); files([ix target])=files([target ix]); app.loadFiles(files); app.Handles.Files.Selection=target;
        end
        function pick(app), [f,p]=uigetfile({'*.png;*.jpg;*.tif;*.bmp','Images'},'Ordered images','MultiSelect','on'); if ~isequal(f,0), app.loadFiles(fullfile(p,string(f))); end, end
        function export(app), p=uigetdir(pwd); if ~isequal(p,0), folder=app.Data.export(p); app.Handles.Status.Text="匯出 / Exported: "+string(folder); end, end
        function action(app,callback)
            if app.Busy, return; end; app.Busy=true; cleanup=onCleanup(@() app.finish()); for h=reshape(findall(app.UIFigure,'-isa','matlab.ui.control.Button'),1,[]), h.Enable='off'; end; drawnow;
            try, callback(); catch err, app.Handles.Status.Text=string(err.message); if strcmp(app.UIFigure.Visible,'off'), rethrow(err); end; uialert(app.UIFigure,err.message,'VIStudio V21','Interpreter','none'); end
        end
        function finish(app)
            app.Busy=false; if ~isvalid(app.UIFigure), return; end; for h=reshape(findall(app.UIFigure,'-isa','matlab.ui.control.Button'),1,[]), h.Enable='on'; end; h=getappdata(app.UIFigure,'VIStudioThemeV21'); h.Sync.Enable='off';
        end
        function close(app)
            if app.Busy, app.Handles.Status.Text='正在配準／融合；完成後可關閉 / Registration/blending is active; close after completion.'; else, delete(app); end
        end
    end
end
