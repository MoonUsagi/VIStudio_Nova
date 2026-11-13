function tests=testStitchV20
tests=functiontests(localfunctions);
end
function setupOnce(t)
addpath(fileparts(fileparts(mfilename('fullpath')))); t.TestData.Dir=tempname; mkdir(t.TestData.Dir); t.TestData.Files=VIStudioStitchV20.demo(fullfile(t.TestData.Dir,'views'));
end
function teardownOnce(t)
folder=t.TestData.Dir; assert(startsWith(string(folder),string(tempdir))); rmdir(folder,'s');
end
function a=fixture(t)
a=VIStudioStitchV20; a.setFiles(t.TestData.Files);
end
function testNativeOverlapAndCoordinateMapping(t)
a=fixture(t); image=a.run(); verifyEqual(t,a.State,"COMPLETE"); verifyEqual(t,size(image,1),320,'AbsTol',4); verifyEqual(t,size(image,2),720,'AbsTol',4); verifyGreaterThan(t,a.Quality.Inliers(2),12); verifyGreaterThan(t,a.Quality.Overlap(2),.35);
xy=transformPointsForward(a.Transforms{2},[100 100]); verifyEqual(t,double(xy),[360 100],'AbsTol',1); verifyTrue(t,any(a.Coverage>1,'all'));
left=imread(t.TestData.Files(1)); right=imread(t.TestData.Files(2)); base=[left right(:,201:end)]; file=fullfile(t.TestData.Dir,'third.png'); imwrite(base(:,421:720),file); a.setFiles([t.TestData.Files string(file)]); a.run(); verifyEqual(t,numel(a.Transforms),3); xy=transformPointsForward(a.Transforms{3},[100 100]); verifyEqual(t,double(xy),[520 100],'AbsTol',1);
end
function testNativeTranslationAndMeanBlend(t)
for model=["translation","affine","projective"]
 a=fixture(t); o=a.Options; o.Model=model; o.Blend="mean"; a.configure(o); a.run(); verifyEqual(t,a.State,"COMPLETE"); verifyLessThan(t,a.Quality.RMSEpx(2),1);
end
end
function testUniformImagesRejectedAndFailureReportExported(t)
files=strings(2,1); for k=1:2, files(k)=fullfile(t.TestData.Dir,sprintf('blank_%d.png',k)); imwrite(uint8(100*ones(80)),files(k)); end
a=VIStudioStitchV20; a.setFiles(files); verifyError(t,@() a.run(),'VIStudioV20:StitchFeatures'); verifyEqual(t,a.State,"ERROR"); verifyEmpty(t,a.Panorama); folder=a.export(t.TestData.Dir); verifyTrue(t,isfile(fullfile(folder,'registration-quality.csv'))); verifyFalse(t,isfile(fullfile(folder,'panorama.png')));
end
function testCanvasLimitRejectsBeforeOutputAllocation(t)
a=fixture(t); o=a.Options; o.MaxCanvasPixels=100; a.configure(o); verifyError(t,@() a.run(),'VIStudioV20:StitchCanvas'); verifyEmpty(t,a.Panorama);
end
function testHorizonRejected(t)
tform=projtform2d([1 0 0;0 1 0;.01 0 -2]); verifyError(t,@() VIStudioStitchV20.bounds(tform,[320 460]),'VIStudioV20:StitchHorizon');
end
function testSourceChangeAndRngRestoration(t)
a=fixture(t); before=rng; a.run(); verifyEqual(t,rng,before);
file=fullfile(t.TestData.Dir,'changed.png'); copyfile(t.TestData.Files(1),file); a.setFiles([file t.TestData.Files(2)]); fid=fopen(file,'a'); fwrite(fid,uint8(0)); fclose(fid); verifyError(t,@() a.run(),'VIStudioV20:StitchSourceChanged'); verifyEqual(t,rng,before);
end
function testExportCoverageAndTransformEvidence(t)
a=fixture(t); a.run(); folder=a.export(t.TestData.Dir); im=imread(fullfile(folder,'panorama.png')); verifyClass(t,im,'uint16'); verifyEqual(t,im,im2uint16(a.Panorama)); saved=load(fullfile(folder,'stitch-report.mat')); verifyEqual(t,numel(saved.canvasTransforms),2); verifyEqual(t,imread(fullfile(folder,'valid-coverage.png'))>0,a.Coverage>0);
end
function testChangedSettingsInvalidatePriorPanorama(t)
a=fixture(t); a.run(); o=a.Options; o.MaxError=2; a.configure(o); verifyEmpty(t,a.Panorama); verifyEmpty(t,a.Quality); verifyEqual(t,a.State,"READY");
end
function testNativeStitchUI(t)
a=VIStudioStitchAppV20('off'); cleanup=onCleanup(@() delete(a)); a.loadFiles(t.TestData.Files); a.run(); verifyEqual(t,height(a.Handles.Quality.Data),2); verifyTrue(t,contains(a.UIFigure.Name,'V20'));
end
function testMixedGrayscaleAndRgb16BitSources(t)
im=imread(t.TestData.Files(2)); rgb=uint16(repmat(im,1,1,3)).*uint16(257); file=fullfile(t.TestData.Dir,'rgb16.png'); imwrite(rgb,file); a=VIStudioStitchV20; a.setFiles([t.TestData.Files(1) string(file)]); image=a.run(); verifyEqual(t,size(image,3),3); verifyTrue(t,all(isfinite(image),'all')); verifyEqual(t,a.State,"COMPLETE");
end
