function tests=testMeasurementV17
tests=functiontests(localfunctions);
end
function setupOnce(t)
root=fileparts(fileparts(mfilename('fullpath'))); addpath(root); folder=tempname; mkdir(folder); t.TestData.Folder=folder; t.TestData.OldUser=getenv('VISTUDIO_V16_USER_DIR'); setenv('VISTUDIO_V16_USER_DIR',fullfile(folder,'preferences')); [image,defs,mask]=VIStudioMeasurementDemoV17; t.TestData.Image=image; t.TestData.Definitions=defs; t.TestData.Mask=mask;
end
function teardownOnce(t), setenv('VISTUDIO_V16_USER_DIR',t.TestData.OldUser); folder=t.TestData.Folder; assert(startsWith(string(folder),string(tempdir))); rmdir(folder,'s'); end
function d=data(t), d=VIStudioMeasurementV17; d.loadImage(t.TestData.Image,'synthetic-test'); end
function testPhysicalDistanceAnisotropicAndTolerance(t)
d=data(t); d.setScale(.2,.5); id=d.add('distance',[20 20;23 24],struct('Lower',2,'Upper',2.2)); verifyEqual(t,d.Records.Value,hypot(.6,2),'AbsTol',1e-12); verifyEqual(t,d.Records.Unit,"mm"); verifyEqual(t,d.Records.Decision,"OK"); d.setTolerance(id,0,1); verifyEqual(t,d.Records.Decision,"NG"); d.undo(); verifyEqual(t,d.Records.Decision,"OK"); d.setTolerance(id,NaN,NaN); verifyEqual(t,d.Records.Decision,"MEASURED");
end
function testNativeCaliperPolarityPairs(t)
d=data(t); d.add('caliper',[40 175;340 175],struct('Width',8,'Polarity',"rising",'Threshold',.08)); verifyEqual(t,d.Records.Method,"native-caliper"); verifyEqual(t,d.Records.Value,221,'AbsTol',1.2); verifyEqual(t,d.Records.State,"MEASURED"); verifyGreaterThanOrEqual(t,d.Records.Details.CandidatePairs,1);
d.setScale(.1,.1); d.add('caliper',[40 175;340 175],struct('Width',8,'Threshold',.08)); verifyEqual(t,d.Records.Value,22.1,'AbsTol',.15); verifyEqual(t,d.Records.Unit,"mm");
end
function testNoEdgesIsNotZeroOrOK(t)
d=VIStudioMeasurementV17; d.loadImage(uint8(zeros(100,150))); d.add('caliper',[20 50;130 50],struct('Lower',0,'Upper',100)); verifyTrue(t,isnan(d.Records.Value)); verifyEqual(t,d.Records.Decision,"NOT_MEASURED"); verifyNotEmpty(t,d.Records.Message);
d.add('circle',[75 50 20],struct('Snap',true,'Lower',0,'Upper',100)); verifyTrue(t,isnan(d.Records(2).Value)); verifyEqual(t,d.Records(2).Decision,"NOT_MEASURED");
end
function testNativeCircleAndRngPreservation(t)
d=data(t); previous=rng; s=t.TestData.Definitions{2}; d.add(s.Kind,s.Geometry,s.Options); verifyEqual(t,rng,previous); verifyEqual(t,d.Records.Method,"native-fitcircle"); verifyEqual(t,d.Records.Value,130,'AbsTol',2); verifyEqual(t,d.Records.State,"MEASURED"); verifyEqual(t,d.Records.Details.Radius,d.Records.Value/2); d.add(s.Kind,s.Geometry,s.Options); verifyEqual(t,d.Records(1).Value,d.Records(2).Value,'AbsTol',1e-10);
end
function testCircleRejectsAnisotropicPhysicalDiameter(t)
d=data(t); d.setScale(.1,.2); d.add('circle',[465 185 65]); verifyEqual(t,d.Records.Decision,"NOT_MEASURED"); verifyTrue(t,isnan(d.Records.Value)); verifyEqual(t,d.Records.Details.ErrorID,"VIStudioV17:CircleScale");
end
function testManualAngleAndPointLine(t)
d=data(t); d.add('angle',[20 10;20 30;60 30]); verifyEqual(t,d.Records.Value,90,'AbsTol',1e-12); verifyEqual(t,d.Records.Unit,"deg"); d.add('pointline',[20 20;120 20;60 50]); verifyEqual(t,d.Records(2).Value,30,'AbsTol',1e-12); d.add('angle',[20 20;20 20;40 30]); verifyEqual(t,d.Records(3).Decision,"NOT_MEASURED");
end
function testNativeAngleWithImageEdges(t)
d=data(t); d.add('angle',[80 90;80 280;300 280],struct('Snap',true,'Neighborhood',8)); verifyEqual(t,d.Records.Method,"native-fitangle"); verifyEqual(t,d.Records.State,"MEASURED"); verifyEqual(t,d.Records.Value,90,'AbsTol',3);
end
function testMaskAreaAndRotatedDimensions(t)
d=data(t); mask=false(size(t.TestData.Mask)); mask(40:69,40:89)=true; d.add('area',mask); verifyEqual(t,d.Records.Value,1500); verifyEqual(t,d.Records.Unit,"px^2"); d.add('length',mask); d.add('width',mask); verifyEqual(t,d.Records(2).Value,50,'AbsTol',1e-8); verifyEqual(t,d.Records(3).Value,30,'AbsTol',1e-8); d.setScale(.1,.2); d.add('area',mask); verifyEqual(t,d.Records.Value,30,'AbsTol',1e-10); d.add('length',mask); d.add('width',mask); verifyEqual(t,d.Records(2).Value,6,'AbsTol',1e-8); verifyEqual(t,d.Records(3).Value,5,'AbsTol',1e-8);
end
function testHistoryUpdateDeleteAndCalibrationClear(t)
d=data(t); id=d.add('distance',[20 20;30 20]); d.update(id,[20 20;50 20]); verifyEqual(t,d.Records.Value,30); d.undo(); verifyEqual(t,d.Records.Value,10); d.redo(); verifyEqual(t,d.Records.Value,30); d.setScale(.1,.1); verifyEmpty(t,d.Records); d.undo(); verifyEqual(t,d.Records.Value,30); verifyEqual(t,d.Unit,"px"); d.remove(id); verifyEmpty(t,d.Records); d.undo(); verifyEqual(t,d.Records.ID,id);
end
function testReferenceScaleAndPerspective(t)
d=data(t); d.setReference([20 20;120 20],10); verifyEqual(t,d.Scale,[.1 .1]); profile=VIStudioGeometryV11.perspective([.5 .5;640.5 .5;640.5 420.5;.5 420.5],[420 640],[64 42],[420 640]); d.setProfile(profile); d.add('distance',[20 20;120 20]); verifyEqual(t,d.Records.Value,10,'AbsTol',1e-9); verifyEqual(t,d.Unit,"mm"); verifyError(t,@() d.setScale(.2,.2),'VIStudioV17:Scale');
end
function testBoundsAndInvalidOptionsDoNotChangeTruth(t)
d=data(t); verifyError(t,@() d.add('distance',[0 20;30 20]),'VIStudioV17:Bounds'); verifyEmpty(t,d.Records); verifyError(t,@() d.add('distance',[20 20;30 20],struct('Lower',5,'Upper',1)),'VIStudioV17:Limits'); verifyError(t,@() d.add('area',false(20)),'VIStudioV17:Mask'); verifyError(t,@() d.loadImage(ones(30)*2),'VIStudioV17:ImageRange'); verifyEqual(t,d.SourceName,"synthetic-test");
end
function testSessionPortableRecomputeAndNoOverwrite(t)
d=data(t); s=t.TestData.Definitions{2}; d.add(s.Kind,s.Geometry,s.Options); file=fullfile(t.TestData.Folder,'session.mat'); d.saveSession(file); other=VIStudioMeasurementV17; other.loadSession(file); verifyEqual(t,other.Records.Value,d.Records.Value,'AbsTol',1e-10); verifyEqual(t,other.Records.ID,d.Records.ID); verifyEqual(t,other.SourceHash,d.SourceHash); verifyFalse(t,other.Dirty); verifyError(t,@() d.saveSession(file),'VIStudioV17:FileExists');
loaded=load(file); session=loaded.session; session.Records.Value=99999; altered=fullfile(t.TestData.Folder,'altered-result.mat'); save(altered,'session'); other.loadSession(altered); verifyNotEqual(t,other.Records.Value,99999); session.Image(1,1)=session.Image(1,1)+1; altered2=fullfile(t.TestData.Folder,'altered-image.mat'); save(altered2,'session'); verifyError(t,@() other.loadSession(altered2),'VIStudioV17:SessionHash');
end
function testRecipeTransactionalAndSizeGuard(t)
d=data(t); d.add('distance',[20 20;120 20]); recipe=d.recipe(); other=data(t); other.applyRecipe(recipe); verifyEqual(t,other.Records.Value,100); small=VIStudioMeasurementV17; small.loadImage(uint8(zeros(50))); verifyError(t,@() small.applyRecipe(recipe),'VIStudioV17:RecipeSize'); broken=recipe; broken.Definitions{1}.Geometry=[-1 5;10 5]; previous=other.Records; verifyError(t,@() other.applyRecipe(broken),'VIStudioV17:Bounds'); verifyEqual(t,other.Records,previous);
end
function testBatchKeepsFailuresAndExports(t)
d=data(t); d.add('caliper',[40 175;340 175],struct('Lower',215,'Upper',225)); recipe=d.recipe(); files=strings(3,1); files(1)=fullfile(t.TestData.Folder,'batch-good.png'); files(2)=fullfile(t.TestData.Folder,'batch-flat.png'); files(3)=fullfile(t.TestData.Folder,'batch-small.png'); imwrite(t.TestData.Image,files(1)); imwrite(uint8(zeros(size(t.TestData.Image))),files(2)); imwrite(uint8(zeros(40)),files(3)); folder=fullfile(t.TestData.Folder,'batch'); rows=VIStudioMeasurementV17.batch(recipe,files,folder); verifyEqual(t,rows.State,["OK";"REVIEW";"ERROR"]); verifyEqual(t,rows.NotMeasured(2),1); verifyTrue(t,isfile(fullfile(folder,'image_00001','measurement-overlay.png'))); verifyTrue(t,isfile(fullfile(folder,'batch-summary.csv'))); verifyError(t,@() VIStudioMeasurementV17.batch(recipe,files,folder),'VIStudioV17:FileExists');
end
function testNativeCanvasCaptureAndUpdate(t)
a=VIStudioMeasurementAppV17('off'); cleanup=onCleanup(@() delete(a)); a.loadImage(t.TestData.Image,'test-image'); a.Handles.Snap.Value=false; a.place('distance',[20 20;120 20]); id=a.capture(); verifyEqual(t,a.Data.Records.Value,100); a.Tool.Position=[20 20;150 20]; a.capture(true); verifyEqual(t,a.Data.Records.Value,130); verifyEqual(t,a.Data.Records.ID,id); a.place('circle',[465 185 65]); verifyClass(t,a.Tool,'uifitcircle'); a.place('angle',[80 90;80 280;300 280]); verifyClass(t,a.Tool,'uifitangle'); a.place('pointline',[80 90;80 280;300 220]); verifyClass(t,a.Tool,'uitsquare'); a.capture(); verifyEqual(t,a.Data.Records(2).Value,220,'AbsTol',1e-9);
end
function testNewHomeAndEnglishHelp(t)
fig=VIStudioV17('','off'); cleanup=onCleanup(@() delete(fig)); hub=getappdata(fig,'VIStudioHomeV17'); app=hub.openTask('measurement'); closeApp=onCleanup(@() delete(app)); verifyClass(t,app,'VIStudioMeasurementAppV17'); verifyEqual(t,numel(findall(fig,'-isa','matlab.ui.control.Image')),10); guide=VIStudioGuideV17.show(fig); closeGuide=onCleanup(@() delete(guide)); controls=getappdata(guide,'VIStudioHelpControls'); verifyTrue(t,contains(strjoin(string(controls.English.Value)),"VIStudioMeasurementAppV17"));
end
function testVisibleViewerImageSwitchDoesNotKeepDeletedAnnotations(t)
a=VIStudioMeasurementAppV17('on'); cleanup=onCleanup(@() delete(a)); a.loadImage(t.TestData.Image); a.place('caliper',[40 175;340 175]); drawnow; a.setScale(.1,.1); a.place('circle',[465 185 65]); drawnow; a.loadImage(uint8(zeros(420,640)),'flat'); a.place('caliper',[40 175;340 175]); a.capture(); verifyEqual(t,a.Data.Records.Decision,"NOT_MEASURED"); verifyTrue(t,isnan(a.Data.Records.Value));
end
function testNativePointLineCaptureAndReplayGuard(t)
a=VIStudioMeasurementAppV17('off'); cleanup=onCleanup(@() delete(a)); a.loadImage(t.TestData.Image); a.Handles.Snap.Value=true; a.place('pointline',[80 90;80 280;300 220]); a.capture(); verifyEqual(t,a.Data.Records.Method,"native-uitsquare-capture"); verifyEqual(t,a.Data.Records.State,"MEASURED"); verifyEqual(t,a.Data.Records.Value,220,'AbsTol',2); recipe=a.Data.recipe(); changed=t.TestData.Image; changed(1,1)=changed(1,1)+1; other=VIStudioMeasurementV17; other.loadImage(changed); verifyError(t,@() other.applyRecipe(recipe),'VIStudioV17:NativeReplay');
end
