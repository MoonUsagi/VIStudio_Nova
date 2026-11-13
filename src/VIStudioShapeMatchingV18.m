classdef VIStudioShapeMatchingV18 < handle
    % One-template R2026b native edge-based matching; pixel coordinates only.
    properties (SetAccess=private)
        Template=[]
        SearchImage=[]
        Options
        Model=[]
        Matches=[]
        Results=table()
        State="EMPTY"
        PolarityImplementation="NOT_RUN"
    end
    methods
        function app=VIStudioShapeMatchingV18, app.Options=app.defaults(); end
        function setTemplate(app,input,roi)
            image=app.readImage(input);
            if nargin>2 && ~isempty(roi)
                validateattributes(roi,{'numeric'},{'real','finite','vector','numel',4,'integer','positive'});
                roi=double(roi(:)'); x=roi(1); y=roi(2); w=roi(3); h=roi(4);
                assert(x+w-1<=size(image,2) && y+h-1<=size(image,1),'VIStudioV18:ROI','ROI exceeds reference image.');
                image=image(y:y+h-1,x:x+w-1,:);
            end
            assert(all(size(image,[1 2])>=16),'VIStudioV18:TemplateSize','Use a template at least 16 x 16 pixels.');
            app.Template=image; app.Model=[]; app.clearResult();
        end
        function setSearch(app,input), candidate=app.readImage(input); app.SearchImage=candidate; app.clearResult(); end
        function configure(app,options)
            candidate=app.validateOptions(options);
            if ~isequal(candidate,app.Options), app.Options=candidate; app.Model=[]; app.clearResult(); end
        end
        function buildModel(app)
            app.clearResult(); app.Model=[];
            assert(~isempty(app.Template),'VIStudioV18:Template','Load a template first.');
            assert(app.resources().APIAvailable,'VIStudioV18:ShapeUnavailable','Requires R2026b Visual Inspection Toolbox shapemodel.');
            o=app.Options;
            candidate=shapemodel(app.Template,'RotationRange',o.RotationRange,'ScaleRange',o.ScaleRange,'ClassName',o.ClassName);
            app.Model=candidate; app.State="MODEL_READY";
        end
        function results=run(app)
            app.clearResult();
            assert(~isempty(app.SearchImage),'VIStudioV18:SearchImage','Load a search image first.');
            if isempty(app.Model), app.buildModel(); end
            o=app.Options;
            try
                args={'ScoreThreshold',o.ScoreThreshold,'MaxMatches',o.MaxMatches,'OverlapThreshold',o.OverlapThreshold};
                try
                    candidates=matchshape(app.Model,app.SearchImage,args{:},'EdgePolarity',o.EdgePolarity);
                    app.PolarityImplementation="EdgePolarity="+o.EdgePolarity;
                catch apiError
                    % Some R2026b builds expose logical UsePolarity instead.
                    if contains(apiError.message,"Invalid argument name 'EdgePolarity'")
                        candidates=matchshape(app.Model,app.SearchImage,args{:},'UsePolarity',o.EdgePolarity=="sensitive");
                        app.PolarityImplementation="UsePolarity="+string(o.EdgePolarity=="sensitive");
                    else, rethrow(apiError); end
                end
                n=numel(candidates); id=(1:n)'; label=strings(n,1); score=zeros(n,1); x=score; y=score; angle=score; scale=score;
                for k=1:n
                    m=candidates(k); t=m.ModelOriginTransformation; a=t.A;
                    center=transformPointsForward(t,[0 0]); x(k)=center(1); y(k)=center(2);
                    angle(k)=atan2d(a(2,1),a(1,1)); scale(k)=hypot(a(1,1),a(2,1));
                    label(k)=string(m.ClassName); score(k)=double(m.Score);
                end
                results=table(id,label,score,x,y,angle,scale,'VariableNames',{'ID','Class','Score','OriginXpx','OriginYpx','AngleDeg','Scale'});
                app.Matches=candidates; app.Results=results; app.State="MATCHED"; if n==0, app.State="NO_MATCH"; end
            catch err
                app.clearResult(); app.State="ERROR"; rethrow(err);
            end
        end
        function points=templatePointsToSearch(app,points,index)
            validateattributes(points,{'numeric'},{'2d','ncols',2,'real','finite'});
            validateattributes(index,{'numeric'},{'scalar','integer','positive','<=',numel(app.Matches)});
            % Native transformations operate relative to the cropped model origin.
            points=double(transformPointsForward(app.Matches(index).ModelOriginTransformation,double(points)-app.Model.ModelOrigin));
        end
        function saveDefinition(app,file)
            assert(~isempty(app.Template),'VIStudioV18:Template','Load a template first.');
            definition=struct('Format',"VIStudioShapeDefinition",'Version',1,'Template',app.Template,'Options',app.Options);
            save(file,'definition','-v7.3');
        end
        function loadDefinition(app,file)
            loaded=load(file,'definition'); assert(isfield(loaded,'definition'),'VIStudioV18:Definition','Missing shape definition.'); d=loaded.definition;
            assert(isstruct(d) && isscalar(d) && all(isfield(d,{'Format','Version','Template','Options'})) && string(d.Format)=="VIStudioShapeDefinition" && isequal(d.Version,1),'VIStudioV18:Definition','Unsupported shape definition.');
            image=app.readImage(d.Template); o=app.validateOptions(d.Options);
            assert(all(size(image,[1 2])>=16),'VIStudioV18:TemplateSize','Template too small.');
            app.Template=image; app.Options=o; app.Model=[]; app.clearResult();
        end
        function folder=export(app,parent)
            assert(ismember(app.State,["MATCHED","NO_MATCH"]),'VIStudioV18:Results','Run matching before exporting.');
            assert(isfolder(parent),'VIStudioV18:Folder','Select an existing parent folder.'); folder=tempname(parent); mkdir(folder);
            writetable(app.Results,fullfile(folder,'matches.csv'));
            report=struct('Version',"18.0.0",'State',app.State,'CoordinateSpace',"search-image pixels; template-origin relative transform",'Options',app.Options,'Results',app.Results,'ModelOrigin',app.Model.ModelOrigin,'Template',app.Template,'SearchImage',app.SearchImage);
            report.Transforms=cell(1,numel(app.Matches)); for k=1:numel(app.Matches), report.Transforms{k}=app.Matches(k).ModelOriginTransformation.A; end
            report.PolarityImplementation=app.PolarityImplementation;
            save(fullfile(folder,'shape-report.mat'),'report','-v7.3'); app.saveDefinition(fullfile(folder,'shape-definition.mat'));
        end
    end
    methods (Access=private)
        function clearResult(app)
            app.Matches=[]; app.Results=table(); app.State="EMPTY"; app.PolarityImplementation="NOT_RUN";
            if ~isempty(app.Template), app.State="TEMPLATE_READY"; end
        end
    end
    methods (Static)
        function o=defaults()
            o=struct('RotationRange',[-180 180],'ScaleRange',[1 1],'ClassName',"part",'ScoreThreshold',.75,'MaxMatches',10,'OverlapThreshold',.5,'EdgePolarity',"sensitive");
        end
        function o=validateOptions(o)
            keys=fieldnames(VIStudioShapeMatchingV18.defaults()); assert(isstruct(o) && isscalar(o) && isequal(sort(fieldnames(o)),sort(keys)),'VIStudioV18:Options','Use the full shape options structure.');
            validateattributes(o.RotationRange,{'numeric'},{'real','finite','vector','numel',2,'>=',-180,'<=',180});
            validateattributes(o.ScaleRange,{'numeric'},{'real','finite','positive','vector','numel',2});
            o.RotationRange=double(o.RotationRange(:)'); o.ScaleRange=double(o.ScaleRange(:)');
            assert(o.RotationRange(1)<=o.RotationRange(2) && o.ScaleRange(1)<=o.ScaleRange(2),'VIStudioV18:Range','Minimum must not exceed maximum.');
            validateattributes(o.ScoreThreshold,{'numeric'},{'real','finite','scalar','>=',0,'<=',1});
            validateattributes(o.OverlapThreshold,{'numeric'},{'real','finite','scalar','>=',0,'<=',1});
            validateattributes(o.MaxMatches,{'numeric'},{'real','finite','scalar','integer','positive','<=',1000});
            o.ClassName=string(o.ClassName); assert(isscalar(o.ClassName) && ~ismissing(o.ClassName) && strlength(strtrim(o.ClassName))>0,'VIStudioV18:ClassName','Enter a class name.');
            o.EdgePolarity=string(validatestring(o.EdgePolarity,{'sensitive','globally-insensitive'}));
        end
        function im=readImage(input)
            if ischar(input) || isstring(input), input=imread(input); end
            assert((isnumeric(input) || islogical(input)) && isreal(input) && ~isempty(input) && all(isfinite(input),'all') && (ismatrix(input) || (ndims(input)==3 && size(input,3)==3)),'VIStudioV18:Image','Use a finite grayscale or RGB image.');
            if isfloat(input), assert(all(input>=0 & input<=1,'all'),'VIStudioV18:ImageRange','Floating-point images must be in [0,1].'); end
            im=input;
        end
        function r=resources()
            r=struct('APIAvailable',~isempty(which('shapemodel')),'Status',"API_NOT_FOUND");
            if r.APIAvailable, r.Status="API_PRESENT_NOT_RUN"; end
        end
        function [template,search,roi]=demo()
            template=uint8(30*ones(80,100)); template(14:66,18:82)=210; template(14:32,62:82)=30;
            [x,y]=meshgrid(1:100,1:80); template((x-40).^2+(y-40).^2<10^2)=30;
            search=uint8(30*ones(240,340)); search(91:170,111:210)=template; roi=[111 91 100 80];
        end
    end
end
