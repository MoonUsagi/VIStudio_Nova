classdef VIStudioChangeDetectionAppV25 < handle
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
        function app=VIStudioChangeDetectionAppV25(visible)
            if nargin<1, visible='on'; end; app.Data=VIStudioChangeDetectionV25; app.build(); app.UIFigure.Visible=validatestring(visible,{'on','off'});
        end
        function delete(app), if ~isempty(app.UIFigure) && isvalid(app.UIFigure), delete(app.UIFigure); end, end
        function loadReference(app,input), app.Data.setReference(input); app.ROI=[]; app.refresh(); end
        function loadCurrent(app,input), app.Data.setCurrent(input); app.refresh(); end
        function loadTruth(app,mask), app.Data.setTruth(mask); app.refresh(); end
        function initializeModel(app,variant)
            if nargin<2, variant=string(app.Handles.Method.Value); end
            assert(ismember(string(variant),["fc-siam-diff","fc-siam-conc","bit-r18","opencd-changeformer-b0"]),'VIStudioV25:ChangeModel','Select a native FC-Siam, BIT or Open-CD ChangeFormer model first.');
            sz=[64 64 3]; if ~isempty(app.Data.Reference), sz=size(app.Data.Reference); end
            if string(variant)=="opencd-changeformer-b0", artifact=VIStudioChangeFormerV25.create(sz); elseif string(variant)=="bit-r18", artifact=VIStudioBITV25.create(sz); else, artifact=VIStudioFCSiamV25.create(variant,sz); end; app.Data.setArtifact(artifact); app.Handles.Method.Value=char(variant); app.refresh(); app.Handles.Status.Text='隨機初始化；僅架構測試，尚未訓練 / RANDOM INITIALIZATION: architecture testing only, not trained';
        end
        function loadModel(app,file)
            app.Data.loadArtifact(file); method='research-model'; if ismember(string(app.Data.Artifact.Metadata.Architecture),["fc-siam-diff","fc-siam-conc","bit-r18","opencd-changeformer-b0"]), method=char(app.Data.Artifact.Metadata.Architecture); end; app.Handles.Method.Value=method; app.refresh(); app.Handles.Status.Text='MAT 權重已載入；需獨立驗證 / Native MAT weights loaded; independent validation required';
        end
        function loadPretrained(app,variant)
            if nargin<2, variant=string(app.Handles.Method.Value); end
            assert(ismember(string(variant),["fc-siam-diff","fc-siam-conc","bit-r18","opencd-changeformer-b0"]),'VIStudioV25:ChangeModel','Select a native FC-Siam, BIT or Open-CD ChangeFormer model first.');
            folder='VIStudio_Pretrained_V23'; if string(variant)=="bit-r18", folder='VIStudio_BIT_Pretrained_V24'; elseif string(variant)=="opencd-changeformer-b0", folder='VIStudio_ChangeFormer_Pretrained_V25'; end; file=fullfile(fileparts(mfilename('fullpath')),folder,string(variant)+"-levircd.mat"); assert(isfile(file),'VIStudioV25:PretrainedMissing','Bundled pretrained checkpoint is missing.');
            sz=[256 256 3]; if ~isempty(app.Data.Reference), sz=size(app.Data.Reference); end
            if string(variant)=="opencd-changeformer-b0", artifact=VIStudioChangeFormerV25.loadWeights(file,sz); elseif string(variant)=="bit-r18", artifact=VIStudioBITV25.loadWeights(file,sz); else, artifact=VIStudioFCSiamV25.loadWeights(file,sz); end; app.Data.setArtifact(artifact); app.Handles.Method.Value=char(variant); app.Handles.Threshold.Value=.5; app.refresh(); app.Handles.Status.Text='已載入 LEVIR-CD 預訓練權重；非工業驗證 / Pretrained LEVIR-CD weights loaded; industrial accuracy unvalidated';
        end
        function mask=run(app)
            app.applyROI(); o=app.Data.Options; o.Method=string(app.Handles.Method.Value); o.Alignment=string(app.Handles.Alignment.Value); o.Threshold=app.Handles.Threshold.Value; o.MinArea=app.Handles.Area.Value; o.Border=app.Handles.Border.Value; o.BrightnessOffset=app.Handles.Brightness.Value; app.Data.configure(o);
            try, mask=app.Data.run(); app.refresh(); catch err, app.refresh(); rethrow(err); end
        end
        function demo(app)
            [a,b,g]=VIStudioChangeDetectionV25.demo(); app.loadReference(a); app.loadCurrent(b); app.loadTruth(g); app.run();
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
            app.UIFigure=uifigure('Name','VIStudio V25 | 影像變化偵測 Change Detection','Position',[60 40 1480 850],'Visible','off','CloseRequestFcn',@(~,~) app.close());
            root=uigridlayout(app.UIFigure,[4 1],'RowHeight',{42,64,'1x',42},'Scrollable','on'); bar=uigridlayout(root,[1 10],'Padding',[0 0 0 0]);
            labels={'參考 / Reference','待測 / Compare','真值 / Truth','分析 ROI / ROI','載入 / Load MAT','預訓練 / Pretrained','建立 / New model','說明 / Models','示例 / Demo','匯出 / Export'};
            calls={@() app.pickReference(),@() app.pickCurrent(),@() app.pickTruth(),@() app.region(),@() app.pickModel(),@() app.loadPretrained(),@() app.initializeModel(),@() app.research(),@() app.demo(),@() app.export()};
            for k=1:numel(labels), cb=calls{k}; uibutton(bar,'Text',labels{k},'ButtonPushedFcn',@(~,~) app.action(cb)); end
            opts=uigridlayout(root,[2 7],'RowHeight',{24,32},'RowSpacing',4,'Padding',[0 0 0 0]); titles={'方法 / Method','對齊 / Alignment','門檻 / Threshold','最小區域 px / Area','忽略邊界 px / Border','亮度偏移 / Brightness','執行 / Run'};
            for k=1:7, h=uilabel(opts,'Text',titles{k}); h.Layout.Row=1; h.Layout.Column=k; end
            app.Handles.Method=uidropdown(opts,'Items',{'像素差分 / Abs difference','結構相似度 / SSIM','小型研究模型 / Tiny research','FC-Siam-diff / MATLAB','FC-Siam-conc / MATLAB','BIT-R18 / MATLAB','CF MiT-B0 / Open-CD'},'ItemsData',{'absdiff','ssim','research-model','fc-siam-diff','fc-siam-conc','bit-r18','opencd-changeformer-b0'},'Tooltip','CF MiT-B0 is the Open-CD Siamese SegFormer variant, not original ChangeFormer V6.'); app.Handles.Method.Layout.Row=2; app.Handles.Method.Layout.Column=1;
            app.Handles.Alignment=uidropdown(opts,'Items',{'none','translation','rigid','similarity'}); app.Handles.Alignment.Layout.Row=2; app.Handles.Alignment.Layout.Column=2;
            fields={'Threshold','Area','Border'}; values=[.15 12 2]; for k=1:3, h=uieditfield(opts,'numeric','Value',values(k)); h.Layout.Row=2; h.Layout.Column=k+2; app.Handles.(fields{k})=h; end
            app.Handles.Brightness=uicheckbox(opts,'Text','補償 / Compensate','Value',false,'Tooltip','Subtract global median offset; may hide widespread brightness changes.'); app.Handles.Brightness.Layout.Row=2; app.Handles.Brightness.Layout.Column=6;
            h=uibutton(opts,'Text','比較 / Detect','ButtonPushedFcn',@(~,~) app.action(@() app.run())); h.Layout.Row=2; h.Layout.Column=7;
            body=uigridlayout(root,[3 2],'RowHeight',{'1x','1x',140}); app.Handles.Reference=uiaxes(body); title(app.Handles.Reference,'參考 / Reference'); app.Handles.Current=uiaxes(body); title(app.Handles.Current,'待測／對齊 / Current / aligned'); app.Handles.Score=uiaxes(body); title(app.Handles.Score,'變化分數 / Change score'); app.Handles.Overlay=uiaxes(body); title(app.Handles.Overlay,'候選區域 / Candidates');
            tabs=uitabgroup(body); tabs.Layout.Row=3; tabs.Layout.Column=[1 2]; p=uitab(tabs,'Title','變化區域 / Regions'); g=uigridlayout(p,[1 1]); app.Handles.Regions=uitable(g); p=uitab(tabs,'Title','真值評估 / Evaluation'); g=uigridlayout(p,[1 1]); app.Handles.Evaluation=uitable(g);
            app.Handles.Status=uilabel(root,'Text','載入成對影像 / Load a registered image pair','WordWrap','on','Interpreter','none'); h=VIStudioThemeV25.install(app.UIFigure,'影像變化偵測 / Change Detection'); h.Guide.Text='參考座標 → 對齊與有效區 → 變化候選 → 覆核 / Reference coordinates → Registration/valid region → Change candidates → Review. Research models are experimental.';
        end
        function applyROI(app)
            if isempty(app.ROI) || ~isvalid(app.ROI), return; end; p=app.ROI.Position; x=ceil(p(1)); y=ceil(p(2)); x2=floor(p(1)+p(3)); y2=floor(p(2)+p(4)); sz=size(app.Data.Reference,[1 2]); assert(x>=1 && y>=1 && x2<=sz(2) && y2<=sz(1) && x2>=x && y2>=y,'VIStudioV25:ChangeROI','ROI must stay inside the reference image.'); m=false(sz); m(y:y2,x:x2)=true; app.Data.setAllowed(m);
        end
        function region(app)
            assert(~isempty(app.Data.Reference),'VIStudioV25:ChangePair','Load a reference first.'); if ~isempty(app.ROI) && isvalid(app.ROI), delete(app.ROI); end; sz=size(app.Data.Reference,[1 2]); app.ROI=drawrectangle(app.Handles.Reference,'Position',[sz(2)*.1 sz(1)*.1 sz(2)*.8 sz(1)*.8],'Color',[.1 .8 .7]);
        end
        function pickReference(app), [f,p]=uigetfile({'*.png;*.jpg;*.tif;*.bmp','Reference image'}); if ~isequal(f,0), app.loadReference(fullfile(p,f)); end, end
        function pickCurrent(app), [f,p]=uigetfile({'*.png;*.jpg;*.tif;*.bmp','Comparison image'}); if ~isequal(f,0), app.loadCurrent(fullfile(p,f)); end, end
        function pickTruth(app)
            [f,p]=uigetfile({'*.png;*.tif;*.bmp','Binary truth mask'}); if isequal(f,0), return; end; m=imread(fullfile(p,f)); values=unique(m); assert(ismatrix(m) && numel(values)<=2 && (numel(values)<2 || any(values==0)),'VIStudioV25:ChangeTruth','Use a binary mask with zero background.'); app.loadTruth(m~=0);
        end
        function pickModel(app), [f,p]=uigetfile('*.mat','Native FC-Siam checkpoint / research artifact'); if ~isequal(f,0), app.loadModel(fullfile(p,f)); end, end
        function research(app)
            fig=uifigure('Name','V25 | Change Detection Model Research','Position',[150 130 950 430]); g=uigridlayout(fig,[2 1],'RowHeight',{90,'1x'}); uilabel(g,'Text','FC-Siam、BIT-R18 與 Open-CD ChangeFormer MiT-B0 均提供原生預訓練 MAT。MiT-B0 是 Open-CD 的 Siamese SegFormer 變體，非原作者 ChangeFormer V6。單次推論為一張參考＋一張待測，不會從標準照學習正常外觀。工業準確率需實測。New model 為隨機權重。 / Native pretrained inference; no Python runtime. See docs/CHANGEFORMER_NATIVE.md and REFERENCE_PAIR_GUIDE.md.','WordWrap','on');
            names=["Abs difference / SSIM";"Tiny early fusion";"Tiny shared Siamese";"FC-Siam-diff / conc";"BIT-R18";"Open-CD ChangeFormer MiT-B0"]; statuses=["本工作區可用 / Available";"原生研究原型 / Native research prototype";"共享權重研究原型 / Shared-weight prototype";"完整原生架構與 MAT 權重 / Full native architecture and MAT weights";"Open-CD 原生架構與預訓練 MAT / Native architecture and pretrained MAT";"原生 Siamese SegFormer，非原作者 V6 / Native Siamese SegFormer, not original V6"];
            uitable(g,'Data',table(names,statuses,'VariableNames',{'Method','Scope'})); VIStudioThemeV25.apply(fig);
        end
        function export(app), p=uigetdir(pwd); if ~isequal(p,0), folder=app.Data.export(p); app.Handles.Status.Text="已匯出 / Exported: "+string(folder); end, end
        function action(app,callback)
            if app.Busy, return; end; app.Busy=true; cleanup=onCleanup(@() app.finish()); for h=reshape(findall(app.UIFigure,'-isa','matlab.ui.control.Button'),1,[]), h.Enable='off'; end; drawnow;
            try, callback(); catch err, app.Handles.Status.Text=string(err.message); if strcmp(app.UIFigure.Visible,'off'), rethrow(err); end; uialert(app.UIFigure,err.message,'VIStudio V25','Interpreter','none'); end
        end
        function finish(app)
            app.Busy=false; if ~isvalid(app.UIFigure), return; end; for h=reshape(findall(app.UIFigure,'-isa','matlab.ui.control.Button'),1,[]), h.Enable='on'; end; h=getappdata(app.UIFigure,'VIStudioThemeV25'); h.Sync.Enable='off';
        end
        function close(app), if ~app.Busy, delete(app); end, end
    end
end
