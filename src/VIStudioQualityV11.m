classdef VIStudioQualityV11
    methods (Static)
        function o=defaults()
            o=struct('Enabled',false,'MinBrightness',.08,'MaxBrightness',.92,'MinContrast',.03, ...
                'MinFocus',.0002,'MaxDarkFraction',.5,'MaxBrightFraction',.5,'MaxShiftPixels',10,'Reference',[]);
        end
        function o=options(value)
            o=VIStudioQualityV11.defaults();
            for f=fieldnames(value)', assert(isfield(o,f{1}),'VIStudioV11:QualityOption','Unknown quality option.'); o.(f{1})=value.(f{1}); end
            validateattributes(o.Enabled,{'logical'},{'scalar'});
            for f={'MinBrightness','MaxBrightness','MinContrast','MaxDarkFraction','MaxBrightFraction'}
                validateattributes(o.(f{1}),{'numeric'},{'scalar','real','finite','>=',0,'<=',1});
            end
            assert(o.MinBrightness<=o.MaxBrightness,'VIStudioV11:QualityRange','Brightness range is invalid.');
            for f={'MinFocus','MaxShiftPixels'}, validateattributes(o.(f{1}),{'numeric'},{'scalar','real','finite','nonnegative'}); end
            if ~isempty(o.Reference), VIStudioQualityV11.gray(o.Reference); end
        end
        function r=check(image,options)
            if nargin<2, options=struct(); end; o=VIStudioQualityV11.options(options); g=VIStudioQualityV11.gray(image);
            lap=imfilter(g,[0 1 0;1 -4 1;0 1 0],'replicate'); focus=var(lap(:),1); average=mean(g(:)); contrast=std(g(:),1);
            dark=mean(g(:)<=.02); bright=mean(g(:)>=.98); shift=[NaN NaN]; reasons=strings(0,1);
            if average<o.MinBrightness, reasons(end+1,1)="過暗 / Underexposed"; end
            if average>o.MaxBrightness, reasons(end+1,1)="過亮 / Overexposed"; end
            if contrast<o.MinContrast, reasons(end+1,1)="對比不足 / Low contrast"; end
            if focus<o.MinFocus, reasons(end+1,1)="影像模糊 / Low focus"; end
            if dark>o.MaxDarkFraction, reasons(end+1,1)="暗部比例過高 / Too many dark pixels"; end
            if bright>o.MaxBrightFraction, reasons(end+1,1)="亮部比例過高 / Too many saturated pixels"; end
            if ~isempty(o.Reference)
                ref=VIStudioQualityV11.gray(o.Reference); assert(isequal(size(ref),size(g)),'VIStudioV11:QualityReference','Reference resolution must match.');
                if std(ref(:))<eps || contrast<eps, reasons(end+1,1)="無法估計偏移 / Alignment unavailable";
                else
                    a=fft2(g-mean(g(:))); b=fft2(ref-mean(ref(:))); c=a.*conj(b); c=c./max(abs(c),eps);
                    correlation=real(ifft2(c)); [~,index]=max(correlation(:)); [y,x]=ind2sub(size(g),index); shift=[x-1 y-1];
                    for k=1:2, limit=size(g,3-k); if shift(k)>limit/2, shift(k)=shift(k)-limit; end, end
                    if hypot(shift(1),shift(2))>o.MaxShiftPixels, reasons(end+1,1)="拍攝位置偏移 / Image shifted"; end
                end
            end
            decision="PASS"; if ~isempty(reasons), decision="RETAKE"; end
            r=struct('Decision',decision,'GateEnabled',o.Enabled,'Blocked',o.Enabled && decision=="RETAKE",'Reasons',reasons, ...
                'Metrics',table(average,contrast,focus,dark,bright,shift(1),shift(2),'VariableNames', ...
                {'Brightness','Contrast','FocusVariance','DarkFraction','BrightFraction','ShiftX','ShiftY'}));
        end
        function g=gray(image)
            validateattributes(image,{'numeric','logical'},{'nonempty','real','finite'});
            assert(ismatrix(image) || (ndims(image)==3 && size(image,3)==3),'VIStudioV11:Image','Use grayscale or RGB images.');
            g=im2double(image); if size(g,3)==3, g=rgb2gray(g); end
            assert(all(g>=0 & g<=1,'all'),'VIStudioV11:ImageRange','Floating images must be in [0,1].');
        end
    end
end
