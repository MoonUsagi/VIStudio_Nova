function tests=testStructuredV25Regression
 tests=functiontests(localfunctions);
end
function setupOnce(t)
 root=fileparts(fileparts(mfilename('fullpath'))); addpath(root); folder=tempname; mkdir(folder); t.TestData.Folder=folder; t.TestData.OldHome=getenv('VISTUDIO_V16_USER_DIR'); setenv('VISTUDIO_V16_USER_DIR',fullfile(folder,'test_user')); rng(14); files=strings(4,1);
 for k=1:4, files(k)=fullfile(folder,sprintf('image%d.png',k)); imwrite(uint8(30+180*rand(64,96,3)),files(k)); end; t.TestData.Files=files;
end
function teardownOnce(t), setenv('VISTUDIO_V16_USER_DIR',t.TestData.OldHome); folder=t.TestData.Folder; assert(startsWith(string(folder),string(tempdir))); rmdir(folder,'s'); end
function d=doc(t)
 d=VIStudioAnnotationDataV15; d.loadFiles(t.TestData.Files); d.addClass('part',[.1 .8 .7]); d.addClass('other',[.9 .4 .3]);
end
function d=instances(t)
 d=doc(t); for k=1:4, mask=false(64,96); mask(8:24,8:30)=true; d.add(d.Files(k),'part','mask',mask); mask=false(64,96); mask(15:32,23:44)=true; d.add(d.Files(k),'part','mask',mask); d.markReviewed(d.Files(k),true); end
end
function g=pose()
 template=VIStudioPoseV15.template(); g=VIStudioPoseV15.geometry(template,[10 10;40 10;40 40;NaN NaN],[2;2;1;0],[1 1 96 64]);
end
function testInstanceOverlapExportRoundTrip(t)
 d=instances(t); out=d.exportStructured(fullfile(t.TestData.Folder,'instances'),'instance'); data=VIStudioStructuredV15.read(out.Path); verifyEqual(t,height(data.objects),8); a=VIStudioMasksV11.mask(data.objects.MaskFile(1)); b=VIStudioMasksV11.mask(data.objects.MaskFile(2)); verifyTrue(t,any(a & b,'all')); verifyFalse(t,isequal(a,b));
 verifyEqual(t,data.objects.ObjectID,d.Annotations.InstanceID); imported=VIStudioAnnotationDataV15; imported.importStructured(out.Path); verifyEqual(t,imported.Annotations.InstanceID,d.Annotations.InstanceID); verifyTrue(t,all(imported.Reviewed));
 ds=VIStudioStructuredV15.instanceDatastore(data,'train'); sample=read(ds); verifyNumElements(t,sample,4); verifySize(t,sample{4},[64 96 2]); verifyEqual(t,sample{2}(1,:),[8 8 23 17]);
end
function testSplitMergeAtomicUndo(t)
 d=doc(t); mask=false(64,96); mask(5:8,5:8)=true; mask(20:24,20:24)=true; id=d.add(d.Files(1),'part','mask',mask); ids=d.splitInstance(id); verifyNumElements(t,ids,2); verifyEqual(t,height(d.Annotations),2); d.undo(); verifyEqual(t,d.Annotations.ID,id); d.redo(); id=d.mergeInstances(ids); verifyEqual(t,height(d.Annotations),1); verifyEqual(t,d.Annotations.Geometry{1},mask); verifyEqual(t,d.Annotations.InstanceID,id);
end
function testMergeClassAndFileGuard(t)
 d=doc(t); a=d.add(d.Files(1),'part','rectangle',[3 3 6 6]); b=d.add(d.Files(1),'other','rectangle',[15 15 6 6]); verifyError(t,@() d.mergeInstances([a b]),'VIStudioV15:InstanceMerge'); verifyEqual(t,height(d.Annotations),2);
end
function testPoseVisibilityAndNames(t)
 g=VIStudioPoseV15.validate(pose(),[64 96]); verifyTrue(t,all(isnan(g.XY(4,:)))); g.XY(4,:)=[0 0]; verifyError(t,@() VIStudioPoseV15.validate(g,[64 96]),'VIStudioV15:PoseVisibility');
 g=pose(); g.Names(2)=g.Names(1); verifyError(t,@() VIStudioPoseV15.validate(g,[64 96]),'VIStudioV15:PoseNames');
end
function testPoseMetricsMissesAndAnisotropicMeasures(t)
 truth=pose(); predicted=truth; predicted.Visibility(2)=0; predicted.XY(2,:)=[NaN NaN]; [rows,summary]=VIStudioPoseV15.metrics(predicted,truth,.05); verifyEqual(t,summary.PCK,.5); verifyEqual(t,summary.MissRate,.5); verifyEqual(t,sum(rows.Evaluated),2);
 measures=VIStudioPoseV15.measure(truth,.5,.25); verifyEqual(t,measures.Distance(1),15); verifyEqual(t,measures.AngleDegrees(1),0); verifyTrue(t,isnan(measures.Distance(3)));
