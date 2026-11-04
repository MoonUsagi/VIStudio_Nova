classdef VIStudioDatasetPaneV9 < handle
    properties (SetAccess=private)
        Handles=struct()
    end
    properties (Access=private)
        Data
        Callbacks
        Visible=[]
    end
    methods
        function pane=VIStudioDatasetPaneV9(tab,data,callbacks)
            pane.Data=data; pane.Callbacks=callbacks;
            grid=uigridlayout(tab,[6 2],'RowHeight',{34,34,120,36,'1x',125},'ColumnWidth',{'1x','1x'});
            bar=uigridlayout(grid,[1 5],'ColumnWidth',{185,160,75,185,75},'Padding',[0 0 0 0]); bar.Layout.Column=[1 2];
            pane.Handles.Mode=uidropdown(bar,'Items',{'自動群組切分 / Automatic','指定資料來源 / Explicit'},'ItemsData',{'automatic','explicit'}, ...
                'ValueChangedFcn',@(~,~) pane.change());
            uilabel(bar,'Text','測試比例 % / Test %'); pane.Handles.Test=uieditfield(bar,'numeric','Value',0,'Limits',[0 50],'ValueChangedFcn',@(~,~) pane.change());
            uilabel(bar,'Text','校準比例 % / Calibration %'); pane.Handles.Calibration=uieditfield(bar,'numeric','Value',0,'Limits',[0 50],'ValueChangedFcn',@(~,~) pane.change());
            bar=uigridlayout(grid,[1 6],'Padding',[0 0 0 0]); bar.Layout.Column=[1 2];
            pane.Handles.Role=uidropdown(bar,'Items',{'訓練 / Train','驗證 / Validation','測試 / Test','校準 / Calibration'},'ItemsData',{'train','validation','test','calibration'});
            uibutton(bar,'Text','指定來源 / Set source','ButtonPushedFcn',@(~,~) pane.action(@() pane.pickSource()));
            uibutton(bar,'Text','清除來源 / Clear','ButtonPushedFcn',@(~,~) pane.action(@() pane.clearSource()));
            uibutton(bar,'Text','群組 CSV / Group CSV','ButtonPushedFcn',@(~,~) pane.action(@() pane.pickGroups()));
            uibutton(bar,'Text','清除群組 / Clear groups','ButtonPushedFcn',@(~,~) pane.action(@() pane.clearGroups()));
            uibutton(bar,'Text','建立計畫 / Build plan','ButtonPushedFcn',@(~,~) pane.action(@() pane.Callbacks.Build()));
            pane.Handles.Sources=uitable(grid); pane.Handles.Sources.Layout.Row=3; pane.Handles.Sources.Layout.Column=[1 2];
            pane.Handles.Summary=uilabel(grid,'Text','先載入訓練資料，再建立切分計畫 / Load training data, then build a plan','WordWrap','on'); pane.Handles.Summary.Layout.Row=4; pane.Handles.Summary.Layout.Column=[1 2];
            pane.Handles.Chart=uiaxes(grid); pane.Handles.Chart.Layout.Row=5;
            pane.Handles.Preview=uiaxes(grid); pane.Handles.Preview.Layout.Row=5; pane.Handles.Preview.Layout.Column=2;
            pane.Handles.Chart.Toolbar.Visible='off'; pane.Handles.Preview.Toolbar.Visible='off';
            lower=uigridlayout(grid,[2 1],'RowHeight',{35,'1x'},'Padding',[0 0 0 0]); lower.Layout.Row=6; lower.Layout.Column=[1 2];
            bar=uigridlayout(lower,[1 4],'Padding',[0 0 0 0]);
            pane.Handles.Filter=uidropdown(bar,'Items',{'all','train','validation','test','calibration'},'ValueChangedFcn',@(~,~) pane.filter());
            uibutton(bar,'Text','送測試集檢測 / Inspect test','ButtonPushedFcn',@(~,~) pane.action(@() pane.Callbacks.Use('test')));
            pane.Handles.UseCalibration=uibutton(bar,'Text','送校準集 / Use calibration','Enable',matlab.lang.OnOffSwitchState(data.Task=="anomaly"),'ButtonPushedFcn',@(~,~) pane.action(@() pane.Callbacks.Use('calibration')));
            uibutton(bar,'Text','匯出清單 / Export manifest','ButtonPushedFcn',@(~,~) pane.action(@() pane.export()));
            pane.Handles.Manifest=uitable(lower,'CellSelectionCallback',@(~,e) pane.preview(e)); pane.sync();
        end
        function sync(pane)
            config=pane.Data.Config; pane.Handles.Mode.Value=char(config.Mode); pane.Handles.Test.Value=config.TestPercent; pane.Handles.Calibration.Value=config.CalibrationPercent;
            role=["train";"validation";"test";"calibration"]; source=strings(4,1);
            for k=1:4, source(k)=config.Sources.(role(k)); end
            used=strlength(source)>0 & (role=="train" | config.Mode=="explicit");
            pane.Handles.Sources.Data=table(role,used,source,'VariableNames',{'Role','Used','Source'});
            pane.Handles.Sources.ColumnWidth={90,55,'auto'};
            pane.Handles.Test.Enable=matlab.lang.OnOffSwitchState(config.Mode=="automatic"); pane.Handles.Calibration.Enable=pane.Handles.Test.Enable;
            pane.Handles.UseCalibration.Enable=matlab.lang.OnOffSwitchState(pane.Data.Task=="anomaly");
            pane.Handles.Summary.Text="設定尚待建立計畫 / Build plan to apply settings · Group CSV: "+string(config.GroupFile);
            pane.Handles.Manifest.Data=[]; cla(pane.Handles.Chart); cla(pane.Handles.Preview);
        end
        function show(pane,plan)
            pane.Handles.Summary.Text=sprintf('錯誤 / Errors: %d · 警告 / Warnings: %d · 資料版本 / Dataset: %s',plan.Health.Errors,plan.Health.Warnings,plan.Fingerprint);
            if pane.Data.Task=="anomaly" && any(plan.Manifest.Split=="validation")
                pane.Handles.Summary.Text=pane.Handles.Summary.Text+newline+"異常驗證集目前僅保留，不參與模型挑選 / Anomaly validation is reserved, not used for model selection";
            end
            cla(pane.Handles.Chart); rows=plan.Counts.Images>0;
            labels=plan.Counts.Split(rows)+" ("+string(plan.Counts.Images(rows))+")";
            pie(pane.Handles.Chart,plan.Counts.Images(rows),cellstr(labels)); title(pane.Handles.Chart,'資料用途分布 / Dataset roles');
            pane.filter();
        end
    end
    methods (Access=private)
        function change(pane)
            pane.Data.configure(struct('Mode',string(pane.Handles.Mode.Value),'TestPercent',pane.Handles.Test.Value,'CalibrationPercent',pane.Handles.Calibration.Value)); pane.sync(); pane.Callbacks.Changed();
        end
        function pickSource(pane)
            if pane.Data.Task=="detection"
                [file,path]=uigetfile('*.mat','Select annotations'); if isequal(file,0), return; end; path=fullfile(path,file);
            else, path=uigetdir(pwd,'Select dataset folder'); if isequal(path,0), return; end, end
            pane.Callbacks.Source(string(pane.Handles.Role.Value),path); pane.sync(); pane.Callbacks.Changed();
        end
        function clearSource(pane)
            assert(string(pane.Handles.Role.Value)~="train",'VIStudioV9:DatasetTrain','Replace training data using Set source.');
            pane.Data.setSource(pane.Handles.Role.Value,""); pane.sync();
        end
        function pickGroups(pane)
            [file,path]=uigetfile('*.csv','Group mapping: File,Group'); if isequal(file,0), return; end
            pane.Data.configure(struct('GroupFile',string(fullfile(path,file)))); pane.sync();
        end
        function clearGroups(pane), pane.Data.configure(struct('GroupFile',"")); pane.sync(); end
        function filter(pane)
            if isempty(pane.Data.Plan), return; end
            m=pane.Data.Plan.Manifest; role=string(pane.Handles.Filter.Value); rows=true(height(m),1); if role~="all", rows=m.Split==role; end
            pane.Visible=m(rows,:); pane.Handles.Manifest.Data=pane.Visible(:,{'Split','Label','Group','File'});
            readable=pane.Data.Plan.Health.Images.File(pane.Data.Plan.Health.Images.Readable);
            selected=find(ismember(pane.Visible.File,readable),1);
            if ~isempty(selected), pane.preview(struct('Indices',[selected 1])); end
        end
        function preview(pane,event)
            if isempty(event.Indices) || isempty(pane.Visible), return; end
            file=pane.Visible.File(event.Indices(1,1)); imshow(VIStudioData.readImage(file,[]),'InitialMagnification','fit','Parent',pane.Handles.Preview); title(pane.Handles.Preview,'來源影像 / Source image');
        end
        function export(pane)
            assert(~isempty(pane.Data.Plan),'VIStudioV9:MissingPlan','Build a dataset plan first.');
            [file,path]=uiputfile('*.csv','Export dataset manifest'); if isequal(file,0), return; end
            file=fullfile(path,file); assert(~isfile(file),'VIStudioV9:FileExists','Choose a new filename.'); writetable(pane.Data.Plan.Manifest,file,'Encoding','UTF-8');
        end
        function action(pane,callback)
            try, callback(); catch err, uialert(ancestor(pane.Handles.Sources,'figure'),err.message,'資料集 / Dataset','Interpreter','none'); end
        end
    end
end
