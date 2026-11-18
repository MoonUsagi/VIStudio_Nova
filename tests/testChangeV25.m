function tests=testChangeV25
tests=functiontests(localfunctions);
end
function a=fixture
a=VIStudioChangeDetectionV25; [r,c,g]=a.demo(); a.setReference(r); a.setCurrent(c); a.setTruth(g);
end
function testKnownChange(t)
a=fixture; a.run(); verifyEqual(t,a.Evaluation.IoU,1); verifyEqual(t,a.Evaluation.Dice,1); verifyEqual(t,height(a.Regions),1);
end
function testEmptyTruthIsUndefined(t)
a=fixture; a.setCurrent(a.Reference); a.setTruth(false(size(a.Reference,[1 2]))); a.run(); verifyFalse(t,any(a.Mask,'all')); verifyTrue(t,isnan(a.Evaluation.IoU));
end
function testSSIM(t)
a=fixture; o=a.Options; o.Method="ssim"; a.configure(o); a.run(); verifySize(t,a.Score,[240 320]); verifyTrue(t,any(a.Mask,'all'));
end
function testROI(t)
a=fixture; roi=false(240,320); roi(20:70,20:70)=true; a.setAllowed(roi); a.run(); verifyFalse(t,any(a.Mask,'all')); verifyEqual(t,nnz(a.Valid),nnz(roi));
end
function testMinimumArea(t)
a=fixture; o=a.Options; o.MinArea=2000; a.configure(o); a.run(); verifyFalse(t,any(a.Mask,'all'));
end
function testBrightnessCorrection(t)
a=fixture; a.setCurrent(a.Reference+.1); a.run(); verifyFalse(t,any(a.Mask,'all')); o=a.Options; o.Threshold=.05; o.BrightnessOffset=true; a.configure(o); a.run(); verifyFalse(t,any(a.Mask,'all')); verifyEqual(t,a.Registration.BrightnessOffset,[.1 .1 .1],'AbsTol',1e-6);
end
function testSizeMismatch(t)
a=fixture; a.setCurrent(zeros(30,40,3,'single')); verifyError(t,@() a.run(),'VIStudioV25:ChangeSize'); verifyEqual(t,a.State,"ERROR"); verifyEmpty(t,a.Mask);
end
function testRegistration(t)
a=fixture; a.setCurrent(imtranslate(a.Reference,[7 4])); o=a.Options; o.Alignment="translation"; a.configure(o); before=rng; a.run(); verifyEqual(t,rng,before); verifyLessThan(t,a.Registration.RMSEpx,1); verifyLessThan(t,nnz(a.Mask),30);
end
function testUniformRegistrationRejected(t)
a=VIStudioChangeDetectionV25; a.setReference(zeros(80,80)); a.setCurrent(zeros(80,80)); o=a.Options; o.Alignment="translation"; a.configure(o); verifyError(t,@() a.run(),'VIStudioV25:ChangeFeatures');
end
function testInvalidation(t)
a=fixture; a.run(); o=a.Options; o.Threshold=.2; a.configure(o); verifyEmpty(t,a.Mask); verifyEqual(t,a.State,"READY");
end
function testExport(t)
a=fixture; a.run(); parent=tempname; mkdir(parent); cleanup=onCleanup(@() rmdir(parent,'s')); folder=a.export(parent); verifyEqual(t,imread(fullfile(folder,'change-mask.png'))>0,a.Mask); saved=load(fullfile(folder,'change-report.mat')); verifyEqual(t,saved.report.Evaluation.IoU,1); verifyTrue(t,isfile(fullfile(folder,'regions.csv')));
end
function testUI(t)
a=VIStudioChangeDetectionAppV25('off'); cleanup=onCleanup(@() delete(a)); a.demo(); verifyEqual(t,a.Data.State,"COMPLETE"); verifyTrue(t,contains(a.UIFigure.Name,'V25'));
end
