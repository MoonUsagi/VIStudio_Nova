classdef VIStudioGuideV19
    methods (Static)
        function fig=show(owner)
            if nargin<1, owner=[]; end; fig=VIStudioHelpV16_1.show(owner); fig.Name='VIStudio V19 | 操作說明 / User Guide'; h=getappdata(fig,'VIStudioHelpControls'); zh=string(h.Chinese.Value); en=string(h.English.Value);
            zh(end-1:end)=["獨立量測 / Measurement";"到工作區選擇「獨立量測」，或執行 VIStudioMeasurementAppV19。載入影像、設定校正、放置工具後按 Capture。可保存工作／配方、批次套用及匯出報告。變化偵測留待後續版本。"];
            en(end-1:end)=["Independent measurement";"Open Measurement in Workspaces, or run VIStudioMeasurementAppV19. Load an image, configure calibration, place a tool, and click Capture. Save sessions/recipes, process batches, or export reports. Change detection is planned for a later release."];
            zh=[zh;"樣板定位與多物件量測";"載入並擷取樣板後，開啟量測編輯器並記錄工具；回到匹配工作區按套用編輯器。搜尋時依每個物件的位置與角度搬移工具，再重新量測。匯出包含物件摘要、各工具結果及逐物件資料夾。配方必須來自完全相同的樣板；校正比例保持固定。";"影片 ROI 擷取";"第二頁開啟影片 ROI 工作區。匯入影片、選定固定 ROI，設定每隔 N 影格或每秒 N 張及起訖範圍，再擷取到新資料夾。停止時保留部分輸出並標記 CANCELLED。"];
            en=[en;"Pose-aware multi-object measurement";"Crop the template, open the measurement editor, capture tools and click Use editor in Shape Matching. Each match transforms tool geometry and remeasures the search image. Export includes summaries, tool results and per-object folders. Recipes must belong to the exact template; camera calibration remains fixed.";"Video ROI extraction";"On workspace page two, load a video, select a fixed ROI and configure every N frames or images per second, plus frame bounds. Extract to a new folder. Stop preserves partial outputs with CANCELLED status."];
            h.Chinese.Value=zh; h.English.Value=en; VIStudioThemeV19.normalizeVersions(fig);
        end
    end
end
