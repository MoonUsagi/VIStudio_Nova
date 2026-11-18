classdef VIStudioVideoExtractAppV24 < handle
    properties (SetAccess=private)
        UIFigure
        Data
        Handles=struct()
        ROI=[]
    end
    properties (Access=private)
        Busy=false
        CloseAfterStop=false
    end
    methods
        function app=VIStudioVideoExtractAppV24(visible)
            if nargin<1, visible='on'; end; app.Data=VIStudioVideoExtractV24; app.build(); app.UIFigure.Visible=validatestring(char(visible),{'on','off'});
        end
        function delete(app)
            if ~isempty(app.UIFigure) && isvalid(app.UIFigure), delete(app.UIFigure); end
        end
        function loadVideo(app,file)
            app.Data.loadVideo(file); app.showFrame(); app.Handles.Results.Data=table();
            app.Handles.Source.Text=string(app.Data.Info.Width)+" × "+app.Data.Info.Height+" px · "+app.Data.Info.FrameRate+" fps · "+app.Data.Info.Duration+" s";
            app.Handles.Status.Text='拖曳 ROI 後按套用，設定取樣模式與影格範圍 / Draw/resize the ROI, apply it and set sampling/range.';
        end
        function setROI(app,roi)
            app.Data.setROI(roi); if ~isempty(app.ROI) && isvalid(app.ROI), app.ROI.Position=[roi(1)-.5 roi(2)-.5 roi(3:4)]; end; app.showCrop();
        end
        function result=extract(app,parent)
            app.applyROI(); app.Data.configure(app.options()); cleanup=onCleanup(@() app.setBusy(false)); app.setBusy(true);
            result=app.Data.extract(parent,@(p) app.progress(p)); app.Handles.Results.Data=result.Manifest;
            app.Handles.Status.Text=result.Status+" · "+result.SavedImages+" images · "+result.Folder+" · "+result.Message;
        end
    end
    methods (Access=private)
        function build(app)
            app.UIFigure=uifigure('Name','VIStudio V24 | 影片 ROI 擷取 Video ROI Extraction','Visible','off','Position',[70 50 1440 900],'CloseRequestFcn',@(~,~) app.close());
            root=uigridlayout(app.UIFigure,[5 1],'RowHeight',{44,86,45,'1x',44},'Padding',[10 8 10 8],'Scrollable','on');
            bar=uigridlayout(root,[1 4],'ColumnWidth',{180,180,140,'1x'},'Padding',[0 0 0 0]);
            app.Handles.Load=uibutton(bar,'Text','匯入影片 / Load video','ButtonPushedFcn',@(~,~) app.action(@() app.pickVideo()));
            app.Handles.Apply=uibutton(bar,'Text','套用 ROI / Apply ROI','ButtonPushedFcn',@(~,~) app.action(@() app.applyROI()));
            app.Handles.Stop=uibutton(bar,'Text','停止 / Stop','Enable','off','ButtonPushedFcn',@(~,~) app.Data.requestStop()); app.Handles.Source=uilabel(bar,'Text','尚未載入影片 / No video','WordWrap','on');
            g=uigridlayout(root,[2 7],'RowHeight',{25,34},'Padding',[0 0 0 0]); labels={'取樣模式 / Mode','N 影格或張/秒 / Rate','起始影格 / Start','結束影格 / End','最大張數 / Limit','格式 / Format','檔名前綴 / Prefix'};
            for k=1:7, h=uilabel(g,'Text',labels{k},'WordWrap','on'); h.Layout.Row=1; h.Layout.Column=k; end
            app.Handles.Mode=uidropdown(g,'Items',{'每隔 N 影格 / Every N frames','每秒 N 張 / Images per second'},'ItemsData',{'interval','fps'}); app.Handles.Mode.Layout.Row=2; app.Handles.Mode.Layout.Column=1;
            fields={'Rate','Start','End','Limit'}; values=[30 1 Inf 10000];
            for k=1:4, h=uieditfield(g,'numeric','Value',values(k)); h.Layout.Row=2; h.Layout.Column=k+1; app.Handles.(fields{k})=h; end
            app.Handles.Format=uidropdown(g,'Items',{'png','jpg'}); app.Handles.Format.Layout.Row=2; app.Handles.Format.Layout.Column=6;
            app.Handles.Prefix=uieditfield(g,'text','Value','frame'); app.Handles.Prefix.Layout.Row=2; app.Handles.Prefix.Layout.Column=7;
            bar=uigridlayout(root,[1 2],'ColumnWidth',{230,'1x'},'Padding',[0 0 0 0]); app.Handles.Extract=uibutton(bar,'Text','裁切並儲存 / Extract & save','ButtonPushedFcn',@(~,~) app.action(@() app.pickOutput()));
            uilabel(bar,'Text','ROI 固定，不追蹤物件。PNG 無損；影格編號從 1 開始 / Fixed ROI, no tracking. PNG is lossless; source frame numbers start at 1.','WordWrap','on');
            body=uigridlayout(root,[2 2],'RowHeight',{'1x',180}); app.Handles.FullAxes=uiaxes(body); title(app.Handles.FullAxes,'來源影格與 ROI / Source frame & ROI'); app.Handles.CropAxes=uiaxes(body); title(app.Handles.CropAxes,'裁切預覽 / Cropped preview');
            app.Handles.Results=uitable(body,'RowName',{}); app.Handles.Results.Layout.Row=2; app.Handles.Results.Layout.Column=[1 2];
            app.Handles.Status=uilabel(root,'Text','匯入影片後開始 / Load a video to begin','WordWrap','on','Interpreter','none');
            h=VIStudioThemeV24.install(app.UIFigure,'影片 ROI 擷取 / Video ROI'); h.Guide.Text='匯入 → 選 ROI → 設定影格取樣 → 預覽 → 擷取至新資料夾 / Load → Select ROI → Configure sampling → Preview → Save to a new folder. Cancellation preserves partial outputs with CANCELLED status.';
        end
        function showFrame(app)
            if ~isempty(app.ROI) && isvalid(app.ROI), delete(app.ROI); end
            imshow(app.Data.Preview,'Parent',app.Handles.FullAxes); r=app.Data.ROI; app.ROI=drawrectangle(app.Handles.FullAxes,'Position',[r(1)-.5 r(2)-.5 r(3:4)],'Color',[.1 .8 .7]); app.showCrop();
        end
        function showCrop(app), imshow(app.Data.croppedPreview(),'Parent',app.Handles.CropAxes); end
        function applyROI(app)
            assert(~isempty(app.ROI) && isvalid(app.ROI),'VIStudioV24:VideoROI','Load a video and select an ROI.');
            p=app.ROI.Position; x=ceil(p(1)+.5); y=ceil(p(2)+.5); w=floor(p(1)+p(3)-.5)-x+1; h=floor(p(2)+p(4)-.5)-y+1;
            app.setROI([x y w h]);
        end
        function o=options(app)
            o=VIStudioVideoExtractV24.defaults(); o.Mode=string(app.Handles.Mode.Value); o.Rate=app.Handles.Rate.Value; o.StartFrame=app.Handles.Start.Value; o.EndFrame=app.Handles.End.Value; o.MaxImages=app.Handles.Limit.Value; o.Format=string(app.Handles.Format.Value); o.Prefix=string(app.Handles.Prefix.Value);
        end
        function progress(app,p)
            app.Handles.Status.Text=sprintf('已解碼 %d 影格，已存 %d 張 / Decoded %d, saved %d · %.3f s',p.Decoded,p.Saved,p.Decoded,p.Saved,p.Time); drawnow limitrate;
        end
        function setBusy(app,busy)
            app.Busy=busy; if ~isvalid(app.UIFigure), return; end
            state='on'; if busy, state='off'; end
            for h=reshape(findall(app.UIFigure),1,[])
                if isprop(h,'Enable'), h.Enable=state; end
            end
            if ~isempty(app.ROI) && isvalid(app.ROI), app.ROI.InteractionsAllowed='all'; if busy, app.ROI.InteractionsAllowed='none'; end, end
            app.Handles.Stop.Enable=matlab.lang.OnOffSwitchState(busy); h=getappdata(app.UIFigure,'VIStudioThemeV24'); h.Sync.Enable='off';
            if ~busy && app.CloseAfterStop, delete(app); end
        end
        function pickVideo(app), [f,p]=uigetfile({'*.mp4;*.avi;*.mov;*.m4v;*.mj2','Videos'}); if ~isequal(f,0), app.loadVideo(fullfile(p,f)); end, end
        function pickOutput(app), parent=uigetdir(pwd); if ~isequal(parent,0), app.extract(parent); end, end
        function action(app,callback)
            if app.Busy, return; end
            try, callback(); catch err, app.Handles.Status.Text=string(err.message); if strcmp(app.UIFigure.Visible,'off'), rethrow(err); end; uialert(app.UIFigure,err.message,'VIStudio V24','Interpreter','none'); end
        end
        function close(app)
            if app.Busy, app.CloseAfterStop=true; app.Data.requestStop(); else, delete(app); end
        end
    end
end
