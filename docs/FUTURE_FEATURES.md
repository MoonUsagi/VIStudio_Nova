# 功能擴充分析與未來考量 / Feature Expansion Analysis

## 本次範圍 / Current scope

V25 新增 **影像變化偵測** 與 **原生雙影像研究模型**，延續分類、偵測、分割、關鍵點、標記品質、定位量測與影片擷取。下表分析在現有功能之上值得擴充的部分，並非已排定的交付時程。

V25 adds **Change Detection** and **native paired-image research networks**, building on the existing vision, annotation, metrology and video workflows. The proposals below are options, not committed delivery dates.

**範例庫：暫緩，保留為未來更新考量之一。沒有新增範例庫介面、素材下載或自動實作排程。** [既有優缺點評估](EXAMPLE_LIBRARY_ASSESSMENT.md) 保留供日後重新考慮。

**Example library: deferred and retained for future consideration.** No library browser, download service or automatic implementation schedule is added. The [assessment](EXAMPLE_LIBRARY_ASSESSMENT.md) remains available.

## 優先候選 / Prioritized candidates

| 優先 / Priority | 功能 / Feature | 使用價值 / Value | 主要成本與前提 / Cost and dependency | 建議驗收 / Suggested acceptance |
|---|---|---|---|---|
| P1 | 合成資料覆核→標記→訓練串接 / Reviewed synthetic-data adapters | 減少手動搬檔；把影像與遮罩送入既有標記及資料流程 / Reduce manual image-mask transfer | 需各任務格式轉換、類別對應、覆核門檻 / Task schemas, class mapping and review gates | 未覆核資料不自動成真值；正常背景與 ignore ID 不混淆 / Preserve review and class semantics |
| P1 | 來源群組切分 / Source-group-aware splits | 避免同一原圖合成變體、同一影片近似影格流入 train/test / Avoid related variants leaking across splits | 現有資料集設定需理解來源群組及時間段 / Dataset grouping and time-range metadata | 群組重疊為零；保存切分種子及清單 / No group overlap; reproducible manifests |
| P1 | 變化模型實際資料驗證 / Real-data validation of change models | 延續先前待辦，找出參考與當前影像的變化區域 / Detect changes against a reference | 先處理對齊、照明、有效區與正常變動 / Alignment, illumination and valid regions | 在獨立正常／缺陷資料驗證誤報與漏報 / Held-out false-positive/miss analysis |
| P1 | 拼接品質檢視 / Stitch-quality inspection | 顯示對應點、接縫差異、局部重影與累積偏移 / Inspect correspondences, seams and drift | 需區分實際內容變動與配準誤差 / Separate scene changes from alignment errors | 可定位失敗影像及區域，不只看全圖 / Localizable rejection evidence |
| P2 | 大圖與已知位置拼接 / Large-image and known-position mosaics | 支援掃描平台、顯微視野、超大工件 / Stage scans and large parts | 需分塊寫檔、記憶體預估、XY／像素尺寸資料 / Tiled output, memory budget, stage metadata | 有效區、座標往返與資源上限可驗證 / Round-trip coordinates and bounded memory |
| P2 | 多 ROI 與影片物件追蹤 / Multiple ROIs and video tracking | 跟隨移動物件擷取；一次輸出多區 / Extract moving objects or several regions | 需處理失追、遮擋、重入及跨區 ID / Lost tracks, occlusion and identity management | 失追不沿用錯誤框；來源與時間可追溯 / No silent stale boxes |
| P2 | 貼片前景遮罩與外觀融合 / Donor masks and appearance matching | 減少矩形貼片邊界，提高外觀多樣性 / Improve rectangular cut-paste appearance | 需前景遮罩、色彩匹配、接縫與真實資料檢查 / Foreground masks, appearance matching and review | 變更區遮罩吻合儲存影像；真實測試集不被合成資料取代 / Exact masks and independent real evaluation |
| P2 | 既有產品配方加入新節點 / Extend existing product recipes | 串接影片、拼接、檢測與定位量測 / Connect new data tools to existing pipelines | 需統一影像、遮罩、座標、校正與錯誤狀態契約 / Shared data/coordinate/error contracts | 前置失敗會阻擋後續錯誤判定 / Failure gating |
| P2 | 資料／模型／校正關聯圖 / Artifact lineage view | 知道哪個資料版本、模型、門檻與校正產生結果 / Trace dataset/model/calibration relationships | 延伸既有實驗與來源快照 / Extend current provenance and experiments | 搬移或版本不符可辨識與重新連結 / Relocation/version checks |
| P2 | 標準件與 R&R 記錄 / Reference artifacts and R&R records | 管理量測基準、重複量測與校正記錄 / Manage physical measurement evidence | 需要實體標準件、操作程序與實際採樣 / Physical artifacts and procedures required | 軟體統計不等於自動取得精度認證 / Report evidence without certifying precision |
| P3 | 即時相機與觸發採集 / Live acquisition and triggers | 從離線原型走向現場資料採集 / Bridge offline tools and production capture | 另評估硬體、採集支援、緩衝及丟幀 / Hardware, buffers and dropped-frame handling | 觸發對應、時序與掉線恢復 / Trigger/timing/recovery tests |
| P3 | 多人覆核與衝突合併 / Collaborative review and merge | 分工標記、追蹤修改與覆核差異 / Shared annotation workloads | 檔案鎖、身分、權限及衝突規則 / Locking, identity and merge rules | 不默默覆蓋他人標記 / No silent lost updates |
| 未來考量 / Deferred | 範例庫 / Example library | 教學、展示與共同除錯案例 / Tutorials and shared minimal cases | 容量、授權與每版維護 / Size, rights and maintenance | 使用者決定恢復規劃後再細化 / Refine only when resumed |

## 建議下一步 / Suggested next step

先實測變化偵測工作區，再優先選擇 **合成資料覆核／格式串接、來源群組切分、變化模型實際資料驗證**。這三項能把新增的資料生成能力接回既有檢測流程，也補上先前保留的變化偵測需求。

After trying the Change Detection workspace, prioritize **review/schema adapters, grouped splits and real-data model validation**. These connect the new data tools to inspection workflows and retain the previously deferred change-detection direction.

拼接若用於量測，應先建立輸出座標與校正策略；目前拼接圖是重取樣像素影像，不自動承接原圖 mm/px。缺陷合成先檢查多樣性與實際任務價值，不能以合成測試表現代表真實缺陷表現。

Before using stitched mosaics for metrology, define output coordinates and calibration. Current mosaics do not inherit original mm/px automatically. Evaluate synthetic diversity and usefulness on independent real defects.


V25 已加入差分／SSIM、配準、ROI、變化區域匯出及真值評估；研究模型可行性測試不等於實際資料驗收。

V25 implements baseline paired-image detection, registration, ROI, region export and truth evaluation. Research-network feasibility is separate from real-data acceptance. See [model research](CHANGE_MODELS_RESEARCH.md).
