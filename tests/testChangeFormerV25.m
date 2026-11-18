function tests=testChangeFormerV25
tests=functiontests(localfunctions);
end
function setupOnce(t)
t.TestData.Root=fileparts(fileparts(mfilename('fullpath'))); if isfolder(fullfile(t.TestData.Root,'src')), addpath(fullfile(t.TestData.Root,'src')); end
t.TestData.Bundle=fullfile(fileparts(which('VIStudioChangeFormerV25')),'VIStudio_ChangeFormer_Pretrained_V25'); t.TestData.File=fullfile(t.TestData.Bundle,'opencd-changeformer-b0-levircd.mat'); f=load(fullfile(t.TestData.Root,'tests','fixtures','changeformer_reference_v25.mat')); t.TestData.Cases=f.cases; t.TestData.Dir=tempname; mkdir(t.TestData.Dir);
end
function teardownOnce(t), rmdir(t.TestData.Dir,'s'); end
function testArchitectureVariantAndSeedContract(t)
before=rng; a=VIStudioChangeFormerV25.create([32 32 3]); verifyEqual(t,rng,before); verifyEqual(t,numel(fieldnames(a.Weights)),187); verifyFalse(t,a.Metadata.OriginalChangeFormerV6); verifySize(t,a.Weights.backbone_layers_2_1_1_attn_attn_in_proj_weight,[480 160]); verifySize(t,a.Weights.backbone_layers_3_1_1_ffn_layers_1_weight,[3 3 1 1024]); verifyEqual(t,a.Metadata.WeightStatus,"RANDOM_INITIALIZATION");
end
function testReferenceProbabilitiesAndFourStages(t)
for k=1:numel(t.TestData.Cases)
 c=t.TestData.Cases{k}; a=VIStudioChangeFormerV25.loadWeights(t.TestData.File,size(c.reference)); [~,p,trace]=VIStudioChangeFormerV25.predict(a,c.reference,c.current); verifyLessThan(t,double(max(abs(p-c.probabilities),[],'all')),1e-4); verifyEqual(t,p(:,:,2)>=.5,c.probabilities(:,:,2)>=.5);
 for stage=1:4, verifyLessThan(t,double(max(abs(trace.ReferenceStages{stage}-c.(sprintf('stage%d',stage))),[],'all')),1e-4); end
