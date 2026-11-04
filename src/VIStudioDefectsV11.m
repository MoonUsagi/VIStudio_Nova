classdef VIStudioDefectsV11
    methods (Static)
        function o=defaults()
            o=VIStudioDefectsV10.defaults(); o.UseLength=false; o.MaxLength=0; o.UseShortWidth=false; o.MaxShortWidth=0;
        end
        function o=options(value,base)
            if nargin<2, base=VIStudioDefectsV11.defaults(); end; o=base;
            for field=fieldnames(value)', assert(isfield(o,field{1}),'VIStudioV11:DefectOptions','Unknown defect option.'); o.(field{1})=value.(field{1}); end
            extra={'UseLength','MaxLength','UseShortWidth','MaxShortWidth'}; b=rmfield(o,extra); enabled=b.Enabled; b.Enabled=false; b=VIStudioDefectsV10.options(b);
            for field=fieldnames(b)', o.(field{1})=b.(field{1}); end; o.Enabled=enabled;
            validateattributes(o.Enabled,{'logical'},{'scalar'}); validateattributes(o.UseLength,{'logical'},{'scalar'}); validateattributes(o.UseShortWidth,{'logical'},{'scalar'});
            validateattributes([o.MaxLength o.MaxShortWidth],{'numeric'},{'real','finite','nonnegative'});
            assert(isscalar(o.MaxLength) && isscalar(o.MaxShortWidth),'VIStudioV11:DefectOptions','Rotated limits must be scalars.');
            assert(~o.Enabled || any([o.UseCount o.UseTotalArea o.UseRegionArea o.UseWidth o.UseHeight o.UseImageScore o.UseLength o.UseShortWidth]),'VIStudioV11:EmptyRules','Enable a rule.');
        end
        function r=analyze(mask,roi,options,context)
            if nargin<3, options=struct(); end; if nargin<4, context=struct('Calibrated',true); end
            o=VIStudioDefectsV11.options(options); b=rmfield(o,{'UseLength','MaxLength','UseShortWidth','MaxShortWidth'});
            if b.Enabled && ~any([b.UseCount b.UseTotalArea b.UseRegionArea b.UseWidth b.UseHeight b.UseImageScore]), b.UseCount=true; b.MaxRegions=flintmax; end
            r=VIStudioDefectsV10.analyze(mask,roi,b,context); rotated=VIStudioDefectsV11.rotated(r.FilteredMask,o); r.Rotated=rotated; r.Options=o; r.RuleDigest=VIStudioDatasetV9.digest(jsonencode(o));
            if r.Decision=="OK" || r.Decision=="NG"
                for k=1:height(rotated)
                    lengthValue=rotated.LengthPx(k); widthValue=rotated.ShortWidthPx(k);
                    if o.LimitUnit=="mm", lengthValue=rotated.LengthMM(k); widthValue=rotated.ShortWidthMM(k); end
                    why=strings(0,1);
                    if o.UseLength && lengthValue>o.MaxLength+8*eps(max(1,o.MaxLength)), why(end+1,1)="旋轉長邊超限 / Rotated length exceeded"; end
                    if o.UseShortWidth && widthValue>o.MaxShortWidth+8*eps(max(1,o.MaxShortWidth)), why(end+1,1)="旋轉短邊超限 / Rotated width exceeded"; end
                    if ~isempty(why)
                        r.Decision="NG"; r.Reasons(end+1,1)="Region "+k+": "+join(why,'; '); r.Regions.Pass(k)=false; r.Regions.RegionRuleState(k)="FAIL";
                        r.Regions.Violations(k)=join([r.Regions.Violations(k);why],'; ');
                    elseif o.UseLength || o.UseShortWidth
                        if r.Regions.RegionRuleState(k)~="FAIL", r.Regions.Pass(k)=true; r.Regions.RegionRuleState(k)="PASS"; end
                    end
                end
            end
        end
        function rows=rotated(mask,o)
            rows=table('Size',[0 8],'VariableTypes',{'double','double','double','double','double','double','double','string'}, ...
                'VariableNames',{'ID','LengthPx','ShortWidthPx','AnglePx','LengthMM','ShortWidthMM','AngleMM','VerticesJSON'});
            if isempty(mask), return; end
            cc=bwconncomp(mask,o.Connectivity); keys=zeros(cc.NumObjects,3);
            for k=1:cc.NumObjects, [y,x]=ind2sub(size(mask),cc.PixelIdxList{k}); keys(k,:)=[-numel(x) min(y) min(x)]; end
            [~,order]=sortrows(keys,[1 2 3]);
            for id=1:numel(order)
                [y,x]=ind2sub(size(mask),cc.PixelIdxList{order(id)}); small=false(max(y)-min(y)+3,max(x)-min(x)+3); small(sub2ind(size(small),y-min(y)+2,x-min(x)+2))=true;
                [by,bx]=find(bwperim(small,8)); bx=bx+min(x)-2; by=by+min(y)-2;
                points=[bx-.5 by-.5;bx+.5 by-.5;bx+.5 by+.5;bx-.5 by+.5]; points=unique(points,'rows');
                [lengthPx,widthPx,angle,vertices]=VIStudioDefectsV11.box(points); lengthMM=NaN; widthMM=NaN; angleMM=NaN;
                if o.ScaleEnabled
                    [lengthMM,widthMM,angleMM]=VIStudioDefectsV11.box(points.*[o.MMPerPixelX o.MMPerPixelY]);
                end
                rows(end+1,:)={id,lengthPx,widthPx,angle,lengthMM,widthMM,angleMM,string(jsonencode(vertices))}; %#ok<AGROW>
            end
        end
        function [long,short,angle,vertices]=box(points)
            hull=points(convhull(points(:,1),points(:,2)),:); edges=diff(hull); angles=unique(mod(atan2(edges(:,2),edges(:,1)),pi/2)); best=Inf;
            for a=angles'
                rotation=[cos(a) -sin(a);sin(a) cos(a)]; q=hull*rotation; lo=min(q); hi=max(q); spans=hi-lo; area=prod(spans);
                if area<best
                    best=area; long=max(spans); short=min(spans); angle=rad2deg(a); if spans(2)>spans(1), angle=angle+90; end
                    vertices=[lo;hi(1) lo(2);hi;lo(1) hi(2)]/rotation;
                end
            end
            angle=mod(angle+90,180)-90;
        end
    end
end
