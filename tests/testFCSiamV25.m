function tests=testFCSiamV25
tests=functiontests(localfunctions);
end
function setupOnce(t)
t.TestData.Dir=tempname; mkdir(t.TestData.Dir); t.TestData.Diff=VIStudioFCSiamV25.create('fc-siam-diff',[33 35 3]); t.TestData.Conc=VIStudioFCSiamV25.create('fc-siam-conc',[32 48 3]);
end
function teardownOnce(t)
rmdir(t.TestData.Dir,'s');
end
function testCompleteArchitectureAndSharedEncoder(t)
a=t.TestData.Diff; verifyEqual(t,numel(a.Encoder.OutputNames),5); verifyEqual(t,sum(arrayfun(@(l) isa(l,'nnet.cnn.layer.Convolution2DLayer'),a.Encoder.Layers)),10); verifyEqual(t,sum(arrayfun(@(l) isa(l,'nnet.cnn.layer.MaxPooling2DLayer'),a.Encoder.Layers)),4);
counts=cellfun(@(n) sum(arrayfun(@(l) isa(l,'nnet.cnn.layer.TransposedConvolution2DLayer'),n.Layers)),a.Block); verifyEqual(t,counts,[2 2 3 3]); verifyEqual(t,numel(a.Up),4); verifyFalse(t,isfield(a,'SecondEncoder')); verifyEqual(t,string(a.Encoder.Layers(2).Name),"conv11");
end
function testOddSizeDiffProbabilityAndRepeatability(t)
a=t.TestData.Diff; x=zeros(33,35,3,'single'); y=ones(33,35,3,'single'); before=rng; [s,p]=VIStudioFCSiamV25.predict(a,x,y); verifySize(t,p,[33 35 2]); verifyEqual(t,sum(p,3),ones(33,35,'single'),'AbsTol',single(1e-6)); verifyEqual(t,s,VIStudioFCSiamV25.predict(a,x,y),'AbsTol',single(1e-6)); verifyEqual(t,rng,before);
end
function testConcVariant(t)
a=t.TestData.Conc; [~,p]=VIStudioFCSiamV25.predict(a,zeros(32,48,3),ones(32,48,3)); verifySize(t,p,[32 48 2]); verifyEqual(t,a.Block{4}.Layers(1).InputSize(3),384); verifyEqual(t,t.TestData.Diff.Block{4}.Layers(1).InputSize(3),256);
end
function testFactorySeedRestoration(t)
before=rng; a=VIStudioFCSiamV25.create('fc-siam-diff',[33 35 3]); verifyEqual(t,rng,before); verifyEqual(t,extractdata(a.Encoder.Learnables.Value{1}),extractdata(t.TestData.Diff.Encoder.Learnables.Value{1}));
end
function testNativeWeightsRoundTripBothVariants(t)
for a={t.TestData.Diff,t.TestData.Conc}
 artifact=a{1}; file=[tempname(t.TestData.Dir) '.mat']; VIStudioFCSiamV25.saveWeights(artifact,file); loaded=VIStudioFCSiamV25.loadWeights(file); sz=artifact.Metadata.InputSize; x=zeros(sz,'single'); y=ones(sz,'single'); verifyEqual(t,VIStudioFCSiamV25.predict(artifact,x,y),VIStudioFCSiamV25.predict(loaded,x,y),'AbsTol',single(1e-6)); verifyEqual(t,loaded.Metadata.WeightStatus,"RANDOM_INITIALIZATION");
