function tests=testVideoExtractV20
tests=functiontests(localfunctions);
end
function setupOnce(t)
addpath(fileparts(fileparts(mfilename('fullpath')))); t.TestData.Dir=tempname; mkdir(t.TestData.Dir); t.TestData.Video=fullfile(t.TestData.Dir,'original.avi');
v=VideoWriter(t.TestData.Video,'Uncompressed AVI'); v.FrameRate=12; open(v); cleanup=onCleanup(@() close(v));
for k=1:12
    image=uint8(10*k*ones(24,40,3)); image(5:10,6:15,2)=200; writeVideo(v,image);
end
end
function teardownOnce(t)
folder=t.TestData.Dir; assert(startsWith(string(folder),string(tempdir))); rmdir(folder,'s');
end
function a=video(t)
a=VIStudioVideoExtractV20; a.loadVideo(t.TestData.Video); a.setROI([6 5 10 6]);
end
function testExactIntervalFrameNumbersAndCropPixels(t)
a=video(t); o=a.Options; o.Rate=3; o.StartFrame=2; o.EndFrame=11; a.configure(o); result=a.extract(t.TestData.Dir);
verifyEqual(t,result.Status,"COMPLETE"); verifyEqual(t,result.Manifest.SourceFrame,[2;5;8;11]); verifyEqual(t,result.SavedImages,4);
im=imread(fullfile(result.Folder,result.Manifest.Filename(1))); verifySize(t,im,[6 10 3]); verifyTrue(t,all(im(:,:,2)==200,'all')); verifyTrue(t,all(im(:,:,1)==20,'all')); verifyEqual(t,result.Manifest.SHA256(1),VIStudioToolsV3.fileHash(fullfile(result.Folder,result.Manifest.Filename(1))));
end
function testFramesPerSecondSampling(t)
a=video(t); o=a.Options; o.Mode="fps"; o.Rate=3; a.configure(o); result=a.extract(t.TestData.Dir); verifyEqual(t,result.Manifest.SourceFrame,[1;5;9]); verifyEqual(t,result.Manifest.TimestampSeconds,[0;1/3;2/3],'AbsTol',.01);
end
function testMaximumCountAndNoOverwrite(t)
a=video(t); o=a.Options; o.Rate=1; o.MaxImages=2; a.configure(o); one=a.extract(t.TestData.Dir); two=a.extract(t.TestData.Dir); verifyEqual(t,one.SavedImages,2); verifyEqual(t,one.StopReason,"MAX_IMAGES"); verifyNotEqual(t,one.Folder,two.Folder); verifyTrue(t,isfile(fullfile(one.Folder,'frames.csv')));
end
function testCancelKeepsTraceablePartialOutput(t)
a=video(t); o=a.Options; o.Rate=1; a.configure(o); result=a.extract(t.TestData.Dir,@(p) stopAfterTwo(a,p)); verifyEqual(t,result.Status,"CANCELLED"); verifyEqual(t,result.SavedImages,2); verifyTrue(t,isfile(fullfile(result.Folder,'extraction.json'))); verifyFalse(t,a.Busy);
end
function stopAfterTwo(a,p)
if p.Saved>=2, a.requestStop(); end
end
function testROIIsBoundedAndOnePixelCrop(t)
a=video(t); before=a.ROI; verifyError(t,@() a.setROI([39 1 3 3]),'VIStudioV20:VideoROI'); verifyEqual(t,a.ROI,before); a.setROI([40 24 1 1]); verifySize(t,a.croppedPreview(),[1 1 3]);
end
function testOutOfRangeStartAndSourceChange(t)
a=video(t); o=a.Options; o.StartFrame=100; a.configure(o); result=a.extract(t.TestData.Dir); verifyEqual(t,result.Status,"NO_FRAMES"); verifyEqual(t,result.SavedImages,0);
file=fullfile(t.TestData.Dir,'changed.avi'); copyfile(t.TestData.Video,file); a.loadVideo(file); fid=fopen(file,'a'); fwrite(fid,uint8(0)); fclose(fid); verifyError(t,@() a.extract(t.TestData.Dir),'VIStudioV20:VideoChanged');
end
function testUnsafePrefixAndInvalidRateRejected(t)
a=video(t); o=a.Options; o.Prefix="../escape"; verifyError(t,@() a.configure(o),'VIStudioV20:VideoPrefix'); o=a.Options; o.Mode="fps"; o.Rate=20; a.configure(o); verifyError(t,@() a.extract(t.TestData.Dir),'VIStudioV20:VideoRate');
end
function testMidRunErrorPreservesOutputsAndResetsBusy(t)
a=video(t); o=a.Options; o.Rate=1; a.configure(o); result=a.extract(t.TestData.Dir,@(~) error('Test:Failure','Injected progress failure')); verifyEqual(t,result.Status,"ERROR"); verifyEqual(t,result.SavedImages,1); verifyTrue(t,isfile(fullfile(result.Folder,'frames.csv'))); verifyFalse(t,a.Busy);
end
function testNativeVideoUIExtractsROI(t)
a=VIStudioVideoExtractAppV20('off'); cleanup=onCleanup(@() delete(a)); a.loadVideo(t.TestData.Video); a.setROI([6 5 10 6]); a.Handles.Rate.Value=4; result=a.extract(t.TestData.Dir); verifyEqual(t,result.SavedImages,3); verifySize(t,imread(fullfile(result.Folder,result.Manifest.Filename(1))),[6 10 3]); verifyTrue(t,contains(a.UIFigure.Name,'V20'));
end
