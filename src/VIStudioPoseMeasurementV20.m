classdef VIStudioPoseMeasurementV20
    % Move tool geometry, then remeasure search pixels. Never scale old values.
    methods (Static)
        function recipe=validateRecipe(input,template)
            if ischar(input) || isstring(input)
                loaded=load(input,'recipe'); assert(isfield(loaded,'recipe'),'VIStudioV20:Recipe','MAT requires recipe.'); input=loaded.recipe;
            end
            recipe=input; required={'Version','Kind','SourceSize','Profile','Scale','Unit','Definitions','ReferenceHash'};
            assert(isstruct(recipe) && isscalar(recipe) && all(isfield(recipe,required)) && isequal(recipe.Version,17) && string(recipe.Kind)=="VIStudioMeasurementRecipe",'VIStudioV20:Recipe','Unsupported measurement recipe.');
            assert(isequal(recipe.SourceSize,size(template,[1 2])) && string(recipe.ReferenceHash)==VIStudioDataHealthV8.pixelHash(template),'VIStudioV20:RecipeReference','Create the recipe on this exact cropped template. Source dimensions/hash differ.');
            VIStudioGeometryV11.validate(recipe.Profile);
            assert(~recipe.Profile.Perspective && isempty(recipe.Profile.Camera),'VIStudioV20:RecipeCalibration','Use an unrectified template with pixel units or fixed X/Y mm-per-pixel. Lens/perspective recipes need a shared rectified coordinate pipeline.');
            validateattributes(recipe.Scale,{'numeric'},{'size',[1 2],'real','positive','finite'});
            assert(isscalar(string(recipe.Unit)) && ismember(string(recipe.Unit),["px","mm"]),'VIStudioV20:RecipeUnit','Use px or mm units.');
            if string(recipe.Unit)=="px", assert(isequal(double(recipe.Scale),[1 1]),'VIStudioV20:RecipeUnit','Pixel recipes require unit scale.'); end
            assert(iscell(recipe.Definitions) && ~isempty(recipe.Definitions),'VIStudioV20:RecipeTools','Record at least one supported measurement.');
            candidate=VIStudioMeasurementV17; candidate.loadImage(template);
            for k=1:numel(recipe.Definitions)
                s=recipe.Definitions{k}; assert(isstruct(s) && isscalar(s) && all(isfield(s,{'Kind','Geometry'})),'VIStudioV20:RecipeTools','Malformed tool definition.');
                assert(ismember(string(s.Kind),["distance","caliper","circle","angle","pointline"]),'VIStudioV20:RecipeToolUnsupported','Pose recipes support point/line/circle tools. Mask area and rotated dimensions require new object segmentation, not warped template truth.');
                s=VIStudioMeasurementV17.definition(s.Kind,s.Geometry,rmfield(s,{'Kind','Geometry'}));
                assert(~(s.Kind=="pointline" && s.Snap),'VIStudioV20:PointLineReplay','Snapped T-square captures cannot be replayed on new objects. Use manual point-to-line, caliper or snapped angle tools.');
                candidate.add(s.Kind,s.Geometry,rmfield(s,{'Kind','Geometry'}));
                recipe.Definitions{k}=s;
            end
        end
        function [summary,rows,objects]=measure(template,search,recipe,origin,matches)
            recipe=VIStudioPoseMeasurementV20.validateRecipe(recipe,template);
            [summary,rows]=VIStudioPoseMeasurementV20.emptyTables(); objects=cell(numel(matches),1);
            for k=1:numel(matches)
                m=matches(k); t=m.ModelOriginTransformation; a=double(t.A); scale=hypot(a(1,1),a(2,1)); angle=atan2d(a(2,1),a(1,1)); center=double(transformPointsForward(t,[0 0]));
                data=VIStudioMeasurementV17; data.loadImage(search,"matched-object-"+k);
                if string(recipe.Unit)=="mm", data.setScale(recipe.Scale(1),recipe.Scale(2)); end
                objectRows=rows([],:); failures=struct('ToolIndex',{},'Definition',{},'Message',{});
                for j=1:numel(recipe.Definitions)
                    s=recipe.Definitions{j}; moved=s;
                    try
                        moved=VIStudioPoseMeasurementV20.transform(s,t,origin,scale);
                        data.add(moved.Kind,moved.Geometry,rmfield(moved,{'Kind','Geometry'})); rec=data.Records(end);
                        value=rec.Value; unit=rec.Unit; decision=rec.Decision; method=rec.Method; message=rec.Message;
                    catch err
                        value=NaN; unit=string(recipe.Unit); if string(s.Kind)=="angle", unit="deg"; end
                        decision="NOT_MEASURED"; method="not-run"; message=string(err.message);
                        failures(end+1)=struct('ToolIndex',j,'Definition',moved,'Message',message);
                    end
                    objectRows(end+1,:)={k,j,string(s.Name),string(s.Kind),value,unit,double(s.Lower),double(s.Upper),decision,method,message,double(m.Score),center(1),center(2),angle,scale};
                end
                failed=nnz(objectRows.Decision=="NOT_MEASURED"); ng=nnz(objectRows.Decision=="NG"); decision="MEASURED";
                if failed>0, decision="REVIEW"; elseif ng>0, decision="NG"; elseif all(objectRows.Decision=="OK"), decision="OK"; end
                summary(end+1,:)={k,double(m.Score),center(1),center(2),angle,scale,height(objectRows),height(objectRows)-failed,ng,failed,decision};
                rows=[rows;objectRows]; objects{k}=struct('ObjectID',k,'Data',data,'Rows',objectRows,'Failures',failures,'Transform',a);
            end
        end
        function s=transform(s,t,origin,scale)
            if string(s.Kind)=="circle"
                xy=double(transformPointsForward(t,double(s.Geometry(1:2))-double(origin))); s.Geometry=[xy double(s.Geometry(3))*scale];
            else, s.Geometry=double(transformPointsForward(t,double(s.Geometry)-double(origin))); end
            s.Width=s.Width*scale; s.Neighborhood=max(1,round(s.Neighborhood*scale)); s.InlierDistance=s.InlierDistance*scale;
            s.NativeCaptured=false;
        end
        function [summary,rows]=emptyTables()
            summary=table('Size',[0 11],'VariableTypes',[repmat({'double'},1,10),{'string'}],'VariableNames',{'ObjectID','MatchScore','OriginXpx','OriginYpx','AngleDeg','Scale','Tools','Measured','NG','NotMeasured','Decision'});
            rows=table('Size',[0 16],'VariableTypes',{'double','double','string','string','double','string','double','double','string','string','string','double','double','double','double','double'},'VariableNames',{'ObjectID','ToolIndex','Name','Type','Value','Unit','Lower','Upper','Decision','Method','Message','MatchScore','OriginXpx','OriginYpx','AngleDeg','Scale'});
        end
        function export(folder,summary,rows,objects,recipe,image)
            writetable(summary,fullfile(folder,'object-summary.csv'),'Encoding','UTF-8'); writetable(rows,fullfile(folder,'object-measurements.csv'),'Encoding','UTF-8');
            save(fullfile(folder,'measurement-recipe.mat'),'recipe','-v7.3'); allRecords=[];
            for k=1:numel(objects)
                entry=objects{k}; sub=fullfile(folder,sprintf('object_%04d',entry.ObjectID)); mkdir(sub); measurements=entry.Rows; records=entry.Data.Records; failures=entry.Failures; transform=entry.Transform;
                writetable(measurements,fullfile(sub,'measurements.csv'),'Encoding','UTF-8'); save(fullfile(sub,'measurements.mat'),'measurements','records','failures','transform','-v7.3');
                for j=1:numel(records), records(j).Definition.Name="Object "+k+" / "+records(j).Definition.Name; end
                if isempty(allRecords), allRecords=records; else, allRecords=[allRecords records]; end
            end
            imwrite(image,fullfile(folder,'search-image.png'));
            if ~isempty(allRecords), VIStudioMeasurementV17.overlay(image,allRecords,fullfile(folder,'all-object-measurements.png')); end
        end
        function draw(ax,objects)
            hold(ax,'on');
            for k=1:numel(objects)
                for rec=objects{k}.Data.Records
                    g=rec.Definition.Geometry; if isfield(rec.Details,'Position'), g=rec.Details.Position; end
                    color=[.2 .8 1]; if rec.Decision=="NG", color=[1 .2 .2]; elseif rec.Decision=="NOT_MEASURED", color=[1 .65 .1]; end
                    if rec.Definition.Kind=="circle", a=linspace(0,2*pi,80); plot(ax,g(1)+g(3)*cos(a),g(2)+g(3)*sin(a),'Color',color,'LineWidth',1.5);
                    else, plot(ax,g(:,1),g(:,2),'-o','Color',color,'LineWidth',1.5); end
                end
            end
            hold(ax,'off');
        end
    end
end
