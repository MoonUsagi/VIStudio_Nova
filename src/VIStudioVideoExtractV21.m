classdef VIStudioVideoExtractV21 < handle
    % Streaming decoder-frame extraction; no full-video arrays or overwrites.
    properties (SetAccess=private)
        File=""
        SourceHash=""
        Info=struct()
        Preview=[]
        ROI=[]
        Options
        LastRun=[]
        Busy=false
        StopRequested=false
    end
    methods
        function app=VIStudioVideoExtractV21, app.Options=app.defaults(); end
        function loadVideo(app,file)
            app.assertIdle(); assert(isscalar(string(file)) && isfile(file),'VIStudioV21:Video','Select an existing video.');
            v=VideoReader(file); assert(hasFrame(v),'VIStudioV21:Video','Video has no decodable frames.'); image=readFrame(v); digest=VIStudioToolsV3.fileHash(file);
            info=struct('Width',size(image,2),'Height',size(image,1),'Duration',v.Duration,'FrameRate',v.FrameRate,'VideoFormat',string(v.VideoFormat));
            app.File=VIStudioToolsV3.canonicalPath(file); app.SourceHash=digest; app.Info=info; app.Preview=image; app.ROI=[1 1 info.Width info.Height]; app.LastRun=[];
        end
        function setROI(app,roi)
            app.assertIdle(); assert(~isempty(app.Preview),'VIStudioV21:Video','Load a video first.');
            roi=app.validateROI(roi,size(app.Preview,[1 2])); app.ROI=roi; app.LastRun=[];
        end
        function configure(app,options)
            app.assertIdle(); candidate=app.validateOptions(options); app.Options=candidate; app.LastRun=[];
        end
        function image=croppedPreview(app)
            assert(~isempty(app.Preview),'VIStudioV21:Video','Load a video first.'); roi=app.ROI; image=app.Preview(roi(2):roi(2)+roi(4)-1,roi(1):roi(1)+roi(3)-1,:);
        end
        function requestStop(app), app.StopRequested=true; end
        function result=extract(app,parent,progress)
            if nargin<3, progress=[]; end
            app.assertIdle(); assert(strlength(app.File)>0,'VIStudioV21:Video','Load a video first.');
            assert(isfolder(parent),'VIStudioV21:Folder','Select an existing output parent folder.');
            assert(isempty(progress) || isa(progress,'function_handle'),'VIStudioV21:Progress','Progress must be a callback.');
            o=app.validateOptions(app.Options); roi=app.validateROI(app.ROI,[app.Info.Height app.Info.Width]);
            assert(VIStudioToolsV3.fileHash(app.File)==app.SourceHash,'VIStudioV21:VideoChanged','Source video changed. Reload it before extraction.');
            if o.Mode=="fps", assert(o.Rate<=app.Info.FrameRate+1e-8,'VIStudioV21:VideoRate','Requested images/second exceeds average source FPS.'); end
            app.Busy=true; app.StopRequested=false; app.LastRun=[]; cleanup=onCleanup(@() app.finish());
            folder=tempname(parent); mkdir(folder); manifest=app.emptyManifest(); status="COMPLETE"; reason="EOF"; message=""; decoded=0; baseTime=NaN; nextTime=Inf; reachedStart=false;
            try
                v=VideoReader(app.File);
                while hasFrame(v)
                    if app.StopRequested, status="CANCELLED"; reason="USER_STOP"; break; end
                    if decoded>=o.EndFrame, reason="END_FRAME"; break; end
                    if height(manifest)>=o.MaxImages, reason="MAX_IMAGES"; break; end
                    timestamp=v.CurrentTime; image=readFrame(v); decoded=decoded+1;
                    assert(isequal(size(image,[1 2]),[app.Info.Height app.Info.Width]),'VIStudioV21:VideoSize','Decoded frame size changed; fixed ROI cannot be applied.');
                    selected=false;
                    if decoded>=o.StartFrame
                        reachedStart=true;
                        if isnan(baseTime), baseTime=timestamp; nextTime=timestamp; end
                        if o.Mode=="interval", selected=mod(decoded-o.StartFrame,o.Rate)==0;
                        else, selected=timestamp+1e-9>=nextTime; end
                    end
                    if selected
                        crop=image(roi(2):roi(2)+roi(4)-1,roi(1):roi(1)+roi(3)-1,:);
                        name=sprintf('%s_f%09d.%s',o.Prefix,decoded,o.Format); target=fullfile(folder,name);
                        if o.Format=="jpg", imwrite(crop,target,'Quality',o.JPEGQuality); else, imwrite(crop,target); end
                        manifest(end+1,:)={string(name),decoded,double(timestamp),roi(1),roi(2),roi(3),roi(4),VIStudioToolsV3.fileHash(target)};
                        if o.Mode=="fps", nextTime=baseTime+(floor((timestamp-baseTime)*o.Rate+1e-9)+1)/o.Rate; end
                    end
                    if ~isempty(progress), progress(struct('Decoded',decoded,'Saved',height(manifest),'Time',timestamp,'Folder',string(folder))); end
                end
                if ~reachedStart && status~="CANCELLED", status="NO_FRAMES"; message="StartFrame was beyond the decoded video."; end
                assert(VIStudioToolsV3.fileHash(app.File)==app.SourceHash,'VIStudioV21:VideoChanged','Source video changed during decoding. Outputs require review.');
            catch err
                status="ERROR"; reason="ERROR"; message=string(err.message);
            end
            result=struct('Version',"21.0.0",'Status',status,'StopReason',reason,'Message',message,'Folder',string(folder),'Source',app.File,'SourceSHA256',app.SourceHash,'SourceInfo',app.Info,'Options',o,'EndFrameIsEOF',isinf(o.EndFrame),'ROI',roi,'DecodedFrames',decoded,'SavedImages',height(manifest),'Manifest',manifest,'TimestampMeaning',"VideoReader.CurrentTime before sequential readFrame; not certified original capture PTS");
            writetable(manifest,fullfile(folder,'frames.csv'),'Encoding','UTF-8'); save(fullfile(folder,'extraction.mat'),'result','-v7.3');
            meta=rmfield(result,'Manifest'); app.writeJSON(fullfile(folder,'extraction.json'),meta); app.LastRun=result;
        end
    end
    methods (Access=private)
        function assertIdle(app), assert(~app.Busy,'VIStudioV21:VideoBusy','Stop/wait for the active extraction before changing settings.'); end
        function finish(app), app.Busy=false; end
    end
    methods (Static)
        function o=defaults()
            o=struct('Mode',"interval",'Rate',30,'StartFrame',1,'EndFrame',Inf,'MaxImages',10000,'Format',"png",'JPEGQuality',95,'Prefix',"frame");
        end
        function o=validateOptions(o)
            assert(isstruct(o) && isscalar(o) && isequal(sort(fieldnames(o)),sort(fieldnames(VIStudioVideoExtractV21.defaults()))),'VIStudioV21:VideoOptions','Use the full video options structure.');
            o.Mode=string(validatestring(o.Mode,{'interval','fps'})); o.Format=string(validatestring(o.Format,{'png','jpg'}));
            validateattributes(o.Rate,{'numeric'},{'scalar','real','finite','positive'});
            if o.Mode=="interval", validateattributes(o.Rate,{'numeric'},{'integer'}); end
            validateattributes(o.StartFrame,{'numeric'},{'scalar','real','finite','integer','positive'});
            validateattributes(o.EndFrame,{'numeric'},{'scalar','real','positive'});
            assert((isfinite(o.EndFrame) && fix(o.EndFrame)==o.EndFrame && o.EndFrame>=o.StartFrame) || o.EndFrame==Inf,'VIStudioV21:VideoRange','End frame must be an integer >= start or Inf.');
            validateattributes(o.MaxImages,{'numeric'},{'scalar','real','finite','integer','positive'});
            validateattributes(o.JPEGQuality,{'numeric'},{'scalar','real','finite','integer','>=',1,'<=',100});
            o.Prefix=string(o.Prefix); assert(isscalar(o.Prefix) && ~ismissing(o.Prefix) && ~isempty(regexp(char(o.Prefix),'^[A-Za-z0-9_-]{1,60}$','once')),'VIStudioV21:VideoPrefix','Prefix: 1-60 letters, digits, underscore or hyphen.');
        end
        function roi=validateROI(roi,sz)
            validateattributes(roi,{'numeric'},{'vector','numel',4,'real','finite','integer','positive'}); roi=double(roi(:)');
            assert(roi(1)+roi(3)-1<=sz(2) && roi(2)+roi(4)-1<=sz(1),'VIStudioV21:VideoROI','ROI exceeds the frame. Use [x y width height] in whole pixels.');
        end
        function rows=emptyManifest()
            rows=table('Size',[0 8],'VariableTypes',{'string','double','double','double','double','double','double','string'},'VariableNames',{'Filename','SourceFrame','TimestampSeconds','ROIX','ROIY','Width','Height','SHA256'});
        end
        function writeJSON(file,value)
            fid=fopen(file,'w','n','UTF-8'); assert(fid>0,'VIStudioV21:Write','Cannot write output metadata.'); cleanup=onCleanup(@() fclose(fid)); fprintf(fid,'%s',jsonencode(value));
        end
    end
end
