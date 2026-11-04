classdef VIStudioPoseV15
    methods (Static)
        function t=template(name)
            if nargin<1, name='industrial'; end
            if string(name)=="human"
                names=["nose";"left_shoulder";"right_shoulder";"left_elbow";"right_elbow";"left_wrist";"right_wrist";"left_hip";"right_hip";"left_knee";"right_knee";"left_ankle";"right_ankle"]; edges=[2 3;2 4;4 6;3 5;5 7;2 8;3 9;8 9;8 10;10 12;9 11;11 13];
            else, names=["hole_left";"hole_right";"connector_tip";"reference_corner"]; edges=[1 2;2 3;1 4]; end
            t=struct('Name',string(name),'Names',names,'Edges',edges);
        end
        function g=geometry(template,xy,visibility,box)
            g=struct('Names',string(template.Names(:)),'XY',double(xy),'Visibility',double(visibility(:)),'Edges',double(template.Edges),'Box',double(box));
        end
        function g=validate(g,imageSize)
            assert(isstruct(g) && isscalar(g) && all(isfield(g,{'Names','XY','Visibility','Edges','Box'})),'VIStudioV15:PoseGeometry','Require Names, XY, Visibility, Edges, Box.'); g.Names=string(g.Names(:)); n=numel(g.Names);
            assert(n>0 && numel(unique(g.Names))==n && all(strlength(g.Names)>0),'VIStudioV15:PoseNames','Point names must be nonempty and unique.'); validateattributes(g.XY,{'numeric'},{'size',[n 2],'real'}); validateattributes(g.Visibility,{'numeric'},{'vector','numel',n,'integer','>=',0,'<=',2}); g.Visibility=double(g.Visibility(:));
            known=g.Visibility>0; assert(all(isfinite(g.XY(known,:)),'all') && all(isnan(g.XY(~known,:)),'all'),'VIStudioV15:PoseVisibility','Unknown points use NaN coordinates; occluded/visible points require finite coordinates.');
            assert(all(g.XY(known,1)>=1 & g.XY(known,1)<=imageSize(2)) && all(g.XY(known,2)>=1 & g.XY(known,2)<=imageSize(1)),'VIStudioV15:PoseBounds','Points are outside the image.');
            if ~isempty(g.Edges), validateattributes(g.Edges,{'numeric'},{'2d','ncols',2,'integer','positive','<=',n,'finite'}); assert(all(g.Edges(:,1)~=g.Edges(:,2)),'VIStudioV15:PoseEdges','Self edges are invalid.'); end
            b=g.Box; validateattributes(b,{'numeric'},{'vector','numel',4,'integer','positive','finite'}); assert(b(1)+b(3)-1<=imageSize(2) && b(2)+b(4)-1<=imageSize(1),'VIStudioV15:PoseBounds','Object box is outside image.');
            assert(all(g.XY(known,1)>=b(1) & g.XY(known,1)<=b(1)+b(3)-1) && all(g.XY(known,2)>=b(2) & g.XY(known,2)<=b(2)+b(4)-1),'VIStudioV15:PoseBox','Known points must be inside their object box.');
        end
        function [rows,summary]=metrics(predicted,truth,threshold,includeOccluded)
            if nargin<3, threshold=.05; end; if nargin<4, includeOccluded=false; end
            validateattributes(threshold,{'numeric'},{'scalar','positive','<=',1,'finite'}); assert(isequal(string(predicted.Names(:)),string(truth.Names(:))),'VIStudioV15:PoseNames','Point order and names must match.');
            known=truth.Visibility==2; if includeOccluded, known=truth.Visibility>0; end; predictedKnown=predicted.Visibility>0 & all(isfinite(predicted.XY),2); detected=known & predictedKnown; scale=hypot(truth.Box(3),truth.Box(4)); error=nan(numel(known),1); error(detected)=vecnorm(predicted.XY(detected,:)-truth.XY(detected,:),2,2); normalized=error/scale; correct=detected & normalized<=threshold;
            rows=table(string(truth.Names(:)),truth.Visibility,predicted.Visibility,known,error,normalized,correct,'VariableNames',{'Point','TruthVisibility','PredictionVisibility','Evaluated','ErrorPx','NormalizedError','Correct'});
            pck=NaN; miss=NaN; if any(known), pck=sum(correct)/nnz(known); miss=nnz(known & ~predictedKnown)/nnz(known); end
            summary=struct('PCK',pck,'Threshold',threshold,'Normalization',"truth-box diagonal",'EvaluatedPoints',nnz(known),'MissRate',miss,'MeanDetectedErrorPx',mean(error,'omitnan'));
        end
        function rows=measure(g,sx,sy)
            if nargin<2, sx=1; sy=1; end; validateattributes([sx sy],{'numeric'},{'positive','finite','numel',2}); rows=table(strings(0,1),strings(0,1),zeros(0,1),zeros(0,1),'VariableNames',{'From','To','Distance','AngleDegrees'});
            for k=1:size(g.Edges,1), a=g.Edges(k,1); b=g.Edges(k,2); distance=NaN; angle=NaN; if all(g.Visibility([a b])>0), delta=(g.XY(b,:)-g.XY(a,:)).*[sx sy]; distance=norm(delta); angle=atan2d(delta(2),delta(1)); end; rows(end+1,:)={g.Names(a),g.Names(b),distance,angle}; end
        end
        function g=swap(g,a,b)
            validateattributes([a b],{'numeric'},{'integer','positive','<=',numel(g.Names),'numel',2}); assert(a~=b,'VIStudioV15:PointPair','Choose different points.'); g.XY([a b],:)=g.XY([b a],:); g.Visibility([a b])=g.Visibility([b a]);
        end
        function g=mirror(g,pairs)
            if nargin<2, pairs=zeros(0,2); end
            if ~isempty(pairs), validateattributes(pairs,{'numeric'},{'2d','ncols',2,'integer','positive','<=',numel(g.Names)}); assert(numel(unique(pairs(:)))==numel(pairs),'VIStudioV15:PointPair','Mirror pairs must be disjoint.'); end
            known=g.Visibility>0; g.XY(known,1)=2*g.Box(1)+g.Box(3)-1-g.XY(known,1);
            for j=1:size(pairs,1), g=VIStudioPoseV15.swap(g,pairs(j,1),pairs(j,2)); end
        end
        function pairs=leftRightPairs(names)
            names=string(names(:)); pairs=zeros(0,2);
            for k=1:numel(names), name=names(k); other="";
                if startsWith(name,"left_"), other="right_"+extractAfter(name,5); elseif endsWith(name,"_left"), other=extractBefore(name,strlength(name)-4)+"_right"; end
                j=find(names==other,1); if ~isempty(j), pairs(end+1,:)=[k j]; end
            end
        end
        function image=overlay(image,g)
            for k=1:size(g.Edges,1), a=g.Edges(k,1); b=g.Edges(k,2); if all(g.Visibility([a b])>0), image=insertShape(image,'Line',[g.XY(a,:) g.XY(b,:)],'Color','cyan','LineWidth',3); end, end
            for k=1:numel(g.Names), if g.Visibility(k)==0, continue; end; color='yellow'; if g.Visibility(k)==1, color='magenta'; end; image=insertMarker(image,g.XY(k,:),'o','Color',color,'Size',7); image=insertText(image,g.XY(k,:)+[5 5],char(g.Names(k)),'FontSize',11,'BoxOpacity',.4); end
        end
    end
end
