classdef VIStudioChangeDetectionV22 < handle
    properties (SetAccess=private)
        Reference=[]
        Current=[]
        ReferenceHash=""
        CurrentHash=""
        Allowed=[]
        Truth=[]
        Artifact=[]
        Options
        Aligned=[]
        Valid=[]
        Score=[]
        Mask=[]
        Regions=table()
        Registration=struct()
        Evaluation=[]
        State="EMPTY"
        Message=""
    end
    methods
        function app=VIStudioChangeDetectionV22, app.Options=app.defaults(); end
        function setReference(app,input)
            [im,digest]=app.read(input); app.Reference=im; app.ReferenceHash=digest; app.Allowed=true(size(im,[1 2])); app.Truth=[]; app.clear();
        end
        function setCurrent(app,input), [im,digest]=app.read(input); app.Current=im; app.CurrentHash=digest; app.Truth=[]; app.clear(); end
        function setAllowed(app,mask)
            assert(islogical(mask) && isequal(size(mask),size(app.Reference,[1 2])) && any(mask,'all'),'VIStudioV22:ChangeROI','Use a nonempty logical ROI mask in reference coordinates.'); app.Allowed=mask; app.clear();
        end
        function setTruth(app,mask)
            assert(islogical(mask) && isequal(size(mask),size(app.Reference,[1 2])),'VIStudioV22:ChangeTruth','Truth mask must match reference coordinates.'); app.Truth=mask; app.Evaluation=[]; if app.State=="COMPLETE", app.evaluate(); end
        end
        function configure(app,o), o=app.validate(o); if ~isequal(o,app.Options), app.Options=o; app.clear(); end, end
        function loadArtifact(app,file)
            app.Artifact=[]; app.clear();
            info=whos('-file',file);
            if any(strcmp({info.name},'checkpoint')), artifact=VIStudioFCSiamV22.loadWeights(file);
            else, loaded=load(file,'artifact'); assert(isfield(loaded,'artifact'),'VIStudioV22:ChangeModel','MAT requires a native checkpoint or artifact variable.'); artifact=loaded.artifact;
                assert(~isfield(artifact,'Metadata') || ~isfield(artifact.Metadata,'Kind') || ~isequal(string(artifact.Metadata.Kind),"VIStudioNativeFCSiam"),'VIStudioV22:ChangeModel','Load full FC-Siam through its strict native weights checkpoint.');
            end
            app.setArtifact(artifact);
        end
        function setArtifact(app,artifact)
            VIStudioChangeModelsV22.validate(artifact); app.Artifact=artifact; app.clear();
        end
        function mask=run(app)
            app.clear(); assert(~isempty(app.Reference) && ~isempty(app.Current),'VIStudioV22:ChangePair','Load a reference and comparison image.'); o=app.Options; app.State="RUNNING";
            try
                ref=app.Reference; cur=app.Current; sz=size(ref,[1 2]); registration=struct('Mode',o.Alignment,'Matrix',eye(3),'Matches',0,'Inliers',0,'RMSEpx',NaN);
                if o.Alignment=="none"
                    assert(isequal(size(cur,[1 2]),sz),'VIStudioV22:ChangeSize','Without registration, image dimensions must match. No automatic resizing is performed.'); aligned=cur; valid=true(sz);
                else
                    previous=rng; rng(o.Seed,'twister'); reset=onCleanup(@() rng(previous));
                    a=im2gray(cur); b=im2gray(ref); p1=detectSURFFeatures(a,'MetricThreshold',100); p2=detectSURFFeatures(b,'MetricThreshold',100);
                    assert(p1.Count>=8 && p2.Count>=8,'VIStudioV22:ChangeFeatures','Not enough textured features for reliable registration.');
                    [f1,v1]=extractFeatures(a,p1.selectStrongest(1500)); [f2,v2]=extractFeatures(b,p2.selectStrongest(1500)); pairs=matchFeatures(f1,f2,'Unique',true,'MaxRatio',.7);
                    assert(size(pairs,1)>=8,'VIStudioV22:ChangeMatches','Too few registration matches.'); x=v1(pairs(:,1)).Location; y=v2(pairs(:,2)).Location;
                    [t,inliers,status]=estgeotform2d(x,y,char(o.Alignment),'MaxDistance',3,'Confidence',99.5,'MaxNumTrials',2000);
                    assert(status==0 && nnz(inliers)>=8 && nnz(inliers)/size(pairs,1)>=.25,'VIStudioV22:ChangeRegistration','Registration was rejected by the inlier gate.');
                    pred=transformPointsForward(t,x(inliers,:)); rmse=sqrt(mean(sum((pred-y(inliers,:)).^2,2))); assert(isfinite(rmse) && rmse<=3,'VIStudioV22:ChangeRegistration','Registration error exceeds 3 px.');
                    view=imref2d(sz); aligned=imwarp(cur,t,'OutputView',view); valid=imwarp(true(size(cur,[1 2])),t,'nearest','OutputView',view);
                    registration=struct('Mode',o.Alignment,'Matrix',double(t.A),'Matches',size(pairs,1),'Inliers',nnz(inliers),'RMSEpx',double(rmse)); clear reset;
                end
                margin=o.Border; if o.Method=="ssim", margin=max(margin,6); end
                if margin>0, valid=imerode(padarray(valid,[margin margin],false),strel('disk',margin,0)); valid=valid(margin+1:end-margin,margin+1:end-margin); end
                analysis=valid & app.Allowed; fraction=nnz(analysis)/nnz(app.Allowed);
                assert(nnz(analysis)>0 && fraction>=o.MinValidFraction,'VIStudioV22:ChangeValidArea','Too little valid overlap remains inside the ROI.');
                corrected=aligned; offset=zeros(1,3);
                if o.BrightnessOffset
                    for c=1:3, r=ref(:,:,c); q=aligned(:,:,c); offset(c)=median(q(analysis)-r(analysis)); corrected(:,:,c)=min(1,max(0,q-offset(c))); end
                end
                switch o.Method
                    case "absdiff", score=max(abs(corrected-ref),[],3);
                    case "ssim"
                        [~,map]=ssim(im2gray(corrected),im2gray(ref),'DynamicRange',1); assert(isequal(size(map),sz),'VIStudioV22:ChangeSSIM','Unexpected native SSIM map dimensions.'); score=min(1,max(0,1-map));
                    case {"research-model","fc-siam-diff","fc-siam-conc"}
                        assert(~isempty(app.Artifact),'VIStudioV22:ChangeModel','Load a research model artifact first.'); score=VIStudioChangeModelsV22.predict(app.Artifact,ref,corrected);
                        if o.Method~="research-model", assert(app.Artifact.Metadata.Architecture==o.Method,'VIStudioV22:ChangeModelVariant','Selected model differs from loaded weights.'); end
                end
                assert(isequal(size(score),sz) && all(isfinite(score),'all') && all(score>=0 & score<=1,'all'),'VIStudioV22:ChangeScore','Score map must be finite [0,1] in reference coordinates.');
                score(~analysis)=0; mask=bwareaopen(score>=o.Threshold & analysis,o.MinArea,8); stats=regionprops(mask,score,'Area','BoundingBox','Centroid','MeanIntensity','MaxIntensity');
                regions=table('Size',[0 6],'VariableTypes',{'double','double','cell','cell','double','double'},'VariableNames',{'RegionID','AreaPx','BoundingBox','Centroid','MeanScore','MaxScore'});
                for k=1:numel(stats), s=stats(k); regions(end+1,:)={k,s.Area,{s.BoundingBox},{s.Centroid},s.MeanIntensity,s.MaxIntensity}; end
                app.Aligned=aligned; app.Valid=analysis; app.Score=single(score); app.Mask=mask; app.Regions=regions; registration.ValidFraction=fraction; registration.BrightnessOffset=offset; app.Registration=registration; app.State="COMPLETE";
                app.Message="變化候選，不等於缺陷判定 / Change candidates, not defect acceptance"; if ~ismember(o.Method,["absdiff","ssim"]), app.Message="實驗模型；未通過實際資料驗證 / Research model; not validated on real data"; if isfield(app.Artifact.Metadata,'WeightStatus'), app.Message=app.Message+" · "+app.Artifact.Metadata.WeightStatus; end, end
                if ~isempty(app.Truth), app.evaluate(); end
            catch err, app.State="ERROR"; app.Message=string(err.message); rethrow(err); end
        end
        function metrics=evaluate(app)
            assert(app.State=="COMPLETE" && ~isempty(app.Truth),'VIStudioV22:ChangeEvaluation','Run the pair and load a reference-space truth mask.');
            p=app.Mask(app.Valid); g=app.Truth(app.Valid); tp=nnz(p & g); fp=nnz(p & ~g); fn=nnz(~p & g); tn=nnz(~p & ~g);
            iou=NaN; dice=NaN; precision=NaN; recall=NaN; status="DEFINED"; if tp+fp+fn>0, iou=tp/(tp+fp+fn); dice=2*tp/(2*tp+fp+fn); else, status="NO_POSITIVES_BOTH_EMPTY"; end
            if tp+fp>0, precision=tp/(tp+fp); end; if tp+fn>0, recall=tp/(tp+fn); end
            metrics=struct('TP',tp,'FP',fp,'FN',fn,'TN',tn,'IoU',iou,'Dice',dice,'Precision',precision,'Recall',recall,'EvaluatedPixels',nnz(app.Valid),'Status',status); app.Evaluation=metrics;
        end
        function folder=export(app,parent)
            assert(app.State=="COMPLETE",'VIStudioV22:ChangeResult','Complete detection before exporting.'); assert(isfolder(parent),'VIStudioV22:Folder','Select an output parent.'); folder=tempname(parent); mkdir(folder);
            report=struct('Version',"22.0.0",'Options',app.Options,'ReferenceHash',app.ReferenceHash,'CurrentHash',app.CurrentHash,'Registration',app.Registration,'Regions',app.Regions,'Evaluation',app.Evaluation,'Reference',app.Reference,'AlignedCurrent',app.Aligned,'Score',app.Score,'Mask',app.Mask,'Valid',app.Valid,'Truth',app.Truth,'Meaning',app.Message);
            if ~isempty(app.Artifact), report.ResearchModelMetadata=app.Artifact.Metadata; end
            save(fullfile(folder,'change-report.mat'),'report','-v7.3');
            imwrite(im2uint16(app.Reference),fullfile(folder,'reference.png')); imwrite(im2uint16(app.Aligned),fullfile(folder,'aligned-current.png')); imwrite(im2uint16(app.Score),fullfile(folder,'change-score.png')); imwrite(uint8(app.Mask)*255,fullfile(folder,'change-mask.png')); imwrite(uint8(app.Valid)*255,fullfile(folder,'valid-region.png')); imwrite(app.overlay(),fullfile(folder,'change-overlay.png'));
            imwrite(im2uint16(app.Current),fullfile(folder,'current.png')); imwrite(uint8(app.Allowed)*255,fullfile(folder,'allowed-roi.png')); if ~isempty(app.Truth), imwrite(uint8(app.Truth)*255,fullfile(folder,'truth.png')); end
            regions=app.Regions; flat=table(regions.RegionID,regions.AreaPx,regions.MeanScore,regions.MaxScore,'VariableNames',{'RegionID','AreaPx','MeanScore','MaxScore'}); boxes=zeros(height(regions),4); centers=zeros(height(regions),2); for k=1:height(regions), boxes(k,:)=regions.BoundingBox{k}; centers(k,:)=regions.Centroid{k}; end; flat.BoxX=boxes(:,1); flat.BoxY=boxes(:,2); flat.BoxWidth=boxes(:,3); flat.BoxHeight=boxes(:,4); flat.CentroidX=centers(:,1); flat.CentroidY=centers(:,2); writetable(flat,fullfile(folder,'regions.csv'),'Encoding','UTF-8');
            if ~isempty(app.Evaluation), writetable(struct2table(app.Evaluation),fullfile(folder,'evaluation.csv'),'Encoding','UTF-8'); end
        end
        function image=overlay(app)
            image=im2uint8(app.Aligned); if isempty(app.Mask), return; end
            edge=bwperim(app.Mask); for c=1:3, p=image(:,:,c); value=uint8(0); if c==1, value=255; end; p(edge)=value; image(:,:,c)=p; end
        end
    end
    methods (Access=private)
        function clear(app)
            app.Aligned=[]; app.Valid=[]; app.Score=[]; app.Mask=[]; app.Regions=table(); app.Evaluation=[]; app.Registration=struct(); app.Message=""; app.State="EMPTY"; if ~isempty(app.Reference) && ~isempty(app.Current), app.State="READY"; end
        end
    end
    methods (Static)
        function o=defaults(), o=struct('Method',"absdiff",'Alignment',"none",'Threshold',.15,'MinArea',12,'Border',2,'MinValidFraction',.75,'BrightnessOffset',false,'Seed',21); end
        function o=validate(o)
            assert(isstruct(o) && isscalar(o) && isequal(sort(fieldnames(o)),sort(fieldnames(VIStudioChangeDetectionV22.defaults()))),'VIStudioV22:ChangeOptions','Use the full change options structure.');
            o.Method=string(validatestring(o.Method,{'absdiff','ssim','research-model','fc-siam-diff','fc-siam-conc'})); o.Alignment=string(validatestring(o.Alignment,{'none','translation','rigid','similarity'}));
            validateattributes(o.Threshold,{'numeric'},{'scalar','finite','>',0,'<=',1}); validateattributes(o.MinArea,{'numeric'},{'scalar','integer','positive'}); validateattributes(o.Border,{'numeric'},{'scalar','integer','>=',0,'<=',100}); validateattributes(o.MinValidFraction,{'numeric'},{'scalar','finite','>',0,'<=',1}); validateattributes(o.BrightnessOffset,{'logical'},{'scalar'}); validateattributes(o.Seed,{'numeric'},{'scalar','integer','>=',0,'<=',2^32-1});
        end
        function [image,digest]=read(input)
            if ischar(input) || isstring(input), digest=VIStudioToolsV3.fileHash(input); [image,map,alpha]=imread(input); maximum=1; if ~isempty(alpha) && isinteger(alpha), maximum=intmax(class(alpha)); end; assert(isempty(alpha) || all(alpha==maximum,'all'),'VIStudioV22:ChangeAlpha','Flatten transparent inputs explicitly.'); if ~isempty(map), image=ind2rgb(image,map); end
            else, image=input; digest=VIStudioDataHealthV8.pixelHash(image); end
            VIStudioMeasurementV17.validateImage(image); assert(prod(size(image,[1 2]))<=8e6,'VIStudioV22:ChangeSize','Use images up to 8 million pixels.'); image=im2single(image); if size(image,3)==1, image=repmat(image,1,1,3); end
        end
        function [reference,current,truth]=demo()
            s=RandStream('mt19937ar','Seed',21); gray=imgaussfilt(.35+.3*rand(s,240,320,'single'),.6); gray(40:190,45:275)=gray(40:190,45:275)+.12; reference=repmat(gray,1,1,3); current=reference; current(105:135,150:185,:)=.05; truth=false(240,320); truth(105:135,150:185)=true;
        end
    end
end
