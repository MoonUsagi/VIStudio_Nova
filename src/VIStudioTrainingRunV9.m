classdef VIStudioTrainingRunV9 < handle
    % Native training callbacks and durable, independent run records.
    properties (SetAccess=private)
        History=table('Size',[0 8],'VariableTypes',repmat({'double'},1,8), ...
            'VariableNames',{'Iteration','Epoch','TrainingLoss','ValidationLoss','LearnRate','ElapsedSeconds','TrainingAccuracy','ValidationAccuracy'})
        Summary=struct('Status',"idle")
        RunFolder=""
        StopRequested=false
        Handles=struct()
    end
    properties (Access=private)
        Clock
        LastWrite=0
    end
    methods
        function run=VIStudioTrainingRunV9(tab)
            if nargin==0 || isempty(tab), return; end
            grid=uigridlayout(tab,[4 2],'RowHeight',{40,55,'1x',160});
            bar=uigridlayout(grid,[1 2]); bar.Layout.Column=[1 2];
            run.Handles.Stop=uibutton(bar,'Text','停止訓練 / Stop training','Enable','off','ButtonPushedFcn',@(~,~) run.requestStop());
            uibutton(bar,'Text','開啟紀錄資料夾 / Open run folder','ButtonPushedFcn',@(~,~) run.openFolder());
            run.Handles.Status=uilabel(grid,'Text','尚未訓練 / No run','WordWrap','on'); run.Handles.Status.Layout.Column=[1 2];
            run.Handles.Loss=uiaxes(grid); run.Handles.Loss.Layout.Row=3; title(run.Handles.Loss,'損失 / Loss'); xlabel(run.Handles.Loss,'Iteration');
            run.Handles.Rate=uiaxes(grid); run.Handles.Rate.Layout.Row=3; run.Handles.Rate.Layout.Column=2; title(run.Handles.Rate,'學習率 / Learning rate');
            run.Handles.TrainLine=line(run.Handles.Loss,NaN,NaN,'Color',[.1 .45 .8],'DisplayName','Training');
            run.Handles.ValidationLine=line(run.Handles.Loss,NaN,NaN,'Color',[.85 .3 .1],'Marker','o','DisplayName','Validation');
            legend(run.Handles.Loss,'show','Location','best');
            run.Handles.RateLine=line(run.Handles.Rate,NaN,NaN,'Color',[.1 .6 .4]);
            run.Handles.Metrics=uitable(grid); run.Handles.Metrics.Layout.Row=4; run.Handles.Metrics.Layout.Column=[1 2];
        end
        function begin(run,task,choice,base,advanced,root)
            if nargin<6, root=fullfile(fileparts(mfilename('fullpath')),'V9_Runs'); end
            if ~isfolder(root), mkdir(root); end
            [~,name]=fileparts(tempname(root)); run.RunFolder=string(fullfile(root,name)); mkdir(run.RunFolder);
            run.History=run.History([],:); run.StopRequested=false; run.Clock=tic; run.LastWrite=0;
            run.Summary=struct('Status',"running",'Task',string(task),'Model',string(choice), ...
                'StartedAtUTC',string(datetime('now','TimeZone','UTC','Format',"yyyy-MM-dd'T'HH:mm:ss.SSSXXX")),'Stage',"準備資料 / Preparing data", ...
                'BestValidationLoss',NaN,'BestIteration',NaN,'ElapsedSeconds',0,'LiveCallbackRecords',0,'Message',"");
            configuration=struct('Task',task,'Model',choice,'Base',base,'Advanced',advanced); %#ok<NASGU>
            save(fullfile(run.RunFolder,'configuration.mat'),'configuration'); run.persist(); run.render();
        end
        function attachDataset(run,plan)
            assert(strlength(run.RunFolder)>0,'VIStudioV9:RunMissing','Begin a training run first.');
            run.Summary.DatasetFingerprint=plan.Fingerprint;
            save(fullfile(run.RunFolder,'dataset.mat'),'plan','-v7.3');
            writetable(plan.Manifest,fullfile(run.RunFolder,'dataset_manifest.csv'),'Encoding','UTF-8');
            loaded=load(fullfile(run.RunFolder,'configuration.mat'),'configuration'); configuration=loaded.configuration;
            configuration.DatasetFingerprint=plan.Fingerprint; configuration.DatasetConfig=plan.Config; configuration.DatasetCounts=plan.Counts;
            save(fullfile(run.RunFolder,'configuration.mat'),'configuration'); run.persist();
        end
        function attachParent(run,external)
            loaded=load(fullfile(run.RunFolder,'configuration.mat'),'configuration'); configuration=loaded.configuration;
            configuration.Parent=struct('File',external.File,'Digest',external.Digest,'Variable',external.Variable,'ModelClass',string(class(external.Model)));
            save(fullfile(run.RunFolder,'configuration.mat'),'configuration');
        end
        function attachCheckpoint(run,file)
            assert(isfile(file),'VIStudioV9:CheckpointMissing','Checkpoint file is missing.');
            run.Summary.Checkpoint=VIStudioToolsV3.canonicalPath(file); run.Summary.CheckpointDigest=VIStudioToolsV3.fileHash(file); run.persist();
        end
        function stop=callback(run,info)
            run.Summary.CallbackFields=string(fieldnames(info));
            if ~isfield(info,'State') || string(info.State)=="iteration"
                iteration=value('Iteration');
                if isfinite(iteration)
                    run.Summary.LiveCallbackRecords=run.Summary.LiveCallbackRecords+1;
                    row=[iteration value('Epoch') value('TrainingLoss') value('ValidationLoss') value('BaseLearnRate') toc(run.Clock) value('TrainingAccuracy') value('ValidationAccuracy')];
                    if isnan(row(5)), row(5)=value('LearnRate'); end
                    index=find(run.History.Iteration==iteration,1);
                    if isempty(index), run.History(end+1,:)=array2table(row,'VariableNames',run.History.Properties.VariableNames);
                    else
                        previous=run.History{index,:}; valid=isfinite(row); previous(valid)=row(valid); run.History{index,:}=previous;
                    end
                end
            end
            run.Summary.ElapsedSeconds=toc(run.Clock);
            finite=isfinite(run.History.ValidationLoss);
            if any(finite)
                rows=find(finite); [loss,index]=min(run.History.ValidationLoss(finite));
                run.Summary.BestValidationLoss=loss; run.Summary.BestIteration=run.History.Iteration(rows(index));
            end
            if toc(run.Clock)-run.LastWrite>=1, run.persist(); end
            run.render(); drawnow limitrate; stop=run.StopRequested;
            function x=value(field)
                x=NaN; if isfield(info,field) && isnumeric(info.(field)) && isscalar(info.(field)), x=double(gather(info.(field))); end
            end
        end
        function stage(run,text,canStop)
            run.Summary.Stage=string(text); run.render();
            if isfield(run.Handles,'Stop'), run.Handles.Stop.Enable=matlab.lang.OnOffSwitchState(canStop); end
            drawnow;
        end
        function ingest(run,info)
            % Fill metrics returned by native trainers, including validation
            % points that are not included in their per-epoch callbacks.
            if ~isstruct(info) || isempty(info), return; end
            names=run.History.Properties.VariableNames;
            aliases={{'Iteration'},{'Epoch'},{'TrainingLoss','TrainingFcddLoss','TrainingYoloXLoss'}, ...
                {'ValidationLoss','ValidationYoloXLoss'},{'BaseLearnRate','LearnRate'}, ...
                {'TimeElapsed','TimeSinceStart'},{'TrainingAccuracy'},{'ValidationAccuracy'}};
            for item=1:numel(info)
                record=info(item); count=0;
                for col=1:numel(aliases)
                    for field=aliases{col}
                        if isfield(record,field{1}), count=max(count,numel(record.(field{1}))); end
                    end
                end
                for k=1:count
                    row=nan(1,8);
                    for col=1:8
                        for field=aliases{col}
                            if ~isfield(record,field{1}), continue; end
                            values=record.(field{1}); if isduration(values), values=seconds(values); end
                            if isnumeric(values) && numel(values)>=k, row(col)=double(values(k)); break; end
                        end
                    end
                    if isnan(row(1)), row(1)=k; end
                    index=find(run.History.Iteration==row(1),1);
                    if isempty(index), run.History(end+1,:)=array2table(row,'VariableNames',names);
                    else
                        previous=run.History{index,:}; valid=isfinite(row); previous(valid)=row(valid); run.History{index,:}=previous;
                    end
                end
            end
            run.History=sortrows(run.History,'Iteration'); run.callback(struct('State','done'));
        end
        function requestStop(run)
            run.StopRequested=true; run.Summary.Stage="已要求停止；等待目前步驟結束 / Stop requested; waiting for current step"; run.render();
        end
        function finish(run,status,message)
            if nargin<3, message=""; end
            run.Summary.Status=string(status); run.Summary.Message=string(message);
            if ~isempty(run.Clock), run.Summary.ElapsedSeconds=toc(run.Clock); end
            run.persist(); run.render();
            if isfield(run.Handles,'Stop'), run.Handles.Stop.Enable='off'; end
        end
        function openFolder(run)
            if strlength(run.RunFolder)>0 && isfolder(run.RunFolder), winopen(char(run.RunFolder)); end
        end
    end
    methods (Access=private)
        function persist(run)
            if strlength(run.RunFolder)==0, return; end
            history=run.History; summary=run.Summary; %#ok<NASGU>
            temporary=fullfile(run.RunFolder,'run_pending.mat'); save(temporary,'history','summary');
            movefile(temporary,fullfile(run.RunFolder,'run.mat'),'f');
            temporary=fullfile(run.RunFolder,'metrics_pending.csv'); writetable(history,temporary);
            movefile(temporary,fullfile(run.RunFolder,'metrics.csv'),'f');
            if ~isempty(run.Clock), run.LastWrite=toc(run.Clock); end
        end
        function render(run)
            if ~isfield(run.Handles,'Status') || ~isvalid(run.Handles.Status), return; end
            best="N/A"; if isfinite(run.Summary.BestValidationLoss), best=string(run.Summary.BestValidationLoss); end
            run.Handles.Status.Text=sprintf('%s · %s · %.1f s · 最佳驗證損失 / Best validation loss: %s\n%s', ...
                run.Summary.Status,run.Summary.Stage,run.Summary.ElapsedSeconds,best,run.RunFolder);
            h=run.History; run.Handles.Metrics.Data=h;
            set(run.Handles.TrainLine,'XData',h.Iteration,'YData',h.TrainingLoss);
            set(run.Handles.ValidationLine,'XData',h.Iteration,'YData',h.ValidationLoss);
            set(run.Handles.RateLine,'XData',h.Iteration,'YData',h.LearnRate);
            rates=h.LearnRate(isfinite(h.LearnRate) & h.LearnRate>0);
            if ~isempty(rates), ylim(run.Handles.Rate,[min(rates)*.8 max(rates)*1.2]); end
        end
    end
end
