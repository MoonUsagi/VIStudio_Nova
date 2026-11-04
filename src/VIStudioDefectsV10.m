classdef VIStudioDefectsV10
    % Original-image connected components, explicit physical scale and auditable rules.
    methods (Static)
        function o=defaults()
            o=struct('Enabled',false,'Connectivity',8,'MinRegionAreaPx',1,'FillHoles',false,'IgnoreBorder',false, ...
                'ScaleEnabled',false,'MMPerPixelX',1,'MMPerPixelY',1,'LimitUnit',"px", ...
                'UseCount',true,'MaxRegions',0,'UseTotalArea',false,'MaxTotalArea',0, ...
                'UseRegionArea',false,'MaxRegionArea',0,'UseWidth',false,'MaxWidth',0, ...
                'UseHeight',false,'MaxHeight',0,'UseImageScore',false);
        end
        function o=options(value,base)
            if nargin<2, base=VIStudioDefectsV10.defaults(); end
            assert(isstruct(value) && isscalar(value),'VIStudioV10:DefectOptions','Options must be a scalar struct.');
            o=base; names=fieldnames(value);
            for k=1:numel(names)
                assert(isfield(o,names{k}),'VIStudioV10:DefectOptions','Unknown option: %s',names{k}); o.(names{k})=value.(names{k});
            end
            for field={'Enabled','FillHoles','IgnoreBorder','ScaleEnabled','UseCount','UseTotalArea','UseRegionArea','UseWidth','UseHeight','UseImageScore'}
                validateattributes(o.(field{1}),{'logical'},{'scalar'});
            end
            validateattributes(o.Connectivity,{'numeric'},{'scalar','integer'});
            assert(ismember(o.Connectivity,[4 8]),'VIStudioV10:Connectivity','Choose 4 or 8 connectivity.');
            validateattributes(o.MinRegionAreaPx,{'numeric'},{'scalar','finite','integer','>=',1});
            validateattributes(o.MaxRegions,{'numeric'},{'scalar','finite','integer','nonnegative'});
            for field={'MaxTotalArea','MaxRegionArea','MaxWidth','MaxHeight'}, validateattributes(o.(field{1}),{'numeric'},{'scalar','real','finite','nonnegative'}); end
            for field={'MMPerPixelX','MMPerPixelY'}, validateattributes(o.(field{1}),{'numeric'},{'scalar','real','finite','positive'}); end
            for field={'Connectivity','MinRegionAreaPx','MaxRegions','MaxTotalArea','MaxRegionArea','MaxWidth','MaxHeight','MMPerPixelX','MMPerPixelY'}
                o.(field{1})=double(o.(field{1}));
            end
            o.LimitUnit=string(validatestring(o.LimitUnit,{'px','mm'}));
            assert(o.LimitUnit~="mm" || o.ScaleEnabled,'VIStudioV10:ScaleRequired','Enable physical calibration before using mm limits.');
            assert(~o.Enabled || any([o.UseCount o.UseTotalArea o.UseRegionArea o.UseWidth o.UseHeight o.UseImageScore]), ...
                'VIStudioV10:EmptyRules','Enable at least one decision rule.');
        end
        function scale=referenceScale(points,lengthMM)
            validateattributes(points,{'numeric'},{'size',[2 2],'real','finite'});
            validateattributes(lengthMM,{'numeric'},{'scalar','real','finite','positive'});
            points=double(points); lengthMM=double(lengthMM);
            distance=hypot(diff(points(:,1)),diff(points(:,2)));
            assert(distance>0,'VIStudioV10:ScaleReference','Choose two different reference points.'); scale=lengthMM/distance;
        end
        function report=analyze(mask,roi,o,context)
            if nargin<3, o=struct(); end; o=VIStudioDefectsV10.options(o);
            if nargin<4, context=struct('Calibrated',true,'ImageScore',NaN,'ImageThreshold',NaN,'PixelThreshold',NaN); end
            assert(isstruct(context) && isscalar(context),'VIStudioV10:MeasurementContext','Invalid measurement context.');
            defaults=struct('Calibrated',true,'ImageScore',NaN,'ImageThreshold',NaN,'PixelThreshold',NaN);
            for name=fieldnames(defaults)', if ~isfield(context,name{1}), context.(name{1})=defaults.(name{1}); end, end
            validateattributes(context.Calibrated,{'logical'},{'scalar'});
            for name={'ImageScore','ImageThreshold','PixelThreshold'}
                validateattributes(context.(name{1}),{'numeric'},{'scalar','real'});
                assert(isfinite(context.(name{1})) || isnan(context.(name{1})),'VIStudioV10:MeasurementContext','Invalid score or threshold.');
            end
            available=~isempty(mask); regions=VIStudioDefectsV10.emptyRegions(); reasons=strings(0,1); filtered=[];
            rawCount=0; rawArea=NaN; outside=0; removedSmall=0; removedBorder=0; filled=0;
            if available
                validateattributes(mask,{'logical'},{'2d','nonempty'});
                if isempty(roi), roi=[1 1 size(mask,2) size(mask,1)]; end
                validateattributes(roi,{'numeric'},{'vector','numel',4,'real','finite','integer','positive'}); roi=double(roi(:)');
                assert(roi(1)+roi(3)-1<=size(mask,2) && roi(2)+roi(4)-1<=size(mask,1),'VIStudioV10:MeasurementROI','ROI extends outside mask.');
                ys=roi(2)+(0:roi(4)-1); xs=roi(1)+(0:roi(3)-1); local=mask(ys,xs);
                outside=nnz(mask)-nnz(local); rawArea=nnz(local); rawCount=bwconncomp(local,o.Connectivity).NumObjects;
                if o.FillHoles, previous=nnz(local); local=imfill(local,o.Connectivity,'holes'); filled=nnz(local)-previous; end
                components=bwconncomp(local,o.Connectivity); filtered=false(size(mask));
                regions=VIStudioDefectsV10.emptyRegions(components.NumObjects); accepted=0;
                scoreMap=[];
                if isfield(context,'Map') && ~isempty(context.Map)
                    validateattributes(context.Map,{'numeric'},{'2d','real','finite'}); scoreMap=imresize(double(context.Map),roi([4 3]),'nearest');
                end
                for k=1:components.NumObjects
                    indices=components.PixelIdxList{k}; [y,x]=ind2sub(size(local),indices);
                    if numel(indices)<o.MinRegionAreaPx, removedSmall=removedSmall+1; continue; end
                    border=any(x==1 | x==roi(3) | y==1 | y==roi(4));
                    if o.IgnoreBorder && border, removedBorder=removedBorder+1; continue; end
                    x=x+roi(1)-1; y=y+roi(2)-1; minX=min(x); minY=min(y); boxWidth=max(x)-minX+1; boxHeight=max(y)-minY+1;
                    area=numel(indices); centroid=[mean(x) mean(y)]; physical=nan(1,7);
                    if o.ScaleEnabled
                        physical=[area*o.MMPerPixelX*o.MMPerPixelY boxWidth*o.MMPerPixelX boxHeight*o.MMPerPixelY ...
                            (minX-1)*o.MMPerPixelX (minY-1)*o.MMPerPixelY (centroid(1)-.5)*o.MMPerPixelX (centroid(2)-.5)*o.MMPerPixelY];
                    end
                    maximum=NaN; average=NaN; if ~isempty(scoreMap), maximum=max(scoreMap(indices)); average=mean(scoreMap(indices)); end
                    accepted=accepted+1; regions(accepted,:)={0,area,100*area/prod(roi(3:4)),minX,minY,boxWidth,boxHeight,centroid(1),centroid(2), ...
                        physical(1),physical(2),physical(3),physical(4),physical(5),physical(6),physical(7),border,maximum,average,false,"","NOT_EVALUATED"}; %#ok<AGROW>
                    filtered(sub2ind(size(mask),y,x))=true;
                end
                regions=regions(1:accepted,:);
                if ~isempty(regions), regions=sortrows(regions,{'AreaPx','YPx','XPx'},{'descend','ascend','ascend'}); regions.ID=(1:height(regions))'; end
            end
            total=sum(regions.AreaPx); count=height(regions); if ~available, total=NaN; count=NaN; end
            totalMM=NaN; if o.ScaleEnabled && available, totalMM=total*o.MMPerPixelX*o.MMPerPixelY; end
            decision="DISABLED";
            if o.Enabled
                if ~available || ~context.Calibrated || (o.UseImageScore && (~isfinite(context.ImageScore) || ~isfinite(context.ImageThreshold)))
                    decision="REVIEW";
                    if ~available, reasons(end+1,1)="缺少像素遮罩／門檻 / Pixel mask or threshold is missing"; end
                    if ~context.Calibrated, reasons(end+1,1)="模型尚未校準 / Model is not calibrated"; end
                    if o.UseImageScore && (~isfinite(context.ImageScore) || ~isfinite(context.ImageThreshold)), reasons(end+1,1)="影像分數規則缺少分數或門檻 / Image score rule lacks a score or threshold"; end
                else
                    decision="OK";
                    if o.UseRegionArea || o.UseWidth || o.UseHeight
                        regions.Pass(:)=true; regions.RegionRuleState(:)="PASS";
                    else, regions.RegionRuleState(:)="NOT_APPLICABLE"; end
                    if o.UseCount && height(regions)>o.MaxRegions, reasons(end+1,1)=sprintf('區域數 / Regions %d > %d',height(regions),o.MaxRegions); end
                    unit=o.LimitUnit; area=total; if unit=="mm", area=totalMM; end
                    if o.UseTotalArea && exceeds(area,o.MaxTotalArea), reasons(end+1,1)=sprintf('總面積 / Total area %g > %g %s^2',area,o.MaxTotalArea,unit); end
                    for k=1:height(regions)
                        area=regions.AreaPx(k); width=regions.WidthPx(k); heightValue=regions.HeightPx(k);
                        if unit=="mm", area=regions.AreaMM2(k); width=regions.WidthMM(k); heightValue=regions.HeightMM(k); end
                        violations=strings(0,1);
                        if o.UseRegionArea && exceeds(area,o.MaxRegionArea), violations(end+1,1)="單區面積 / Region area"; end
                        if o.UseWidth && exceeds(width,o.MaxWidth), violations(end+1,1)="外接框寬 / Bounding width"; end
                        if o.UseHeight && exceeds(heightValue,o.MaxHeight), violations(end+1,1)="外接框高 / Bounding height"; end
                        if ~isempty(violations)
                            regions.Pass(k)=false; regions.RegionRuleState(k)="FAIL"; regions.Violations(k)=join(violations,'; ');
                            reasons(end+1,1)="區域 / Region "+k+": "+regions.Violations(k); %#ok<AGROW>
                        end
                    end
                    if o.UseImageScore && context.ImageScore>=context.ImageThreshold, reasons(end+1,1)="影像異常分數達到門檻 / Image anomaly score meets threshold"; end
                    if ~isempty(reasons), decision="NG"; end
                end
            end
            if isfield(context,'Map'), context=rmfield(context,'Map'); end
            coverage=NaN; if available, coverage=100*total/prod(roi(3:4)); end
            report=struct('Version',1,'Available',available,'Decision',decision,'Reasons',reasons,'Regions',regions, ...
                'Count',count,'TotalAreaPx',total,'TotalAreaMM2',totalMM,'AreaPercent',coverage, ...
                'RawAreaPx',rawArea,'RawRegions',rawCount,'FilteredMask',filtered,'ROI',roi, ...
                'RemovedSmall',removedSmall,'RemovedBorder',removedBorder,'FilledPixels',filled,'OutsideROIPixels',outside, ...
                'Options',o,'RuleDigest',VIStudioDatasetV9.digest(jsonencode(o)),'Context',context);
            function yes=exceeds(value,limit), yes=value>limit+8*eps(max(1,abs(limit))); end
        end
        function regions=emptyRegions(count)
            if nargin<1, count=0; end
            names={'ID','AreaPx','AreaPercent','XPx','YPx','WidthPx','HeightPx','CentroidXPx','CentroidYPx', ...
                'AreaMM2','WidthMM','HeightMM','XMM','YMM','CentroidXMM','CentroidYMM','TouchesBorder','MaxScore','MeanScore','Pass','Violations','RegionRuleState'};
            types=repmat({'double'},1,numel(names)); types{17}='logical'; types{20}='logical'; types{21}='string'; types{22}='string';
            regions=table('Size',[count numel(names)],'VariableTypes',types,'VariableNames',names);
        end
        function image=overlay(image,report)
            if ~report.Available, return; end
            image=labeloverlay(image,report.FilteredMask,'Transparency',.65);
            r=report.Regions;
            if ~isempty(r)
                color='green'; if report.Decision=="NG", color='red'; elseif report.Decision=="REVIEW", color='yellow'; end
                labels=compose('#%d  %g px',r.ID,r.AreaPx);
                if report.Options.ScaleEnabled, labels=compose('#%d  %.4g mm^2',r.ID,r.AreaMM2); end
                boxes=[r.XPx-.5 r.YPx-.5 r.WidthPx r.HeightPx]; image=insertShape(image,'rectangle',boxes,'Color',color,'LineWidth',2);
                visible=1:min(5,height(r));
                image=insertObjectAnnotation(image,'rectangle',boxes(visible,:),cellstr(labels(visible)),'Color',color,'LineWidth',2);
            end
        end
        function json=toJSON(report)
            compact=rmfield(report,'FilteredMask'); compact.Regions=table2struct(report.Regions);
            compact.MaskSize=size(report.FilteredMask); compact.FilteredMaskRLE="";
            if report.Available, compact.FilteredMaskRLE=VIStudioToolsV3.encodeMask(report.FilteredMask); end
            json=string(jsonencode(compact));
        end
        function report=fromJSON(json)
            report=jsondecode(char(json));
            assert(isstruct(report) && isscalar(report) && all(isfield(report,{'Version','Available','Options','Regions','MaskSize','FilteredMaskRLE'})) && report.Version==1, ...
                'VIStudioV10:MeasurementRecord','Invalid measurement record.');
            report.Options=VIStudioDefectsV10.options(report.Options); regions=VIStudioDefectsV10.emptyRegions(); names=regions.Properties.VariableNames;
            for k=1:numel(report.Regions)
                row=cell(1,numel(names));
                for c=1:numel(names)
                    if isfield(report.Regions(k),names{c}), value=report.Regions(k).(names{c}); else, value="NOT_EVALUATED"; end
                    if c>=21, value=string(value);
                    elseif ismember(c,[17 20]), value=logical(value);
                    elseif isempty(value), value=NaN; end
                    row{c}=value;
                end
                regions(end+1,:)=row; %#ok<AGROW>
            end
            report.Regions=regions; reasons=string(report.Reasons); report.Reasons=reasons(:); report.Decision=string(report.Decision); report.RuleDigest=string(report.RuleDigest);
            report.FilteredMask=[];
            if report.Available, report.FilteredMask=VIStudioToolsV3.decodeMask(report.FilteredMaskRLE,double(report.MaskSize(:)')); end
            report=rmfield(report,{'MaskSize','FilteredMaskRLE'});
        end
        function export(report,folder,sourceImage)
            assert(~isfolder(folder) && ~isfile(folder),'VIStudioV10:FileExists','Choose a new export folder.');
            mkdir(folder); writetable(report.Regions,fullfile(folder,'regions.csv'),'Encoding','UTF-8');
            summary=rmfield(report,{'Regions','FilteredMask'}); %#ok<NASGU>
            save(fullfile(folder,'measurement.mat'),'report','-v7.3');
            fid=fopen(fullfile(folder,'summary.json'),'w','n','UTF-8'); assert(fid~=-1,'VIStudioV10:ExportWrite','Cannot write summary.'); cleanup=onCleanup(@() fclose(fid));
            fprintf(fid,'%s',jsonencode(summary,'PrettyPrint',true));
            if report.Available, imwrite(report.FilteredMask,fullfile(folder,'filtered_mask.png')); end
            if nargin>2 && ~isempty(sourceImage), imwrite(VIStudioDefectsV10.overlay(sourceImage,report),fullfile(folder,'measurement.png')); end
        end
    end
end
