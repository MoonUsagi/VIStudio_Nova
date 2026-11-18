# Validation / 驗證範圍

V25 uses fifteen native MATLAB suites: 152 existing regressions plus 10 Open-CD ChangeFormer-variant checks, for **162 unique checks**. See the machine-readable [summary](../validation/summary.json) and [per-test results](../validation/test-results.json) for actual outcomes.

V25 包含既有 152 項回歸檢查，以及新增 10 項 Open-CD ChangeFormer 變體檢查，共 162 項。實際通過狀態以附帶 JSON 為準。

- Open-CD ChangeFormer MiT-B0: 187-tensor architecture/seed and explicit non-V6 contract; five-case probability/four-stage parity; odd-size cropping; publisher/hash/variant attribution; actual changed-weight effects; corrupt tensors, BN variance, shape and original-V6 mislabel rejection; random/pretrained/MAT workspace routes; missing/wrong model rejection and exported provenance. [Parity evidence](../validation/changeformer-native-parity.json).

- Native BIT: 225-tensor architecture/seed contract, five-case backbone and probability parity, odd-size output cropping, publisher license/hash checks, actual changed-weight loading effects, BN/NaN/metadata/size rejection, random/pretrained/MAT workspace routes, wrong/missing model gating and exported publisher provenance. See [BIT parity evidence](../validation/bit-native-parity.json).

- Pretrained FC-Siam: publisher license/hash files, both variants' five-case reference parity, normalized zero-padding/cropping, input-geometry adaptation, normalization-contract rejection, pretrained workspace selection/0.5 threshold, exported weight provenance and V22 raw checkpoint compatibility.

- Full FC-Siam: four-level encoder/decoder structure and actual weight sharing, both difference/concatenation variants, odd image dimensions, two-class softmax normalization, inference repeatability using single-precision tolerances, native MAT round trips and changed-weight effects, corrupt values/shapes/BN variance/class order/missing-stage rejection, exact-size guards, shared-encoder CPU gradients/BN updates and workspace model selection/loading.

- Baseline Change Detection: known changed region, identical pair/undefined empty truth, SSIM dimensions, ROI, minimum area, brightness offset, dimension rejection, native translation registration, uniform-image rejection, RNG preservation, invalidation, image/report exports and UI.
- Native tiny models: Early Fusion and shared Siamese CPU forward/backprop/Adam, finite and decreasing synthetic training loss, Siamese input-order symmetry, exact input dimensions, malformed-artifact rejection and MAT round-trip/workspace inference.
- Existing regressions: measurement, project/frontends, shape matching, structured annotation, paging, pose-aware measurement, video extraction, image stitching and procedural defect synthesis.

`run_validation` runs all fifteen final suites directly. Full suite results are used without duplicate test counts. FC-Siam acceptance is 1e-5 maximum probability error; BIT and the Open-CD MiT-B0 variant use 1e-4, original synthetic fixtures and matching threshold-0.5 masks. The functional PyTorch reference is not a full upstream framework end-to-end certification.

Paging checks include bounded previous/next callbacks and repeated first/last-page events. Native inference smoke also checks industrial-validation status text and captures the fixed-size UI.

預訓練按鈕的 0.5 門檻設定完成後重測相關 suite，以唯一名稱合併，不重複計算通過數。

Fresh-source-path smoke opens all **14 workspaces**, checks V25 entry labels and supported English switching, and confirms three pages with at most six cards. Native screenshots show the homepage, navigation and pretrained native inference.

## Limits / 尚未驗證

These checks use original synthetic inputs and public pretrained weights. They do not establish real industrial accuracy, held-out model accuracy, physical metrology traceability, original-author BIT or ChangeFormer V6 checkpoint compatibility, GPU, BIT/ChangeFormer training, arbitrary checkpoint conversion, ONNX, large-image throughput, all codecs/OS versions or every interactive mouse/dialog path.

本版已執行兩份 FC-Siam、一份 Open-CD BIT 及一份 Open-CD ChangeFormer MiT-B0 變體公開權重；未以實際工業配對資料驗證誤報、漏報與門檻，也未驗證 BIT／變體訓練、GPU、ONNX、所有平台／編碼器及每個滑鼠操作流程。

Registration may fail on low texture, repeated patterns, strong parallax or illumination changes. Difference scores are not calibrated defect probabilities. Compensation can suppress real global brightness changes. Review candidates before acceptance.

Stitched mosaics do not inherit physical calibration automatically. Synthetic masks are appearance changes requiring review. Example-library implementation remains deferred.

## Evidence / 證據

- [Workspace smoke](../validation/package-smoke.json)
- [Native model feasibility evidence](../validation/change-model-research.json)
- [Full native FC-Siam evidence](../validation/fc-siam-native.json)
- [Pretrained conversion/parity evidence](../validation/fc-siam-pretrained-parity.json)
- [Source preservation](../validation/source-preservation.json)
- [Model research and primary sources](CHANGE_MODELS_RESEARCH.md)