end
end
function testPublisherLicenseHashAndVariantDisclosure(t)
m=jsondecode(fileread(fullfile(t.TestData.Bundle,'MANIFEST.json'))); verifyTrue(t,m.Passed); verifyFalse(t,m.OriginalChangeFormerV6); verifyEqual(t,string(m.Source.ModelCardLicense),"apache-2.0"); verifyEqual(t,VIStudioToolsV3.fileHash(t.TestData.File),string(m.SHA256)); verifyTrue(t,contains(string(m.Source.ImplementationVariant),'not strict original')); verifyTrue(t,isfile(fullfile(t.TestData.Bundle,'LICENSE-APACHE-2.0.txt'))); verifyTrue(t,isfile(fullfile(t.TestData.Bundle,'NOTICE.md')));
end
function testOddShapeAndProbabilityContract(t)
a=VIStudioChangeFormerV25.loadWeights(t.TestData.File,[65 67 3]); [s,p]=VIStudioChangeFormerV25.predict(a,zeros(65,67,3),ones(65,67,3)); verifySize(t,s,[65 67]); verifySize(t,p,[65 67 2]); verifyLessThan(t,double(max(abs(sum(p,3)-1),[],'all')),1e-5); verifyFalse(t,a.Metadata.ValidatedForRealInspection);
end
function testRealWeightLoadingEffect(t)
a=VIStudioChangeFormerV25.create([32 32 3]); p=VIStudioChangeFormerV25.predict(a,zeros(32,32,3),ones(32,32,3)); a.Weights.decode_head_conv_seg_bias(2)=5; file=fullfile(t.TestData.Dir,'changed.mat'); VIStudioChangeFormerV25.saveWeights(a,file); b=VIStudioChangeFormerV25.loadWeights(file); q=VIStudioChangeFormerV25.predict(b,zeros(32,32,3),ones(32,32,3)); verifyGreaterThan(t,double(max(abs(p-q),[],'all')),.1); verifyEqual(t,b.Weights,a.Weights);
end
function testRejectCorruptOrMissingTensors(t)
a=VIStudioChangeFormerV25.create([32 32 3]); a.Weights.backbone_layers_0_0_projection_weight(1)=NaN; verifyError(t,@() VIStudioChangeFormerV25.validate(a),'VIStudioV25:ChangeFormerWeights'); a=VIStudioChangeFormerV25.create([32 32 3]); a.Weights.decode_head_convs_0_bn_running_var(1)=-1; verifyError(t,@() VIStudioChangeFormerV25.validate(a),'VIStudioV25:ChangeFormerWeights'); a.Weights=rmfield(a.Weights,'decode_head_conv_seg_bias'); verifyError(t,@() VIStudioChangeFormerV25.validate(a),'VIStudioV25:ChangeFormerWeights');
end
function testRejectOriginalV6ClaimAndInputShape(t)
a=VIStudioChangeFormerV25.create([32 32 3]); a.Metadata.OriginalChangeFormerV6=true; verifyError(t,@() VIStudioChangeFormerV25.validate(a),'VIStudioV25:ChangeFormerArtifact'); verifyError(t,@() VIStudioChangeFormerV25.create([1024 1024 3]),'VIStudioV25:ChangeFormerSize'); a=VIStudioChangeFormerV25.create([32 32 3]); verifyError(t,@() VIStudioChangeFormerV25.predict(a,zeros(33,32,3),zeros(33,32,3)),'VIStudioV25:ChangeFormerSize');
end
function testWorkspaceCreationPretrainedAndMAT(t)
a=VIStudioChangeDetectionAppV25('off'); cleanup=onCleanup(@() delete(a)); c=t.TestData.Cases{1}; a.loadReference(c.reference); a.loadCurrent(c.current); a.initializeModel('opencd-changeformer-b0'); verifyEqual(t,a.Data.Artifact.Metadata.WeightStatus,"RANDOM_INITIALIZATION"); a.loadPretrained('opencd-changeformer-b0'); verifyEqual(t,string(a.Handles.Method.Value),"opencd-changeformer-b0"); verifyEqual(t,a.Handles.Threshold.Value,.5); a.run(); verifyEqual(t,a.Data.State,"COMPLETE"); a.loadModel(t.TestData.File); verifyEqual(t,a.Data.Artifact.Metadata.InputSize,size(c.reference)); a.run(); verifyEqual(t,a.Data.State,"COMPLETE");
end
function testMissingOrWrongModelRejected(t)
a=VIStudioChangeDetectionV25; a.setReference(zeros(32,32,3)); a.setCurrent(ones(32,32,3)); o=a.Options; o.Method="opencd-changeformer-b0"; a.configure(o); verifyError(t,@() a.run(),'VIStudioV25:ChangeModel'); a.setArtifact(VIStudioChangeFormerV25.create([32 32 3])); o.Method="bit-r18"; a.configure(o); verifyError(t,@() a.run(),'VIStudioV25:ChangeModelVariant'); verifyEmpty(t,a.Score);
end
function testReportCarriesVariantAndPublisher(t)
a=VIStudioChangeDetectionV25; c=t.TestData.Cases{1}; a.setReference(c.reference); a.setCurrent(c.current); a.setArtifact(VIStudioChangeFormerV25.loadWeights(t.TestData.File,size(c.reference))); o=a.Options; o.Method="opencd-changeformer-b0"; a.configure(o); a.run(); folder=a.export(t.TestData.Dir); f=load(fullfile(folder,'change-report.mat')); m=f.report.ResearchModelMetadata; verifyFalse(t,m.OriginalChangeFormerV6); verifyEqual(t,string(m.Provenance.Publisher),"likyoo/Open-CD_Model_Zoo"); verifyEqual(t,string(m.Provenance.ModelCardLicense),"apache-2.0");
end
