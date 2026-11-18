classdef VIStudioDefectSynthesisAppV25 < handle
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
        function app=VIStudioDefectSynthesisAppV25(visible)
            if nargin<1, visible='on'; end; app.Data=VIStudioDefectSynthesisV25; app.build(); app.UIFigure.Visible=validatestring(visible,{'on','off'});
        end
        function delete(app), if ~isempty(app.UIFigure) && isvalid(app.UIFigure), delete(app.UIFigure); end, end
        function loadSource(app,input)
            app.Data.setSource(input); app.ROI=[]; imshow(app.Data.Base,'Parent',app.Handles.Source); app.refresh();
        end
        function [image,mask]=generate(app)
            app.applyROI(); app.Data.configure(app.options()); try, [image,mask]=app.Data.generate(); app.refresh(); catch err, app.refresh(); rethrow(err); end
        end
        function demo(app), app.loadSource(VIStudioDefectSynthesisV25.demo()); app.generate(); end
        function result=exportBatch(app,parent,count)
            app.applyROI(); app.Data.configure(app.options()); app.refresh(); cleanup=onCleanup(@() app.setBusy(false)); app.setBusy(true); result=app.Data.exportBatch(parent,count,@(p) app.progress(p)); app.Handles.Rows.Data=result.Rows; app.Handles.Status.Text=result.State+" · "+result.Saved+" samples · "+result.Folder+" · "+result.Message;
        end
        function refresh(app)
            cla(app.Handles.Result); cla(app.Handles.Mask);
            app.Handles.Rows.Data=table(); if ~isempty(app.Data.LastBatch), app.Handles.Rows.Data=app.Data.LastBatch.Rows; end
            if ~isempty(app.Data.Output), imshow(app.Data.Output,'Parent',app.Handles.Result); imshow(app.Data.Mask,'Parent',app.Handles.Mask); end
            app.Handles.Status.Text=app.Data.State+" · 合成資料需覆核；同來源變體不可分散到訓練與測試 / Review synthetic samples; group variants by original source.";
        end
    end
    methods (Access=private)
        function build(app)
            app.UIFigure=uifigure('Name','VIStudio V25 | 影像缺陷合成 Defect Synthesis','Visible','off','Position',[60 50 1440 800],'CloseRequestFcn',@(~,~) app.close());
            g=uigridlayout(app.UIFigure,[5 1],'RowHeight',{42,66,38,'1x',44},'Scrollable','on'); bar=uigridlayout(g,[1 6],'Padding',[0 0 0 0]); labels={'正常影像 / Normal image','貼片來源 / Donor patch','限制 ROI / Restrict ROI','允許遮罩 / Allowed mask','示例 / Demo','停止 / Stop'}; callbacks={@() app.pickSource(),@() app.pickDonor(),@() app.region(),@() app.mask(),@() app.demo(),@() app.Data.requestStop()};
            for k=1:6, cb=callbacks{k}; h=uibutton(bar,'Text',labels{k},'ButtonPushedFcn',@(~,~) app.action(cb)); if k==6, app.Handles.Stop=h; h.ButtonPushedFcn=@(~,~) app.Data.requestStop(); h.Enable='off'; end, end
            options=uigridlayout(g,[2 8],'RowHeight',{24,32},'RowSpacing',4,'Padding',[0 0 0 0]); titles={'缺陷 / Type','數量 / Count','尺寸 px / Size','刮痕長 px / Length','強度 / Contrast','柔邊 σ / Blur','種子 / Seed','明暗 / Polarity'};
            for k=1:8, h=uilabel(options,'Text',titles{k}); h.Layout.Row=1; h.Layout.Column=k; end
            app.Handles.Type=uidropdown(options,'Items',{'scratch','spots','stain','cutpaste'}); app.Handles.Type.Layout.Row=2; app.Handles.Type.Layout.Column=1;
            fields={'Count','Size','Length','Contrast','Blur','Seed'}; values=[3 16 80 .65 .8 20]; for k=1:6, h=uieditfield(options,'numeric','Value',values(k)); h.Layout.Row=2; h.Layout.Column=k+1; app.Handles.(fields{k})=h; end
            app.Handles.Polarity=uidropdown(options,'Items',{'dark','bright'}); app.Handles.Polarity.Layout.Row=2; app.Handles.Polarity.Layout.Column=8;
            bar=uigridlayout(g,[1 4],'ColumnWidth',{200,140,220,'1x'},'Padding',[0 0 0 0]); uibutton(bar,'Text','產生預覽 / Generate','ButtonPushedFcn',@(~,~) app.action(@() app.generate())); app.Handles.Samples=uieditfield(bar,'numeric','Value',10); uibutton(bar,'Text','批次匯出 / Export batch','ButtonPushedFcn',@(~,~) app.action(@() app.pickOutput())); uilabel(bar,'Text','每張自動增加種子；輸出原圖、合成圖、遮罩與清單 / Seeds increment per sample; originals, masks and manifest retained','WordWrap','on');
            body=uigridlayout(g,[2 3],'RowHeight',{'1x',130}); app.Handles.Source=uiaxes(body); title(app.Handles.Source,'正常影像 / Normal'); app.Handles.Result=uiaxes(body); title(app.Handles.Result,'合成預覽 / Synthetic'); app.Handles.Mask=uiaxes(body); title(app.Handles.Mask,'實際變更遮罩 / Changed pixels'); app.Handles.Rows=uitable(body); app.Handles.Rows.Layout.Row=2; app.Handles.Rows.Layout.Column=[1 3];
            app.Handles.Status=uilabel(g,'Text','先載入正常影像 / Load a normal image','WordWrap','on','Interpreter','none'); h=VIStudioThemeV25.install(app.UIFigure,'影像缺陷合成 / Defect Synthesis'); h.Guide.Text='程序式合成，非生成式 AI；遮罩代表儲存影像實際變更像素 / Procedural synthesis, not generative AI. Masks mark actual changed pixels; samples are synthetic and unreviewed.';
        end
        function o=options(app)
            o=app.Data.Options; o.Type=string(app.Handles.Type.Value); for key={'Count','Size','Length','Contrast','Blur','Seed'}, o.(key{1})=app.Handles.(key{1}).Value; end; o.Polarity=string(app.Handles.Polarity.Value);
        end
        function applyROI(app)
            if isempty(app.ROI) || ~isvalid(app.ROI), return; end; p=app.ROI.Position; x=ceil(p(1)); y=ceil(p(2)); x2=floor(p(1)+p(3)); y2=floor(p(2)+p(4)); assert(x>=1 && y>=1 && x2<=size(app.Data.Base,2) && y2<=size(app.Data.Base,1) && x2>=x && y2>=y,'VIStudioV25:SynthesisROI','ROI must stay inside the image.'); m=false(size(app.Data.Base,[1 2])); m(y:y2,x:x2)=true; app.Data.setAllowed(m);
        end
        function region(app)
            assert(~isempty(app.Data.Base),'VIStudioV25:SynthesisSource','Load a normal image.'); if ~isempty(app.ROI) && isvalid(app.ROI), delete(app.ROI); end; sz=size(app.Data.Base,[1 2]); app.ROI=drawrectangle(app.Handles.Source,'Position',[sz(2)*.2 sz(1)*.2 sz(2)*.6 sz(1)*.6],'Color',[.1 .8 .7]);
        end
        function mask(app)
            [f,p]=uigetfile({'*.png;*.tif;*.bmp','Binary allowed mask'}); if isequal(f,0), return; end; m=imread(fullfile(p,f)); assert(ismatrix(m) && numel(unique(m))<=2,'VIStudioV25:SynthesisMask','Use a binary mask.'); app.Data.setAllowed(m~=0); if ~isempty(app.ROI) && isvalid(app.ROI), delete(app.ROI); end; app.ROI=[]; app.refresh();
        end
        function pickSource(app), [f,p]=uigetfile({'*.png;*.jpg;*.tif;*.bmp','Normal image'}); if ~isequal(f,0), app.loadSource(fullfile(p,f)); end, end
        function pickDonor(app), [f,p]=uigetfile({'*.png;*.jpg;*.tif;*.bmp','Donor patch'}); if ~isequal(f,0), app.Data.setDonor(fullfile(p,f)); app.refresh(); end, end
        function pickOutput(app), p=uigetdir(pwd); if ~isequal(p,0), app.exportBatch(p,app.Handles.Samples.Value); end, end
        function progress(app,p), app.Handles.Status.Text=sprintf('%d / %d synthetic samples',p.Saved,p.Total); drawnow limitrate; end
        function setBusy(app,value)
            app.Busy=value; if ~isvalid(app.UIFigure), return; end; state='on'; if value, state='off'; end
            for h=reshape(findall(app.UIFigure),1,[]), if isprop(h,'Enable'), h.Enable=state; end, end
            app.Handles.Stop.Enable=matlab.lang.OnOffSwitchState(value); h=getappdata(app.UIFigure,'VIStudioThemeV25'); h.Sync.Enable='off'; if ~value && app.CloseAfterStop, delete(app); end
        end
        function close(app), if app.Busy, app.CloseAfterStop=true; app.Data.requestStop(); else, delete(app); end, end
        function action(app,callback)
            if app.Busy, return; end; try, callback(); catch err, app.Handles.Status.Text=string(err.message); if strcmp(app.UIFigure.Visible,'off'), rethrow(err); end; uialert(app.UIFigure,err.message,'VIStudio V25','Interpreter','none'); end
        end
    end
end
