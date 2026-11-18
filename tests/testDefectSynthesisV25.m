function tests=testDefectSynthesisV25
tests=functiontests(localfunctions);
end
function setupOnce(t)
addpath(fileparts(fileparts(mfilename('fullpath')))); t.TestData.Dir=tempname; mkdir(t.TestData.Dir);
end
function teardownOnce(t)
folder=t.TestData.Dir; assert(startsWith(string(folder),string(tempdir))); rmdir(folder,'s');
end
function a=fixture()
a=VIStudioDefectSynthesisV25; a.setSource(a.demo());
end
function testAllFourModesProduceExactChangedPixelMasks(t)
for type=["scratch","spots","stain","cutpaste"]
 a=fixture(); a.setDonor(uint8(30*ones(30,40))); o=a.Options; o.Type=type; a.configure(o); [image,mask]=a.generate(); verifyEqual(t,mask,any(image~=a.Base,3)); verifyGreaterThan(t,nnz(mask),0); verifyEqual(t,a.State,"SYNTHETIC_UNREVIEWED");
end
end
function testSeedsReproduceWithoutChangingGlobalRng(t)
a=fixture(); before=rng; [one,m1]=a.generate(); [two,m2]=a.generate(); verifyEqual(t,one,two); verifyEqual(t,m1,m2); verifyEqual(t,rng,before); o=a.Options; o.Seed=99; a.configure(o); image=a.generate(); verifyNotEqual(t,image,one);
end
function testAllowedRegionIsStrictAfterBlur(t)
a=fixture(); allowed=false(size(a.Base)); allowed(70:140,100:240)=true; a.setAllowed(allowed); o=a.Options; o.Blur=5; o.Length=400; a.configure(o); [image,mask]=a.generate(); verifyFalse(t,any(mask & ~allowed,'all')); verifyEqual(t,image(~allowed),a.Base(~allowed));
end
function testFloatSourceUsesPortable16BitWorkingRepresentation(t)
a=VIStudioDefectSynthesisV25; a.setSource(.6*ones(60)); [image,mask]=a.generate(); verifyClass(t,a.Base,'uint16'); verifyClass(t,image,'uint16'); verifyEqual(t,a.SourceClass,"double"); verifyEqual(t,mask,image~=a.Base);
end
function testBatchSavedMasksMatchSavedImagesAndGroupSeeds(t)
a=fixture(); o=a.Options; o.Seed=2^32-1; a.configure(o); result=a.exportBatch(t.TestData.Dir,3); verifyEqual(t,result.State,"COMPLETE"); verifyEqual(t,result.Rows.Seed,[2^32-1;0;1]); verifyEqual(t,numel(unique(result.Rows.SourceGroup)),1); verifyTrue(t,all(result.Rows.IsSynthetic)); verifyTrue(t,all(result.Rows.ReviewStatus=="UNREVIEWED"));
normal=imread(fullfile(result.Folder,'original-normal.png'));
for k=1:3, image=imread(fullfile(result.Folder,result.Rows.Image(k))); mask=imread(fullfile(result.Folder,result.Rows.Mask(k)))>0; verifyEqual(t,mask,any(image~=normal,3)); end
end
function testCancelRetainsPartialManifest(t)
a=fixture(); result=a.exportBatch(t.TestData.Dir,5,@(p) stop(a,p)); verifyEqual(t,result.State,"CANCELLED"); verifyEqual(t,result.Saved,2); verifyTrue(t,isfile(fullfile(result.Folder,'manifest.csv'))); verifyFalse(t,a.Busy);
end
function stop(a,p), if p.Saved==2, a.requestStop(); end, end
function testInvisibleDefectIsNotLabeledSuccessful(t)
a=fixture(); a.generate(); a.setSource(uint8(zeros(60))); verifyError(t,@() a.generate(),'VIStudioV25:NoVisibleDefect'); verifyEmpty(t,a.Output); verifyEqual(t,a.State,"ERROR");
end
function testInvalidMaskAndMissingDonor(t)
a=fixture(); verifyError(t,@() a.setAllowed(false(size(a.Base))),'VIStudioV25:SynthesisMask'); o=a.Options; o.Type="cutpaste"; a.configure(o); verifyError(t,@() a.generate(),'VIStudioV25:SynthesisDonor'); verifyEmpty(t,a.Output);
end
function testNativeSynthesisUI(t)
a=VIStudioDefectSynthesisAppV25('off'); cleanup=onCleanup(@() delete(a)); a.demo(); verifyNotEmpty(t,a.Data.Mask); result=a.exportBatch(t.TestData.Dir,2); verifyEqual(t,result.Saved,2); verifyEqual(t,height(a.Handles.Rows.Data),2); verifyTrue(t,contains(a.UIFigure.Name,'V25'));
end
function testRgb16BitCutPasteAndDonorEvidence(t)
a=VIStudioDefectSynthesisV25; base=uint16(repmat(a.demo(),1,1,3)).*uint16(257); a.setSource(base); a.setDonor(uint8(30*ones(30,40))); o=a.Options; o.Type="cutpaste"; a.configure(o); [image,mask]=a.generate(); verifyClass(t,image,'uint16'); verifyEqual(t,mask,any(image~=base,3)); result=a.exportBatch(t.TestData.Dir,1); verifyNotEmpty(t,result.DonorSHA256); verifyTrue(t,isfile(fullfile(result.Folder,'donor-patch.png'))); verifyEqual(t,imread(fullfile(result.Folder,result.Rows.Image(1))),image);
end
