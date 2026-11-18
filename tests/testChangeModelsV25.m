function tests=testChangeModelsV25
tests=functiontests(localfunctions);
end
function testEarlyFusionTraining(t)
[a,r]=VIStudioChangeModelsV25.trainSynthetic('early-fusion',4); verifyTrue(t,r.Finite); verifyLessThan(t,r.FinalLoss,r.InitialLoss); p=VIStudioChangeModelsV25.predict(a,zeros(64,64,3),ones(64,64,3)); verifySize(t,p,[64 64]); verifyFalse(t,a.Metadata.ValidatedForRealInspection);
end
function testSharedSiameseTrainingAndSymmetry(t)
[a,r]=VIStudioChangeModelsV25.trainSynthetic('siamese-absdiff',4); verifyTrue(t,r.Finite); verifyLessThan(t,r.FinalLoss,r.InitialLoss); x=zeros(64,64,3); y=ones(64,64,3); verifyEqual(t,VIStudioChangeModelsV25.predict(a,x,y),VIStudioChangeModelsV25.predict(a,y,x),'AbsTol',1e-6);
end
function testContractSize(t)
a=VIStudioChangeModelsV25.create('early-fusion'); verifyError(t,@() VIStudioChangeModelsV25.predict(a,zeros(32,32,3),zeros(32,32,3)),'VIStudioV25:ChangeModelSize');
end
function testMATRoundTripAndWorkspaceInference(t)
artifact=VIStudioChangeModelsV25.create('siamese-absdiff'); file=[tempname '.mat']; save(file,'artifact'); cleanup=onCleanup(@() delete(file)); a=VIStudioChangeDetectionV25; a.setReference(zeros(64,64,3)); a.setCurrent(ones(64,64,3)); a.loadArtifact(file); o=a.Options; o.Method="research-model"; a.configure(o); a.run(); verifySize(t,a.Score,[64 64]); verifyTrue(t,contains(a.Message,'Research model'));
end
function testMalformedArtifact(t)
verifyError(t,@() VIStudioChangeModelsV25.validate(struct()),'VIStudioV25:ChangeModel');
end
