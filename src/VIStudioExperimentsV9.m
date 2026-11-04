classdef VIStudioExperimentsV9 < handle
    properties (SetAccess=private)
        Records=table()
        Handles=struct()
        Root
    end
    properties (Access=private)
        Task
        Activate
    end
    methods
        function pane=VIStudioExperimentsV9(tab,task,activate,root)
            if nargin<4, root=fullfile(fileparts(mfilename('fullpath')),'V9_Runs'); end
            pane.Root=string(root); pane.Task=string(task); pane.Activate=activate;
            grid=uigridlayout(tab,[5 1],'RowHeight',{34,36,140,'1x',80});
            bar=uigridlayout(grid,[1 5],'Padding',[0 0 0 0]);
            uibutton(bar,'Text','更新清單 / Refresh','ButtonPushedFcn',@(~,~) pane.action(@() pane.refresh()));
            uibutton(bar,'Text','選紀錄資料夾 / Run root','ButtonPushedFcn',@(~,~) pane.action(@() pane.pickRoot()));
            uibutton(bar,'Text','比較選取實驗 / Compare','ButtonPushedFcn',@(~,~) pane.action(@() pane.compare(pane.selection())));
            uibutton(bar,'Text','啟用選取模型 / Activate','ButtonPushedFcn',@(~,~) pane.action(@() pane.activate(pane.selection())));
            uibutton(bar,'Text','匯出比較 / Export','ButtonPushedFcn',@(~,~) pane.action(@() pane.pickExport()));
            pane.Handles.Status=uilabel(grid,'Text','選取同任務的實驗進行比較 / Select runs from the same task','WordWrap','on');
            pane.Handles.Runs=uitable(grid,'SelectionType','row','CellSelectionCallback',@(~,e) pane.showDetails(e));
            pane.Handles.Plot=uiaxes(grid); title(pane.Handles.Plot,'損失比較 / Loss comparison'); xlabel(pane.Handles.Plot,'Iteration');
            pane.Handles.Details=uitextarea(grid,'Editable','off'); pane.refresh();
        end
        function refresh(pane)
            pane.Records=VIStudioExperimentsV9.scan(pane.Root,pane.Task);
            pane.Handles.Runs.Data=pane.Records(:,{'RunID','Model','Status','Dataset','Epochs','Batch','Solver','LearnRate','Seconds','BestVal','StartedAtUTC'});
            pane.Handles.Runs.ColumnWidth={140,140,70,100,50,50,65,80,65,80,160};
            pane.Handles.Status.Text=sprintf('%d 次實驗 / runs · %s',height(pane.Records),pane.Root);
        end
        function result=compare(pane,rows)
            pane.validateSelection(rows); assert(numel(rows)<=6,'VIStudioV9:CompareLimit','Select up to six experiments.');
            rows=reshape(rows,1,[]);
            selected=pane.Records(rows,:); ax=pane.Handles.Plot; cla(ax); hold(ax,'on'); palette=lines(numel(rows));
            for k=1:numel(rows)
                loaded=load(fullfile(selected.Folder(k),'run.mat'),'history'); h=loaded.history;
                label=selected.Model(k)+" / "+extractAfter(selected.RunID(k),max(0,strlength(selected.RunID(k))-8));
                if ~isempty(h)
                    plot(ax,h.Iteration,h.TrainingLoss,'Color',palette(k,:),'DisplayName',char(label+" train"));
                    if any(isfinite(h.ValidationLoss)), plot(ax,h.Iteration,h.ValidationLoss,'--','Color',palette(k,:),'DisplayName',char(label+" val")); end
                end
            end
            hold(ax,'off'); grid(ax,'on'); if ~isempty(ax.Children), legend(ax,'show','Location','best','Interpreter','none'); end
            comparable=all(strlength(selected.Dataset)>0) && numel(unique(selected.Dataset))==1;
            message="資料版本相同；仍須確認損失定義及測試指標 / Same dataset; compare loss definitions and test metrics before choosing.";
            if ~comparable, message="資料版本不同或未知，曲線僅供檢視，不自動排名 / Different or unknown datasets; curves are exploratory, no automatic ranking."; end
            pane.Handles.Status.Text=message;
            pane.Handles.Runs.Selection=rows; pane.showDetails(struct('Indices',[rows(1) 1]));
            result=struct('Runs',selected,'SameDataset',comparable,'Message',message);
        end
        function file=activate(pane,rows)
            pane.validateSelection(rows); assert(numel(rows)==1,'VIStudioV9:SelectOneRun','Select one experiment to activate.');
            row=pane.Records(rows,:); file=row.Checkpoint;
            assert(strlength(file)>0 && isfile(file) && strlength(row.CheckpointDigest)>0 && VIStudioToolsV3.fileHash(file)==row.CheckpointDigest, ...
                'VIStudioV9:CheckpointChanged','Checkpoint is missing or changed; activation cancelled.');
            pane.Activate(file);
        end
        function export(pane,rows,folder)
            pane.validateSelection(rows); assert(~isfolder(folder) && ~isfile(folder),'VIStudioV9:FileExists','Choose a new export folder.');
            mkdir(folder); selected=pane.Records(rows,:); writetable(selected,fullfile(folder,'experiments.csv'),'Encoding','UTF-8');
            for k=1:height(selected)
                loaded=load(fullfile(selected.Folder(k),'run.mat'),'history','summary');
                writetable(loaded.history,fullfile(folder,sprintf('run_%02d_metrics.csv',k)));
                configuration=load(fullfile(selected.Folder(k),'configuration.mat'),'configuration'); %#ok<NASGU>
                save(fullfile(folder,sprintf('run_%02d_details.mat',k)),'loaded','configuration');
                manifest=fullfile(selected.Folder(k),'dataset_manifest.csv');
                if isfile(manifest), copyfile(manifest,fullfile(folder,sprintf('run_%02d_dataset.csv',k))); end
            end
        end
    end
    methods (Access=private)
        function rows=selection(pane), rows=unique(pane.Handles.Runs.Selection); rows=rows(:)'; end
        function validateSelection(pane,rows)
            validateattributes(rows,{'numeric'},{'vector','nonempty','integer','positive','<=',height(pane.Records)});
        end
        function showDetails(pane,event)
            if isempty(event.Indices), return; end
            row=event.Indices(1,1); loaded=load(fullfile(pane.Records.Folder(row),'configuration.mat'),'configuration');
            c=loaded.configuration;
            first=sprintf('Epochs %g | Batch %g | LR %g | %s | Dataset: %s',c.Base.Epochs,c.Base.Batch,c.Base.LearnRate,pane.Records.Solver(row),pane.Records.Dataset(row));
            pane.Handles.Details.Value=[string(first);splitlines(string(jsonencode(c,'PrettyPrint',true)))];
        end
        function pickRoot(pane)
            folder=uigetdir(pwd,'Select V8_Runs or V9_Runs root'); if isequal(folder,0), return; end
            pane.Root=string(folder); pane.refresh();
        end
        function pickExport(pane)
            rows=pane.selection(); pane.validateSelection(rows); parent=uigetdir(pwd,'Select comparison export parent'); if isequal(parent,0), return; end
            [~,name]=fileparts(tempname(parent)); pane.export(rows,fullfile(parent,['comparison_' name]));
        end
        function action(pane,callback)
            try, callback(); catch err, uialert(ancestor(pane.Handles.Runs,'figure'),err.message,'實驗比較 / Experiments','Interpreter','none'); end
        end
    end
    methods (Static)
        function records=scan(root,task)
            fields={'RunID','Task','Model','Status','Dataset','Epochs','Batch','Solver','LearnRate','Seconds','BestVal','StartedAtUTC','Folder','Checkpoint','CheckpointDigest'};
            types={'string','string','string','string','string','double','double','string','double','double','double','string','string','string','string'};
            records=table('Size',[0 numel(fields)],'VariableTypes',types,'VariableNames',fields);
            if ~isfolder(root), return; end
            entries=dir(fullfile(root,'*','run.mat'));
            for k=1:numel(entries)
                try
                    loaded=load(fullfile(entries(k).folder,'run.mat'),'summary'); s=loaded.summary;
                    if string(s.Task)~=string(task), continue; end
                    loaded=load(fullfile(entries(k).folder,'configuration.mat'),'configuration'); c=loaded.configuration;
                    dataset=""; checkpoint=""; digest=""; solver="";
                    if isfield(s,'DatasetFingerprint'), dataset=string(s.DatasetFingerprint); end
                    if isfield(s,'Checkpoint'), checkpoint=string(s.Checkpoint); end
                    if isfield(s,'CheckpointDigest'), digest=string(s.CheckpointDigest); end
                    if isfield(c.Advanced,'Solver'), solver=string(c.Advanced.Solver); end
                    try
                        stamp=datetime(s.StartedAtUTC,'InputFormat',"yyyy-MM-dd'T'HH:mm:ss.SSSXXX",'TimeZone','UTC');
                    catch
                        try, stamp=datetime(s.StartedAtUTC,'InputFormat','dd-MMM-yyyy HH:mm:ss','Locale','en_US','TimeZone','UTC');
                        catch, stamp=datetime(entries(k).datenum,'ConvertFrom','datenum','TimeZone','UTC'); end
                    end
                    stamp.Format="yyyy-MM-dd'T'HH:mm:ss.SSSXXX";
                    [~,id]=fileparts(entries(k).folder);
                    records(end+1,:)={string(id),string(s.Task),string(s.Model),string(s.Status),dataset,c.Base.Epochs,c.Base.Batch,solver, ...
                        c.Base.LearnRate,s.ElapsedSeconds,s.BestValidationLoss,string(stamp),string(entries(k).folder),checkpoint,digest}; %#ok<AGROW>
                catch
                    % Incomplete or damaged run directories do not hide valid runs.
                end
            end
            records=sortrows(records,'StartedAtUTC','descend');
        end
    end
end
