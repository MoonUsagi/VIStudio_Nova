function results=run_validation
root=fileparts(mfilename('fullpath'));
if isfolder(fullfile(root,'src'))
    addpath(fullfile(root,'src')); results=runtests(fullfile(root,'tests'));
else
    addpath(root); names={'testMeasurementV20.m','testProjectHubV20.m','testShapeMatchingV20.m','testStructuredV20Regression.m','testWorkspacePagingV20.m','testPoseMeasurementV20.m','testVideoExtractV20.m','testStitchV20.m','testDefectSynthesisV20.m'};
    paths=cellfun(@(name) fullfile(root,'tests',name),names,'UniformOutput',false); results=runtests(paths);
end
folder=fullfile(root,'outputs','validation'); if ~isfolder(folder), mkdir(folder); end
save(fullfile(folder,'local-results.mat'),'results');
summary=struct('Tests',numel(results),'Passed',sum([results.Passed]),'Failed',sum([results.Failed]),'Incomplete',sum([results.Incomplete]),'MATLAB',version,'Scope',"Native image stitching, procedural defect synthesis, multi-object pose measurements, video ROI extraction, shape matching, measurement and V20 UI/project/annotation regression; no large-model training or GPU validation");
fid=fopen(fullfile(folder,'summary.json'),'w'); close=onCleanup(@() fclose(fid)); fprintf(fid,'%s',jsonencode(summary)); assertSuccess(results);
end
