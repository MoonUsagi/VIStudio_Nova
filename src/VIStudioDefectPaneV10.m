classdef VIStudioDefectPaneV10 < handle
    properties (SetAccess=private)
        SettingsPanel
        Handles=struct()
        Report=[]
    end
    properties (Access=private)
        Controls=struct()
        Callbacks
        Image=[]
        Options
        Language='bilingual'
    end
    methods
        function pane=VIStudioDefectPaneV10(tab,body,callbacks)
            pane.Callbacks=callbacks; pane.Options=VIStudioDefectsV10.defaults();
            pane.SettingsPanel=uipanel(body,'Title','量測與規則 / Measurement & Rules','Visible','off'); pane.SettingsPanel.Layout.Row=1; pane.SettingsPanel.Layout.Column=1;
            settings=uigridlayout(pane.SettingsPanel,[28 2],'RowHeight',repmat({30},1,28),'ColumnWidth',{190,'1x'},'Scrollable','on');
            specs={ 'Enabled','啟用規則 / Enable rules','bool'; 'Connectivity','連通性 / Connectivity',{4,8}; ...
                'MinRegionAreaPx','最小保留面積 px / Min area',[]; 'FillHoles','填補內孔 / Fill holes','bool'; ...
                'IgnoreBorder','排除 ROI 邊界 / Ignore border','bool'; 'ScaleEnabled','實際尺寸 / Physical scale','bool'; ...
                'MMPerPixelX','水平 mm/px / X scale',[]; 'MMPerPixelY','垂直 mm/px / Y scale',[]; ...
                'LimitUnit','規則單位 / Limit unit',{'px','mm'}; 'UseCount','檢查區域數 / Check count','bool'; ...
                'MaxRegions','最多區域數 / Max regions',[]; 'UseTotalArea','檢查總面積 / Total area','bool'; ...
                'MaxTotalArea','總面積上限 / Max total area',[]; 'UseRegionArea','檢查單區面積 / Region area','bool'; ...
                'MaxRegionArea','單區面積上限 / Max area',[]; 'UseWidth','檢查外接框寬 / Check width','bool'; ...
                'MaxWidth','外接框寬上限 / Max width',[]; 'UseHeight','檢查外接框高 / Check height','bool'; ...
                'MaxHeight','外接框高上限 / Max height',[]; 'UseImageScore','分數達門檻亦 NG / Score rule','bool'};
            for k=1:size(specs,1)
                field=specs{k,1}; label=uilabel(settings,'Text',specs{k,2},'WordWrap','on'); label.Layout.Row=k; label.Layout.Column=1;
                if isequal(specs{k,3},'bool'), control=uicheckbox(settings,'Text','');
                elseif strcmp(field,'Connectivity'), control=uidropdown(settings,'Items',{'4','8'},'ItemsData',[4 8]);
                elseif strcmp(field,'LimitUnit'), control=uidropdown(settings,'Items',{'px','mm'});
                else, control=uieditfield(settings,'numeric','Limits',[0 realmax]); end
                pane.Controls.(field)=control; control.Layout.Row=k; control.Layout.Column=2;
            end
            button=uibutton(settings,'Text','套用並重算 / Apply & recompute','ButtonPushedFcn',@(~,~) pane.action(@() pane.apply())); button.Layout.Row=21; button.Layout.Column=[1 2];
            label=uilabel(settings,'Text','已知長度 mm / Reference mm'); label.Layout.Row=22;
            pane.Handles.ReferenceMM=uieditfield(settings,'numeric','Value',10,'Limits',[eps realmax]); pane.Handles.ReferenceMM.Layout.Row=22; pane.Handles.ReferenceMM.Layout.Column=2;
            button=uibutton(settings,'Text','畫參考線校正 / Draw reference','ButtonPushedFcn',@(~,~) pane.action(@() pane.reference())); button.Layout.Row=23; button.Layout.Column=[1 2];
            note=uilabel(settings,'Text','面積：px² / mm²；長寬：px / mm。長寬為軸對齊外接框。參考線假設 X/Y 比例相同；更換相機或縮放後需重新校正。 / Area uses squared units; dimensions are axis-aligned. Recalibrate when imaging geometry changes.','WordWrap','on'); note.Layout.Row=[24 28]; note.Layout.Column=[1 2];
            grid=uigridlayout(tab,[5 1],'RowHeight',{34,50,'1x',120,60});
            bar=uigridlayout(grid,[1 5],'Padding',[0 0 0 0]);
            pane.Handles.Measure=uibutton(bar,'Text','檢測目前影像 / Inspect current','ButtonPushedFcn',@(~,~) pane.action(@() callbacks.Predict()));
            uibutton(bar,'Text','載入規則 / Load rules','ButtonPushedFcn',@(~,~) pane.action(@() pane.load()));
            uibutton(bar,'Text','另存規則 / Save rules','ButtonPushedFcn',@(~,~) pane.action(@() pane.save()));
            pane.Handles.Export=uibutton(bar,'Text','匯出量測 / Export report','Enable','off','ButtonPushedFcn',@(~,~) pane.action(@() pane.export()));
            pane.Handles.BatchExport=uibutton(bar,'Text','批次報告 / Batch reports','Enable','off','ButtonPushedFcn',@(~,~) pane.action(@() pane.Callbacks.ExportBatch()));
            pane.Handles.Summary=uilabel(grid,'Text','等待影像及像素門檻 / Waiting for an image and pixel threshold','FontWeight','bold','FontSize',16,'WordWrap','on');
            pane.Handles.Image=uiaxes(grid); pane.Handles.Image.Toolbar.Visible='off';
            pane.Handles.Regions=uitable(grid,'SelectionType','row','CellSelectionCallback',@(~,e) pane.select(e));
            pane.Handles.Reasons=uitextarea(grid,'Editable','off'); pane.sync(pane.Options);
        end
        function setLanguage(pane,language)
            pane.Language=validatestring(language,{'bilingual','zh','en'});
            if isempty(pane.Report), pane.source(pane.Image); else, pane.show(pane.Image,pane.Report); end
        end
        function sync(pane,o)
            pane.Options=o;
            for field=fieldnames(pane.Controls)', pane.Controls.(field{1}).Value=o.(field{1}); end
        end
        function source(pane,image)
            pane.Image=image; pane.Report=[]; pane.Handles.Regions.Data=[]; pane.Handles.Reasons.Value={''}; pane.Handles.Export.Enable='off';
            pane.Handles.Summary.Text=pane.caption('請執行檢測','Run inspection to measure defects'); cla(pane.Handles.Image);
            if ~isempty(image), imshow(image,'InitialMagnification','fit','Parent',pane.Handles.Image); title(pane.Handles.Image,pane.caption('原始影像','Source image')); end
        end
        function show(pane,image,report)
            pane.Image=image; pane.Report=report;
            fields={'ID','AreaPx','WidthPx','HeightPx','XPx','YPx','AreaPercent','RegionRuleState','Violations','MaxScore','MeanScore'};
            if report.Options.ScaleEnabled, fields(2:4)={'AreaMM2','WidthMM','HeightMM'}; end
            data=report.Regions(:,fields); data.Violations=pane.localize(data.Violations); pane.Handles.Regions.Data=data;
            pane.Handles.Regions.ColumnWidth={45,85,85,85,60,60,80,150,200,90,90};
            verdict=report.Decision; if verdict=="DISABLED", verdict=pane.caption('未啟用規則','Rules disabled'); elseif verdict=="REVIEW", verdict=pane.caption('待確認','Review'); end
            if report.Available
                area=string(report.TotalAreaPx)+" px²"; if report.Options.ScaleEnabled, area=area+sprintf(' / %.5g mm²',report.TotalAreaMM2); end
                pane.Handles.Summary.Text=sprintf('%s | %s: %g | %s: %s | ROI coverage %.3g%%',verdict,pane.caption('區域數','Regions'),report.Count,pane.caption('面積','Area'),area,report.AreaPercent);
            else
                pane.Handles.Summary.Text=verdict+" | "+pane.caption('無像素遮罩，尚無量測值','No pixel mask; measurements unavailable');
            end
            color=[.08 .45 .35]; if report.Decision=="NG", color=[.8 .15 .12]; elseif report.Decision=="REVIEW", color=[.7 .4 .05]; end
            pane.Handles.Summary.FontColor=color;
            audit=sprintf('原始 / Raw: %g px, %d regions · 小區域移除 / Small removed: %d · 邊界移除 / Border removed: %d · 填孔 / Filled: %d px',report.RawAreaPx,report.RawRegions,report.RemovedSmall,report.RemovedBorder,report.FilledPixels);
            reasons=report.Reasons; if isempty(reasons), reasons="沒有超過已啟用的限制 / No enabled limits exceeded"; end
            if report.Decision=="DISABLED", reasons="規則未啟用；僅顯示量測 / Rules disabled; measurements only"; end
            pane.Handles.Reasons.Value=pane.localize([reasons(:);string(audit)]);
            imshow(VIStudioDefectsV10.overlay(image,report),'InitialMagnification','fit','Parent',pane.Handles.Image);
            title(pane.Handles.Image,pane.caption('原圖座標；前五區標籤','Original coordinates; labels for five largest regions')); pane.Handles.Export.Enable='on';
        end
        function busy(pane,value,hasBatch)
            if nargin<3, hasBatch=false; end
            objects=[findall(pane.SettingsPanel);findall(pane.Handles.Image.Parent)];
            state='on'; if value, state='off'; end
            for h=reshape(objects,1,[]), if isprop(h,'Enable'), h.Enable=state; end, end
            if ~value
                pane.Handles.Export.Enable=matlab.lang.OnOffSwitchState(~isempty(pane.Report));
                pane.Handles.BatchExport.Enable=matlab.lang.OnOffSwitchState(hasBatch);
            end
        end
    end
    methods (Access=private)
        function text=caption(pane,zh,en), text=VIStudioToolsV3.translate(string(zh)+" / "+string(en),pane.Language); end
        function value=localize(pane,value)
            value=string(value); if strcmp(pane.Language,'bilingual'), return; end
            phrases={ '區域數','Regions'; '總面積','Total area'; '單區面積','Region area'; '外接框寬','Bounding width'; ...
                '外接框高','Bounding height'; '區域','Region'; '原始','Raw'; '小區域移除','Small removed'; '邊界移除','Border removed'; '填孔','Filled'};
            for k=1:size(phrases,1)
                full=string(phrases{k,1})+" / "+string(phrases{k,2}); value=replace(value,full,pane.caption(phrases{k,1},phrases{k,2}));
            end
            value=VIStudioToolsV3.translate(value,pane.Language);
        end
        function apply(pane)
            options=struct(); for field=fieldnames(pane.Controls)', options.(field{1})=pane.Controls.(field{1}).Value; end
            candidate=VIStudioDefectsV10.options(options); pane.Callbacks.Configure(candidate);
        end
        function reference(pane)
            assert(~isempty(pane.Image),'VIStudioV10:MissingImage','Load an image before calibrating scale.');
            object=drawline(pane.Handles.Image); cleanup=onCleanup(@() delete(object)); points=wait(object);
            assert(~isempty(points),'VIStudioV10:Cancelled','Reference calibration cancelled.'); pane.Callbacks.Reference(points,pane.Handles.ReferenceMM.Value);
        end
        function select(pane,event)
            if isempty(event.Indices) || isempty(pane.Report), return; end
            row=event.Indices(1,1); pane.show(pane.Image,pane.Report); r=pane.Report.Regions(row,:);
            hold(pane.Handles.Image,'on'); rectangle(pane.Handles.Image,'Position',[r.XPx-.5 r.YPx-.5 r.WidthPx r.HeightPx],'EdgeColor','yellow','LineWidth',3); hold(pane.Handles.Image,'off');
        end
        function load(pane)
            [file,path]=uigetfile('*.mat','Load inspection rules'); if isequal(file,0), return; end; pane.Callbacks.Load(fullfile(path,file));
        end
        function save(pane)
            [file,path]=uiputfile('*.mat','Save inspection rules'); if isequal(file,0), return; end; pane.Callbacks.Save(fullfile(path,file));
        end
        function export(pane)
            assert(~isempty(pane.Report),'VIStudioV10:MissingMeasurement','Run an inspection first.');
            parent=uigetdir(pwd,'Select report parent folder'); if isequal(parent,0), return; end
            [~,name]=fileparts(tempname(parent)); pane.Callbacks.Export(fullfile(parent,['measurement_' name]));
        end
        function action(pane,callback)
            try, callback(); catch err
                pane.sync(pane.Options); uialert(ancestor(pane.Handles.Image,'figure'),err.message,'缺陷量測 / Defect measurement','Interpreter','none');
            end
        end
    end
end
