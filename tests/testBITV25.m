function tests=testBITV25
tests=functiontests(localfunctions);
end
function setupOnce(t)
t.TestData.Root=fileparts(fileparts(mfilename('fullpath'))); if isfolder(fullfile(t.TestData.Root,'src')), addpath(fullfile(t.TestData.Root,'src')); end
t.TestData.Bundle=fullfile(fileparts(which('VIStudioBITV25')),'VIStudio_BIT_Pretrained_V24'); t.TestData.File=fullfile(t.TestData.Bundle,'bit-r18-levircd.mat'); f=load(fullfile(t.TestData.Root,'tests','fixtures','bit_reference_v24.mat')); t.TestData.Cases=f.cases; t.TestData.Dir=tempname; mkdir(t.TestData.Dir);
end
function teardownOnce(t), rmdir(t.TestData.Dir,'s'); end
function testNativeFactoryArchitectureAndRNG(t)
before=rng; a=VIStudioBITV25.create([32 32 3]); verifyEqual(t,rng,before); verifyEqual(t,numel(fieldnames(a.Weights)),225); verifyTrue(t,isfield(a.Weights,'decode_head_decoder_7_attn_to_q_weight')); verifyFalse(t,isfield(a.Weights,'decode_head_decoder_8_attn_to_q_weight')); verifySize(t,a.Weights.decode_head_enc_pos_embedding,[1 8 32]); verifySize(t,a.Weights.backbone_stem_0_weight,[3 3 3 32]); verifyEqual(t,a.Metadata.WeightStatus,"RANDOM_INITIALIZATION");
end
function testReferenceProbabilityAndBackboneParity(t)
for k=1:numel(t.TestData.Cases)
 c=t.TestData.Cases{k}; a=VIStudioBITV25.loadWeights(t.TestData.File,size(c.reference)); [~,p,trace]=VIStudioBITV25.predict(a,c.reference,c.current); verifyLessThan(t,double(max(abs(p-c.probabilities),[],'all')),1e-4); verifyLessThan(t,double(max(abs(trace.ReferenceBackbone-c.backbone),[],'all')),1e-4); verifyEqual(t,p(:,:,2)>=.5,c.probabilities(:,:,2)>=.5); verifyLessThan(t,double(max(abs(sum(p,3)-1),[],'all')),1e-5);
