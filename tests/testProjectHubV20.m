function tests=testProjectHubV20
tests=functiontests(localfunctions);
end
function setupOnce(t)
root=fileparts(fileparts(mfilename('fullpath'))); addpath(root); folder=tempname; mkdir(folder); t.TestData.Folder=folder; t.TestData.OldUser=getenv('VISTUDIO_V16_USER_DIR'); setenv('VISTUDIO_V16_USER_DIR',fullfile(folder,'preferences')); t.TestData.OldV15User=getenv('VISTUDIO_V15_USER_DIR'); setenv('VISTUDIO_V15_USER_DIR',fullfile(folder,'v15_preferences')); rng(16); images=fullfile(folder,'images'); mkdir(images); files=strings(3,1);
for k=1:3, files(k)=fullfile(images,sprintf('part_%d.png',k)); imwrite(uint8(rand(72,100,3)*255),files(k)); end; t.TestData.Images=images; t.TestData.Files=files;
end
function teardownOnce(t)
setenv('VISTUDIO_V16_USER_DIR',t.TestData.OldUser); setenv('VISTUDIO_V15_USER_DIR',t.TestData.OldV15User); folder=t.TestData.Folder; assert(startsWith(string(folder),string(tempdir))); rmdir(folder,'s');
end
function p=project(t,name,task)
if nargin<3, task='instance'; end; p=VIStudioProjectV16.create(name,task,fullfile(t.TestData.Folder,name));
end
function [out,session]=data(t,name)
d=VIStudioAnnotationDataV15; d.loadFiles(t.TestData.Files); d.addClass('part'); mask=false(72,100); mask(10:35,12:40)=true;
for k=1:3, d.add(d.Files(k),'part','mask',mask); d.markReviewed(d.Files(k),true); end
folder=fullfile(t.TestData.Folder,name); mkdir(folder); session=fullfile(folder,'session.mat'); d.saveSession(session); out=d.exportStructured(fullfile(folder,'dataset'),'instance'); loaded=load(out.Path); manifest=loaded.manifest; manifest.Split=["train";"train";"test"]; objects=loaded.objects; classes=loaded.classes; schema=loaded.schema; save(out.Path,'manifest','objects','classes','schema','-v7.3');
end
function testProjectMetadataRoundTripRelativePaths(t)
p=project(t,'relative'); images=fullfile(fileparts(p.File),'images'); mkdir(images); copyfile(t.TestData.Files(1),fullfile(images,'one.png')); p.attach('ImageFolder',images); p.setName('Inspection A','Test note'); p.save(); loaded=load(p.File); verifyEqual(t,string(loaded.project.ImageFolder),"images"); other=VIStudioProjectV16(p.File); verifyEqual(t,other.Info.ImageFolder,string(images)); verifyEqual(t,other.Info.Name,"Inspection A"); verifyEqual(t,other.status().Images,1);
verifyError(t,@() VIStudioProjectV16.create('Again','instance',fileparts(p.File)),'VIStudioV16:FileExists');
end
function testConcurrentProjectSaveGuard(t)
p=project(t,'concurrent'); second=VIStudioProjectV16(p.File); second.setName('Updated'); second.save(); p.setName('Stale'); verifyError(t,@() p.save(),'VIStudioV16:ProjectChanged'); verifyEqual(t,VIStudioProjectV16(p.File).Info.Name,"Updated");
end
function testFolderProgressDoesNotClaimTraining(t)
p=project(t,'folder','classification'); p.attach('ImageFolder',t.TestData.Images); s=p.status(); verifyEqual(t,s.Images,3); verifyEqual(t,s.Stages.State(3),"FOLDER_LINKED"); verifyEqual(t,s.ModelState,"NOT_LINKED"); verifyEqual(t,s.Next,"label"); verifyFalse(t,any(contains(s.Stages.State,["VERIFIED","COMPLETE","PASS"])));
end
function testDatasetSplitsAndReviewProgress(t)
[out,session]=data(t,'split_data'); p=project(t,'splits'); p.attach('DatasetFile',out.Path); p.attach('SessionFile',session); s=p.status(); verifyEqual(t,s.Train,2); verifyEqual(t,s.Test,1); verifyEqual(t,s.Reviewed,3); verifyEqual(t,s.Stages.State(3),"READY_TO_CONFIGURE"); verifyEqual(t,s.Next,"train");
d=VIStudioAnnotationDataV15; d.loadSession(session); d.add(d.Files(3),'part','rectangle',[45 20 10 10],'model',.8,'candidate'); file=fullfile(fileparts(session),'pending.mat'); d.saveSession(file); p.attach('SessionFile',file); s=p.status(); verifyEqual(t,s.Pending,1); verifyEqual(t,s.Stages.State(3),"REVIEW_PENDING"); verifyEqual(t,s.Next,"label");
end
function testAttachTaskMismatchAndRollback(t)
[out,~]=data(t,'mismatch_data'); p=project(t,'mismatch','keypoints'); verifyError(t,@() p.attach('DatasetFile',out.Path),'VIStudioV16:DatasetTask'); verifyEqual(t,p.Info.DatasetFile,""); file=fullfile(t.TestData.Folder,'not-model.mat'); x=1; save(file,'x'); verifyError(t,@() p.attach('ModelFile',file),'VIStudioV16:Model'); verifyEqual(t,p.Info.ModelFile,"");
end
function testReportModelMismatchIsExplicit(t)
p=project(t,'report'); model=struct('Placeholder',true); file=fullfile(t.TestData.Folder,'model-placeholder.mat'); save(file,'model'); p.attach('ModelFile',file); evaluation=struct('Task',"instance",'ModelDigest',"wrong",'Summary',struct('AP50',.75),'Meaning',"Synthetic report fixture; not model execution"); report=fullfile(t.TestData.Folder,'report.mat'); save(report,'evaluation'); p.attach('EvaluationFile',report); s=p.status(); verifyEqual(t,s.ModelState,"LINKED_NOT_RUN"); verifyEqual(t,s.Stages.State(4),"REPORT_MODEL_MISMATCH"); verifyEqual(t,s.Evaluation.Summary.AP50,.75);
evaluation.ModelDigest=VIStudioToolsV3.fileHash(file); save(report,'evaluation'); s=p.status(); verifyEqual(t,s.Stages.State(4),"REPORT_LINKED_UNVERIFIED"); verifyFalse(t,any(s.Stages.State=="PASS"));
end
function testMissingResourceAndRelink(t)
p=project(t,'missing'); folder=fullfile(t.TestData.Folder,'move_images'); mkdir(folder); original=fullfile(folder,'one.png'); copyfile(t.TestData.Files(1),original); p.attach('ImageFolder',folder); p.save(); moved=fullfile(t.TestData.Folder,'relocated_images'); movefile(folder,moved); s=p.status(); verifyEqual(t,s.Stages.State(1),"CHECK_LINKS"); verifyNotEmpty(t,s.Issues); p.attach('ImageFolder',moved); p.save(); verifyEqual(t,p.status().Images,1); verifyEmpty(t,p.status().Issues);
end
function testSessionSyncKeepsSourceAndReviewState(t)
[~,session]=data(t,'label_sync_data'); digest=VIStudioToolsV3.fileHash(session); p=project(t,'label_sync'); p.attach('SessionFile',session); p.save(); w=VIStudioWorkspaceV20(p,'label','off'); cleanup=onCleanup(@() delete(w)); w.Inner.configureAutosave(false,60); w.Inner.selectImage(1); w.Inner.addAnnotation('rectangle',[45 45 10 10],'part'); folder=w.sync(); verifyTrue(t,isfolder(folder)); verifyNotEqual(t,p.Info.SessionFile,string(session)); verifyEqual(t,VIStudioToolsV3.fileHash(session),digest); verifyEqual(t,p.status().Reviewed,2); verifyEqual(t,height(w.Inner.Data.Annotations),4); verifyTrue(t,isappdata(w.Inner.UIFigure,'VIStudioThemeV20'));
end
function testStructuredSyncAndReportRoundTrip(t)
[out,~]=data(t,'structured_sync_data'); digest=VIStudioToolsV3.fileHash(out.Path); p=project(t,'structured_sync'); p.attach('DatasetFile',out.Path); p.save(); w=VIStudioWorkspaceV20(p,'evaluate','off'); cleanup=onCleanup(@() delete(w)); pane=w.Inner.Pane; d=pane.Dataset; file=d.manifest.File(3); row=d.objects.File==file; mask=VIStudioMasksV11.mask(d.objects.MaskFile(find(row,1))); result=struct('Masks',mask,'Labels',"part",'Scores',.9,'SourceHash',VIStudioToolsV3.fileHash(file)); pane.evaluateOffline(file,{result}); w.sync(); verifyEqual(t,VIStudioToolsV3.fileHash(out.Path),digest); verifyTrue(t,isfile(p.Info.EvaluationFile)); verifyNotEqual(t,p.Info.DatasetFile,string(out.Path)); verifyEqual(t,p.status().Evaluation.Summary.AP50,1,'AbsTol',1e-12); reread=VIStudioStructuredV15.read(p.Info.DatasetFile); verifyEqual(t,reread.manifest.Split,["train";"train";"test"]);
end
function testHomeGuidanceAndSavedProjectResume(t)
h=VIStudioHomeV20('','off'); cleanup=onCleanup(@() delete(h)); h.createProject('Home demo','instance',fullfile(t.TestData.Folder,'home_project')); h.attachResource('ImageFolder',t.TestData.Images); verifyEqual(t,h.Snapshot.Images,3); verifyTrue(t,contains(h.Handles.Next.Text,'Label')); w=h.openStage('label'); cleanup2=onCleanup(@() delete(w)); verifyEqual(t,numel(w.Inner.Data.Files),3); w.Inner.configureAutosave(false,60); verifyEqual(t,char(getappdata(w.Inner.UIFigure,'VIStudioThemeV20').Sync.Enable),'on');
again=VIStudioHomeV20('','off'); cleanup3=onCleanup(@() delete(again)); verifyEqual(t,again.Project.File,h.Project.File); verifyTrue(t,isfile(again.Project.File));
end
function testThemedAllTaskFrontends(t)
for task=["classification","detection","anomaly"]
 a=VIStudioVisionAppV20(task,'off'); cleanup=onCleanup(@() delete(a)); verifyTrue(t,isappdata(a.UIFigure,'VIStudioThemeV20')); a.selectWorkspace('training'); a.selectWorkspace('evaluation'); a.selectWorkspace('inspection'); verifyClass(t,a.advancedTools().Structured,'VIStudioTaskPaneV20'); clear cleanup;
