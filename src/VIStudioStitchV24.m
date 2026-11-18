classdef VIStudioStitchV24 < handle
    properties (SetAccess=private)
        Sources=struct('File',{},'SHA256',{},'Size',{},'Channels',{})
        Options
        Panorama=[]
        Coverage=[]
        Quality=table()
        Transforms={}
        CanvasTransforms={}
        OutputView=[]
        State="EMPTY"
        Message=""
    end
    methods
        function app=VIStudioStitchV24, app.Options=app.defaults(); end
        function setFiles(app,files)
            files=string(files(:)); assert(numel(files)>=2 && numel(files)<=20 && numel(unique(files))==numel(files),'VIStudioV24:StitchFiles','Choose 2-20 distinct ordered images.');
            sources=app.Sources([]); total=0;
            for k=1:numel(files)
                assert(isfile(files(k)),'VIStudioV24:StitchFiles','Missing source image.'); im=app.read(files(k)); total=total+size(im,1)*size(im,2);
                assert(total<=40e6,'VIStudioV24:StitchInputLimit','Total input exceeds 40 million pixels. Resize or split the sequence.');
                sources(end+1)=struct('File',VIStudioToolsV3.canonicalPath(files(k)),'SHA256',VIStudioToolsV3.fileHash(files(k)),'Size',size(im,[1 2]),'Channels',size(im,3));
            end
            app.Sources=sources; app.clear();
        end
        function configure(app,o), candidate=app.validate(o); if ~isequal(app.Options,candidate), app.Options=candidate; app.clear(); end, end
        function image=run(app)
            app.clear(); assert(numel(app.Sources)>=2,'VIStudioV24:StitchFiles','Load an ordered image sequence.'); o=app.Options; app.State="RUNNING"; n=numel(app.Sources); active=0;
            app.Quality=table((1:n)',zeros(n,1),zeros(n,1),nan(n,1),nan(n,1),nan(n,1),repmat("PENDING",n,1),strings(n,1),'VariableNames',{'Source','Matches','Inliers','InlierRatio','RMSEpx','Overlap','State','Message'});
            previousRng=rng; rng(o.Seed,'twister'); restore=onCleanup(@() rng(previousRng));
            try
                transforms=cell(1,n); transforms{1}=projtform2d(eye(3)); app.Quality.State(1)="REFERENCE";
                prev=im2gray(app.checkedRead(1));
                for k=2:n
                    active=k; current=im2gray(app.checkedRead(k));
                    p1=detectSURFFeatures(current,'MetricThreshold',100); p2=detectSURFFeatures(prev,'MetricThreshold',100);
                    assert(p1.Count>=o.MinInliers && p2.Count>=o.MinInliers,'VIStudioV24:StitchFeatures','Too few stable features. Use overlapping textured images.');
                    [f1,v1]=extractFeatures(current,p1.selectStrongest(o.MaxFeatures)); [f2,v2]=extractFeatures(prev,p2.selectStrongest(o.MaxFeatures));
                    pairs=matchFeatures(f1,f2,'Unique',true,'MaxRatio',.7); app.Quality.Matches(k)=size(pairs,1);
                    assert(size(pairs,1)>=o.MinInliers,'VIStudioV24:StitchMatches','Too few feature matches between adjacent images.');
                    a=v1(pairs(:,1)).Location; b=v2(pairs(:,2)).Location;
                    [pair,inliers,status]=estgeotform2d(a,b,char(o.Model),'MaxDistance',o.MaxError,'Confidence',99.5,'MaxNumTrials',3000);
                    assert(status==0,'VIStudioV24:StitchRegistration','Robust registration failed.'); count=nnz(inliers); ratio=count/size(pairs,1);
                    app.Quality.Inliers(k)=count; app.Quality.InlierRatio(k)=ratio;
                    assert(count>=o.MinInliers && ratio>=o.MinInlierRatio,'VIStudioV24:StitchInliers','Insufficient inliers or inlier ratio.');
                    predicted=transformPointsForward(pair,a(inliers,:)); error=sqrt(mean(sum((predicted-b(inliers,:)).^2,2))); app.Quality.RMSEpx(k)=error;
                    assert(isfinite(error) && error<=o.MaxError,'VIStudioV24:StitchError','Registration reprojection error is too large.');
                    transforms{k}=projtform2d(double(transforms{k-1}.A)*double(pair.A)); app.bounds(transforms{k},app.Sources(k).Size);
                    app.Quality.State(k)="REGISTERED"; prev=current;
                end
                active=0; limits=zeros(n,4);
                for k=1:n, limits(k,:)=app.bounds(transforms{k},app.Sources(k).Size); end
                xmin=floor(min(limits(:,1))); xmax=ceil(max(limits(:,2))); ymin=floor(min(limits(:,3))); ymax=ceil(max(limits(:,4))); width=xmax-xmin+1; height=ymax-ymin+1;
                assert(isfinite(width*height) && width>0 && height>0 && width*height<=o.MaxCanvasPixels,'VIStudioV24:StitchCanvas','Output canvas exceeds the pixel limit or is invalid.');
                view=imref2d([height width],[xmin-.5 xmax+.5],[ymin-.5 ymax+.5]); channels=max([app.Sources.Channels]); accumulator=zeros(height,width,channels,'single'); weights=zeros(height,width,'single'); coverage=zeros(height,width,'uint8'); canvas=cell(1,n);
                for k=1:n
                    active=k; im=app.checkedRead(k); if channels==3 && size(im,3)==1, im=repmat(im,1,1,3); end
                    warped=imwarp(im,transforms{k},'OutputView',view); mask=imwarp(true(size(im,[1 2])),transforms{k},'nearest','OutputView',view);
                    if k>1
                        overlap=nnz(mask & coverage>0)/max(1,min(nnz(mask),nnz(coverage>0))); app.Quality.Overlap(k)=overlap;
                        assert(overlap>=o.MinOverlap,'VIStudioV24:StitchOverlap','Registered image has insufficient overlap with the current mosaic.');
                    end
                    w=single(mask);
                    if o.Blend=="feather", d=bwdist(~padarray(mask,[1 1],false)); d=d(2:end-1,2:end-1); w=single(mask).*min(single(d),32); end
                    accumulator=accumulator+warped.*w; weights=weights+w; coverage=coverage+uint8(mask);
                    canvas{k}=projtform2d([1 0 1-xmin;0 1 1-ymin;0 0 1]*double(transforms{k}.A)); app.Quality.State(k)="ACCEPTED"; if k==1, app.Quality.State(k)="REFERENCE"; end
                end
                for k=1:n, active=k; assert(VIStudioToolsV3.fileHash(app.Sources(k).File)==app.Sources(k).SHA256,'VIStudioV24:StitchSourceChanged','Input changed during stitching. Reload sources.'); end
                image=accumulator./max(weights,eps('single')); image=min(1,max(0,image));
                app.Panorama=image; app.Coverage=coverage; app.OutputView=view; app.Transforms=transforms; app.CanvasTransforms=canvas; app.State="COMPLETE"; app.Message="Pixel mosaic; original physical calibration is not automatically transferred.";
            catch err
                app.State="ERROR"; app.Message=string(err.message); if active>0, app.Quality.State(active)="REJECTED"; app.Quality.Message(active)=app.Message; end
                rethrow(err);
            end
        end
        function folder=export(app,parent)
            assert(ismember(app.State,["COMPLETE","ERROR"]),'VIStudioV24:StitchResult','Run stitching before exporting.'); assert(isfolder(parent),'VIStudioV24:Folder','Choose an output parent.'); folder=tempname(parent); mkdir(folder);
            quality=app.Quality; sources=app.Sources; options=app.Options; state=app.State; message=app.Message; panorama=app.Panorama; coverage=app.Coverage; transforms=app.Transforms; canvasTransforms=app.CanvasTransforms; outputView=app.OutputView;
            writetable(quality,fullfile(folder,'registration-quality.csv'),'Encoding','UTF-8'); save(fullfile(folder,'stitch-report.mat'),'quality','sources','options','state','message','transforms','canvasTransforms','outputView','panorama','coverage','-v7.3');
            if state=="COMPLETE", imwrite(im2uint16(panorama),fullfile(folder,'panorama.png')); imwrite(uint8(coverage>0)*255,fullfile(folder,'valid-coverage.png')); imwrite(coverage,fullfile(folder,'contribution-count.tif')); end
        end
    end
    methods (Access=private)
        function clear(app)
            app.Panorama=[]; app.Coverage=[]; app.Transforms={}; app.CanvasTransforms={}; app.OutputView=[]; app.Quality=table(); app.Message=""; app.State="EMPTY"; if ~isempty(app.Sources), app.State="READY"; end
        end
        function im=checkedRead(app,k)
            s=app.Sources(k); assert(VIStudioToolsV3.fileHash(s.File)==s.SHA256,'VIStudioV24:StitchSourceChanged','A source image changed; reload the sequence.'); im=app.read(s.File);
        end
    end
    methods (Static)
        function o=defaults()
            o=struct('Model',"similarity",'Blend',"feather",'MinInliers',12,'MinInlierRatio',.25,'MaxError',3,'MinOverlap',.05,'MaxFeatures',1800,'MaxCanvasPixels',8e6,'Seed',20);
        end
        function o=validate(o)
            assert(isstruct(o) && isscalar(o) && isequal(sort(fieldnames(o)),sort(fieldnames(VIStudioStitchV24.defaults()))),'VIStudioV24:StitchOptions','Use full stitch options.');
            o.Model=string(validatestring(o.Model,{'translation','similarity','affine','projective'})); o.Blend=string(validatestring(o.Blend,{'mean','feather'}));
            validateattributes(o.MinInliers,{'numeric'},{'scalar','integer','>=',4,'<=',5000}); validateattributes(o.MaxFeatures,{'numeric'},{'scalar','integer','>=',o.MinInliers,'<=',10000});
            validateattributes(o.MinInlierRatio,{'numeric'},{'scalar','finite','>',0,'<=',1}); validateattributes(o.MinOverlap,{'numeric'},{'scalar','finite','>',0,'<=',1}); validateattributes(o.MaxError,{'numeric'},{'scalar','finite','positive'});
            validateattributes(o.MaxCanvasPixels,{'numeric'},{'scalar','integer','positive','<=',30e6}); validateattributes(o.Seed,{'numeric'},{'scalar','integer','>=',0,'<=',2^32-1});
        end
        function im=read(file)
            [im,map,alpha]=imread(file); maxAlpha=1; if ~isempty(alpha) && isinteger(alpha), maxAlpha=intmax(class(alpha)); end; assert(isempty(alpha) || all(alpha==maxAlpha,'all'),'VIStudioV24:StitchAlpha','Flatten transparent images before stitching.'); if ~isempty(map), im=ind2rgb(im,map); end
            VIStudioMeasurementV17.validateImage(im); assert(min(size(im,[1 2]))>=32,'VIStudioV24:StitchSize','Use images at least 32x32.'); im=im2single(im);
        end
        function limits=bounds(t,sz)
            points=[1 1;sz(2) 1;sz(2) sz(1);1 sz(1)]; a=double(t.A); d=[points ones(4,1)]*a(3,:)';
            assert(all(isfinite(a),'all') && all(abs(d)>1e-8) && (all(d>0) || all(d<0)),'VIStudioV24:StitchHorizon','Projective horizon crosses the source image.');
            p=double(transformPointsForward(t,points)); area=polyarea(p(:,1),p(:,2))/prod(sz); assert(all(isfinite(p),'all') && area>.1 && area<10,'VIStudioV24:StitchDistortion','Transformed area is implausibly distorted.');
            limits=[min(p(:,1)) max(p(:,1)) min(p(:,2)) max(p(:,2))];
        end
        function files=demo(folder)
            if ~isfolder(folder), mkdir(folder); end; stream=RandStream('mt19937ar','Seed',7); base=imgaussfilt(rand(stream,320,760,'single'),.6);
            for k=1:160, x=randi(stream,[4 730]); y=randi(stream,[4 290]); base(y:y+20,x:x+20)=rand(stream); end
            base=im2uint8(base); files=string({fullfile(folder,'view_01.png'),fullfile(folder,'view_02.png')}); assert(~any(isfile(files)),'VIStudioV24:FileExists','Choose a new demo directory.'); imwrite(base(:,1:460),files(1)); imwrite(base(:,261:720),files(2));
        end
    end
end
