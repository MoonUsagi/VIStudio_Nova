function results=run_validation
root=fileparts(mfilename('fullpath')); addpath(fullfile(root,'src')); results=runtests(fullfile(root,'tests'));
folder=fullfile(root,'outputs','validation'); if ~isfolder(folder), mkdir(folder); end
save(fullfile(folder,'local-results.mat'),'results');
summary=struct('Tests',numel(results),'Passed',sum([results.Passed]),'Failed',sum([results.Failed]),'Incomplete',sum([results.Incomplete]),'MATLAB',version,'Scope',"Native measurement and UI/project regression; no large-model training or GPU validation");
fid=fopen(fullfile(folder,'summary.json'),'w'); close=onCleanup(@() fclose(fid)); fprintf(fid,'%s',jsonencode(summary)); assertSuccess(results);
end