end
a=VIStudioSemanticAppV20('off'); cleanup=onCleanup(@() delete(a)); verifyTrue(t,isappdata(a.UIFigure,'VIStudioThemeV20')); clear cleanup;
a=VIStudioTaskAppV20('keypoints','off'); cleanup=onCleanup(@() delete(a)); verifyEqual(t,a.Pane.options().Task,"keypoints"); verifyTrue(t,isappdata(a.UIFigure,'VIStudioThemeV20'));
end
function testThemeIdempotenceAndReviewColor(t)
a=VIStudioLabelerV20('off',[],fullfile(t.TestData.Folder,'theme_recovery')); cleanup=onCleanup(@() delete(a)); a.configureAutosave(false,60); h=VIStudioThemeV20.install(a.UIFigure,'again'); other=VIStudioThemeV20.install(a.UIFigure,'again'); verifyEqual(t,h.Shell,other.Shell); verifyEqual(t,numel(findall(a.UIFigure,'ImageSource',VIStudioThemeV20.logo())),1); verifyEqual(t,a.Handles.Review.BackgroundColor,[.08 .48 .36]); verifyEqual(t,a.Handles.Review.FontColor,[1 1 1]);
end
function testBrandedEvaluationMatchesExistingMetrics(t)
mask=true(8); g=struct('Image',"a",'Class',"part",'Mask',mask); p=struct('Image',"a",'Class',"part",'Mask',mask,'Score',.9); old=VIStudioEvaluationV15.instances(p,g,"part"); current=VIStudioEvaluationV20.instances(p,g,"part"); verifyEqual(t,current,old); e=struct('Task',"instance",'Detailed',current,'Images',table("a",'VariableNames',{'File'}),'Meaning',"Synthetic fixture, not model inference"); fig=VIStudioEvaluationV20.show(e); cleanup=onCleanup(@() delete(fig)); verifyTrue(t,isappdata(fig,'VIStudioThemeV20'));
end
function testWrongEvaluationTaskRejected(t)
p=project(t,'wrong_eval'); evaluation=struct('Task',"keypoints",'Summary',struct('PCK',1)); file=fullfile(t.TestData.Folder,'wrong_eval.mat'); save(file,'evaluation'); verifyError(t,@() p.attach('EvaluationFile',file),'VIStudioV16:Evaluation'); verifyEqual(t,p.Info.EvaluationFile,"");
end
