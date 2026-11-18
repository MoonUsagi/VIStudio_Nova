classdef VIStudioChangeDetectionAppV21 < handle
    properties (SetAccess=private)
        UIFigure
        Data
        Handles=struct()
        ROI=[]
    end
    properties (Access=private)
        Busy=false
    end
    methods
        function app=VIStudioChangeDetectionAppV21(visible)
            if nargin<1, visible='on'; end; app.Data=VIStudioChangeDetectionV21; app.build(); app.UIFigure.Visible=validatestring(visible,{'on','off'});
        end
        function delete(app), if ~isempty(app.UIFigure) && isvalid(app.UIFigure), delete(app.UIFigure); end, end
        function loadReference(app,input), app.Data.setReference(input); app.ROI=[]; app.refresh(); end
        function loadCurrent(app,input), app.Data.setCurrent(input); app.refresh(); end
        function loadTruth(app,mask), app.Data.setTruth(mask); app.refresh(); end
        function mask=run(app)
            app.applyROI(); o=app.Data.Options; o.Method=string(app.Handles.Method.Value); o.Alignment=string(app.Handles.Alignment.Value); o.Threshold=app.Handles.Threshold.Value; o.MinArea=app.Handles.Area.Value; o.Border=app.Handles.Border.Value; o.BrightnessOffset=app.Handles.Brightness.Value; app.Data.configure(o);
            try, mask=app.Data.run(); app.refresh(); catch err, app.refresh(); rethrow(err); end
        end
        function demo(app)
            [a,b,g]=VIStudioChangeDetectionV21.demo(); app.loadReference(a); app.loadCurrent(b); app.loadTruth(g); app.run();
        end
        function refresh(app)
            if ~isempty(app.Data.Reference) && (isempty(app.ROI) || ~isvalid(app.ROI)), imshow(app.Data.Reference,'Parent',app.Handles.Reference); end
            cla(app.Handles.Current); cla(app.Handles.Score); cla(app.Handles.Overlay);
            if ~isempty(app.Data.Current), imshow(app.Data.Current,'Parent',app.Handles.Current); end
            if app.Data.State=="COMPLETE"
                imshow(app.Data.Aligned,'Parent',app.Handles.Current); imshow(app.Data.Score,[0 1],'Parent',app.Handles.Score); colormap(app.Handles.Score,turbo); imshow(app.Data.overlay(),'Parent',app.Handles.Overlay);
            end
            for name={'Reference','Current','Score','Overlay'}, ax=app.Handles.(name{1}); ax.Toolbar.Visible='off'; ax.Title.FontSize=11; ax.Title.Interpreter='none'; end
            app.Handles.Regions.Data=app.Data.Regions; app.Handles.Evaluation.Data=table(); if ~isempty(app.Data.Evaluation), app.Handles.Evaluation.Data=struct2table(app.Data.Evaluation); end
            app.Handles.Status.Text=app.Data.State+" · "+app.Data.Message; if app.Data.State=="COMPLETE", app.Handles.Status.Text=app.Handles.Status.Text+" · "+nnz(app.Data.Mask)+" changed px / "+nnz(app.Data.Valid)+" evaluated px"; end
        end
    end
    methods (Access=private)
        function build(app)
            app.UIFigure=uifigure('Name','VIStudio V21 | 影像變化偵測 Change Detection','Position',[60 40 1480 850],'Visible','off','CloseRequestFcn',@(~,~) app.close());
            root=uigridlayout(app.UIFigure,[4 1],'RowHeight',{42,64,'1x',42},'Scrollable','on'); bar=uigridlayout(root,[1 8],'Padding',[0 0 0 0]);
            labels={'參考影像 / Reference','待測影像 / Compare','真值遮罩 / Truth','分析 ROI / ROI','研究模型 / Model MAT','模型研究 / Research','示例 / Demo','匯出 / Export'};
            calls={@() app.pickReference(),@() app.pickCurrent(),@() app.pickTruth(),@() app.region(),@() app.pickModel(),@() app.research(),@() app.demo(),@() app.export()};
            for k=1:numel(labels), cb=calls{k}; uibutton(bar,'Text',labels{k},'ButtonPushedFcn',@(~,~) app.action(cb)); end
            opts=uigridlayout(root,[2 7],'RowHeight',{24,32},'RowSpacing',4,'Padding',[0 0 0 0]); titles={'方法 / Method','對齊 / Alignment','門檻 / Threshold','最小區域 px / Area','忽略邊界 px / Border','亮度偏移 / Brightness','執行 / Run'};
            for k=1:7, h=uilabel(opts,'Text',titles{k}); h.Layout.Row=1; h.Layout.Column=k; end
            app.Handles.Method=uidropdown(opts,'Items',{'像素差分 / Abs difference','結構相似度 / SSIM','實驗模型 / Research model'},'ItemsData',{'absdiff','ssim','research-model'}); app.Handles.Method.Layout.Row=2; app.Handles.Method.Layout.Column=1;
            app.Handles.Alignment=uidropdown(opts,'Items',{'none','translation','rigid','similarity'}); app.Handles.Alignment.Layout.Row=2; app.Handles.Alignment.Layout.Column=2;
            fields={'Threshold','Area','Border'}; values=[.15 12 2]; for k=1:3, h=uieditfield(opts,'numeric','Value',values(k)); h.Layout.Row=2; h.Layout.Column=k+2; app.Handles.(fields{k})=h; end
            app.Handles.Brightness=uicheckbox(opts,'Text','補償 / Compensate','Value',false,'Tooltip','Subtract global median offset; may hide widespread brightness changes.'); app.Handles.Brightness.Layout.Row=2; app.Handles.Brightness.Layout.Column=6;
            h=uibutton(opts,'Text','比較 / Detect','ButtonPushedFcn',@(~,~) app.action(@() app.run())); h.Layout.Row=2; h.Layout.Column=7;
            body=uigridlayout(root,[3 2],'RowHeight',{'1x','1x',140}); app.Handles.Reference=uiaxes(body); title(app.Handles.Reference,'參考 / Reference'); app.Handles.Current=uiaxes(body); title(app.Handles.Current,'待測／對齊 / Current / aligned'); app.Handles.Score=uiaxes(body); title(app.Handles.Score,'變化分數 / Change score'); app.Handles.Overlay=uiaxes(body); title(app.Handles.Overlay,'候選區域 / Candidates');
            tabs=uitabgroup(body); tabs.Layout.Row=3; tabs.Layout.Column=[1 2]; p=uitab(tabs,'Title','變化區域 / Regions'); g=uigridlayout(p,[1 1]); app.Handles.Regions=uitable(g); p=uitab(tabs,'Title','真值評估 / Evaluation'); g=uigridlayout(p,[1 1]); app.Handles.Evaluation=uitable(g);
            app.Handles.Status=uilabel(root,'Text','載入成對影像 / Load a registered image pair','WordWrap','on','Interpreter','none'); h=VIStudioThemeV21.install(app.UIFigure,'影像變化偵測 / Change Detection'); h.Guide.Text='參考座標 → 對齊與有效區 → 變化候選 → 覆核 / Reference coordinates → Registration/valid region → Change candidates → Review. Research models are experimental.';
        end
        function applyROI(app)
            if isempty(app.ROI) || ~isvalid(app.ROI), return; end; p=app.ROI.Position; x=ceil(p(1)); y=ceil(p(2)); x2=floor(p(1)+p(3)); y2=floor(p(2)+p(4)); sz=size(app.Data.Reference,[1 2]); assert(x>=1 && y>=1 && x2<=sz(2) && y2<=sz(1) && x2>=x && y2>=y,'VIStudioV21:ChangeROI','ROI must stay inside the reference image.'); m=false(sz); m(y:y2,x:x2)=true; app.Data.setAllowed(m);
        end
        function region(app)
            assert(~isempty(app.Data.Reference),'VIStudioV21:ChangePair','Load a reference first.'); if ~isempty(app.ROI) && isvalid(app.ROI), delete(app.ROI); end; sz=size(app.Data.Reference,[1 2]); app.ROI=drawrectangle(app.Handles.Reference,'Position',[sz(2)*.1 sz(1)*.1 sz(2)*.8 sz(1)*.8],'Color',[.1 .8 .7]);
        end
        function pickReference(app), [f,p]=uigetfile({'*.png;*.jpg;*.tif;*.bmp','Reference image'}); if ~isequal(f,0), app.loadReference(fullfile(p,f)); end, end
        function pickCurrent(app), [f,p]=uigetfile({'*.png;*.jpg;*.tif;*.bmp','Comparison image'}); if ~isequal(f,0), app.loadCurrent(fullfile(p,f)); end, end
        function pickTruth(app)
            [f,p]=uigetfile({'*.png;*.tif;*.bmp','Binary truth mask'}); if isequal(f,0), return; end; m=imread(fullfile(p,f)); values=unique(m); assert(ismatrix(m) && numel(values)<=2 && (numel(values)<2 || any(values==0)),'VIStudioV21:ChangeTruth','Use a binary mask with zero background.'); app.loadTruth(m~=0);
        end
        function pickModel(app), [f,p]=uigetfile('*.mat','Research change-model artifact'); if ~isequal(f,0), app.Data.loadArtifact(fullfile(p,f)); app.Handles.Method.Value='research-model'; app.refresh(); app.Handles.Status.Text='模型已載入；實驗用途，未校準 / Loaded: research-only, uncalibrated'; end, end
        function research(app)
            fig=uifigure('Name','V21 | Change Detection Model Research','Position',[150 130 950 430]); g=uigridlayout(fig,[2 1],'RowHeight',{90,'1x'}); uilabel(g,'Text','MATLAB 原生小型 Early Fusion／Shared Siamese 為合成資料可行性原型。FC-Siam／BIT／ChangeFormer／Open-CD 的外部程式、權重與授權另行研究；未隨發布包附帶。詳見 docs/CHANGE_MODELS_RESEARCH.md。 / Native tiny prototypes are feasibility experiments; external model support is not implied.','WordWrap','on');
            names=["Abs difference / SSIM";"Tiny early fusion";"Tiny shared Siamese";"FC-Siam-diff";"BIT / ChangeFormer";"Open-CD"]; statuses=["本工作區可用 / Available";"原生研究原型 / Native research prototype";"共享權重研究原型 / Shared-weight prototype";"外部 PyTorch 可行性研究 / External research";"需額外權重與相容性驗證 / Additional validation";"需 mmcv/mmseg 等環境 / Additional environment"];
            uitable(g,'Data',table(names,statuses,'VariableNames',{'Method','Scope'})); VIStudioThemeV21.apply(fig);
        end
        function export(app), p=uigetdir(pwd); if ~isequal(p,0), folder=app.Data.export(p); app.Handles.Status.Text="已匯出 / Exported: "+string(folder); end, end
        function action(app,callback)
            if app.Busy, return; end; app.Busy=true; cleanup=onCleanup(@() app.finish()); for h=reshape(findall(app.UIFigure,'-isa','matlab.ui.control.Button'),1,[]), h.Enable='off'; end; drawnow;
            try, callback(); catch err, app.Handles.Status.Text=string(err.message); if strcmp(app.UIFigure.Visible,'off'), rethrow(err); end; uialert(app.UIFigure,err.message,'VIStudio V21','Interpreter','none'); end
        end
        function finish(app)
            app.Busy=false; if ~isvalid(app.UIFigure), return; end; for h=reshape(findall(app.UIFigure,'-isa','matlab.ui.control.Button'),1,[]), h.Enable='on'; end; h=getappdata(app.UIFigure,'VIStudioThemeV21'); h.Sync.Enable='off';
        end
        function close(app), if ~app.Busy, delete(app); end, end
    end
end
