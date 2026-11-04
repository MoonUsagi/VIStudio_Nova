classdef VIStudioMeasurementV17 < handle
    properties (SetAccess=private)
        Raw=[]
        Image=[]
        ValidMask=[]
        SourceName=""
        SourceHash=""
        Profile=VIStudioGeometryV11.defaults()
        Scale=[1 1]
        Unit="px"
        Records=struct('ID',{},'Definition',{},'Value',{},'Unit',{},'State',{},'Decision',{},'Method',{},'Message',{},'Details',{},'SourceHash',{},'CalibrationHash',{})
        Dirty=false
    end
    properties (Access=private)
        UndoStack={}
        RedoStack={}
    end
    methods
        function loadImage(app,input,name)
            if nargin<3, name="image"; end
            if ischar(input) || isstring(input), [image,map]=imread(input); if ~isempty(map), image=ind2rgb(image,map); end; [~,n,e]=fileparts(input); name=string(n)+string(e); else, image=input; end
            VIStudioMeasurementV17.validateImage(image); app.Raw=image; app.Image=image; app.ValidMask=true(size(image,[1 2])); app.SourceName=string(name); app.SourceHash=VIStudioDataHealthV8.pixelHash(image); app.Profile=VIStudioGeometryV11.defaults(); app.Scale=[1 1]; app.Unit="px"; app.Records=app.Records([]); app.UndoStack={}; app.RedoStack={}; app.Dirty=false;
        end
        function setScale(app,sx,sy)
            app.requireImage(); validateattributes([sx sy],{'numeric'},{'finite','positive','numel',2}); assert(~app.Profile.Perspective,'VIStudioV17:Scale','Perspective calibration supplies the physical scale. Reset calibration before overriding it.'); app.remember(); app.Scale=double([sx sy]); app.Unit="mm"; app.Records=app.Records([]); app.Dirty=true;
        end
        function setReference(app,points,lengthMM)
            app.requireImage(); VIStudioMeasurementV17.checkPoints(points,size(app.Image,[1 2]),2); validateattributes(lengthMM,{'numeric'},{'scalar','positive','finite'}); pixels=norm(diff(points)); assert(pixels>0,'VIStudioV17:Reference','Reference points must differ.'); app.setScale(lengthMM/pixels,lengthMM/pixels);
        end
        function setProfile(app,profile)
            app.requireImage(); VIStudioGeometryV11.validate(profile); [image,context]=VIStudioGeometryV11.apply(app.Raw,profile); assert(context.ValidFraction>=profile.MinValidFraction,'VIStudioV17:Calibration','Insufficient valid calibrated image area.'); app.remember(); app.Profile=profile; app.Image=image; app.ValidMask=context.ValidMask; app.Scale=[1 1]; app.Unit="px";
            if profile.Perspective, app.Scale=[context.ScaleX context.ScaleY]; app.Unit="mm"; end; app.Records=app.Records([]); app.Dirty=true;
        end
        function resetCalibration(app), app.setProfile(VIStudioGeometryV11.defaults()); end
        function id=add(app,kind,geometry,options)
            if nargin<4, options=struct(); end; app.requireImage(); spec=VIStudioMeasurementV17.definition(kind,geometry,options); record=app.compute(spec); app.remember(); record.ID=VIStudioMeasurementV17.id(); app.Records(end+1)=record; app.Dirty=true; id=record.ID;
        end
        function remove(app,id)
            ix=app.index(id); app.remember(); app.Records(ix)=[]; app.Dirty=true;
        end
        function update(app,id,geometry,options)
            ix=app.index(id); if nargin<4, options=rmfield(app.Records(ix).Definition,{'Kind','Geometry'}); end; spec=VIStudioMeasurementV17.definition(app.Records(ix).Definition.Kind,geometry,options); record=app.compute(spec); record.ID=string(id); app.remember(); app.Records(ix)=record; app.Dirty=true;
        end
        function clear(app), if isempty(app.Records), return; end; app.remember(); app.Records=app.Records([]); app.Dirty=true; end
        function setTolerance(app,id,lower,upper)
            VIStudioMeasurementV17.limits(lower,upper); ix=app.index(id); app.remember(); app.Records(ix).Definition.Lower=lower; app.Records(ix).Definition.Upper=upper; app.Records(ix).Decision=VIStudioMeasurementV17.decide(app.Records(ix).Value,app.Records(ix).State,lower,upper); app.Dirty=true;
        end
        function undo(app)
            if isempty(app.UndoStack), return; end; app.RedoStack{end+1}=app.snapshot(); state=app.UndoStack{end}; app.UndoStack(end)=[]; app.restore(state); app.Dirty=true;
        end
        function redo(app)
            if isempty(app.RedoStack), return; end; app.UndoStack{end+1}=app.snapshot(); state=app.RedoStack{end}; app.RedoStack(end)=[]; app.restore(state); app.Dirty=true;
        end
        function rows=table(app)
            rows=table(strings(0,1),strings(0,1),strings(0,1),zeros(0,1),strings(0,1),zeros(0,1),zeros(0,1),strings(0,1),strings(0,1),strings(0,1),'VariableNames',{'ID','Name','Type','Value','Unit','Lower','Upper','Decision','Method','Message'});
            for r=app.Records, s=r.Definition; rows(end+1,:)={r.ID,s.Name,s.Kind,r.Value,r.Unit,s.Lower,s.Upper,r.Decision,r.Method,r.Message}; end
        end
        function recipe=recipe(app)
            app.requireImage(); recipe=struct('Version',17,'Kind',"VIStudioMeasurementRecipe",'SourceSize',size(app.Raw,[1 2]),'Profile',app.Profile,'Scale',app.Scale,'Unit',app.Unit,'Definitions',{{app.Records.Definition}},'ReferenceHash',app.SourceHash);
        end
        function saveRecipe(app,file)
            assert(~isfile(file),'VIStudioV17:FileExists','Choose a new recipe file.'); recipe=app.recipe(); save(file,'recipe','-v7.3');
        end
        function applyRecipe(app,input)
            app.requireImage(); if ischar(input) || isstring(input), loaded=load(input,'recipe'); recipe=loaded.recipe; else, recipe=input; end
            assert(isstruct(recipe) && isscalar(recipe) && all(isfield(recipe,{'Version','Kind','SourceSize','Profile','Scale','Unit','Definitions'})) && recipe.Version==17 && recipe.Kind=="VIStudioMeasurementRecipe",'VIStudioV17:Recipe','Invalid measurement recipe.'); assert(isequal(size(app.Raw,[1 2]),recipe.SourceSize),'VIStudioV17:RecipeSize','Recipe and source resolution differ.'); VIStudioGeometryV11.validate(recipe.Profile); validateattributes(recipe.Scale,{'numeric'},{'size',[1 2],'positive','finite'}); assert(any(string(recipe.Unit)==["px","mm"]),'VIStudioV17:Recipe','Invalid unit.');
            candidate=VIStudioMeasurementV17; candidate.loadImage(app.Raw,app.SourceName); candidate.setProfile(recipe.Profile);
            if recipe.Profile.Perspective, assert(string(recipe.Unit)=="mm" && max(abs(double(recipe.Scale)-candidate.Scale))<1e-10,'VIStudioV17:RecipeScale','Recipe scale must match perspective calibration.'); elseif string(recipe.Unit)=="px", assert(isequal(double(recipe.Scale),[1 1]),'VIStudioV17:RecipeScale','Pixel recipes must use unit scale.'); end
            candidate.Scale=double(recipe.Scale); candidate.Unit=string(recipe.Unit);
            for k=1:numel(recipe.Definitions), s=recipe.Definitions{k}; if s.Kind=="pointline" && s.Snap && s.NativeCaptured, assert(recipe.ReferenceHash==app.SourceHash,'VIStudioV17:NativeReplay','Snapped point-to-line captures require recapture on a new image; use a manual point-to-line recipe for fixed geometry.'); end; candidate.add(s.Kind,s.Geometry,rmfield(s,{'Kind','Geometry'})); end
            app.remember(); app.Profile=candidate.Profile; app.Image=candidate.Image; app.ValidMask=candidate.ValidMask; app.Scale=candidate.Scale; app.Unit=candidate.Unit; app.Records=candidate.Records; app.Dirty=true;
        end
        function saveSession(app,file)
            app.requireImage(); assert(~isfile(file),'VIStudioV17:FileExists','Choose a new session file.'); session=struct('Version',17,'Kind',"VIStudioMeasurementSession",'Image',app.Raw,'SourceName',app.SourceName,'SourceHash',app.SourceHash,'Recipe',app.recipe(),'Records',app.Records); save(file,'session','-v7.3'); app.Dirty=false;
        end
        function loadSession(app,file)
            loaded=load(file,'session'); assert(isfield(loaded,'session'),'VIStudioV17:Session','MAT requires a measurement session.'); s=loaded.session; assert(s.Version==17 && s.Kind=="VIStudioMeasurementSession",'VIStudioV17:Session','Unsupported measurement session.'); VIStudioMeasurementV17.validateImage(s.Image); assert(VIStudioDataHealthV8.pixelHash(s.Image)==s.SourceHash,'VIStudioV17:SessionHash','Embedded source image changed.');
            candidate=VIStudioMeasurementV17; candidate.loadImage(s.Image,s.SourceName); candidate.applyRecipe(s.Recipe); assert(numel(s.Records)==numel(candidate.Records),'VIStudioV17:Session','Record count differs from recipe.');
            % Recompute values from embedded image; never trust modified saved results.
            ids=string({s.Records.ID}); assert(all(strlength(ids)>0) && numel(unique(ids))==numel(ids),'VIStudioV17:Session','Measurement IDs must be unique and nonempty.'); for k=1:numel(s.Records), candidate.Records(k).ID=ids(k); end
            app.Raw=candidate.Raw; app.Image=candidate.Image; app.ValidMask=candidate.ValidMask; app.SourceName=candidate.SourceName; app.SourceHash=candidate.SourceHash; app.Profile=candidate.Profile; app.Scale=candidate.Scale; app.Unit=candidate.Unit; app.Records=candidate.Records; app.UndoStack={}; app.RedoStack={}; app.Dirty=false;
        end
        function export(app,folder)
            app.requireImage(); assert(~isfolder(folder) && ~isfile(folder),'VIStudioV17:FileExists','Choose a new output folder.'); mkdir(folder); rows=app.table(); records=app.Records; recipe=app.recipe(); sourceName=app.SourceName; sourceHash=app.SourceHash; save(fullfile(folder,'measurements.mat'),'rows','records','recipe','sourceName','sourceHash','-v7.3'); writetable(rows,fullfile(folder,'measurements.csv'),'Encoding','UTF-8'); imwrite(app.Image,fullfile(folder,'measurement-image.png')); VIStudioMeasurementV17.overlay(app.Image,records,fullfile(folder,'measurement-overlay.png')); app.saveSession(fullfile(folder,'measurement-session.mat'));
        end
    end
    methods (Access=private)
        function record=compute(app,s)
            image=app.Image; sz=size(image,[1 2]); scale=app.Scale; unit=app.Unit; value=NaN; state="MEASURED"; method="manual-geometry"; message=""; details=struct(); g=s.Geometry;
            if any(s.Kind==["area","length","width"]), assert(islogical(g) && isequal(size(g),sz) && any(g,'all'),'VIStudioV17:Mask','Require a nonempty logical mask with the current image dimensions.'); else
                n=2; if any(s.Kind==["angle","pointline"]), n=3; end
                if s.Kind=="circle", validateattributes(g,{'numeric'},{'size',[1 3],'real','finite'}); assert(g(3)>0 && g(1)-g(3)>=.5 && g(2)-g(3)>=.5 && g(1)+g(3)<=sz(2)+.5 && g(2)+g(3)<=sz(1)+.5,'VIStudioV17:Bounds','Circle must be inside the image.'); else, VIStudioMeasurementV17.checkPoints(g,sz,n); end
            end
            if s.Kind=="angle", unit="deg"; elseif s.Kind=="area", unit=app.Unit+"^2"; end
            try
                if ~all(app.ValidMask,'all')
                    if islogical(g), supported=all(app.ValidMask(g)); elseif s.Kind=="circle", [x,y]=meshgrid(1:sz(2),1:sz(1)); region=(x-g(1)).^2+(y-g(2)).^2<=g(3)^2; supported=all(app.ValidMask(region)); else, region=false(sz); for j=1:size(g,1)-1, t=linspace(0,1,max(2,ceil(norm(diff(g(j:j+1,:))))*2)); xy=g(j,:)+t'.*diff(g(j:j+1,:)); region(sub2ind(sz,round(xy(:,2)),round(xy(:,1))))=true; end; supported=all(app.ValidMask(region)); end
                    assert(supported,'VIStudioV17:InvalidRegion','Measurement touches pixels outside the valid calibrated image region.');
                end
                switch s.Kind
                    case "distance", value=norm(diff(g).*scale); details.Position=g;
                    case "caliper"
                        method="native-caliper"; assert(exist('caliper','file')>0,'VIStudioV17:Unavailable','Native caliper is unavailable.'); native=caliper(im2single(image),double(g),'Width',s.Width,'Sigma',s.Sigma,'GradientThreshold',s.Threshold,'EdgeTransition',char(s.Polarity),'MeasurementMode','edge-pair'); values=double(native.IntraEdgeDistance(:)); details.Native=native;
                        assert(numel(values)>=s.PairIndex,'VIStudioV17:NoEdges','Requested edge pair was not found. Try polarity, threshold, width, or another scan.'); delta=diff(g); factor=norm(delta.*scale)/norm(delta); value=values(s.PairIndex)*factor; details.CandidatePairs=numel(values); details.PairIndex=s.PairIndex; details.Position=g;
                    case "circle"
                        assert(abs(scale(1)-scale(2))<=1e-8*max(scale),'VIStudioV17:CircleScale','Circle diameter requires equal X/Y scale. Rectify the image or use pixel units.'); fitted=g;
                        if s.Snap, method="native-fitcircle"; assert(exist('fitcircle','file')>0,'VIStudioV17:Unavailable','Native circle fitting is unavailable.'); previousRng=rng; rng(s.RansacSeed,'twister'); restoreRng=onCleanup(@() rng(previousRng)); native=fitcircle(im2single(image),double(g),'Snap',true,'SnapNeighborhood',s.CircleBand,'RansacIterations',500,'RansacInlierDistance',s.InlierDistance); clear restoreRng; fitted=[native.Center(:)' native.Radius]; details.Native=native;
                            edges=edge(im2gray(im2single(image)),'canny'); [y,x]=find(edges); residual=abs(hypot(x-fitted(1),y-fitted(2))-fitted(3)); assert(nnz(residual<=max(2,s.InlierDistance*2))>=max(8,ceil(.2*pi*fitted(3))),'VIStudioV17:NoEdges','Circle has insufficient supporting edge pixels.');
                        end
                        assert(all(isfinite(fitted)) && fitted(3)>0,'VIStudioV17:NoEdges','No finite fitted circle.'); value=2*fitted(3)*scale(1); details.Position=fitted; details.Radius=value/2; details.Area=pi*(value/2)^2; details.Circumference=pi*value;
                    case "angle"
                        fitted=g; if s.Snap, native=fitangle(im2single(image),double(g),'Snap',true,'SnapNeighborhood',s.Neighborhood,'LineSnapMethod',char(s.LineMethod)); fitted=native.Position; details.Native=native; method="native-fitangle"; assert(VIStudioMeasurementV17.edgeSupport(image,fitted([1 2],:))>=.35 && VIStudioMeasurementV17.edgeSupport(image,fitted([2 3],:))>=.35,'VIStudioV17:NoEdges','Angle edges have insufficient support.'); end
                        a=(fitted(1,:)-fitted(2,:)).*scale; b=(fitted(3,:)-fitted(2,:)).*scale; assert(norm(a)>eps && norm(b)>eps,'VIStudioV17:Degenerate','Angle arms must have positive length.'); value=acosd(max(-1,min(1,dot(a,b)/(norm(a)*norm(b))))); unit="deg"; details.Position=fitted;
                    case "pointline"
                        assert(~s.Snap || s.NativeCaptured,'VIStudioV17:InteractiveRequired','For snapped point-to-line measurement, capture a native T-square tool; otherwise disable snapping.'); a=g(1,:).*scale; b=g(2,:).*scale; p=g(3,:).*scale; delta=b-a; assert(norm(delta)>eps,'VIStudioV17:Degenerate','Reference line points must differ.'); value=abs(det([delta;p-a]))/norm(delta); details.Position=g;
                        if s.Snap, method="native-uitsquare-capture"; assert(VIStudioMeasurementV17.edgeSupport(image,g(1:2,:))>=.35,'VIStudioV17:NoEdges','Reference line has insufficient edge support.'); e=imdilate(edge(im2gray(im2single(image)),'canny'),strel('disk',2,0)); assert(e(round(g(3,2)),round(g(3,1))),'VIStudioV17:NoEdges','Measurement point has insufficient edge support.'); end
                    case "area", value=nnz(g)*prod(scale); unit=app.Unit+"^2"; method="mask-pixel-area"; details.Position=g;
                    case {"length","width"}
                        o=VIStudioDefectsV11.defaults(); o.ScaleEnabled=unit=="mm"; o.MMPerPixelX=scale(1); o.MMPerPixelY=scale(2); r=VIStudioDefectsV11.rotated(g,o); assert(height(r)==1,'VIStudioV17:MaskObjects','Rotated dimensions require one connected object.'); method="mask-minimum-rectangle"; details.Dimensions=r; details.Position=g;
                        if unit=="mm", value=r.LengthMM; if s.Kind=="width", value=r.ShortWidthMM; end; else, value=r.LengthPx; if s.Kind=="width", value=r.ShortWidthPx; end, end
                end
                assert(isscalar(value) && isfinite(value),'VIStudioV17:NoMeasurement','No finite measurement was produced.');
            catch err
                value=NaN; state="NOT_MEASURED"; message=string(err.message); details.ErrorID=string(err.identifier);
            end
            calibration=struct('Profile',app.Profile,'Scale',scale,'Unit',app.Unit); calibrationHash=VIStudioDatasetV9.digest(jsonencode(calibration)); record=struct('ID',"",'Definition',s,'Value',double(value),'Unit',unit,'State',state,'Decision',VIStudioMeasurementV17.decide(value,state,s.Lower,s.Upper),'Method',method,'Message',message,'Details',details,'SourceHash',app.SourceHash,'CalibrationHash',calibrationHash);
        end
        function requireImage(app), assert(~isempty(app.Image),'VIStudioV17:NoImage','Load an image first.'); end
        function ix=index(app,id), ix=find(string({app.Records.ID})==string(id),1); assert(~isempty(ix),'VIStudioV17:Selection','Select a measurement.'); end
        function s=snapshot(app), s=struct('Image',app.Image,'ValidMask',app.ValidMask,'Profile',app.Profile,'Scale',app.Scale,'Unit',app.Unit,'Records',app.Records); end
        function restore(app,s), app.Image=s.Image; app.ValidMask=s.ValidMask; app.Profile=s.Profile; app.Scale=s.Scale; app.Unit=s.Unit; app.Records=s.Records; end
        function remember(app), app.UndoStack{end+1}=app.snapshot(); if numel(app.UndoStack)>50, app.UndoStack(1)=[]; end; app.RedoStack={}; end
    end
    methods (Static)
        function s=definition(kind,g,o)
            kind=string(validatestring(kind,{'distance','caliper','circle','angle','pointline','area','length','width'})); s=struct('Kind',kind,'Geometry',g,'Name',kind,'Lower',NaN,'Upper',NaN,'Snap',false,'Width',10,'Sigma',1,'Threshold',.1,'Polarity',"both",'PairIndex',1,'Neighborhood',20,'CircleBand',.25,'InlierDistance',1,'LineMethod',"closest",'NativeCaptured',false,'RansacSeed',0);
            assert(isstruct(o) && isscalar(o),'VIStudioV17:Options','Options must be scalar struct.'); for key=fieldnames(o)', assert(isfield(s,key{1}) && ~ismember(key{1},{'Kind','Geometry'}),'VIStudioV17:Options','Unknown option.'); s.(key{1})=o.(key{1}); end
            s.Name=string(s.Name); assert(isscalar(s.Name) && strlength(s.Name)>0,'VIStudioV17:Name','Measurement name is required.'); VIStudioMeasurementV17.limits(s.Lower,s.Upper); validateattributes([s.Snap s.NativeCaptured],{'logical'},{'numel',2}); validateattributes([s.Width s.Sigma],{'numeric'},{'finite','nonnegative'}); validateattributes(s.Threshold,{'numeric'},{'scalar','positive','<=',1,'finite'}); validateattributes([s.PairIndex s.Neighborhood],{'numeric'},{'integer','positive','finite'}); validateattributes(s.RansacSeed,{'numeric'},{'scalar','integer','nonnegative','finite','<=',2^32-1}); validateattributes([s.CircleBand s.InlierDistance],{'numeric'},{'positive','finite'}); validatestring(s.Polarity,{'both','rising','falling'}); validatestring(s.LineMethod,{'closest','strongest','parallel','combined'});
        end
        function limits(lower,upper), validateattributes([lower upper],{'numeric'},{'real','numel',2}); assert(all(isfinite([lower upper]) | isnan([lower upper])) && (isnan(lower) || isnan(upper) || lower<=upper),'VIStudioV17:Limits','Limits must be finite or NaN, with lower <= upper.'); end
        function text=decide(value,state,lower,upper)
            text="NOT_MEASURED"; if state~="MEASURED" || ~isfinite(value), return; end; text="MEASURED"; if isnan(lower) && isnan(upper), return; end; text="OK"; if (~isnan(lower) && value<lower) || (~isnan(upper) && value>upper), text="NG"; end
        end
        function validateImage(image), validateattributes(image,{'uint8','uint16','single','double','logical'},{'nonempty','real','finite'}); assert(ndims(image)<=3 && any(size(image,3)==[1 3]) && min(size(image,[1 2]))>=8,'VIStudioV17:Image','Require a grayscale or RGB image of at least 8x8.'); if isfloat(image), assert(all(image>=0 & image<=1,'all'),'VIStudioV17:ImageRange','Floating images must be in [0,1].'); end, end
        function checkPoints(points,sz,n), validateattributes(points,{'numeric'},{'size',[n 2],'real','finite'}); assert(all(points(:,1)>=1 & points(:,1)<=sz(2)) && all(points(:,2)>=1 & points(:,2)<=sz(1)),'VIStudioV17:Bounds','Measurement points must be inside the current image.'); end
        function support=edgeSupport(image,line)
            edges=imdilate(edge(im2gray(im2single(image)),'canny'),strel('disk',2,0)); t=linspace(.1,.9,max(10,ceil(norm(diff(line))))); xy=line(1,:)+t'.*diff(line); x=round(xy(:,1)); y=round(xy(:,2)); valid=x>=1 & y>=1 & x<=size(image,2) & y<=size(image,1); support=0; if any(valid), support=mean(edges(sub2ind(size(edges),y(valid),x(valid)))); end
        end
        function id=id(), [~,name]=fileparts(tempname); id="m_"+string(name); end
        function overlay(image,records,file)
            fig=figure('Visible','off','Color','white','Position',[0 0 1100 750]); cleanup=onCleanup(@() delete(fig)); ax=axes(fig); imshow(image,'Parent',ax); hold(ax,'on');
            for k=1:numel(records)
                r=records(k); g=r.Definition.Geometry; if isfield(r.Details,'Position'), g=r.Details.Position; end; color=[.0 .8 .65]; if r.Decision=="NG", color=[1 .25 .2]; elseif r.State~="MEASURED", color=[1 .65 .1]; end
                if islogical(g), boundaries=bwboundaries(g); for b=1:numel(boundaries), p=boundaries{b}; plot(ax,p(:,2),p(:,1),'Color',color,'LineWidth',1.8); end; [y,x]=find(g); position=[mean(x) mean(y)];
                elseif r.Definition.Kind=="circle", t=linspace(0,2*pi,150); plot(ax,g(1)+g(3)*cos(t),g(2)+g(3)*sin(t),'Color',color,'LineWidth',1.8); position=g(1:2);
                else, plot(ax,g(:,1),g(:,2),'-o','Color',color,'LineWidth',1.8); position=g(1,:); end
                text(ax,position(1),position(2),sprintf('%s: %.4g %s [%s]',r.Definition.Name,r.Value,r.Unit,r.Decision),'Color','white','BackgroundColor',[.05 .10 .17],'Interpreter','none','FontSize',10,'VerticalAlignment','bottom');
            end; title(ax,'VIStudio Measurement | current measurement image','Interpreter','none'); exportgraphics(ax,file,'Resolution',130);
        end
        function summary=batch(recipeInput,files,folder)
            if ischar(recipeInput) || isstring(recipeInput), loaded=load(recipeInput,'recipe'); recipe=loaded.recipe; else, recipe=recipeInput; end; files=string(files(:)); assert(~isempty(files) && all(isfile(files)),'VIStudioV17:Batch','Select existing image files.'); assert(~isfolder(folder) && ~isfile(folder),'VIStudioV17:FileExists','Choose a new batch folder.'); mkdir(folder); summary=table(strings(0,1),strings(0,1),zeros(0,1),zeros(0,1),zeros(0,1),strings(0,1),'VariableNames',{'File','State','Measurements','NG','NotMeasured','Message'});
            for k=1:numel(files)
                [~,name,ext]=fileparts(files(k)); state="MEASURED"; message=""; count=0; ng=0; failed=0;
                try, data=VIStudioMeasurementV17; data.loadImage(files(k)); data.applyRecipe(recipe); rows=data.table(); count=height(rows); ng=nnz(rows.Decision=="NG"); failed=nnz(rows.Decision=="NOT_MEASURED"); if failed>0, state="REVIEW"; elseif ng>0, state="NG"; elseif all(rows.Decision=="OK") && ~isempty(rows), state="OK"; end; data.export(fullfile(folder,sprintf('image_%05d',k)));
                catch err, state="ERROR"; message=string(err.message); end
                summary(end+1,:)={string(name)+string(ext),state,count,ng,failed,message};
            end; writetable(summary,fullfile(folder,'batch-summary.csv'),'Encoding','UTF-8'); save(fullfile(folder,'batch-summary.mat'),'summary','recipe','-v7.3');
        end
    end
end
