classdef VIStudioGuideV17
    methods (Static)
        function fig=show(owner)
            if nargin<1, owner=[]; end; fig=VIStudioHelpV16_1.show(owner); fig.Name='VIStudio V17 | 操作說明 / User Guide'; h=getappdata(fig,'VIStudioHelpControls'); zh=string(h.Chinese.Value); en=string(h.English.Value);
            zh(end-1:end)=["獨立量測 / Measurement";"到工作區選擇「獨立量測」，或執行 VIStudioMeasurementAppV17。載入影像、設定校正、放置工具後按 Capture。可保存工作／配方、批次套用及匯出報告。變化偵測留待後續版本。"];
            en(end-1:end)=["Independent measurement";"Open Measurement in Workspaces, or run VIStudioMeasurementAppV17. Load an image, configure calibration, place a tool, and click Capture. Save sessions/recipes, process batches, or export reports. Change detection is planned for a later release."];
            h.Chinese.Value=zh; h.English.Value=en; labels=findall(fig,'-isa','matlab.ui.control.Label'); for k=1:numel(labels), labels(k).Text=strrep(labels(k).Text,'V16.1','V17'); end
        end
    end
end