end
function testPoseExportAndNativeVisibilityGuard(t)
 d=doc(t); for k=1:2, d.addKeypoints(d.Files(k),'part',pose()); d.markReviewed(d.Files(k),true); end
 out=d.exportStructured(fullfile(t.TestData.Folder,'poses'),'keypoints'); data=VIStudioStructuredV15.read(out.Path); verifyEqual(t,data.objects.Pose{1}.Visibility,[2;2;1;0]); verifyError(t,@() VIStudioStructuredV15.poseDatastore(data,'train'),'VIStudioV15:PoseNativeVisibility');
end
function testFullyVisiblePoseDatastore(t)
 d=doc(t); g=pose(); g.XY(4,:)=[10 40]; g.Visibility(:)=2; for k=1:2, d.addKeypoints(d.Files(k),'part',g); d.markReviewed(d.Files(k),true); end
 out=d.exportStructured(fullfile(t.TestData.Folder,'visible_poses'),'keypoints'); data=VIStudioStructuredV15.read(out.Path); ds=VIStudioStructuredV15.poseDatastore(data,'train'); sample=read(ds); verifyClass(t,sample{2},'table'); verifyEqual(t,sample{2}{1,1}{1},g.XY);
end
function testStructuredLeakAndMutation(t)
 d=instances(t); out=d.exportStructured(fullfile(t.TestData.Folder,'leak'),'instance'); data=VIStudioStructuredV15.read(out.Path); data.manifest.File(2)=data.manifest.File(1); verifyError(t,@() VIStudioStructuredV15.validate(data),'VIStudioV15:StructuredManifest');
 data=VIStudioStructuredV15.read(out.Path); data.manifest.SourceFile(2)=data.manifest.SourceFile(1); data.manifest.Split(2)="test"; verifyError(t,@() VIStudioStructuredV15.validate(data),'VIStudioV15:StructuredLeak');
 data=VIStudioStructuredV15.read(out.Path); image=imread(data.manifest.File(1)); image(1,1,1)=image(1,1,1)+1; imwrite(image,data.manifest.File(1)); verifyError(t,@() VIStudioStructuredV15.assertUnchanged(data),'VIStudioV15:StructuredChanged');
end
function testInstanceOneToOneMetrics(t)
 mask=false(10); mask(2:4,2:4)=true; p=struct('Mask',mask,'Class',"part"); result=VIStudioStructuredV15.instanceMetrics([p p],p,.5); verifyEqual(t,[result.TP result.FP result.FN],[1 1 0]); verifyEqual(t,result.Precision,.5);
 p.Class="other"; result=VIStudioStructuredV15.instanceMetrics(p,struct('Mask',mask,'Class',"part"),.5); verifyEqual(t,[result.TP result.FP result.FN],[0 1 1]);
end
function testQualityDoesNotChangeTruth(t)
 d=doc(t); d.add(d.Files(1),'part','rectangle',[3 3 1 1]); d.add(d.Files(1),'part','rectangle',[3 3 1 1]); d.addKeypoints(d.Files(1),'other',pose()); before=d.Annotations; revision=d.Revision; report=VIStudioAnnotationQualityV15.analyze(d,4,.95); verifyTrue(t,any(report.Issues.Code=="POSSIBLE_DUPLICATE")); verifyTrue(t,any(report.Issues.Code=="TINY_REGION")); verifyTrue(t,any(report.Issues.Code=="MISSING_POINTS")); verifyEqual(t,d.Annotations,before); verifyEqual(t,d.Revision,revision);
end
function testReviewerAgreementAndExport(t)
 a=doc(t); b=doc(t); a.add(a.Files(1),'part','rectangle',[5 5 10 10]); b.add(b.Files(1),'part','rectangle',[5 5 10 10]); report=VIStudioAnnotationQualityV15.compare(a,b); verifyEqual(t,report.Regions.IoU,1); folder=fullfile(t.TestData.Folder,'quality'); VIStudioAnnotationQualityV15.export(report,folder); verifyTrue(t,isfile(fullfile(folder,'reviewer_agreement.csv')));
end
function testModelFreeConfiguration(t)
 for task=["instance","keypoints","assist"], options=VIStudioTaskModelsV15.defaults(task); file=fullfile(t.TestData.Folder,char(task+"_setup.mat")); VIStudioTaskModelsV15.saveSetup(options,file); verifyEqual(t,VIStudioTaskModelsV15.loadSetup(file),options); verifyError(t,@() VIStudioTaskModelsV15.saveSetup(options,file),'VIStudioV15:FileExists'); end
end
function testEditorInstancesPosesAndQuality(t)
 editor=VIStudioLabelerV25('off',[],fullfile(t.TestData.Folder,'editor_recovery')); cleanup=onCleanup(@() delete(editor)); editor.configureAutosave(false,60); editor.loadFiles(t.TestData.Files(1)); editor.addClass('part',[.1 .8 .7]); editor.openAdvanced('keypoints'); editor.addPose(pose(),'part'); verifyEqual(t,height(editor.Handles.Points.Data),4); editor.analyzeQuality(); verifyNotEmpty(t,editor.QualityReport); editor.setLanguage('en'); editor.setLanguage('bilingual');
