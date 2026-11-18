function tests=testPoseMeasurementV25
tests=functiontests(localfunctions);
end
function setupOnce(t)
addpath(fileparts(fileparts(mfilename('fullpath')))); t.TestData.Dir=tempname; mkdir(t.TestData.Dir);
end
function teardownOnce(t)
folder=t.TestData.Dir; assert(startsWith(string(folder),string(tempdir))); rmdir(folder,'s');
end
function [a,recipe]=example()
a=VIStudioShapeMatchingV25; [template,~]=a.demo(); image=uint8(30*ones(240,520)); image(91:170,111:210)=template; image(81:180,331:410)=rot90(template);
a.setTemplate(template); a.setSearch(image); d=VIStudioMeasurementV17; d.loadImage(template); d.add('caliper',[8 58;92 58],struct('Name','Plate width','Width',3,'Threshold',.05,'Lower',63,'Upper',67)); recipe=d.recipe(); a.attachRecipe(recipe);
end
function testTwoNativeObjectsRemeasuredAtDifferentAngles(t)
[a,~]=example(); a.run(); verifyEqual(t,height(a.ObjectSummary),2); verifyEqual(t,height(a.Measurements),2); verifyEqual(t,a.Measurements.Value,[65;65],'AbsTol',1.5); verifyEqual(t,a.Measurements.Method,["native-caliper";"native-caliper"]); verifyTrue(t,all(a.ObjectSummary.Decision=="OK")); verifyEqual(t,sort(abs(a.Results.AngleDeg)),[0;90],'AbsTol',2);
end
function testMeasurementsUseSearchPixelsRatherThanCopiedReference(t)
[a,~]=example(); image=a.SearchImage; image(104:156,189:192)=30; a.setSearch(image); a.run(); verifyEqual(t,height(a.Measurements),2); verifyEqual(t,sort(a.Measurements.Value),[61;65],'AbsTol',1.5); verifyEqual(t,nnz(a.ObjectSummary.Decision=="NG"),1);
end
function testMillimeterScaleRemainsFixed(t)
[a,recipe]=example(); recipe.Unit="mm"; recipe.Scale=[.1 .1]; recipe.Definitions{1}.Lower=6.3; recipe.Definitions{1}.Upper=6.7; a.attachRecipe(recipe); a.run(); verifyEqual(t,a.Measurements.Value,[6.5;6.5],'AbsTol',.15); verifyTrue(t,all(a.Measurements.Unit=="mm")); verifyEqual(t,a.MeasurementRecipe.Scale,[.1 .1]);
end
function testToolFailureDoesNotSuppressOtherObjects(t)
[a,recipe]=example(); d=VIStudioMeasurementV17; d.loadImage(a.Template); d.add('distance',[20 20;70 20]); recipe=d.recipe();
matches=struct('ModelOriginTransformation',{simtform2d(1,0,[100 100]),simtform2d(1,0,[-50 -50])},'Score',{.9,.9});
[summary,rows]=VIStudioPoseMeasurementV25.measure(a.Template,a.SearchImage,recipe,[50 40],matches); verifyEqual(t,height(rows),2); verifyEqual(t,rows.Value(1),50); verifyTrue(t,isnan(rows.Value(2))); verifyEqual(t,rows.Decision(2),"NOT_MEASURED"); verifyEqual(t,summary.Decision(2),"REVIEW");
end
function testReferenceAndUnsupportedToolsRejected(t)
[a,recipe]=example(); recipe.ReferenceHash="wrong"; verifyError(t,@() a.attachRecipe(recipe),'VIStudioV25:RecipeReference');
d=VIStudioMeasurementV17; d.loadImage(a.Template); d.add('area',true(size(a.Template))); verifyError(t,@() a.attachRecipe(d.recipe()),'VIStudioV25:RecipeToolUnsupported');
d=VIStudioMeasurementV17; d.loadImage(a.Template); d.add('pointline',[20 20;70 20;40 55]); recipe=d.recipe(); recipe.Definitions{1}.Snap=true; recipe.Definitions{1}.NativeCaptured=true; verifyError(t,@() a.attachRecipe(recipe),'VIStudioV25:PointLineReplay');
end
function testTemplateChangeDetachesRecipeAndSearchChangeClearsRows(t)
[a,~]=example(); a.run(); a.setSearch(a.SearchImage); verifyEmpty(t,a.Measurements); verifyNotEmpty(t,a.MeasurementRecipe); a.setTemplate(a.Template); verifyEmpty(t,a.MeasurementRecipe); verifyEmpty(t,a.ObjectSummary);
end
function testCombinedDefinitionRoundTrip(t)
[a,~]=example(); file=fullfile(t.TestData.Dir,'definition.mat'); a.saveDefinition(file); b=VIStudioShapeMatchingV25; b.loadDefinition(file); verifyNotEmpty(t,b.MeasurementRecipe); b.setSearch(a.SearchImage); b.run(); verifyEqual(t,height(b.Measurements),2);
end
function testPerObjectExportAndNoMatch(t)
[a,~]=example(); a.run(); folder=a.export(t.TestData.Dir); rows=readtable(fullfile(folder,'object-measurements.csv')); verifyEqual(t,height(rows),2); verifyTrue(t,isfile(fullfile(folder,'object_0002','measurements.mat'))); verifyTrue(t,isfile(fullfile(folder,'all-object-measurements.png')));
a.setSearch(uint8(30*ones(size(a.SearchImage)))); a.run(); folder=a.export(t.TestData.Dir); verifyEqual(t,a.State,"NO_MATCH"); verifyEmpty(t,a.Measurements); verifyTrue(t,isfile(fullfile(folder,'object-summary.csv'))); verifyFalse(t,isfolder(fullfile(folder,'object_0001')));
end
function testMeasurementEditorConnectsToShapeUI(t)
a=VIStudioShapeMatchingAppV25('off'); cleanup=onCleanup(@() delete(a)); a.demo(); editor=a.editMeasurements(); editor.Data.add('caliper',[8 58;92 58],struct('Width',3)); a.useEditor(); a.run(); verifyEqual(t,height(a.Handles.Measurements.Data),1); verifyEqual(t,height(a.Handles.ObjectSummary.Data),1);
end
function testMatchedScaleDoesNotRescaleCameraCalibration(t)
[a,recipe]=example(); resized=imresize(a.Template,1.2); image=uint8(30*ones(240,340)); image(81:176,111:230)=resized; a.setSearch(image);
o=a.Options; o.ScaleRange=[1.15 1.25]; a.configure(o); recipe.Unit="mm"; recipe.Scale=[.1 .1]; recipe.Definitions{1}.Lower=7.5; recipe.Definitions{1}.Upper=8.1; a.attachRecipe(recipe); a.run();
verifyEqual(t,height(a.Measurements),1); verifyEqual(t,a.Measurements.Value,7.8,'AbsTol',.2); verifyEqual(t,a.MeasurementObjects{1}.Data.Scale,[.1 .1]); verifyEqual(t,a.Measurements.Decision,"OK");
end
function testCircleToolTransformIncludesRadius(t)
s=VIStudioMeasurementV17.definition('circle',[50 40 10],struct('Snap',true)); s=VIStudioPoseMeasurementV25.transform(s,simtform2d(1.5,90,[100 100]),[50 40],1.5); verifyEqual(t,s.Geometry,[100 100 15],'AbsTol',1e-6); verifyTrue(t,s.Snap);
end
function testMissingEdgesRetainOtherToolsOnSameObject(t)
[a,~]=example(); d=VIStudioMeasurementV17; d.loadImage(a.Template); d.add('distance',[20 20;70 20]); d.add('caliper',[8 3;92 3],struct('Width',1)); a.attachRecipe(d.recipe()); a.run();
verifyEqual(t,height(a.Measurements),4); verifyEqual(t,nnz(a.Measurements.Decision=="MEASURED"),2); verifyEqual(t,nnz(a.Measurements.Decision=="NOT_MEASURED"),2); verifyTrue(t,all(isnan(a.Measurements.Value(a.Measurements.Decision=="NOT_MEASURED")))); verifyTrue(t,all(a.ObjectSummary.Decision=="REVIEW"));
end
