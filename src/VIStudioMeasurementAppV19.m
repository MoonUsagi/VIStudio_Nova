classdef VIStudioMeasurementAppV19 < handle
    properties (SetAccess=private)
        UIFigure
        Handles=struct()
        Data
        Viewer=[]
        ImageHandle=[]
        Tool=[]
        ActiveKind=""
        SelectedID=""
        MaskOverlay=[]
    end
    methods
        function app=VIStudioMeasurementAppV19(visible)
            if nargin<1, visible='on'; end; app.Data=VIStudioMeasurementV17; app.build(); app.UIFigure.Visible=validatestring(char(visible),{'on','off'}); app.refresh();
        end
        function delete(app), app.clearTool(); if ~isempty(app.UIFigure) && isvalid(app.UIFigure), delete(app.UIFigure); end, end
        function loadImage(app,input,name)
            if nargin<3, name="image"; end; app.Data.loadImage(input,name); app.SelectedID=""; app.showImage(); app.refresh();
        end
        function setScale(app,sx,sy), app.Data.setScale(sx,sy); app.SelectedID=""; app.showImage(); app.refresh(); end
        function setProfile(app,profile), app.Data.setProfile(profile); app.SelectedID=""; app.showImage(); app.refresh(); end
        function loadSession(app,file), app.Data.loadSession(file); app.SelectedID=""; app.showImage(); app.refresh(); end
        function place(app,kind,geometry)
            if nargin<3, geometry=[]; end; assert(~isempty(app.ImageHandle),'VIStudioV19:NoImage','Load an image first.'); app.clearTool(); if ~isempty(app.MaskOverlay) && isvalid(app.MaskOverlay), delete(app.MaskOverlay); end; app.MaskOverlay=[]; kind=string(kind); assert(ismember(kind,["distance","caliper","circle","angle","pointline"]),'VIStudioV19:Tool','Use Import mask for mask measurements.'); app.Handles.Kind.Value=char(kind); app.ActiveKind=kind;
            args={}; if ~isempty(geometry), args={'Position',double(geometry)}; end
            switch kind
                case {"distance","caliper"}, app.Tool=uicaliper(app.ImageHandle,args{:},'Width',app.Handles.Width.Value,'Sigma',app.Handles.Sigma.Value,'GradientThreshold',app.Handles.Threshold.Value,'EdgeTransition',char(app.Handles.Polarity.Value),'DisplayProfile',kind=="caliper",'DisplayDistance',false);
                case "circle", app.Tool=uifitcircle(app.ImageHandle,args{:},'Snap',false);
                case "angle", app.Tool=uifitangle(app.ImageHandle,args{:},'Snap',false);
                case "pointline", app.Tool=uitsquare(app.ImageHandle,args{:},'LineSnapMethod','none','PointSnapMethod','none');
            end
            app.Handles.Status.Text='在畫布建立／拖曳工具後，按記錄量測 / Place or drag the native tool, then capture. Canvas coordinates are pixels.';
        end
        function id=capture(app,replace)
            if nargin<2, replace=false; end; assert(~isempty(app.Tool) && isvalid(app.Tool),'VIStudioV19:Tool','Create a measurement tool first.'); o=app.options(); kind=app.ActiveKind;
            if kind=="pointline" && o.Snap, snap(app.Tool,'LineSnapMethod',char(o.LineMethod),'PointSnapMethod','closest','SnapNeighborhood',o.Neighborhood); o.NativeCaptured=true; end
            geometry=double(app.Tool.Position); assert(~isempty(geometry),'VIStudioV19:Tool','Finish placing the tool before capture.');
            if kind=="caliper", o.Width=app.Tool.Width; o.Sigma=app.Tool.Sigma; o.Threshold=app.Tool.GradientThreshold; o.Polarity=string(app.Tool.EdgeTransition); end
            if replace, assert(strlength(app.SelectedID)>0,'VIStudioV19:Selection','Select a measurement row first.'); previous=app.Data.Records(string({app.Data.Records.ID})==app.SelectedID); assert(previous.Definition.Kind==kind,'VIStudioV19:Tool','The selected measurement and active tool types differ.'); app.Data.update(app.SelectedID,geometry,o); id=app.SelectedID; else, id=app.Data.add(kind,geometry,o); end
            app.SelectedID=id; app.refresh(); record=app.Data.Records(string({app.Data.Records.ID})==id); app.Handles.Status.Text=record.Decision+" / "+record.Method+" · "+record.Message;
            if record.State=="MEASURED" && isfield(record.Details,'Position') && ~islogical(record.Details.Position), app.Tool.Position=record.Details.Position; end
        end
        function addMask(app,kind,mask,options)
            if nargin<4, options=app.options(); end; app.clearTool(); app.SelectedID=app.Data.add(kind,mask,options); app.showMask(mask); app.refresh();
        end
        function demo(app)
            [image,definitions,~]=VIStudioMeasurementDemoV17; app.loadImage(image,'synthetic-metrology-demo'); for k=1:numel(definitions), s=definitions{k}; app.Data.add(s.Kind,s.Geometry,s.Options); end; app.refresh(); app.place('caliper',definitions{1}.Geometry); app.Handles.Name.Value='Plate width'; app.Handles.Status.Text='合成示例：量測流程驗證，非實體精度保證 / Synthetic workflow demonstration; not a physical accuracy benchmark';
        end
        function refresh(app)
            app.Handles.Results.Data=app.Data.table(); if isempty(app.Data.Image), app.Handles.Source.Text='尚未載入影像 / No image'; app.Handles.Calibration.Text='單位 / Units: px'; else, app.Handles.Source.Text=app.Data.SourceName+" · "+string(size(app.Data.Image,2))+" × "+string(size(app.Data.Image,1)); app.Handles.Calibration.Text="結果單位 / Result units: "+app.Data.Unit+" · X/Y "+join(string(app.Data.Scale)," / ")+" · 原生畫布標籤為 px / canvas labels use pixels"; end
        end
    end
    methods (Access=private)
        function build(app)
            p=VIStudioThemeV19.palette(); app.UIFigure=uifigure('Name','VIStudio V19 | 獨立量測 Measurement','Visible','off','Position',[50 40 1460 940],'Color',p.Canvas,'CloseRequestFcn',@(~,~) app.close()); root=uigridlayout(app.UIFigure,[5 1],'RowHeight',{56,38,52,'1x',36},'Padding',[10 8 10 8],'RowSpacing',8);
            brand=uigridlayout(root,[1 3],'ColumnWidth',{190,'1x',150},'BackgroundColor',p.Navy,'Padding',[8 0 8 0]); uiimage(brand,'ImageSource',VIStudioThemeV19.logo(),'ScaleMethod','fit'); uilabel(brand,'Text','V19 · 量測工作室 / Measurement Studio','FontSize',19,'FontWeight','bold','FontColor',[1 1 1]); uibutton(brand,'Text','首頁 / Home','ButtonPushedFcn',@(~,~) VIStudioV19);
            bar=uigridlayout(root,[1 7],'Padding',[0 0 0 0]); uibutton(bar,'Text','載入影像 / Image','ButtonPushedFcn',@(~,~) app.action(@() app.pickImage())); uibutton(bar,'Text','示例 / Demo','ButtonPushedFcn',@(~,~) app.action(@() app.demoUI())); uibutton(bar,'Text','開啟工作 / Open','ButtonPushedFcn',@(~,~) app.action(@() app.pickSession())); uibutton(bar,'Text','另存工作 / Save','ButtonPushedFcn',@(~,~) app.action(@() app.saveSessionUI())); uibutton(bar,'Text','匯出報告 / Export','ButtonPushedFcn',@(~,~) app.action(@() app.exportUI())); uibutton(bar,'Text','復原 / Undo','ButtonPushedFcn',@(~,~) app.action(@() app.history(false))); uibutton(bar,'Text','重做 / Redo','ButtonPushedFcn',@(~,~) app.action(@() app.history(true)));
            info=uigridlayout(root,[2 1],'RowHeight',{24,22},'Padding',[0 0 0 0],'RowSpacing',0); app.Handles.Source=uilabel(info,'Text',''); app.Handles.Calibration=uilabel(info,'Text','','FontSize',11,'FontColor',p.Muted);
            body=uigridlayout(root,[2 2],'RowHeight',{'1x',160},'ColumnWidth',{'1x',350},'Padding',[0 0 0 0]); app.Handles.ViewPanel=uipanel(body,'Title','影像與原生工具 / Image & native tools'); app.Viewer=viewer2d('Parent',app.Handles.ViewPanel);
            tabs=uitabgroup(body); page=uitab(tabs,'Title','工具 / Tools'); g=uigridlayout(page,[19 2],'RowHeight',repmat({30},1,19),'ColumnWidth',{'1x','1x'},'Scrollable','on','Padding',[8 6 8 6]);
            app.Handles.Kind=uidropdown(g,'Items',{'距離 / Distance','卡尺邊距 / Caliper','圓徑 / Diameter','角度 / Angle','點到線 / Point-line','遮罩面積 / Area','旋轉長邊 / Length','旋轉短邊 / Width'},'ItemsData',{'distance','caliper','circle','angle','pointline','area','length','width'},'Value','caliper'); app.Handles.Kind.Layout.Column=[1 2]; app.Handles.Name=uieditfield(g,'text','Value','Measurement 1','Placeholder','量測名稱 / Name'); app.Handles.Name.Layout.Column=[1 2];
            uibutton(g,'Text','放置工具 / Place','ButtonPushedFcn',@(~,~) app.action(@() app.place(app.Handles.Kind.Value))); uibutton(g,'Text','匯入遮罩 / Mask','ButtonPushedFcn',@(~,~) app.action(@() app.pickMask()));
            uibutton(g,'Text','記錄量測 / Capture','ButtonPushedFcn',@(~,~) app.action(@() app.capture())); uibutton(g,'Text','更新所選 / Update','ButtonPushedFcn',@(~,~) app.action(@() app.capture(true)));
            app.Handles.Snap=uicheckbox(g,'Text','吸附邊緣 / Snap','Value',true); app.Handles.Polarity=uidropdown(g,'Items',{'both','rising','falling'}); uilabel(g,'Text','掃描寬 px / Width'); app.Handles.Width=uieditfield(g,'numeric','Value',8,'Limits',[0 200]); uilabel(g,'Text','平滑 / Sigma'); app.Handles.Sigma=uieditfield(g,'numeric','Value',1,'Limits',[0 20]); uilabel(g,'Text','梯度門檻 / Threshold'); app.Handles.Threshold=uieditfield(g,'numeric','Value',.1,'Limits',[eps 1]); uilabel(g,'Text','邊對序號 / Pair index'); app.Handles.PairIndex=uieditfield(g,'numeric','Value',1,'Limits',[1 1000]);
            app.Handles.LineMethod=uidropdown(g,'Items',{'closest','strongest','parallel','combined'}); app.Handles.Neighborhood=uieditfield(g,'numeric','Value',20,'Limits',[1 200],'Tooltip','搜尋半徑 px / Snap neighborhood');
            uilabel(g,'Text','下限 / Lower'); app.Handles.Lower=uieditfield(g,'text','Placeholder','空白＝不限制 / None'); uilabel(g,'Text','上限 / Upper'); app.Handles.Upper=uieditfield(g,'text','Placeholder','空白＝不限制 / None');
            uibutton(g,'Text','套用公差 / Limits','ButtonPushedFcn',@(~,~) app.action(@() app.limitsUI())); uibutton(g,'Text','刪除所選 / Delete','ButtonPushedFcn',@(~,~) app.action(@() app.removeUI()));
            uibutton(g,'Text','另存配方 / Recipe','ButtonPushedFcn',@(~,~) app.action(@() app.saveRecipeUI())); uibutton(g,'Text','套用配方 / Apply','ButtonPushedFcn',@(~,~) app.action(@() app.pickRecipe()));
            uibutton(g,'Text','批次量測 / Batch','ButtonPushedFcn',@(~,~) app.action(@() app.batchUI())); uibutton(g,'Text','清除量測 / Clear','ButtonPushedFcn',@(~,~) app.action(@() app.clearUI()));
            h=uilabel(g,'Text','卡尺固定使用原生邊對偵測；Snap 控制圓、角度與點到線。放置後可拖曳，按 Capture 保存；未量測成功不判 OK。','WordWrap','on','FontSize',10); h.Layout.Column=[1 2]; h.Layout.Row=[16 19];
            page=uitab(tabs,'Title','校正 / Calibration'); g=uigridlayout(page,[10 2],'RowHeight',repmat({34},1,10),'Scrollable','on'); uilabel(g,'Text','X mm/px'); app.Handles.ScaleX=uieditfield(g,'numeric','Value',.1,'Limits',[eps Inf]); uilabel(g,'Text','Y mm/px'); app.Handles.ScaleY=uieditfield(g,'numeric','Value',.1,'Limits',[eps Inf]);
            h=uibutton(g,'Text','套用比例 / Apply scale','ButtonPushedFcn',@(~,~) app.action(@() app.scaleUI())); h.Layout.Column=[1 2]; h=uibutton(g,'Text','以目前線段校正 / Reference line','ButtonPushedFcn',@(~,~) app.action(@() app.referenceUI())); h.Layout.Column=[1 2]; h=uibutton(g,'Text','載入透視／鏡頭 MAT / Geometry','ButtonPushedFcn',@(~,~) app.action(@() app.profileUI())); h.Layout.Column=[1 2]; h=uibutton(g,'Text','回到原圖像素 / Reset calibration','ButtonPushedFcn',@(~,~) app.action(@() app.resetUI())); h.Layout.Column=[1 2]; h=uilabel(g,'Text','更換校正會清空量測，可 Undo。實體精度取決於鏡頭、拍攝平面與校正；圓徑 mm 要求等向比例。 / Calibration changes clear results; Undo restores them.','WordWrap','on'); h.Layout.Column=[1 2]; h.Layout.Row=[7 10];
            app.Handles.Results=uitable(body,'SelectionType','row','ColumnWidth',{110,130,75,75,55,65,65,100,130,'auto'},'CellSelectionCallback',@(~,e) app.select(e)); app.Handles.Results.Layout.Row=2; app.Handles.Results.Layout.Column=[1 2]; app.Handles.Status=uilabel(root,'Text','載入影像後開始量測 / Load an image to start','WordWrap','on','FontSize',11); VIStudioThemeV19.apply(root);
        end
        function o=options(app)
            o=struct('Name',string(app.Handles.Name.Value),'Lower',app.limit(app.Handles.Lower.Value),'Upper',app.limit(app.Handles.Upper.Value),'Snap',logical(app.Handles.Snap.Value),'Width',app.Handles.Width.Value,'Sigma',app.Handles.Sigma.Value,'Threshold',app.Handles.Threshold.Value,'Polarity',string(app.Handles.Polarity.Value),'PairIndex',app.Handles.PairIndex.Value,'Neighborhood',app.Handles.Neighborhood.Value,'LineMethod',string(app.Handles.LineMethod.Value));
        end
        function showImage(app)
            app.clearTool(); if ~isempty(app.Viewer) && isvalid(app.Viewer), delete(app.Viewer); end; app.MaskOverlay=[]; app.ImageHandle=[]; app.Viewer=viewer2d('Parent',app.Handles.ViewPanel); app.ImageHandle=imageshow(app.Data.Image,'Parent',app.Viewer);
        end
        function showMask(app,mask)
            if ~isempty(app.MaskOverlay) && isvalid(app.MaskOverlay), delete(app.MaskOverlay); end; color=zeros([size(mask) 3],'single'); color(:,:,2)=.8; color(:,:,3)=.7; app.MaskOverlay=imageshow(color,'Parent',app.Viewer,'AlphaData',single(mask)*.35);
        end
        function clearTool(app)
            if ~isempty(app.Viewer) && isvalid(app.Viewer), annotations=app.Viewer.Annotations; if ~isempty(annotations), app.Viewer.Annotations=annotations([]); end, end
            if ~isempty(app.Tool) && isvalid(app.Tool), delete(app.Tool); end; app.Tool=[]; app.ActiveKind=""; drawnow;
        end
        function history(app,redo), if redo, app.Data.redo(); else, app.Data.undo(); end; app.SelectedID=""; if ~isempty(app.Data.Image), app.showImage(); end; app.refresh(); end
        function select(app,event)
            if isempty(event.Indices), return; end; row=event.Indices(1,1); r=app.Data.Records(row); app.SelectedID=r.ID; s=r.Definition; app.Handles.Name.Value=char(s.Name); app.Handles.Lower.Value=app.limitText(s.Lower); app.Handles.Upper.Value=app.limitText(s.Upper); app.Handles.Kind.Value=char(s.Kind); app.Handles.Snap.Value=s.Snap; app.Handles.Width.Value=s.Width; app.Handles.Sigma.Value=s.Sigma; app.Handles.Threshold.Value=s.Threshold; app.Handles.Polarity.Value=char(s.Polarity); app.Handles.PairIndex.Value=s.PairIndex; app.Handles.Neighborhood.Value=s.Neighborhood; app.Handles.LineMethod.Value=char(s.LineMethod);
            if islogical(s.Geometry), app.clearTool(); app.showMask(s.Geometry); else, g=s.Geometry; if isfield(r.Details,'Position'), g=r.Details.Position; end; app.action(@() app.place(s.Kind,g)); end
        end
        function pickImage(app), if ~app.confirmReplace(), return; end; [f,p]=uigetfile({'*.png;*.jpg;*.jpeg;*.tif;*.tiff;*.bmp','Images'}); if ~isequal(f,0), app.loadImage(fullfile(p,f)); end, end
        function pickSession(app), if ~app.confirmReplace(), return; end; [f,p]=uigetfile('*.mat'); if ~isequal(f,0), app.loadSession(fullfile(p,f)); end, end
        function demoUI(app), if app.confirmReplace(), app.demo(); end, end
        function saveSessionUI(app), [f,p]=uiputfile('*.mat'); if ~isequal(f,0), app.Data.saveSession(fullfile(p,f)); end, end
        function exportUI(app), p=uigetdir(pwd); if ~isequal(p,0), folder=tempname(p); app.Data.export(folder); app.Handles.Status.Text="已匯出 / Exported: "+string(folder); end, end
        function pickMask(app)
            assert(ismember(string(app.Handles.Kind.Value),["area","length","width"]),'VIStudioV19:Mask','Choose area, length, or width first.'); [f,p]=uigetfile({'*.png;*.tif;*.bmp','Binary masks'}); if isequal(f,0), return; end; mask=imread(fullfile(p,f)); values=unique(mask); assert(ismatrix(mask) && numel(values)<=2 && (numel(values)<=1 || any(values==0)),'VIStudioV19:Mask','Require a binary grayscale mask with zero background.'); app.addMask(app.Handles.Kind.Value,mask~=0);
        end
        function limitsUI(app), app.Data.setTolerance(app.SelectedID,app.limit(app.Handles.Lower.Value),app.limit(app.Handles.Upper.Value)); app.refresh(); end
        function removeUI(app), app.Data.remove(app.SelectedID); app.SelectedID=""; app.clearTool(); app.refresh(); end
        function saveRecipeUI(app), [f,p]=uiputfile('*.mat'); if ~isequal(f,0), app.Data.saveRecipe(fullfile(p,f)); end, end
        function pickRecipe(app), if ~app.confirmReplace(), return; end; [f,p]=uigetfile('*.mat'); if ~isequal(f,0), app.Data.applyRecipe(fullfile(p,f)); app.SelectedID=""; app.showImage(); app.refresh(); end, end
        function batchUI(app)
            recipe=app.Data.recipe(); assert(~isempty(recipe.Definitions),'VIStudioV19:Recipe','Record at least one measurement first.'); [f,p]=uigetfile({'*.png;*.jpg;*.tif;*.bmp','Images'},'Batch images','MultiSelect','on'); if isequal(f,0), return; end; parent=uigetdir(pwd); if isequal(parent,0), return; end; files=fullfile(p,string(f)); folder=tempname(parent); summary=VIStudioMeasurementV17.batch(recipe,files,folder); app.Handles.Status.Text=sprintf('批次完成 / Batch: %d images · %s',height(summary),folder);
        end
        function scaleUI(app), if app.confirmCalibration(), app.setScale(app.Handles.ScaleX.Value,app.Handles.ScaleY.Value); end, end
        function referenceUI(app)
            assert(~isempty(app.Tool) && isvalid(app.Tool) && any(app.ActiveKind==["distance","caliper"]),'VIStudioV19:Reference','Place a distance/caliper line first.'); points=app.Tool.Position; answer=inputdlg('已知線段長度 mm / Known length (mm)','Reference',1,{'10'}); if isempty(answer), return; end; lengthMM=str2double(answer{1}); if app.confirmCalibration(), app.Data.setReference(points,lengthMM); app.showImage(); app.refresh(); end
        end
        function profileUI(app), [f,p]=uigetfile('*.mat'); if isequal(f,0), return; end; loaded=load(fullfile(p,f),'geometry'); assert(isfield(loaded,'geometry'),'VIStudioV19:Calibration','MAT requires geometry from the existing calibration workspace.'); if app.confirmCalibration(), app.setProfile(loaded.geometry); end, end
        function resetUI(app), if app.confirmCalibration(), app.Data.resetCalibration(); app.showImage(); app.refresh(); end, end
        function clearUI(app), if isempty(app.Data.Records) || strcmp(uiconfirm(app.UIFigure,'清除全部量測？可 Undo。 / Clear measurements? Undo is available.','Clear','Options',{'Clear','Cancel'},'DefaultOption','Cancel'),'Clear'), app.Data.clear(); app.clearTool(); app.refresh(); end, end
        function yes=confirmCalibration(app), yes=isempty(app.Data.Records) || strcmp(uiconfirm(app.UIFigure,'校正變更會清空量測，可 Undo。 / Calibration changes clear measurements. Undo restores them.','Calibration','Options',{'Apply','Cancel'},'DefaultOption','Cancel'),'Apply'); end
        function yes=confirmReplace(app), yes=~app.Data.Dirty || strcmp(uiconfirm(app.UIFigure,'目前尚未保存。要繼續嗎？ / Unsaved changes. Continue?','Unsaved','Options',{'Continue','Cancel'},'DefaultOption','Cancel'),'Continue'); end
        function close(app), if app.confirmReplace(), delete(app); end, end
        function action(app,callback), try, callback(); catch err, app.Handles.Status.Text=string(err.message); if strcmp(char(app.UIFigure.Visible),'off'), rethrow(err); end; uialert(app.UIFigure,err.message,'Measurement','Interpreter','none'); end, end
    end
    methods (Static,Access=private)
        function value=limit(text), if strlength(strtrim(string(text)))==0, value=NaN; else, value=str2double(text); assert(isfinite(value),'VIStudioV19:Limits','Enter a finite limit or leave blank.'); end, end
        function text=limitText(value), text=''; if isfinite(value), text=num2str(value,12); end, end
    end
end