end
function testPendingAICandidateCannotExport(t)
 d=doc(t); d.add(d.Files(1),'part','mask',true(64,96),'model',.9,'SAM fixture'); verifyError(t,@() d.markReviewed(d.Files(1),true),'VIStudioV15:PendingAnnotations'); d.accept(d.Files(1)); d.markReviewed(d.Files(1),true); out=d.exportStructured(fullfile(t.TestData.Folder,'reviewed_ai'),'instance'); verifyTrue(t,isfile(out.Path));
end
function testTaskStudioSetupAndRoles(t)
 app=VIStudioTaskAppV25('instance','off'); cleanup=onCleanup(@() delete(app)); o=app.Pane.options(); verifyEqual(t,o.Task,"instance"); file=fullfile(t.TestData.Folder,'studio_setup.mat'); app.Pane.saveSetup(file); app.Pane.loadSetup(file); verifyEmpty(t,app.Pane.Artifact);
 d=instances(t); output=d.exportStructured(fullfile(t.TestData.Folder,'studio_dataset'),'instance'); app.Pane.loadDataset(output.Path); verifyEqual(t,height(app.Pane.Dataset.objects),8); app.Pane.Handles.Manifest.Selection=4; callback=findall(app.UIFigure,'Text','指定影像用途 / Assign split'); app.Pane.Handles.Split.Value='test'; callback.ButtonPushedFcn([],[]); verifyEqual(t,app.Pane.Dataset.manifest.Split(4),"test"); file=fullfile(t.TestData.Folder,'roles_setup.mat'); app.Pane.saveSetup(file); app.Pane.loadSetup(file); verifyEqual(t,app.Pane.Dataset.manifest.Split(4),"test");
end
function testLegacySessionAndRecovery(t)
 old=VIStudioAnnotationDataV12; old.loadFiles(t.TestData.Files(1)); old.addClass('part'); old.add(old.Files(1),'part','rectangle',[3 3 10 10]); file=fullfile(t.TestData.Folder,'old.mat'); old.saveSession(file); d=VIStudioAnnotationDataV15; d.loadSession(file); verifyEqual(t,height(d.Annotations),1); d.addKeypoints(d.Files(1),'part',pose()); session=fullfile(t.TestData.Folder,'new.mat'); d.saveSession(session); other=VIStudioAnnotationDataV15; other.loadSession(session); verifyEqual(t,other.Annotations,d.Annotations);
end
function testAllIntegratedWorkspacesAndLauncher(t)
 for task=["classification","detection","anomaly"], app=VIStudioVisionAppV25(task,'off'); cleanup=onCleanup(@() delete(app)); app.selectWorkspace('advanced'); verifyClass(t,app.advancedTools().Structured,'VIStudioTaskPaneV25'); clear cleanup; end
 fig=VIStudioV25('', 'off'); cleanup=onCleanup(@() delete(fig)); images=findall(fig,'-isa','matlab.ui.control.Image'); verifyNumElements(t,images,15); verifyTrue(t,contains(fig.Name,'VIStudio V25'));
end

function testSAMPromptValidationAndImageSwitch(t)
 image=uint8(zeros(64,96,3)); verifyError(t,@() VIStudioTaskModelsV15.assist([],image,[100 10],zeros(0,2),[]),'VIStudioV15:PromptBounds'); verifyError(t,@() VIStudioTaskModelsV15.assist([],image,zeros(0,2),zeros(0,2),[]),'VIStudioV15:Prompt');
 editor=VIStudioLabelerV25('off',[],fullfile(t.TestData.Folder,'prompt_recovery')); cleanup=onCleanup(@() delete(editor)); editor.configureAutosave(false,60); editor.loadFiles(t.TestData.Files(1:2)); editor.Handles.Foreground.Data=[20 20]; editor.Handles.Background.Data=[5 5]; editor.selectImage(2); verifyEmpty(t,editor.Handles.Foreground.Data); verifyEmpty(t,editor.Handles.Background.Data);
end
function testCustomPointTemplateAndSemanticExportGuard(t)
 editor=VIStudioLabelerV25('off',[],fullfile(t.TestData.Folder,'custom_recovery')); cleanup=onCleanup(@() delete(editor)); editor.configureAutosave(false,60); editor.loadFiles(t.TestData.Files(1)); editor.addClass('part',[.1 .8 .7]); template=struct('Name',"holes",'Names',["center";"tip"],'Edges',[1 2]); editor.setPoseTemplate(template); geometry=VIStudioPoseV15.geometry(template,[10 10;50 30],[2;2],[1 1 96 64]); editor.addPose(geometry,'part'); editor.markReviewed(true); verifyEqual(t,height(editor.Handles.Points.Data),2);
 verifyError(t,@() editor.Data.exportSemantic(fullfile(t.TestData.Folder,'wrong_semantic')),'VIStudioV15:PoseExportTask');
end
function testPoseNoTruthIsUndefined(t)
 g=pose(); g.Visibility(:)=0; g.XY(:)=NaN; [~,summary]=VIStudioPoseV15.metrics(g,g); verifyEqual(t,summary.EvaluatedPoints,0); verifyTrue(t,isnan(summary.PCK));
end
