# Change Detection 模型可行性研究 / Model feasibility

## V25 目前結果 / Current Open-CD MiT-B0 variant

**Open-CD 發布為 ChangeFormer 的 MiT-B0 已原生整合。** 上游明示這是 Siamese SegFormer 變體，不是原作者 V6 或嚴格重製；本版依公開模型卡的 Apache-2.0 標示整理權重、授權及來源雜湊。四階段特徵與雙類別機率在五組原創合成配對中通過比對，0.5 遮罩一致。推論不需 Python，訓練 API、GPU 與工業準確率仍未實作／驗證。

V25 integrates the **Open-CD model published as ChangeFormer MiT-B0**, explicitly identified upstream as a Siamese SegFormer variant rather than original V6/strict reproduction. Publisher-declared Apache-2.0 native weights, source hashes and notices are bundled. Five synthetic reference cases check four-stage features and probabilities, with matching threshold masks. Runtime is native MATLAB; training/GPU/industrial accuracy remain unestablished. See [variant guide](CHANGEFORMER_NATIVE.md).

BIT 的一張標準照可以重複比對待測照；第二張標準照需手動切換，並不構成正常外觀學習或準確率驗證。詳見 [reference-pair guide](REFERENCE_PAIR_GUIDE.md)。範例庫維持暫緩；以下舊版研究段落作歷史參考。

## V24 目前結果 / Current native BIT result

**Open-CD 改良版 BIT-R18 已整合**：MATLAB 原生共享 ResNetV1c、語意 token、encoder 與 decoder，附發布者模型卡標示 Apache-2.0 的 LEVIR-CD 預訓練原生 MAT。五組合成配對的 backbone／機率比對通過，0.5 遮罩一致；推論不需 Python。原作者 BIT 專案的程式與 checkpoint 未附帶，兩個來源的授權分開記錄。

V24 integrates the **Open-CD improved BIT-R18 variant** as native MATLAB inference, with publisher-declared Apache-2.0 pretrained MAT weights. Five synthetic reference comparisons pass for backbone/probabilities and threshold masks, without Python at runtime. The original BIT author's implementation/checkpoint is not bundled. See [BIT architecture, evidence and licensing](BIT_NATIVE.md).

BIT 訓練 API、GPU、compiled standalone 與工業瑕疵準確率尚未實作／驗證。ChangeFormer 尚未整合；範例庫維持暫緩。以下 V23 與更早段落保留歷史研究狀態，以本節為最新結果。

BIT training, GPU, compiled standalone and industrial accuracy are unimplemented/unvalidated. ChangeFormer remains unintegrated and the example library remains deferred. Older sections below are historical context, superseded by this section for BIT integration status.

## V23 目前結果 / Current pretrained result

