function tests=testWorkspacePagingV25
tests=functiontests(localfunctions);
end
function setupOnce(t)
addpath(fileparts(fileparts(mfilename('fullpath')))); t.TestData.Old=getenv('VISTUDIO_V16_USER_DIR'); t.TestData.Dir=tempname; setenv('VISTUDIO_V16_USER_DIR',t.TestData.Dir);
end
function teardownOnce(t)
setenv('VISTUDIO_V16_USER_DIR',t.TestData.Old); if isfolder(t.TestData.Dir), assert(startsWith(string(t.TestData.Dir),string(tempdir))); rmdir(t.TestData.Dir,'s'); end
end
function testAllWorkspacesReachableAcrossPages(t)
a=VIStudioHomeV25('','off'); cleanup=onCleanup(@() delete(a)); verifyEqual(t,numel(a.Handles.WorkspaceCards),14); verifyEqual(t,numel(a.Handles.WorkspacePages),3);
verifyEqual(t,char(a.Handles.WorkspacePrevious.Enable),'off'); verifyEqual(t,char(a.Handles.WorkspaceNext.Enable),'on');
a.setWorkspacePage(2); verifyEqual(t,a.WorkspacePage,2); verifyEqual(t,char(a.Handles.WorkspacePages(1).Visible),'off'); verifyEqual(t,char(a.Handles.WorkspacePages(2).Visible),'on');
verifyEqual(t,char(a.Handles.WorkspaceNext.Enable),'on'); a.setWorkspacePage(3); verifyEqual(t,char(a.Handles.WorkspaceNext.Enable),'off'); verifyEqual(t,char(a.Handles.WorkspacePrevious.Enable),'on'); a.setWorkspacePage(1); verifyEqual(t,a.WorkspacePage,1);
verifyError(t,@() a.openTask('not-a-task'),'MATLAB:unrecognizedStringChoice');
previous=a.Handles.WorkspacePrevious.ButtonPushedFcn; previous([],[]); previous([],[]); verifyEqual(t,a.WorkspacePage,1);
a.setWorkspacePage(3); next=a.Handles.WorkspaceNext.ButtonPushedFcn; next([],[]); next([],[]); verifyEqual(t,a.WorkspacePage,3); a.setWorkspacePage(1);
end
function testIndependentShapeAndMeasurementRouting(t)
a=VIStudioHomeV25('','off'); cleanup=onCleanup(@() delete(a)); b=a.openTask('shape'); c=onCleanup(@() delete(b)); verifyClass(t,b,'VIStudioShapeMatchingAppV25'); verifyEmpty(t,a.Project);
m=a.openTask('measurement'); d=onCleanup(@() delete(m)); verifyClass(t,m,'VIStudioMeasurementAppV25'); verifyTrue(t,contains(m.UIFigure.Name,'V25'));
end
