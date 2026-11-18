classdef VIStudioThemeV23
    methods (Static)
        function p=palette()
            p=struct('Navy',[14 24 43]/255,'Teal',[16 99 112]/255,'Mint',[66 214 202]/255,'Canvas',[.95 .96 .98],'Text',[.12 .19 .29],'Muted',[.40 .46 .53]);
        end
        function file=logo()
            file=fullfile(fileparts(mfilename('fullpath')),'VIStudio_Brand_V1','vistudio-logo-navy-v1.png');
        end
        function h=install(fig,title)
            if isappdata(fig,'VIStudioThemeV23'), h=getappdata(fig,'VIStudioThemeV23'); return; end
            p=VIStudioThemeV23.palette(); existing=fig.Children; shell=uigridlayout(fig,[3 1],'RowHeight',{54,44,'1x'},'Padding',[8 6 8 6],'RowSpacing',6,'BackgroundColor',p.Canvas);
            brand=uigridlayout(shell,[1 4],'ColumnWidth',{160,'1x',170,160},'Padding',[10 0 10 0],'BackgroundColor',p.Navy);
            uiimage(brand,'ImageSource',VIStudioThemeV23.logo(),'ScaleMethod','fit'); h.Title=uilabel(brand,'Text',"V23  /  "+VIStudioHomeV23.taskTitle(title),'FontColor',[1 1 1],'FontWeight','bold','FontSize',15);
            h.Home=uibutton(brand,'Text','專案首頁 / Home','ButtonPushedFcn',@(~,~) VIStudioV23); h.Sync=uibutton(brand,'Text','同步至專案 / Sync','Enable','off','Tooltip','從專案首頁開啟工作區後可使用 / Open through a project to enable');
            h.Guide=uilabel(shell,'Text','載入資料 → 標記與覆核 → 訓練 → 保留集評估 → 檢測 / Data → Review → Train → Evaluate → Inspect','WordWrap','on','FontSize',11,'FontColor',p.Muted); content=uipanel(shell,'BorderType','none','BackgroundColor',p.Canvas); g=uigridlayout(content,[1 1],'Padding',[0 0 0 0]);
            for object=reshape(existing,1,[]), object.Parent=g; end
            h.Shell=shell; h.Content=content; h.Brand=brand; setappdata(fig,'VIStudioThemeV23',h); VIStudioThemeV23.apply(content); VIStudioThemeV23.apply(brand); VIStudioThemeV23.normalizeVersions(fig); fig.Color=p.Canvas;
        end
        function normalizeVersions(root)
            % UI labels only. Never change model metadata, schemas or filenames.
            for object=reshape(findall(root),1,[])
                for field={'Text','Name','Title'}
                    key=field{1};
                    if isprop(object,key) && (ischar(object.(key)) || isstring(object.(key)))
                        object.(key)=regexprep(object.(key),'\<V(?:[3-9]|1[0-9]|20|21|22)(?:\.1)?\>','V23');
                    end
                end
            end
        end
        function apply(root)
            p=VIStudioThemeV23.palette(); objects=findall(root);
            for object=reshape(objects,1,[])
                if isprop(object,'FontName'), object.FontName='Microsoft JhengHei'; end
                if isa(object,'matlab.ui.control.Button')
                    % Preserve explicitly colored review/stop controls.
                    color=object.BackgroundColor;
                    if max(color)-min(color)<.08 && mean(color)>.65, object.BackgroundColor=p.Teal; object.FontColor=[1 1 1]; end
                    object.FontSize=11;
                elseif isa(object,'matlab.ui.control.Table')
                    object.FontSize=11; object.RowName={};
                end
            end
        end
    end
end
