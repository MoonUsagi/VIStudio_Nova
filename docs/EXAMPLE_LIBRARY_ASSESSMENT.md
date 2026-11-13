# 範例庫評估 / Example Library Assessment

**目前暫緩，列入未來更新考量之一。本版不建立範例庫，也不自動排入下一版實作。**

**Deferred and retained for future consideration. No example library is built or automatically scheduled for the next release.**

## 優點與成本 / Benefits and costs

| 面向 / Area | 好處 / Benefit | 代價或風險 / Cost or risk |
|---|---|---|
| 首次使用 / Onboarding | 按步驟重現完整流程，減少資料準備門檻 / Guided end-to-end workflows reduce initial data preparation | 每個範例需更新說明、設定及畫面 / Tutorials, settings and screenshots need maintenance |
| 除錯 / Troubleshooting | 使用共同的最小案例，容易區分環境與資料問題 / Shared minimal cases help isolate environment vs. data issues | 合成資料太簡單，不能代表產線難度 / Synthetic fixtures can underrepresent production complexity |
| 驗證 / Regression | 保存預期結果與容許範圍，更新 MATLAB 後可重測 / Expected outputs and tolerances support reproducible regression | API、授權、模型權重與隨機性會造成版本差異 / APIs, licenses, weights and randomness vary |
| 展示 / Demonstration | 快速比較標記、訓練、量測、影片流程 / Easy demonstrations of annotation, training, measurement and video workflows | 容易把示範成功誤讀為模型精度或量測能力保證 / Successful demos can be mistaken for accuracy guarantees |
| 發布 / Distribution | 離線小範例可降低網路與權重依賴 / Small offline cases reduce download dependencies | 真實影像、影片與大型模型增加容量、授權與隱私維護 / Real data and models add size, rights and privacy obligations |

## 建議先選的範例 / Suggested first examples

1. **樣板定位與多物件卡尺量測**：兩個方向不同的合成零件，包含一個尺寸超差與無匹配案例。 / Two synthetic orientations, an out-of-tolerance part and a no-match case.
2. **量測校正與失敗判讀**：px/mm、公差、找不到邊緣、NOT_MEASURED。 / Pixel/mm calibration, tolerance and missing-edge handling.
3. **影片 ROI 擷取**：程式產生短片，設定每隔 N 影格，核對來源影格、裁切尺寸與匯出清單。 / Generated short video with verifiable sampling indices and crop dimensions.
4. **實例／關鍵點標記與覆核**：少量自製圖案，示範接受候選、人工修正與格式交換。 / Original shapes for candidate review, correction and exchange.
5. **小型分類或分割訓練**：後續再加入，明確列出 Toolbox、權重下載及預計資源。 / A later tutorial with explicit toolbox, download and resource requirements.

以上是後續候選清單；現有 Demo 與測試合成資料不等於已經有範例庫。

This is a proposed backlog. Existing demos and test fixtures are not a finished example library.

## 建議結構 / Proposed structure

每個範例包含名稱、中英文簡介、適用版本、所需 Toolbox、是否需網路／GPU、原始資料來源與授權、執行步驟、預期結果、數值容許範圍與限制。資料在使用者選定的新資料夾產生，範例資料夾與正式專案分開，避免覆寫使用者工作。

Each example should record bilingual instructions, supported versions, toolbox/network/GPU requirements, data origin and license, steps, expected outputs, numerical tolerances and limitations. Generate working data in a user-selected new folder, separate from production projects.

對外下載項目再加上版本、大小、SHA-256、可取消下載及完整性驗證。第一階段不建議把大型權重或真實產線影片直接放進 Git 儲存庫。

External assets should additionally include version, size, SHA-256, cancellable downloads and integrity verification. Large weights and real production videos should not be part of the initial Git payload.

## 目前決策 / Current decision

依使用者決定，範例庫**暫緩**；以上優缺點與候選範例保留作為未來恢復規劃時的參考，不代表本次已實作或已排期。

The example library is **deferred**. The assessment and candidate examples remain for future reconsideration, not implementation or scheduling in this update.
