classdef VIStudioHealthPaneV8 < handle
    properties (SetAccess=private)
        Report=[]
        Handles=struct()
    end
    properties (Access=private)
        Task
        CheckCurrent
    end
    methods
        function pane=VIStudioHealthPaneV8(tab,task,callback)
            pane.Task=string(task); pane.CheckCurrent=callback;
            grid=uigridlayout(tab,[5 2],'RowHeight',{40,42,42,'1x',180});
            bar=uigridlayout(grid,[1 4],'Padding',[0 0 0 0]); bar.Layout.Column=[1 2];
            uibutton(bar,'Text','檢查訓練資料 / Check training','ButtonPushedFcn',@(~,~) pane.action(@() callback()));
            uibutton(bar,'Text','檢查資料夾 / Check folder','ButtonPushedFcn',@(~,~) pane.action(@() pane.pickFolder()));
            uibutton(bar,'Text','檢查標註 MAT / Check annotation MAT','ButtonPushedFcn',@(~,~) pane.action(@() pane.pickAnnotations()));
            uibutton(bar,'Text','匯出健檢報告 / Export report','ButtonPushedFcn',@(~,~) pane.action(@() pane.pickExport()));
            pane.Handles.Summary=uilabel(grid,'Text','尚未檢查 / Not checked','WordWrap','on'); pane.Handles.Summary.Layout.Column=[1 2];
            pane.Handles.Detail=uilabel(grid,'Text','選取問題或影像以預覽 / Select an issue or image to preview','WordWrap','on'); pane.Handles.Detail.Layout.Column=[1 2];
            pane.Handles.Issues=uitable(grid,'SelectionType','row','CellSelectionCallback',@(~,e) pane.preview(e)); pane.Handles.Issues.Layout.Row=4;
            pane.Handles.Preview=uiaxes(grid); pane.Handles.Preview.Layout.Row=4; pane.Handles.Preview.Layout.Column=2;
            pane.Handles.Images=uitable(grid,'CellSelectionCallback',@(~,e) pane.previewImage(e)); pane.Handles.Images.Layout.Row=5; pane.Handles.Images.Layout.Column=[1 2];
        end
        function show(pane,report)
            pane.Report=report; pane.Handles.Summary.Text=sprintf('影像 / Images: %d · 錯誤 / Errors: %d · 警告 / Warnings: %d · 原檔維持不變 / Sources unchanged', ...
                height(report.Images),report.Errors,report.Warnings);
            pane.Handles.Issues.Data=report.Issues; pane.Handles.Issues.ColumnWidth={75,135,180,180,350};
            pane.Handles.Images.Data=report.Images(:,{'File','Label','Readable','Width','Height','Channels','Objects'});
            cla(pane.Handles.Preview);
            pane.Handles.Detail.Text='選取問題或影像以預覽 / Select an issue or image to preview';
            if ~isempty(report.Issues)
                selected=1;
                for k=1:height(report.Issues)
                    if any(report.Images.File==report.Issues.File(k) & report.Images.Readable), selected=k; break; end
                end
                pane.Handles.Issues.Selection=selected; pane.preview(struct('Indices',[selected 1]));
            end
        end
    end
    methods (Access=private)
        function pickFolder(pane)
            folder=uigetdir(pwd,'Check image folder'); if isequal(folder,0), return; end
            pane.show(VIStudioDataHealthV8.folder(folder,pane.Task));
        end
        function pickAnnotations(pane)
            [file,path]=uigetfile('*.mat','Check box annotations'); if isequal(file,0), return; end
            pane.show(VIStudioDataHealthV8.annotations(fullfile(path,file)));
        end
        function preview(pane,event)
            if isempty(event.Indices) || isempty(pane.Report), return; end
            file=pane.Report.Issues.File(event.Indices(1,1));
            pane.Handles.Detail.Text=pane.Report.Issues.Message(event.Indices(1,1));
            pane.showImage(file);
        end
        function previewImage(pane,event)
            if isempty(event.Indices) || isempty(pane.Report), return; end
            file=pane.Report.Images.File(event.Indices(1,1)); pane.Handles.Detail.Text=file; pane.showImage(file);
        end
        function showImage(pane,file)
            cla(pane.Handles.Preview);
            if strlength(file)>0 && isfile(file)
                try, imshow(VIStudioData.readImage(file,[]),'Parent',pane.Handles.Preview); title(pane.Handles.Preview,'問題影像 / Issue image');
                catch, cla(pane.Handles.Preview); title(pane.Handles.Preview,'影像無法解碼 / Cannot decode image'); end
            end
        end
        function pickExport(pane)
            assert(~isempty(pane.Report),'VIStudioV8:MissingHealth','Run a check first.');
            parent=uigetdir(pwd,'Choose report parent folder'); if isequal(parent,0), return; end
            [~,name]=fileparts(tempname(parent)); VIStudioDataHealthV8.export(pane.Report,fullfile(parent,['health_' name]));
        end
        function action(pane,callback)
            try, callback(); catch err, uialert(ancestor(pane.Handles.Issues,'figure'),err.message,'資料健檢 / Data health'); end
        end
    end
end