end
end
function testPublisherLicenseAndNativeHash(t)
m=jsondecode(fileread(fullfile(t.TestData.Bundle,'MANIFEST.json'))); verifyTrue(t,m.Passed); verifyEqual(t,string(m.Source.ModelCardLicense),"apache-2.0"); verifyFalse(t,m.Source.OriginalBITAuthorCheckpoint); verifyEqual(t,VIStudioToolsV3.fileHash(t.TestData.File),string(m.SHA256)); verifyTrue(t,isfile(fullfile(t.TestData.Bundle,'LICENSE-APACHE-2.0.txt'))); verifyTrue(t,isfile(fullfile(t.TestData.Bundle,'NOTICE.md')));
end
function testOddShapeAndRetarget(t)
a=VIStudioBITV25.loadWeights(t.TestData.File,[65 67 3]); [s,p]=VIStudioBITV25.predict(a,zeros(65,67,3),ones(65,67,3)); verifySize(t,s,[65 67]); verifySize(t,p,[65 67 2]); verifyEqual(t,a.Metadata.InputSize,[65 67 3]); verifyFalse(t,a.Metadata.ValidatedForRealInspection);
end
function testNativeCheckpointReallyLoadsModifiedWeights(t)
a=VIStudioBITV25.create([32 32 3]); p=VIStudioBITV25.predict(a,zeros(32,32,3),ones(32,32,3)); a.Weights.decode_head_conv_seg_bias(2)=5; file=fullfile(t.TestData.Dir,'changed.mat'); VIStudioBITV25.saveWeights(a,file); b=VIStudioBITV25.loadWeights(file); q=VIStudioBITV25.predict(b,zeros(32,32,3),ones(32,32,3)); verifyGreaterThan(t,double(max(abs(p-q),[],'all')),.1); verifyEqual(t,b.Weights,a.Weights);
end
function testRejectCorruptWeightsAndBNState(t)
a=VIStudioBITV25.create([32 32 3]); a.Weights.decode_head_encoder_0_attn_to_q_weight(1)=NaN; verifyError(t,@() VIStudioBITV25.validate(a),'VIStudioV25:BITWeights'); a=VIStudioBITV25.create([32 32 3]); a.Weights.backbone_stem_1_running_var(1)=-1; verifyError(t,@() VIStudioBITV25.validate(a),'VIStudioV25:BITWeights'); a=rmfield(a,'Weights'); verifyError(t,@() VIStudioBITV25.validate(a),'VIStudioV25:BITArtifact');
end
function testRejectMetadataAndInputContracts(t)
a=VIStudioBITV25.create([32 32 3]); a.Metadata.ClassNames=["changed","unchanged"]; verifyError(t,@() VIStudioBITV25.validate(a),'VIStudioV25:BITArtifact'); verifyError(t,@() VIStudioBITV25.create([1024 1024 3]),'VIStudioV25:BITSize'); a=VIStudioBITV25.create([32 32 3]); verifyError(t,@() VIStudioBITV25.predict(a,zeros(33,32,3),zeros(33,32,3)),'VIStudioV25:BITSize');
end
function testWorkspaceCreationPretrainedAndLoadMAT(t)
a=VIStudioChangeDetectionAppV25('off'); cleanup=onCleanup(@() delete(a)); c=t.TestData.Cases{1}; a.loadReference(c.reference); a.loadCurrent(c.current); a.initializeModel('bit-r18'); verifyEqual(t,a.Data.Artifact.Metadata.WeightStatus,"RANDOM_INITIALIZATION"); a.loadPretrained('bit-r18'); verifyEqual(t,string(a.Handles.Method.Value),"bit-r18"); verifyEqual(t,a.Handles.Threshold.Value,.5); a.run(); verifyEqual(t,a.Data.State,"COMPLETE"); verifyTrue(t,contains(a.Data.Message,'PRETRAINED_REMOTE_SENSING')); a.loadModel(t.TestData.File); verifyEqual(t,string(a.Handles.Method.Value),"bit-r18"); verifyEqual(t,a.Data.State,"READY"); verifyEqual(t,a.Data.Artifact.Metadata.InputSize,size(c.reference)); a.run(); verifyEqual(t,a.Data.State,"COMPLETE");
end
function testMissingOrWrongModelFailsWithoutFallback(t)
a=VIStudioChangeDetectionV25; a.setReference(zeros(32,32,3)); a.setCurrent(ones(32,32,3)); o=a.Options; o.Method="bit-r18"; a.configure(o); verifyError(t,@() a.run(),'VIStudioV25:ChangeModel'); a.setArtifact(VIStudioBITV25.create([32 32 3])); o.Method="fc-siam-diff"; a.configure(o); verifyError(t,@() a.run(),'VIStudioV25:ChangeModelVariant'); verifyEmpty(t,a.Mask);
end
function testExportIncludesPublisherProvenance(t)
a=VIStudioChangeDetectionV25; c=t.TestData.Cases{1}; a.setReference(c.reference); a.setCurrent(c.current); a.setArtifact(VIStudioBITV25.loadWeights(t.TestData.File,size(c.reference))); o=a.Options; o.Method="bit-r18"; a.configure(o); a.run(); dest=a.export(t.TestData.Dir); s=load(fullfile(dest,'change-report.mat')); m=s.report.ResearchModelMetadata; verifyEqual(t,m.Architecture,"bit-r18"); verifyEqual(t,string(m.Provenance.Publisher),"likyoo/Open-CD_Model_Zoo"); verifyEqual(t,string(m.Provenance.ModelCardLicense),"apache-2.0");
end