已找到 [Open-CD 官方模型庫](https://huggingface.co/likyoo/Open-CD_Model_Zoo) 的 FC-Siam-diff／conc 公開權重；發布者模型卡標示 Apache-2.0。本版已完成原生 MAT 轉換，附授權與雜湊，兩種模型各五組合成配對的 CPU 機率比對通過；沒有重新訓練。載入、RGB 正規化、32 倍數補邊、推論與裁回原尺寸均由 MATLAB 完成，不需 Python。

V23 converts and bundles the publisher's Apache-2.0-declared Open-CD FC-Siam-diff/conc weights. Both variants pass CPU probability comparisons on five synthetic pairs each. No retraining occurred; runtime loading, normalization, padding, inference and cropping are native MATLAB. See the [pretrained guide](FC_SIAM_PRETRAINED.md) and [parity evidence](../validation/fc-siam-pretrained-parity.json).

BIT、ChangeFormer 仍未整合；工業缺陷準確率、GPU 與 compiled standalone 尚未驗證。範例庫維持暫緩。

BIT/ChangeFormer remain unintegrated. Industrial accuracy, GPU and compiled standalone deployment are unvalidated. The example library remains deferred.

## 歷史評估：V22 與之前 / Archived earlier assessment

以下保留當時的研究狀態；「尚未載入官方權重」等描述已由上述 V23 結果更新，不代表本版仍缺少預訓練推論。

The following is historical research context. Statements about missing pretrained integration are superseded by the V23 result above.

### V22 更新 / Native FC-Siam update

V22 已新增完整 MATLAB 原生 **FC-Siam-diff／FC-Siam-conc**，包含四層共享編碼器、完整解碼器、奇數尺寸對齊、原生 MAT 權重載入、CPU 推論與單步訓練測試。沒有 Python 推論依賴。以下最初研究內容中的「官方模型未執行」仍然成立：本次實作的是獨立 MATLAB 架構，未載入官方預訓練權重，也沒有跨框架數值等價性證據。

V22 adds full native **FC-Siam-diff/conc**, native MAT weight loading, CPU inference and training-step checks. The earlier statement that official external models were not executed remains accurate: this is an independent MATLAB architecture, without official pretrained weights or cross-framework numerical parity evidence. See the [native architecture and checkpoint guide](FC_SIAM_NATIVE.md). BIT/ChangeFormer remain research-only.

原生權重 round trip 測試包含編碼器、解碼器與 BN state，並確認修改輸出頭參數會改變推論結果。新建模型仍為隨機初始化，測試通過不等於具有真實檢出能力。範例庫維持暫緩。

Native checkpoint checks include encoder/decoder/BN state and confirm that changed head weights affect inference. Newly created models remain randomly initialized. Passing tests does not establish real detection accuracy. The example library remains deferred.

研究日期：2026-11-13。結論：可以先以 MATLAB 原生雙影像 CNN 建立可訓練原型；要導入公開預訓練模型，仍需獨立處理雙輸入契約、算子、權重、授權與工業資料落差。

Research date: 2026-11-13. Native paired CNN prototypes are feasible. Public pretrained-model integration still requires operator/input-contract checks, weights, licensing and industrial-domain validation.

| 方法 / Method | 本次狀態 / Status | 下一步 / Next step |
|---|---|---|
| Abs difference / SSIM | MATLAB 本機執行、合成遮罩及 UI 測試 / Locally executed baseline | 實際正常／異常成對資料的誤報與漏報 / Held-out normal and changed pairs |
| Tiny Early Fusion | 自製 6 通道輸入 CNN；CPU forward、backprop、Adam 與 loss 檢查 / Original six-channel CNN, CPU training checks | 真實資料、模型容量與門檻校準 / Real data and calibration |
| Tiny Shared Siamese absdiff | 自製共享編碼器，特徵差接分割頭；CPU 訓練、對稱性、MAT 載入推論測試 / Original shared encoder and difference head | 難例及不同光照、尺度資料 / Hard pairs and illumination/scale variation |
| FC-EF / FC-Siam-diff / FC-Siam-conc | 已查閱作者程式與論文；未執行官方模型、未下載權重 / Source/paper reviewed, official models not run | 優先候選：完整編解碼器重製及等價性驗證 / Full encoder-decoder implementation and parity |
| BIT | 官方 PyTorch Transformer 研究；未整合、未執行 / Research only | 權重、依賴、授權與工業資料評估 / Weights, dependencies and domain checks |
| ChangeFormer | 官方 Siamese Transformer 研究；未整合、未執行 / Research only | 同上，需確認授權文字衝突 / Resolve licensing signals |
| Open-CD | 模型研究平台；未安裝完整環境 / Framework reviewed, full stack not installed | 獨立 Python 環境及每個模型的契約 / Isolated environment and per-model contracts |

兩個 tiny 網路是原創可行性架構，**不是論文 FC-Siam／Transformer 的完整重製**。固定種子、64×64 RGB、四組自製合成訓練對，4 個 Adam steps 檢查 loss 有限且下降；這不是 held-out 評估，不可用來宣稱真實檢出率。未附模型權重，未做 GPU、預訓練模型或 ONNX 匯入驗證。

The two tiny networks are original feasibility architectures, not paper reproductions. Checks use seeded 64×64 RGB synthetic training pairs and four Adam steps, testing finite/decreasing training loss. These are not held-out accuracy measurements. No weights are bundled; GPU, pretrained inference and ONNX import are untested.

本機另確認 PyTorch `2.5.1+cpu` 能 import 與執行基本 tensor 運算，CUDA unavailable。`onnxruntime` 可找到，`onnx`、`mmcv`、`mmseg` 未找到。這只代表部分環境存在，不代表公開模型可直接執行。

PyTorch `2.5.1+cpu` imported and executed a basic tensor operation; CUDA was unavailable. Module discovery found `onnxruntime`, but not `onnx`, `mmcv` or `mmseg`. This does not establish model execution compatibility.

## 重現原生研究測試 / Reproduce native research

```matlab
addpath('src'); % source release
[artifact, report] = VIStudioChangeModelsV21.trainSynthetic('early-fusion', 4);
disp(report)
% Save only if wanted; not an inspection-ready detector.
save('my_change_research.mat','artifact');
% Also supported: 'siamese-absdiff'
```

工作區的 Model MAT 載入 `artifact`，驗證版本、架構、RGB 前處理與固定輸入尺寸。固定尺寸不同會拒絕執行，不做隱式縮放。原型訓練目前走程式 API；沒有成對資料訓練管理 GUI。雙圖必須同時做幾何擴充，標籤也要同步；切分應以產品／來源／時間群組分離，避免近似影像流入 train/test。

Model MAT loads `artifact` with a versioned architecture/preprocessing/shape contract. Mismatched dimensions are rejected. Training is a code API, without a paired-dataset training-management GUI. Pair augmentation must preserve alignment and transform labels consistently; split by source/product/time to avoid leakage.

## 官方來源與授權觀察 / Primary sources and licensing observations

- [FC convolutional change detection author repository](https://github.com/rcdaudt/fully_convolutional_change_detection) and [paper](https://arxiv.org/abs/1810.08462): FC-EF and Siamese paired-image segmentation. Redistribution permission was not established in this review; code/weights are not included.
- [BIT official repository](https://github.com/justchenhao/BIT_CD): README limits use to research/noncommercial purposes and requests author contact for commercial use. 未將其程式或權重放入發布包。
- [ChangeFormer official repository](https://github.com/wgcban/ChangeFormer): README states research/noncommercial use while the repository also exposes an MIT license label. Clarify applicable terms with authors before commercial redistribution; this release includes neither code nor weights.
- [Open-CD official repository](https://github.com/likyoo/open-cd): framework uses Apache-2.0 and includes implementations drawn from other repositories. The umbrella license does not by itself settle every checkpoint, dataset or upstream implementation's terms.

優先建議：先收集相同視野正常／變化配對與真值，再擴充原生 Siamese 的編解碼器與資料讀取，建立 held-out IoU／Dice、每圖誤報與不同亮度測試。確認需求後再選 FC-Siam 完整重製或隔離 Python 模型後端。範例庫維持暫緩。

Recommended order: collect aligned real pairs and truth, extend the native Siamese decoder/data pipeline, then measure held-out IoU/Dice and per-image false positives under illumination changes. Evaluate a full FC-Siam reproduction or isolated Python backend afterward. The example library remains deferred.
