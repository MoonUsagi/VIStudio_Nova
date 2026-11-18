function tests=testPretrainedFCSiamV25
tests=functiontests(localfunctions);
end
function setupOnce(t)
t.TestData.Root=fileparts(fileparts(mfilename('fullpath'))); if isfolder(fullfile(t.TestData.Root,'src')), addpath(fullfile(t.TestData.Root,'src')); end
t.TestData.Bundle=fullfile(fileparts(which('VIStudioFCSiamV25')),'VIStudio_Pretrained_V23'); s=load(fullfile(t.TestData.Root,'tests','fixtures','fc_siam_reference_v23.mat')); t.TestData.Cases=s.cases; t.TestData.Manifest=jsondecode(fileread(fullfile(t.TestData.Bundle,'MANIFEST.json')));
end
function file=modelFile(t,variant)
file=fullfile(t.TestData.Bundle,"fc-siam-"+variant+"-levircd.mat");
end
function testPublisherLicenseAndHashes(t)
m=t.TestData.Manifest; verifyEqual(t,numel(m),2); verifyTrue(t,isfile(fullfile(t.TestData.Bundle,'LICENSE-APACHE-2.0.txt'))); verifyTrue(t,isfile(fullfile(t.TestData.Bundle,'NOTICE.md')));
for k=1:2, verifyEqual(t,string(m(k).Source.ModelCardLicense),"apache-2.0"); verifyEqual(t,VIStudioToolsV3.fileHash(fullfile(t.TestData.Bundle,m(k).File)),string(m(k).SHA256)); verifyTrue(t,m(k).Passed); end
end
function testDiffReferenceParity(t)
compare(t,"diff");
end
function testConcReferenceParity(t)
compare(t,"conc");
end
function compare(t,variant)
for k=1:numel(t.TestData.Cases)
 c=t.TestData.Cases{k}; a=VIStudioFCSiamV25.loadWeights(modelFile(t,variant),size(c.reference)); [~,p]=VIStudioFCSiamV25.predict(a,c.reference,c.current); expected=c.(char(variant)); verifyLessThan(t,double(max(abs(p-expected),[],'all')),1e-5); verifyEqual(t,p(:,:,2)>=.5,expected(:,:,2)>=.5);
end
end
function testPaddingAndRawOutputDimensions(t)
a=VIStudioFCSiamV25.loadWeights(modelFile(t,"diff"),[65 67 3]); [x,y]=VIStudioFCSiamV25.preprocess(a.Metadata,zeros(65,67,3),ones(65,67,3)); verifySize(t,x,[96 96 3]); verifyEqual(t,x(66:end,:,:),zeros(31,96,3,'single')); verifyEqual(t,y(:,68:end,:),zeros(96,29,3,'single')); p=VIStudioFCSiamV25.predict(a,zeros(65,67,3),ones(65,67,3)); verifySize(t,p,[65 67]);
end
function testGeometryRetargetPreservesPretrainedStatus(t)
a=VIStudioFCSiamV25.loadWeights(modelFile(t,"conc"),[96 128 3]); verifyEqual(t,a.Metadata.InputSize,[96 128 3]); verifyTrue(t,contains(a.Metadata.WeightStatus,'PRETRAINED')); verifyFalse(t,a.Metadata.ValidatedForRealInspection); verifyEqual(t,string(a.Metadata.Provenance.TrainingDataset),"LEVIR-CD"); verifyError(t,@() VIStudioFCSiamV25.predict(a,zeros(64,64,3),zeros(64,64,3)),'VIStudioV25:FCSiamSize');
end
function testNormalizationContractRejected(t)
a=VIStudioFCSiamV25.loadWeights(modelFile(t,"diff"),[32 32 3]); a.Metadata.Normalization.Std=[1 1 1]; verifyError(t,@() VIStudioFCSiamV25.validate(a),'VIStudioV25:FCSiamArtifact');
end
function testWorkspaceBothPretrainedVariants(t)
a=VIStudioChangeDetectionAppV25('off'); cleanup=onCleanup(@() delete(a)); c=t.TestData.Cases{1}; a.loadReference(c.reference); a.loadCurrent(c.current);
for v=["fc-siam-diff","fc-siam-conc"], a.loadPretrained(v); verifyEqual(t,string(a.Handles.Method.Value),v); verifyEqual(t,a.Handles.Threshold.Value,.5); a.run(); verifyEqual(t,a.Data.State,"COMPLETE"); verifyTrue(t,contains(a.Data.Message,'PRETRAINED_REMOTE_SENSING')); end
end
function testExportContainsWeightProvenance(t)
a=VIStudioChangeDetectionV25; c=t.TestData.Cases{1}; a.setReference(c.reference); a.setCurrent(c.current); a.setArtifact(VIStudioFCSiamV25.loadWeights(modelFile(t,"diff"),size(c.reference))); o=a.Options; o.Method="fc-siam-diff"; a.configure(o); a.run(); folder=tempname; mkdir(folder); cleanup=onCleanup(@() rmdir(folder,'s')); dest=a.export(folder); s=load(fullfile(dest,'change-report.mat')); verifyEqual(t,string(s.report.ResearchModelMetadata.Provenance.ModelCardLicense),"apache-2.0"); verifyEqual(t,strlength(string(s.report.ResearchModelMetadata.Provenance.SourceSHA256)),64);
end
function testV22NativeCheckpointRemainsCompatible(t)
a=VIStudioFCSiamV22.create('fc-siam-diff',[32 32 3]); file=[tempname '.mat']; VIStudioFCSiamV22.saveWeights(a,file); cleanup=onCleanup(@() delete(file)); b=VIStudioFCSiamV25.loadWeights(file); x=zeros(32,32,3); y=ones(32,32,3); p=VIStudioFCSiamV22.predict(a,x,y); q=VIStudioFCSiamV25.predict(b,x,y); verifyLessThan(t,double(max(abs(p-q),[],'all')),1e-5);
end
