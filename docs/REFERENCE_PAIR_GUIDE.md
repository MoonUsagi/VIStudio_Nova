# BIT／變化偵測的標準照用法 / Reference-pair workflow

**可以固定一張標準照，逐張比較其他待測照片。** 單次輸入是「一張參考影像＋一張待測影像」，不是先交給 BIT 一兩張正常照片來學習正常外觀。載入公開預訓練權重後，標準照只是當次比對的輸入，不會更新模型參數。

**You can keep one standard reference and compare test photos one at a time.** Each inference takes one reference and one current image. Supplying one or two normal photos does not teach BIT a normal appearance model; reference loading does not update weights.

| 用途 / Purpose | 現在可做 / Current behavior | 所需資料 / Required data |
|---|---|---|
| 影像比對 / Pair inspection | 固定 Reference，反覆載入 Compare 後 Detect / Keep Reference, load each Compare and Detect | 同視野、相近拍攝條件的標準與待測照 / Matched field of view and imaging conditions |
| 兩種視角／產品 / Two views or products | 手動切換對應標準照 / Manually switch the matching reference | 每個視角／產品各自對應的標準照 / A matching reference per view/product |
| 誤報與漏報評估 / Accuracy assessment | 載入參考座標的真值遮罩，計算 IoU／Dice 等 / Load reference-space truth for metrics | 獨立正常與缺陷配對、人工覆核及真值 / Independent normal/changed pairs and reviewed truth |
| 從正常影像學習 / Learning normality | 不會因載入標準照自動訓練 / No automatic training from reference loading | 另行設計正常模型／資料訓練流程 / A separately designed training/normality workflow |

## 建議操作 / Practical steps

1. 固定相機、距離、視角與照明，先取得可信的正常標準照。Keep camera/geometry/lighting stable and capture a reviewed normal reference.
2. 開啟影像變化偵測，載入參考照，再載入第一張待測照。Load Reference and the first Compare image.
3. 選 BIT-R18／其他已整合模型，按 Pretrained。依需要設定配準與 ROI，再執行。Select the model, load pretrained weights and configure registration/ROI if needed.
4. 保留參考照，換下一張 Compare 再 Detect。Keep the reference and repeat with another comparison.
5. 複核變化區域。需要比較效果時，先準備人工真值；未載入真值時，只有候選結果，沒有可信的準確率。Review candidates. Ground truth is required for a meaningful accuracy assessment.

目前一次只使用一張標準照，不會自動融合多張標準、挑選最佳標準、批次逐張比對或建立標準照資料庫。第二張標準照可手動切換。這些限制不影響逐組比對，但一兩張正常照通常不足以涵蓋所有正常光照、位置、材質與產品變異。

The current workspace uses one reference at a time. It does not automatically fuse references, choose the best reference, batch comparison pairs or build a reference database. Switch a second standard manually. One or two normal examples usually do not cover every normal variation in lighting, pose, material and product appearance.

**變化不一定是瑕疵。** 光照、反光、位移、遮擋與配準誤差都可能產生候選；相反地，遙測預訓練模型也可能忽略工業微小瑕疵。沒有看到變化不能直接當作 OK。原生推論和權重轉換測試通過，不代表取得工業檢出率保證。

**Change does not automatically mean defect.** Lighting, reflections, movement, occlusion and registration error can create candidates; remote-sensing pretrained weights may also miss small industrial defects. An empty mask does not establish acceptance. Numerical parity does not establish industrial accuracy.

適合把本版先當作成對影像變化檢查工具，再用實際正常／缺陷樣本確認是否符合需求。若目標是只提供少量正常照就建立可泛化的異常模型，那是另一種少樣本／異常偵測流程，並非目前 BIT 參考照載入功能。

Use this release as a paired-image change inspection tool and validate it on actual normal/defect samples. Learning a generalizable anomaly model from a few normal images is a separate few-shot/anomaly workflow, rather than BIT reference loading.

[BIT guide](BIT_NATIVE.md) · [Change Detection](CHANGE_DETECTION.md) · [Validation](VALIDATION.md)
