classdef VIStudioGuideV24
    methods (Static)
        function fig=show(owner)
            if nargin<1, owner=[]; end; fig=VIStudioHelpV16_1.show(owner); fig.Name='VIStudio V24 | 操作說明 / User Guide'; h=getappdata(fig,'VIStudioHelpControls'); zh=string(h.Chinese.Value); en=string(h.English.Value);
            zh(end-1:end)=["獨立量測 / Measurement";"到工作區選擇「獨立量測」，或執行 VIStudioMeasurementAppV24。載入影像、設定校正、放置工具後按 Capture。可保存工作／配方、批次套用及匯出報告。變化偵測留待後續版本。"];
            en(end-1:end)=["Independent measurement";"Open Measurement in Workspaces, or run VIStudioMeasurementAppV24. Load an image, configure calibration, place a tool, and click Capture. Save sessions/recipes, process batches, or export reports. Change detection is planned for a later release."];
            zh=[zh;"樣板定位與多物件量測";"載入並擷取樣板後，開啟量測編輯器並記錄工具；回到匹配工作區按套用編輯器。搜尋時依每個物件的位置與角度搬移工具，再重新量測。匯出包含物件摘要、各工具結果及逐物件資料夾。配方必須來自完全相同的樣板；校正比例保持固定。";"影片 ROI 擷取";"第三頁開啟影片 ROI 工作區。匯入影片、選定固定 ROI，設定每隔 N 影格或每秒 N 張及起訖範圍，再擷取到新資料夾。停止時保留部分輸出並標記 CANCELLED。"];
            en=[en;"Pose-aware multi-object measurement";"Crop the template, open the measurement editor, capture tools and click Use editor in Shape Matching. Each match transforms tool geometry and remeasures the search image. Export includes summaries, tool results and per-object folders. Recipes must belong to the exact template; camera calibration remains fixed.";"Video ROI extraction";"On workspace page three, load a video, select a fixed ROI and configure every N frames or images per second, plus frame bounds. Extract to a new folder. Stop preserves partial outputs with CANCELLED status."];
            zh=[zh;"影像拼接與缺陷合成";"第三頁提供影像拼接與缺陷合成。拼接需依相鄰重疊順序載入；配準品質不足會拒絕輸出。缺陷合成提供刮痕、斑點、污漬與貼片，可限制 ROI 並匯出遮罩與種子。合成資料需覆核。範例庫暫緩，列入未來更新考量。"];
            en=[en;"Image stitching and defect synthesis";"Page three provides image stitching and defect synthesis. Stitching requires adjacent overlapping views and rejects poor registration. Synthesis supports scratches, spots, stains and donor patches, with ROI masks and seed provenance. Synthetic samples need review. The example library is deferred and retained for future consideration."];
            zh=replace(zh,"變化偵測留待後續版本。","變化偵測已在第三頁提供。"); en=replace(en,"Change detection is planned for a later release.","Change Detection is available on page three.");
            zh=[zh;"影像變化偵測";"第三頁載入參考與待測影像，選擇配準、ROI、差分或 SSIM，調整門檻與最小區域。真值遮罩採參考座標，可計算 IoU／Dice；匯出變化區域與 PNG／CSV／MAT。研究模型僅為實驗原型，需獨立實際資料驗證。"];
            en=[en;"Change Detection";"On page three, load reference/current images, choose alignment, ROI and difference/SSIM, then tune threshold and area. Reference-space truth enables IoU/Dice. Export regions and PNG/CSV/MAT evidence. Research models are experimental and require independent real-data validation."];
            h.Chinese.Value=zh; h.English.Value=en; VIStudioThemeV24.normalizeVersions(fig);
        end
    end
end
