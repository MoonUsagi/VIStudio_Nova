classdef VIStudioGuideV18
    methods (Static)
        function fig=show(owner)
            if nargin<1, owner=[]; end; fig=VIStudioHelpV16_1.show(owner); fig.Name='VIStudio V18 | 操作說明 / User Guide'; h=getappdata(fig,'VIStudioHelpControls'); zh=string(h.Chinese.Value); en=string(h.English.Value);
            zh(end-1:end)=["獨立量測 / Measurement";"到工作區選擇「獨立量測」，或執行 VIStudioMeasurementAppV18。載入影像、設定校正、放置工具後按 Capture。可保存工作／配方、批次套用及匯出報告。變化偵測留待後續版本。"];
            en(end-1:end)=["Independent measurement";"Open Measurement in Workspaces, or run VIStudioMeasurementAppV18. Load an image, configure calibration, place a tool, and click Capture. Save sessions/recipes, process batches, or export reports. Change detection is planned for a later release."];
            zh=[zh;"工作區分頁與樣板匹配";"工作區每頁最多六項，用上一頁／下一頁切換。第二頁的樣板／形狀匹配可載入或擷取樣板，設定旋轉與尺度範圍，再搜尋影像並匯出結果。定位為像素座標；本版不會自動移動量測配方。"];
            en=[en;"Workspace pages and shape matching";"Workspaces show up to six cards per page. Use Previous/Next to navigate. On page two, Shape Matching can load/crop a template, configure rotation and scale, search an image and export results. Coordinates are pixels; measurement recipes are not automatically repositioned."];
            h.Chinese.Value=zh; h.English.Value=en; VIStudioThemeV18.normalizeVersions(fig);
        end
    end
end
