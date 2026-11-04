classdef VIStudioPipelineV13
    methods (Static)
        function stage=stage(id,task,file,parent)
            if nargin<4, parent=""; end
            stage=struct('ID',string(id),'Task',string(task),'ModelFile',string(file),'Digest',"",'Parent',string(parent),'ParentClass',"", ...
                'AcceptLabels',strings(0,1),'MinTargets',1,'MaxTargets',9999,'MinObjects',0,'MaxObjects',9999,'ROI',[],'MaxUnacceptedFraction',0,'MinPixelConfidence',.5);
        end
        function recipe=defaults()
            recipe=struct('Version',1,'Name',"New product",'Stages',repmat(VIStudioPipelineV13.stage('','',''),0,1), ...
                'Geometry',VIStudioGeometryV11.defaults(),'Quality',VIStudioQualityV11.defaults(),'DefectRules',VIStudioDefectsV11.defaults());
        end
        function [recipe,artifacts]=validate(recipe,bind)
            if nargin<2, bind=false; end
            assert(isstruct(recipe) && isscalar(recipe) && all(isfield(recipe,{'Version','Name','Stages','Geometry','Quality','DefectRules'})) && recipe.Version==1 && ~isempty(recipe.Stages),'VIStudioV13:Recipe','A recipe requires model stages.');
            recipe.Quality=VIStudioQualityV11.options(recipe.Quality); VIStudioGeometryV11.validate(recipe.Geometry); recipe.DefectRules=VIStudioDefectsV11.options(recipe.DefectRules);
            for field={'MaxUnacceptedFraction','MinPixelConfidence'}
                if ~isfield(recipe.Stages,field{1}), for n=1:numel(recipe.Stages), recipe.Stages(n).(field{1})=0; if strcmp(field{1},'MinPixelConfidence'), recipe.Stages(n).(field{1})=.5; end, end, end
            end
            ids=string({recipe.Stages.ID}); assert(all(strlength(ids)>0) && numel(unique(ids))==numel(ids),'VIStudioV13:StageIDs','Stage IDs must be unique.'); artifacts=cell(numel(ids),1);
            for k=1:numel(ids)
                s=recipe.Stages(k); validatestring(s.Task,{'classification','detection','anomaly','semantic'});
                assert(strlength(s.Parent)==0 || any(ids(1:k-1)==s.Parent),'VIStudioV13:StageOrder','Parents must precede their children.');
                for field={'MinTargets','MaxTargets','MinObjects','MaxObjects'}, validateattributes(s.(field{1}),{'numeric'},{'scalar','integer','finite','nonnegative'}); end
                assert(s.MinTargets<=s.MaxTargets && s.MinObjects<=s.MaxObjects,'VIStudioV13:StageLimits','Stage bounds are invalid.');
                validateattributes([s.MaxUnacceptedFraction s.MinPixelConfidence],{'numeric'},{'finite','>=',0,'<=',1});
                if ~isempty(s.ROI), validateattributes(s.ROI,{'numeric'},{'vector','numel',4,'positive','integer','finite'}); end
                artifacts{k}=VIStudioInferenceV13.load(s.ModelFile,s.Task);
                if bind && strlength(s.Digest)==0, recipe.Stages(k).Digest=artifacts{k}.Digest;
                else, assert(strlength(s.Digest)>0 && s.Digest==artifacts{k}.Digest,'VIStudioV13:RecipeModelChanged','Recipe model is missing or changed.'); end
            end
        end
        function save(recipe,file)
            assert(~isfile(file),'VIStudioV13:FileExists','Choose a new recipe file.'); [recipe,~]=VIStudioPipelineV13.validate(recipe,true); save(file,'recipe','-v7.3');
        end
        function recipe=load(file)
            loaded=load(file,'recipe'); assert(isfield(loaded,'recipe'),'VIStudioV13:Recipe','MAT requires recipe.'); recipe=VIStudioPipelineV13.validate(loaded.recipe,false);
        end
        function result=run(recipe,image)
            [recipe,models]=VIStudioPipelineV13.validate(recipe,false); timer=tic; [corrected,geometry]=VIStudioGeometryV11.apply(image,recipe.Geometry);
            quality=VIStudioQualityV11.check(corrected,recipe.Quality); rows=table(); outputs=cell(numel(models),1); overall="OK";
            if quality.Blocked || geometry.ValidFraction<recipe.Geometry.MinValidFraction
                result=struct('Recipe',recipe,'Decision',"RETAKE",'Image',corrected,'Geometry',geometry,'Quality',quality,'Stages',rows,'Outputs',{outputs},'Milliseconds',1000*toc(timer)); return;
            end
            for k=1:numel(models)
                stage=recipe.Stages(k); inputs=struct('Box',{},'ParentIndex',{});
                if strlength(stage.Parent)==0, inputs=struct('Box',[1 1 size(corrected,2) size(corrected,1)],'ParentIndex',0);
                else
                    parent=find(string({recipe.Stages.ID})==stage.Parent,1); candidates=outputs{parent};
                    for n=1:numel(candidates)
                        p=candidates{n};
                        if p.Prediction.Task=="detection"
                            for b=1:size(p.Prediction.Boxes,1)
                                if strlength(stage.ParentClass)>0 && p.Prediction.BoxLabels(b)~=stage.ParentClass, continue; end
                                inputs(end+1)=struct('Box',p.Prediction.Boxes(b,:),'ParentIndex',n); %#ok<AGROW>
                            end
                        elseif strlength(stage.ParentClass)==0 || p.Prediction.Label==stage.ParentClass
                            inputs(end+1)=struct('Box',p.Box,'ParentIndex',n); %#ok<AGROW>
                        end
                    end
                end
                if numel(inputs)<stage.MinTargets || numel(inputs)>stage.MaxTargets
                    rows=[rows;record(stage.ID,0,"",NaN,"NG",[NaN NaN NaN NaN],"Target count outside bounds",0)]; overall="NG"; %#ok<AGROW>
                end
                outputs{k}={};
                for n=1:numel(inputs)
                    box=inputs(n).Box;
                    try
                        box=VIStudioPipelineV13.clip(box,size(corrected,[1 2]));
                        [crop,~]=VIStudioToolsV3.cropImage(corrected,box);
                        if ~isempty(stage.ROI), [crop,local]=VIStudioToolsV3.cropImage(crop,stage.ROI); box=[box(1:2)+local(1:2)-1 local(3:4)]; end
                        p=VIStudioInferenceV13.run(models{k},crop,'cpu',false); decision=p.Decision; why="";
                        if p.Task=="semantic"
                            assert(~isempty(stage.AcceptLabels) && all(ismember(stage.AcceptLabels,p.Semantic.Classes.Name)),'VIStudioV13:SemanticAcceptLabels','Specify valid accepted pixel classes, including background if allowed.');
                            valid=geometry.ValidMask(box(2)+(0:box(4)-1),box(1)+(0:box(3)-1)); confident=valid & p.Semantic.ConfidenceMap>=stage.MinPixelConfidence;
                            if nnz(valid)==0 || nnz(confident)/nnz(valid)<recipe.Geometry.MinValidFraction, decision="REVIEW"; why="Insufficient confident valid pixels";
                            else
                                accepted=p.Semantic.Classes.ID(ismember(p.Semantic.Classes.Name,stage.AcceptLabels)); fraction=nnz(confident & ~ismember(p.Semantic.Labels,accepted))/nnz(confident);
                                p.UnacceptedFraction=fraction; decision="OK"; if fraction>stage.MaxUnacceptedFraction, decision="NG"; end; why="Unaccepted pixel fraction: "+fraction;
                            end
                        elseif p.Task=="classification"
                            if p.Decision=="REVIEW" || isempty(stage.AcceptLabels), decision="REVIEW"; why="Low confidence or no acceptance labels";
                            elseif ismember(p.Label,string(stage.AcceptLabels)), decision="OK"; else, decision="NG"; why="Class not accepted"; end
                        elseif p.Task=="detection"
                            decision="OK"; if size(p.Boxes,1)<stage.MinObjects || size(p.Boxes,1)>stage.MaxObjects, decision="NG"; why="Object count outside bounds"; end
                            p.Boxes(:,1:2)=p.Boxes(:,1:2)+box(1:2)-1;
                        elseif recipe.DefectRules.Enabled
                            mask=[]; if ~isempty(p.Mask), mask=false(size(corrected,[1 2])); mask(box(2)+(0:box(4)-1),box(1)+(0:box(3)-1))=p.Mask; mask=mask & geometry.ValidMask; end
                            rules=recipe.DefectRules;
                            if recipe.Geometry.Perspective, rules.ScaleEnabled=true; rules.MMPerPixelX=geometry.ScaleX; rules.MMPerPixelY=geometry.ScaleY; end
                            p.Measurement=VIStudioDefectsV11.analyze(mask,box,rules,struct('Calibrated',p.Calibrated,'ImageScore',p.Confidence,'ImageThreshold',p.ImageThreshold,'PixelThreshold',p.PixelThreshold));
                            decision=p.Measurement.Decision; why=join(p.Measurement.Reasons,'; ');
                        end
                        outputs{k}{end+1}=struct('Prediction',p,'Box',box,'ParentIndex',inputs(n).ParentIndex); %#ok<AGROW>
                        rows=[rows;record(stage.ID,n,p.Label,p.Confidence,decision,box,why,p.Milliseconds)]; %#ok<AGROW>
                        if decision=="NG", overall="NG"; elseif decision=="REVIEW" && overall~="NG", overall="REVIEW"; end
                    catch err
                        rows=[rows;record(stage.ID,n,"",NaN,"ERROR",box,string(err.message),0)]; overall="REVIEW"; %#ok<AGROW>
                    end
                end
            end
            if ~isempty(rows) && any(rows.Decision=="ERROR"), overall="REVIEW"; end
            result=struct('Recipe',recipe,'Decision',overall,'Image',corrected,'Geometry',geometry,'Quality',quality,'Stages',rows,'Outputs',{outputs},'Milliseconds',1000*toc(timer));
            function row=record(step,index,label,score,decision,box,reason,time)
                row=table(string(step),index,string(label),score,string(decision),box(1),box(2),box(3),box(4),string(reason),time, ...
                    'VariableNames',{'Stage','Target','Label','Score','Decision','X','Y','Width','Height','Reason','Milliseconds'});
            end
        end
        function export(result,folder)
            assert(isstruct(result) && isfield(result,'Recipe'),'VIStudioV13:InspectionReport','Run a recipe before exporting.');
            assert(~isfolder(folder) && ~isfile(folder),'VIStudioV13:FileExists','Choose a new report folder.'); mkdir(folder);
            save(fullfile(folder,'inspection.mat'),'result','-v7.3'); imwrite(result.Image,fullfile(folder,'rectified_image.png'));
            if width(result.Stages)>0, writetable(result.Stages,fullfile(folder,'stages.csv'),'Encoding','UTF-8'); end
            writetable(result.Quality.Metrics,fullfile(folder,'quality.csv'),'Encoding','UTF-8');
            summary=struct('Product',result.Recipe.Name,'Decision',result.Decision,'CoordinateSpace',result.Geometry.CoordinateSpace, ...
                'Milliseconds',result.Milliseconds,'Quality',result.Quality.Decision,'ModelDigests',string({result.Recipe.Stages.Digest}));
            fid=fopen(fullfile(folder,'summary.json'),'w','n','UTF-8'); assert(fid>=0,'VIStudioV13:ReportFile','Cannot write report.'); cleanup=onCleanup(@() fclose(fid)); fprintf(fid,'%s',jsonencode(summary));
        end
        function box=clip(box,imageSize)
            validateattributes(box,{'numeric'},{'numel',4,'finite','real'}); lo=max([1 1],floor(box(1:2))); hi=min(imageSize([2 1]),ceil(box(1:2)+box(3:4)-1));
            assert(all(hi>=lo),'VIStudioV13:Crop','Object box has no image pixels.'); box=[lo hi-lo+1];
        end
    end
end