end
end
function testChangedParametersAreActuallyLoaded(t)
a=t.TestData.Diff; base=VIStudioFCSiamV25.predict(a,zeros(33,35,3),ones(33,35,3)); rows=a.Block{1}.Learnables; k=find(string(rows.Layer)=="conv11d" & string(rows.Parameter)=="Bias"); value=zeros(size(rows.Value{k}),'single'); value(2)=5; rows.Value{k}=dlarray(value); a.Block{1}.Learnables=rows; file=fullfile(t.TestData.Dir,'changed-weights.mat'); VIStudioFCSiamV25.saveWeights(a,file); b=VIStudioFCSiamV25.loadWeights(file); score=VIStudioFCSiamV25.predict(b,zeros(33,35,3),ones(33,35,3)); verifyGreaterThan(t,max(abs(score-base),[],'all'),.1); verifyEqual(t,score,VIStudioFCSiamV25.predict(a,zeros(33,35,3),ones(33,35,3)),'AbsTol',single(1e-6));
end
function testRejectCorruptWeightsAndState(t)
file=fullfile(t.TestData.Dir,'valid.mat'); VIStudioFCSiamV25.saveWeights(t.TestData.Diff,file); original=load(file); checkpoint=original.checkpoint; checkpoint.Encoder.Learnables.Value{1}=single(NaN(size(checkpoint.Encoder.Learnables.Value{1}))); bad=fullfile(t.TestData.Dir,'nan.mat'); save(bad,'checkpoint'); verifyError(t,@() VIStudioFCSiamV25.loadWeights(bad),'VIStudioV25:FCSiamWeights');
checkpoint=original.checkpoint; checkpoint.Encoder.Learnables.Value{1}=single(0); bad=fullfile(t.TestData.Dir,'shape.mat'); save(bad,'checkpoint'); verifyError(t,@() VIStudioFCSiamV25.loadWeights(bad),'VIStudioV25:FCSiamWeights');
checkpoint=original.checkpoint; checkpoint.Encoder.State.Value{2}=-ones(size(checkpoint.Encoder.State.Value{2}),'single'); bad=fullfile(t.TestData.Dir,'variance.mat'); save(bad,'checkpoint'); verifyError(t,@() VIStudioFCSiamV25.loadWeights(bad),'VIStudioV25:FCSiamWeights');
end
function testMetadataAndMissingWeightsRejected(t)
file=fullfile(t.TestData.Dir,'metadata-source.mat'); VIStudioFCSiamV25.saveWeights(t.TestData.Diff,file); s=load(file); checkpoint=s.checkpoint; checkpoint.Metadata.ClassNames=["changed","unchanged"]; bad=fullfile(t.TestData.Dir,'classes.mat'); save(bad,'checkpoint'); verifyError(t,@() VIStudioFCSiamV25.loadWeights(bad),'VIStudioV25:FCSiamArtifact');
checkpoint=s.checkpoint; checkpoint.Block=checkpoint.Block(1:3); bad=fullfile(t.TestData.Dir,'missing.mat'); save(bad,'checkpoint'); verifyError(t,@() VIStudioFCSiamV25.loadWeights(bad),'VIStudioV25:FCSiamWeights');
end
function testInputGuard(t)
verifyError(t,@() VIStudioFCSiamV25.predict(t.TestData.Diff,zeros(32,35,3),zeros(32,35,3)),'VIStudioV25:FCSiamSize'); verifyError(t,@() VIStudioFCSiamV25.create('fc-siam-diff',[15 32 3]),'VIStudioV25:FCSiamSize');
end
function testCPUGradientAndBatchNormState(t)
a=t.TestData.Diff; before=extractdata(a.Encoder.Learnables.Value{1}); stream=RandStream('mt19937ar','Seed',22); x=rand(stream,33,35,3,'single'); y=x; y(8:20,9:22,:)=.95; truth=false(33,35); truth(8:20,9:22)=true; [b,r]=VIStudioFCSiamV25.trainStep(a,x,y,truth); verifyTrue(t,isfinite(r.Loss)); verifyGreaterThan(t,r.EncoderGradientL1,0); verifyGreaterThan(t,max(abs(before-extractdata(b.Encoder.Learnables.Value{1})),[],'all'),0); verifyFalse(t,isequal(extractdata(a.Encoder.State.Value{1}),extractdata(b.Encoder.State.Value{1}))); verifyEqual(t,b.Metadata.WeightStatus,"USER_TRAINED_UNVALIDATED");
end
function testWorkspaceSelectionAndCheckpoint(t)
a=VIStudioChangeDetectionAppV25('off'); cleanup=onCleanup(@() delete(a)); a.loadReference(zeros(33,35,3)); a.loadCurrent(ones(33,35,3)); a.initializeModel('fc-siam-diff'); verifyEqual(t,string(a.Handles.Method.Value),"fc-siam-diff"); a.run(); verifyEqual(t,a.Data.State,"COMPLETE"); verifyTrue(t,contains(a.Data.Message,'RANDOM_INITIALIZATION')); file=fullfile(t.TestData.Dir,'ui-weights.mat'); VIStudioFCSiamV25.saveWeights(a.Data.Artifact,file); a.loadModel(file); verifyEqual(t,a.Data.State,"READY"); a.run(); verifyEqual(t,a.Data.State,"COMPLETE"); a.Handles.Method.Value='fc-siam-conc'; verifyError(t,@() a.run(),'VIStudioV25:ChangeModelVariant'); verifyEmpty(t,a.Data.Mask);
bad=fullfile(t.TestData.Dir,'unrelated.mat'); unrelated=1; save(bad,'unrelated'); verifyError(t,@() a.loadModel(bad),'VIStudioV25:ChangeModel'); verifyEmpty(t,a.Data.Artifact); verifyEmpty(t,a.Data.Score);
end
function testMissingModelFailsWithoutFallback(t)
a=VIStudioChangeDetectionV25; a.setReference(zeros(32,32,3)); a.setCurrent(ones(32,32,3)); o=a.Options; o.Method="fc-siam-diff"; a.configure(o); verifyError(t,@() a.run(),'VIStudioV25:ChangeModel'); verifyEmpty(t,a.Score);
end
