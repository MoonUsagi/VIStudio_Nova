classdef VIStudioGeometryV11
    methods (Static)
        function p=defaults()
            p=struct('Version',1,'Camera',[],'SourceSize',[],'Perspective',false,'Matrix',eye(3),'OutputSize',[], ...
                'WidthMM',NaN,'HeightMM',NaN,'Points',[],'MinValidFraction',.95);
        end
        function validate(p)
            assert(isstruct(p) && isscalar(p) && all(isfield(p,fieldnames(VIStudioGeometryV11.defaults()))) && p.Version==1,'VIStudioV11:Geometry','Invalid geometry profile.');
            validateattributes(p.Perspective,{'logical'},{'scalar'}); validateattributes(p.MinValidFraction,{'numeric'},{'scalar','>=',0,'<=',1,'finite'});
            if ~isempty(p.Camera), assert(isa(p.Camera,'cameraParameters') || isa(p.Camera,'cameraIntrinsics'),'VIStudioV11:Camera','Use cameraParameters or cameraIntrinsics.'); end
            if ~isempty(p.SourceSize), validateattributes(p.SourceSize,{'numeric'},{'vector','numel',2,'integer','positive','finite'}); end
            if p.Perspective
                validateattributes(p.Matrix,{'numeric'},{'size',[3 3],'real','finite'}); assert(rcond(p.Matrix)>1e-12,'VIStudioV11:Homography','Degenerate homography.');
                validateattributes(p.OutputSize,{'numeric'},{'vector','numel',2,'integer','>=',2,'<=',8192});
                validateattributes([p.WidthMM p.HeightMM],{'numeric'},{'vector','positive','finite'});
            end
        end
        function p=perspective(points,outputSize,worldSize,sourceSize,base)
            if nargin<5, base=VIStudioGeometryV11.defaults(); end
            validateattributes(points,{'numeric'},{'size',[4 2],'real','finite'}); validateattributes(worldSize,{'numeric'},{'vector','numel',2,'positive','finite'});
            validateattributes(outputSize,{'numeric'},{'vector','numel',2,'integer','>=',2,'<=',8192});
            edges=diff([points;points(1,:)],1); cross=edges(:,1).*circshift(edges(:,2),-1)-edges(:,2).*circshift(edges(:,1),-1);
            assert(all(cross>1e-8) || all(cross< -1e-8),'VIStudioV11:Quad','Mark four convex corners in boundary order.');
            assert(all(points(:,1)>=.5 & points(:,1)<=sourceSize(2)+.5) && all(points(:,2)>=.5 & points(:,2)<=sourceSize(1)+.5),'VIStudioV11:Quad','Corners extend outside image.');
            h=outputSize(1); w=outputSize(2); destination=[.5 .5;w+.5 .5;w+.5 h+.5;.5 h+.5]; transform=fitgeotrans(points,destination,'projective');
            p=base; p.Perspective=true; p.Matrix=transform.T; p.SourceSize=double(sourceSize(:)'); p.OutputSize=double(outputSize(:)'); p.WidthMM=worldSize(1); p.HeightMM=worldSize(2); p.Points=points;
            VIStudioGeometryV11.validate(p);
        end
        function [image,context]=apply(image,p,isMask)
            if nargin<3, isMask=false; end; VIStudioGeometryV11.validate(p); originalSize=size(image,[1 2]); valid=true(originalSize);
            if ~isempty(p.SourceSize), assert(isequal(originalSize,p.SourceSize),'VIStudioV11:GeometrySize','Calibration and source resolution differ.'); end
            if ~isempty(p.Camera)
                assert(isequal(double(p.Camera.ImageSize),double(originalSize)),'VIStudioV11:CameraSize','Camera calibration resolution differs.');
                if isMask, image=undistortImage(uint8(image)*255,p.Camera,'nearest','OutputView','same')>0;
                else, image=undistortImage(image,p.Camera,'OutputView','same'); end
                valid=undistortImage(uint8(valid)*255,p.Camera,'OutputView','same')==255;
            end
            if p.Perspective
                transform=projective2d(p.Matrix); view=imref2d(p.OutputSize);
                if isMask, image=imwarp(logical(image),transform,'nearest','OutputView',view);
                else, image=imwarp(image,transform,'OutputView',view); end
                valid=imwarp(valid,transform,'nearest','OutputView',view);
            end
            space="source"; if p.Perspective || ~isempty(p.Camera), space="rectified"; end
            sx=NaN; sy=NaN; if p.Perspective, sx=p.WidthMM/p.OutputSize(2); sy=p.HeightMM/p.OutputSize(1); end
            context=struct('CoordinateSpace',space,'SourceSize',originalSize,'OutputSize',size(image,[1 2]),'ValidMask',valid, ...
                'ValidFraction',mean(valid,'all'),'ScaleX',sx,'ScaleY',sy,'LensApplied',~isempty(p.Camera),'PerspectiveApplied',p.Perspective);
        end
        function [camera,report]=calibrate(folder,squareMM)
            validateattributes(squareMM,{'numeric'},{'scalar','finite','positive'}); ds=imageDatastore(folder);
            assert(numel(ds.Files)>=3,'VIStudioV11:CalibrationImages','Use at least three checkerboard views.');
            first=readimage(ds,1); imageSize=size(first,[1 2]);
            for k=1:numel(ds.Files), im=imfinfo(ds.Files{k}); assert(isequal([im.Height im.Width],imageSize),'VIStudioV11:CameraSize','All calibration views must have the same resolution.'); end
            [points,board,used]=detectCheckerboardPoints(ds.Files,'PartialDetections',false);
            assert(sum(used)>=3,'VIStudioV11:Checkerboard','At least three complete checkerboards must be detected.');
            world=patternWorldPoints('checkerboard',board,squareMM);
            [camera,estimated]=estimateCameraParameters(points,world,'ImageSize',imageSize,'WorldUnits','millimeters');
            report=struct('Images',numel(ds.Files),'Detected',sum(used),'Estimated',sum(estimated),'MeanReprojectionError',camera.MeanReprojectionError,'SquareMM',squareMM,'ImageSize',imageSize);
        end
    end
end
