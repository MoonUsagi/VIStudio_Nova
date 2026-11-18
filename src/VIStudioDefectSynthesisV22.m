classdef VIStudioDefectSynthesisV22 < handle
    properties (SetAccess=private)
        Base=[]
        Donor=[]
        Allowed=[]
        Output=[]
        Mask=[]
        Options
        SourceHash=""
        SourceClass=""
        DonorHash=""
        State="EMPTY"
        LastBatch=[]
        Busy=false
        StopRequested=false
    end
    methods
        function app=VIStudioDefectSynthesisV22, app.Options=app.defaults(); end
        function setSource(app,input)
            app.assertIdle(); [image,sourceClass,digest]=app.read(input); app.Base=image; app.SourceClass=sourceClass; app.SourceHash=digest; app.Allowed=true(size(image,[1 2])); app.clear();
        end
        function setDonor(app,input), app.assertIdle(); [image,~,digest]=app.read(input); app.Donor=image; app.DonorHash=digest; app.clear(); end
        function setAllowed(app,mask)
            app.assertIdle(); assert(islogical(mask) && isequal(size(mask),size(app.Base,[1 2])) && any(mask,'all'),'VIStudioV22:SynthesisMask','Use a nonempty logical allowed-region mask matching the source.'); app.Allowed=mask; app.clear();
        end
        function configure(app,o), app.assertIdle(); candidate=app.validate(o); if ~isequal(candidate,app.Options), app.Options=candidate; app.clear(); end, end
        function [output,mask]=generate(app)
            app.assertIdle(); app.clear();
            try, [output,mask]=app.compose(app.Base,app.Allowed,app.Donor,app.Options); app.Output=output; app.Mask=mask; app.State="SYNTHETIC_UNREVIEWED";
            catch err, app.State="ERROR"; rethrow(err); end
        end
        function requestStop(app), app.StopRequested=true; end
        function result=exportBatch(app,parent,count,progress)
            if nargin<4, progress=[]; end; app.assertIdle(); validateattributes(count,{'numeric'},{'scalar','integer','>=',1,'<=',500}); assert(isfolder(parent),'VIStudioV22:Folder','Choose an output parent.'); app.preflight();
            folder=tempname(parent); mkdir(folder); mkdir(fullfile(folder,'images')); mkdir(fullfile(folder,'masks')); imwrite(app.Base,fullfile(folder,'original-normal.png'));
            if app.Options.Type=="cutpaste", imwrite(app.Donor,fullfile(folder,'donor-patch.png')); end
            app.Busy=true; app.StopRequested=false; cleanup=onCleanup(@() app.finish()); state="COMPLETE"; message="";
            rows=table('Size',[0 8],'VariableTypes',{'string','string','string','double','string','double','logical','string'},'VariableNames',{'Image','Mask','SourceGroup','Seed','DefectType','ChangedPixels','IsSynthetic','ReviewStatus'});
            for k=1:count
                if app.StopRequested, state="CANCELLED"; break; end
                try
                    o=app.Options; o.Seed=mod(double(o.Seed)+k-1,2^32); [image,mask]=app.compose(app.Base,app.Allowed,app.Donor,o);
                    imName=sprintf('images/synthetic_%05d.png',k); maskName=sprintf('masks/synthetic_%05d.png',k); imwrite(image,fullfile(folder,imName)); imwrite(uint8(mask)*255,fullfile(folder,maskName));
                    rows(end+1,:)={string(imName),string(maskName),app.SourceHash,o.Seed,o.Type,nnz(mask),true,"UNREVIEWED"};
                    if ~isempty(progress), progress(struct('Saved',k,'Total',count)); end
                catch err, state="ERROR"; message=string(err.message); break; end
            end
            result=struct('Version',"22.0.0",'State',state,'Message',message,'Folder',string(folder),'Requested',count,'Saved',height(rows),'SourceGroup',app.SourceHash,'DonorSHA256',app.DonorHash,'SourceClass',app.SourceClass,'WorkingClass',string(class(app.Base)),'Options',app.Options,'Rows',rows,'Synthetic',true,'ReviewRequired',true);
            writetable(rows,fullfile(folder,'manifest.csv'),'Encoding','UTF-8'); save(fullfile(folder,'synthesis.mat'),'result','-v7.3'); imwrite(uint8(app.Allowed)*255,fullfile(folder,'allowed-region.png')); app.writeJSON(fullfile(folder,'synthesis.json'),rmfield(result,'Rows')); app.LastBatch=result;
        end
    end
    methods (Access=private)
        function clear(app), app.Output=[]; app.Mask=[]; app.LastBatch=[]; app.State="EMPTY"; if ~isempty(app.Base), app.State="READY"; end, end
        function assertIdle(app), assert(~app.Busy,'VIStudioV22:SynthesisBusy','Stop or wait before changing synthesis settings.'); end
        function finish(app), app.Busy=false; end
        function preflight(app)
            assert(~isempty(app.Base),'VIStudioV22:SynthesisSource','Load a normal image.'); if app.Options.Type=="cutpaste", assert(~isempty(app.Donor),'VIStudioV22:SynthesisDonor','Load a donor image for cut-paste.'); end
        end
    end
    methods (Static)
        function o=defaults()
            o=struct('Type',"scratch",'Count',3,'Size',16,'Length',80,'Contrast',.65,'Blur',.8,'Polarity',"dark",'Seed',20);
        end
        function o=validate(o)
            assert(isstruct(o) && isscalar(o) && isequal(sort(fieldnames(o)),sort(fieldnames(VIStudioDefectSynthesisV22.defaults()))),'VIStudioV22:SynthesisOptions','Use full synthesis options.');
            o.Type=string(validatestring(o.Type,{'scratch','spots','stain','cutpaste'})); o.Polarity=string(validatestring(o.Polarity,{'dark','bright'}));
            validateattributes(o.Count,{'numeric'},{'scalar','integer','>=',1,'<=',50}); validateattributes(o.Size,{'numeric'},{'scalar','finite','>=',1,'<=',2048}); validateattributes(o.Length,{'numeric'},{'scalar','finite','>=',1,'<=',8192});
            validateattributes(o.Contrast,{'numeric'},{'scalar','finite','>',0,'<=',1}); validateattributes(o.Blur,{'numeric'},{'scalar','finite','>=',0,'<=',10}); validateattributes(o.Seed,{'numeric'},{'scalar','integer','>=',0,'<=',2^32-1});
        end
        function [output,mask]=compose(base,allowed,donor,o)
            o=VIStudioDefectSynthesisV22.validate(o); assert(~isempty(base) && islogical(allowed) && isequal(size(allowed),size(base,[1 2])) && any(allowed,'all'),'VIStudioV22:SynthesisSource','Load a source and a nonempty allowed region.');
            if o.Type=="cutpaste", assert(~isempty(donor),'VIStudioV22:SynthesisDonor','Load a donor patch.'); end
            stream=RandStream('mt19937ar','Seed',o.Seed); [h,w,c]=size(base); alpha=zeros(h,w,'single'); target=zeros(h,w,c,'single'); if o.Polarity=="bright", target(:)=1; end
            if o.Type=="cutpaste", target=im2single(base); if size(donor,3)~=c, if c==1, donor=im2gray(donor); else, donor=repmat(donor,1,1,3); end, end, end
            valid=find(allowed); [x,y]=meshgrid(single(1:w),single(1:h));
            for k=1:o.Count
                [cy,cx]=ind2sub([h w],valid(randi(stream,numel(valid)))); sizePx=o.Size*(.65+.7*rand(stream));
                switch o.Type
                    case "scratch"
                        angle=rand(stream)*2*pi; delta=[cos(angle) sin(angle)]*o.Length/2; p=[cx cy]-delta; q=[cx cy]+delta; d=q-p;
                        t=max(0,min(1,((x-p(1))*d(1)+(y-p(2))*d(2))/sum(d.^2))); dist=(x-p(1)-t*d(1)).^2+(y-p(2)-t*d(2)).^2; a=single(dist<=(sizePx/6)^2);
                    case "spots", a=single((x-cx).^2+(y-cy).^2<=(sizePx/2)^2);
                    case "stain"
                        dist=((x-cx).^2+(y-cy).^2)/(max(1,sizePx/2)^2); a=exp(-dist*2).*single(dist<=4); a=a.*(.7+.3*rand(stream,h,w,'single'));
                    case "cutpaste"
                        pw=max(1,round(sizePx)); ph=max(1,round(sizePx*(.6+.8*rand(stream)))); x1=max(1,cx-floor(pw/2)); x2=min(w,x1+pw-1); y1=max(1,cy-floor(ph/2)); y2=min(h,y1+ph-1); a=zeros(h,w,'single'); a(y1:y2,x1:x2)=1;
                        patch=imresize(im2single(donor),[y2-y1+1 x2-x1+1]); target(y1:y2,x1:x2,:)=patch;
                end
                alpha=max(alpha,a);
            end
            if o.Blur>0, alpha=imgaussfilt(alpha,o.Blur); end; alpha(~allowed)=0; alpha=min(1,alpha)*o.Contrast;
            mixed=im2single(base).*(1-alpha)+target.*alpha;
            if isa(base,'uint16'), changed=im2uint16(mixed); else, changed=im2uint8(mixed); end
            output=base; support=alpha>0;
            for k=1:c, plane=output(:,:,k); values=changed(:,:,k); plane(support)=values(support); output(:,:,k)=plane; end
            mask=any(output~=base,3); assert(any(mask,'all'),'VIStudioV22:NoVisibleDefect','No visible pixels changed. Try opposite polarity, stronger contrast or a different donor/ROI.');
            assert(~any(mask & ~allowed,'all'),'VIStudioV22:SynthesisROI','Defect leaked outside the allowed region.');
        end
        function [image,sourceClass,digest]=read(input)
            if ischar(input) || isstring(input)
                digest=VIStudioToolsV3.fileHash(input); [image,map,alpha]=imread(input); maxAlpha=1; if ~isempty(alpha) && isinteger(alpha), maxAlpha=intmax(class(alpha)); end; assert(isempty(alpha) || all(alpha==maxAlpha,'all'),'VIStudioV22:SynthesisAlpha','Flatten transparent images before synthesis.'); if ~isempty(map), image=ind2rgb(image,map); end
            else, image=input; digest=VIStudioDataHealthV8.pixelHash(image); end
            VIStudioMeasurementV17.validateImage(image); assert(numel(image)/size(image,3)<=8e6,'VIStudioV22:SynthesisSize','Use a source up to 8 million pixels.'); sourceClass=string(class(image));
            if isfloat(image), image=im2uint16(image); elseif islogical(image), image=im2uint8(image); end
        end
        function image=demo()
            s=RandStream('mt19937ar','Seed',8); image=im2uint8(.65+.04*randn(s,240,360,'single')); image(45:195,55:305)=180; image(70:170,90:270)=205;
        end
        function writeJSON(file,value)
            fid=fopen(file,'w','n','UTF-8'); assert(fid>0); cleanup=onCleanup(@() fclose(fid)); fprintf(fid,'%s',jsonencode(value));
        end
    end
end
