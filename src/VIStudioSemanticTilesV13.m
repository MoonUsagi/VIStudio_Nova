classdef VIStudioSemanticTilesV13
    methods (Static)
        function starts=starts(length,tile,overlap)
            validateattributes(length,{'numeric'},{'scalar','integer','positive'}); validateattributes(tile,{'numeric'},{'scalar','integer','positive'}); validateattributes(overlap,{'numeric'},{'scalar','>=',0,'<=',.75});
            last=max(1,length-tile+1); stride=max(1,round(tile*(1-overlap))); starts=unique([1:stride:last,last]);
        end
        function boxes=grid(imageSize,tile,overlap)
            xs=VIStudioSemanticTilesV13.starts(imageSize(2),tile,overlap); ys=VIStudioSemanticTilesV13.starts(imageSize(1),tile,overlap); boxes=zeros(numel(xs)*numel(ys),4); n=0;
            for y=ys, for x=xs, n=n+1; boxes(n,:)=[x y min(tile,imageSize(2)-x+1) min(tile,imageSize(1)-y+1)]; end, end
        end
        function [image,labels]=crop(image,labels,box,tile)
            patch=zeros(tile,tile,3,'like',image); truth=repmat(uint16(65535),tile,tile); ys=box(2)+(0:box(4)-1); xs=box(1)+(0:box(3)-1); patch(1:box(4),1:box(3),:)=image(ys,xs,:); truth(1:box(4),1:box(3))=labels(ys,xs); image=patch; labels=truth;
        end
        function stats=weights(data,classes,o)
            counts=zeros(height(classes),1);
            for row=find(data.Split=="train")'
                mask=VIStudioSemanticV13.label(data.LabelFile(row),classes); for k=1:height(classes), counts(k)=counts(k)+nnz(mask==classes.ID(k)); end
            end
            weights=ones(height(classes),1);
            if o.WeightMode=="inverse-frequency"
                assert(all(counts>0),'VIStudioV13:MissingWeightClass','Each class needs original training pixels before inverse-frequency weighting.'); frequency=counts/sum(counts); weights=min(o.WeightCap,median(frequency)./frequency);
            elseif o.WeightMode=="manual"
                validateattributes(o.ClassWeights,{'numeric'},{'vector','numel',height(classes),'positive','finite'}); weights=double(o.ClassWeights(:));
            end
            stats=table(classes.ID,string(classes.Name),counts,weights,'VariableNames',{'ID','Class','TrainingPixels','Weight'});
        end
        function [prepared,stats]=prepare(data,classes,o,folder,run,snapshot)
            mkdir(fullfile(folder,'images')); mkdir(fullfile(folder,'labels')); prepared=table('Size',[0 9],'VariableTypes',{'string','string','string','string','double','double','double','double','double'},'VariableNames',{'File','LabelFile','Split','SourceFile','X','Y','Width','Height','Variant'});
            skipped=0; eligible=find(ismember(data.Split,["train","validation"])); estimate=0;
            for row=eligible'
                info=imfinfo(data.File(row)); amount=1; if o.DataMode=="tiles", amount=size(VIStudioSemanticTilesV13.grid([info(1).Height info(1).Width],o.Size,o.TileOverlap),1); end
                copies=1; if data.Split(row)=="train", copies=1+o.AugmentCopies; end; estimate=estimate+amount*copies;
            end
            assert(estimate<=o.MaxPreparedImages,'VIStudioV13:TileCount','Prepared-image estimate exceeds MaxPreparedImages; use larger tiles or lower overlap.');
            for row=eligible'
                assert(~run.StopRequested,'VIStudioV13:Cancelled','Stopped during data preparation.');
                assert(VIStudioToolsV3.fileHash(data.File(row))==snapshot.SourceHash(row) && VIStudioToolsV3.fileHash(data.LabelFile(row))==snapshot.LabelHash(row),'VIStudioV13:SemanticChanged','Source or labels changed.');
                image=VIStudioData.readImage(data.File(row),[]); truth=VIStudioSemanticV13.label(data.LabelFile(row),classes); boxes=[1 1 size(image,2) size(image,1)]; if o.DataMode=="tiles", boxes=VIStudioSemanticTilesV13.grid(size(truth),o.Size,o.TileOverlap); end
                for n=1:size(boxes,1)
                    assert(~run.StopRequested,'VIStudioV13:Cancelled','Stopped during tile preparation.');
                    if o.DataMode=="tiles", [patch,mask]=VIStudioSemanticTilesV13.crop(image,truth,boxes(n,:),o.Size); else, patch=imresize(image,[o.Size o.Size]); mask=imresize(truth,[o.Size o.Size],'nearest'); end
                    if ~any(mask~=65535,'all'), skipped=skipped+1; continue; end
                    copies=0; if data.Split(row)=="train", copies=o.AugmentCopies; end
                    for copy=0:copies
                        im=patch; labels=mask;
                        if copy>0
                            stream=RandStream('mt19937ar','Seed',mod(o.Seed+row*100000+n*100+copy,2^32-1)); turns=randi(stream,4)-1; im=rot90(im,turns); labels=rot90(labels,turns); if rand(stream)>.5, im=fliplr(im); labels=fliplr(labels); end
                        end
                        id=height(prepared)+1; imFile=string(fullfile(folder,'images',sprintf('%07d.png',id))); labelFile=string(fullfile(folder,'labels',sprintf('%07d.png',id))); imwrite(im,imFile); imwrite(labels,labelFile); b=boxes(n,:); prepared(end+1,:)={imFile,labelFile,data.Split(row),data.File(row),b(1),b(2),b(3),b(4),copy};
                    end
                    if mod(n,20)==0, drawnow; end
                end
                run.stage("準備影像 / Preparing image "+row+" · patches "+height(prepared),true);
            end
            stats=struct('UpperBound',estimate,'PreparedImages',height(prepared),'SkippedAllIgnoreTiles',skipped,'TrainTiles',sum(prepared.Split=="train"),'ValidationTiles',sum(prepared.Split=="validation"));
            for role=["train","validation"], if any(data.Split==role), assert(any(prepared.Split==role),'VIStudioV13:EmptyPreparedRole','A dataset role has no usable tiles.'); end, end
        end
        function result=predict(a,image,o)
            timer=tic; h=size(image,1); w=size(image,2); c=numel(a.Classes); tile=a.InputSize(1); assert(a.InputSize(2)==tile,'VIStudioV13:TileInput','Tiled inference requires square network input.');
            bytes=4*tile*w*(c+1); assert(bytes/1024^2<=o.MaxBufferMB,'VIStudioV13:TileMemory','Streaming score buffer exceeds MaxBufferMB.');
            xs=VIStudioSemanticTilesV13.starts(w,tile,o.TileOverlap); ys=VIStudioSemanticTilesV13.starts(h,tile,o.TileOverlap); band=zeros(tile,w,c,'single'); counts=zeros(tile,w,'single'); labels=zeros(h,w,'uint16'); confidence=zeros(h,w,'single'); ids=uint16(a.Metadata.SemanticClasses.ID);
            for row=1:numel(ys)
                y=ys(row); height=min(tile,h-y+1);
                for x=xs
                    width=min(tile,w-x+1); patch=zeros(tile,tile,3,'like',image); patch(1:height,1:width,:)=image(y+(0:height-1),x+(0:width-1),:); score=VIStudioSemanticV13.probabilities(a,patch);
                    band(1:height,x+(0:width-1),:)=band(1:height,x+(0:width-1),:)+single(score(1:height,1:width,:)); counts(1:height,x+(0:width-1))=counts(1:height,x+(0:width-1))+1;
                end
                flush=h-y+1; if row<numel(ys), flush=ys(row+1)-y; end
                assert(all(counts(1:flush,:)>0,'all'),'VIStudioV13:TileCoverage','Uncovered inference pixels.'); probabilities=band(1:flush,:,:)./counts(1:flush,:); [maximum,index]=max(probabilities,[],3); labels(y+(0:flush-1),:)=reshape(ids(index),size(index)); confidence(y+(0:flush-1),:)=maximum;
                remaining=tile-flush; if remaining>0, band(1:remaining,:,:)=band(flush+1:tile,:,:); counts(1:remaining,:)=counts(flush+1:tile,:); end
                band(remaining+1:tile,:,:)=0; counts(remaining+1:tile,:)=0; drawnow limitrate;
            end
            result=struct('Labels',labels,'ConfidenceMap',confidence,'Classes',a.Metadata.SemanticClasses,'Milliseconds',1000*toc(timer),'ModelDigest',a.Digest,'InferenceMode',"tiles",'TileCount',numel(xs)*numel(ys),'ScoreBufferMB',bytes/1024^2);
        end
    end
end
