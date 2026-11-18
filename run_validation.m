function results=run_validation
root=fileparts(mfilename('fullpath'));
if isfolder(fullfile(root,'src'))
    addpath(fullfile(root,'src')); results=runtests(fullfile(root,'tests'));
else
    addpath(root); names={'testMeasurementV25.m','testProjectHubV25.m','testShapeMatchingV25.m','testStructuredV25Regression.m','testWorkspacePagingV25.m','testPoseMeasurementV25.m','testVideoExtractV25.m','testStitchV25.m','testDefectSynthesisV25.m','testChangeV25.m','testChangeModelsV25.m','testFCSiamV25.m','testPretrainedFCSiamV25.m','testBITV25.m','testChangeFormerV25.m'};
    paths=cellfun(@(name) fullfile(root,'tests',name),names,'UniformOutput',false); results=runtests(paths);
end
folder=fullfile(root,'outputs','validation'); if ~isfolder(folder), mkdir(folder); end
save(fullfile(folder,'local-results.mat'),'results');
summary=struct('Tests',numel(results),'Passed',sum([results.Passed]),'Failed',sum([results.Failed]),'Incomplete',sum([results.Incomplete]),'MATLAB',version,'Scope',"Native Open-CD ChangeFormer variant and BIT architecture/pretrained parity and pretrained FC-Siam conversion/parity and architecture/weights/inference, image stitching, procedural defect synthesis, multi-object pose measurements, video ROI extraction, shape matching, measurement and V25 UI/project/annotation regression; no large-model training or GPU validation");
fid=fopen(fullfile(folder,'summary.json'),'w'); close=onCleanup(@() fclose(fid)); fprintf(fid,'%s',jsonencode(summary)); assertSuccess(results);
end
