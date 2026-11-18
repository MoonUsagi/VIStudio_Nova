function tests=testShapeMatchingV25
tests=functiontests(localfunctions);
end
function setupOnce(t)
addpath(fileparts(fileparts(mfilename('fullpath')))); t.TestData.Root=tempname; mkdir(t.TestData.Root);
end
function teardownOnce(t)
folder=t.TestData.Root; assert(startsWith(string(folder),string(tempdir))); rmdir(folder,'s');
end
function app=demo()
app=VIStudioShapeMatchingV25; [template,search]=app.demo(); app.setTemplate(template); app.setSearch(search);
end
function testNativeTranslationAndCoordinateConvention(t)
a=demo(); r=a.run(); verifyEqual(t,height(r),1); verifyGreaterThan(t,r.Score,.9);
points=[20 20;70 55]; actual=a.templatePointsToSearch(points,1); verifyEqual(t,actual,points+[110 90],'AbsTol',1);
verifyEqual(t,r.Class,"part"); verifyEqual(t,a.State,"MATCHED");
end
function testNativeRotation(t)
a=demo(); template=a.Template; rotated=rot90(template); search=uint8(30*ones(240,340)); search(81:180,111:190)=rotated; a.setSearch(search); r=a.run(); verifyEqual(t,height(r),1);
points=[20 20;70 55]; expected=[points(:,2)+110 101-points(:,1)+80]; verifyEqual(t,a.templatePointsToSearch(points,1),expected,'AbsTol',1.5);
verifyEqual(t,abs(r.AngleDeg),90,'AbsTol',1);
end
function testNativeScale(t)
a=demo(); resized=imresize(a.Template,1.2); search=uint8(30*ones(240,340)); search(81:176,111:230)=resized; a.setSearch(search); o=a.Options; o.ScaleRange=[1.15 1.25]; a.configure(o); r=a.run(); verifyEqual(t,height(r),1); verifyEqual(t,r.Scale,1.2,'AbsTol',.04);
end
function testNoMatchAndExport(t)
a=demo(); a.setSearch(uint8(30*ones(240,340))); r=a.run(); verifyEmpty(t,r); verifyEqual(t,a.State,"NO_MATCH"); folder=a.export(t.TestData.Root); saved=load(fullfile(folder,'shape-report.mat')); verifyEqual(t,saved.report.State,"NO_MATCH"); verifyEmpty(t,saved.report.Transforms);
end
function testChangeInvalidatesStaleResults(t)
a=demo(); a.run(); o=a.Options; o.ScoreThreshold=.8; a.configure(o); verifyEmpty(t,a.Matches); verifyEmpty(t,a.Results); verifyEmpty(t,a.Model);
a.run(); a.setSearch(a.SearchImage); verifyEmpty(t,a.Results); verifyEmpty(t,a.Matches);
end
function testDefinitionRoundTripAndInvalidLoad(t)
a=demo(); a.run(); file=fullfile(t.TestData.Root,'shape.mat'); a.saveDefinition(file); b=demo(); b.run(); b.loadDefinition(file); verifyEmpty(t,b.Results); verifyEmpty(t,b.Model); verifyEqual(t,b.Template,a.Template); verifyEqual(t,b.Options,a.Options); verifyEqual(t,height(b.run()),1);
definition=struct('Format',"bad",'Version',1,'Template',a.Template,'Options',a.Options); bad=fullfile(t.TestData.Root,'bad.mat'); save(bad,'definition'); before=b.Results; verifyError(t,@() b.loadDefinition(bad),'VIStudioV25:Definition'); verifyEqual(t,b.Results,before);
end
function testInvalidRangeIsAtomicAndCropIsBounded(t)
a=demo(); before=a.Options; o=before; o.ScaleRange=[2 1]; verifyError(t,@() a.configure(o),'VIStudioV25:Range'); verifyEqual(t,a.Options,before);
[~,search,roi]=a.demo(); a.setTemplate(search,roi); verifySize(t,a.Template,[80 100]); verifyError(t,@() a.setTemplate(search,[330 1 40 40]),'VIStudioV25:ROI'); verifySize(t,a.Template,[80 100]);
end
function testExportIncludesTransformAndInputEvidence(t)
a=demo(); a.run(); folder=a.export(t.TestData.Root); saved=load(fullfile(folder,'shape-report.mat')); verifyEqual(t,saved.report.Template,a.Template); verifyEqual(t,saved.report.SearchImage,a.SearchImage); verifyEqual(t,numel(saved.report.Transforms),1); verifyEqual(t,saved.report.Transforms{1},a.Matches(1).ModelOriginTransformation.A); verifyTrue(t,isfile(fullfile(folder,'matches.csv')));
end
function testNativeUIRunsAndDisplays(t)
a=VIStudioShapeMatchingAppV25('off'); cleanup=onCleanup(@() delete(a)); a.demo(); a.run(); verifyEqual(t,height(a.Handles.Results.Data),1); verifyTrue(t,contains(a.UIFigure.Name,'V25')); verifyTrue(t,isappdata(a.UIFigure,'VIStudioThemeV25'));
end
