# Changelog

## 25.0.0 — 2026-11-13

- Added independent native MATLAB inference for the Open-CD model published as ChangeFormer MiT-B0, with explicit disclosure that it is a Siamese SegFormer variant, not original ChangeFormer V6.
- Bundled publisher-declared Apache-2.0 LEVIR-CD MAT weights and attribution/license/provenance hashes. Verified all four encoder stages and probabilities on five original synthetic pairs with matching threshold-0.5 masks.
- Integrated random-model creation, Pretrained and strict native MAT loading, preserving image coordinates and source variant metadata.
- Added bilingual guidance distinguishing BIT reference-pair inspection from learning normality and ground-truth accuracy assessment.
- Updated current V25 workspaces, bilingual docs and source release. Training/GPU/industrial accuracy remain unestablished; example library remains deferred.


## 24.0.0 — 2026-11-13

- Added independent native MATLAB inference for the Open-CD improved BIT-R18 variant: shared ResNetV1c-18, semantic tokens, one encoder and eight cross-attention decoder blocks.
- Bundled publisher-declared Apache-2.0 LEVIR-CD native MAT weights, pinned provenance, hashes and attribution/license notice. No original BIT-author code/checkpoint or Python runtime dependency.
- Verified backbone/probability parity on five original synthetic pairs, including odd-size padding, with matching threshold-0.5 masks.
- Integrated random-model creation, Pretrained and native MAT loading into Change Detection, with strict tensor contracts and pixel-preserving input geometry.
- Updated all current V24 workspaces, bilingual docs and release evidence. BIT training and industrial accuracy are not established; example library remains deferred.


## 23.0.0 — 2026-11-13

- Bundled converted native MATLAB FC-Siam-diff/conc pretrained checkpoints from the publisher's Apache-2.0 Open-CD Model Zoo, with pinned source/hash/license/modification notices.
- Verified both-class probability parity against the original published weights on five original synthetic pairs per variant, including normalized zero padding and odd dimensions. No retraining occurred.
- Added Pretrained in Change Detection, native normalization/padding/cropping, explicit input-geometry adaptation and a 0.5 threshold default for the pretrained button. Runtime inference requires no Python.
- Updated bilingual README, model research, screenshots, tests and source release. Industrial defect accuracy and GPU remain unvalidated; example library remains deferred.


## 22.0.0 — 2026-11-13

- Added independently implemented full native MATLAB FC-Siam-diff and FC-Siam-conc: shared four-level encoder, multi-scale skips, complete transposed-convolution decoder, channel-wise dropout and two-class probabilities.
- Added strict native MAT weight/state checkpoints, odd-size alignment, inference and a native SGD training-step API.
- Integrated model creation/loading and variant selection into Change Detection; random weights are explicitly labeled and model failures do not fall back to baseline detection.
- Updated all current V22 frontends, bilingual docs and release evidence. No Python inference dependency or third-party pretrained weights; example library remains deferred.


## 21.0.0 — 2026-11-13

- Added bilingual Change Detection on workspace page three: registration gates, ROI, absolute difference/SSIM, thresholding, regions, IoU/Dice and PNG/CSV/MAT exports.
- Added original tiny Early Fusion and shared Siamese CPU research networks with a strict MAT artifact contract; external pretrained models are not bundled.
- Updated all 14 workspace entry versions, bilingual README, screenshots and model-feasibility documentation.
- Example library remains deferred; historical source implementations are preserved.


## 20.0.0 — 2026-11-12

- Added feature-based Image Stitching with registration quality gates, feather/mean blending, valid coverage and coordinate evidence.
- Added procedural Defect Synthesis: scratches, spots, stains and donor cut-paste with exact changed-pixel masks, seed provenance, source groups and unreviewed labels.
- Grouped 13 current V20 workspaces into model, annotation/metrology and image-data pages, up to six cards per page.
- Added a feature-expansion roadmap. The example library is explicitly deferred and retained for future consideration.
- Updated bilingual documentation, screenshots and validation while preserving historical development implementations.


## 19.0.0 — 2026-11-12

- Integrated template-bound Measurement recipes inside Shape Matching: transform tools, remeasure every object and export object summaries/tool records/per-object evidence.
- Added Video ROI Extraction: fixed crop, every-N-frames/images-per-second selection, frame bounds, limits, PNG/JPG, cancellation, manifests and source integrity checks.
- Expanded paged workspaces to 11 entries with consistently versioned V19 frontends and dedicated shape/video icons.
- Added a bilingual example-library assessment; no library browser/downloader is implemented.
- Retained compatible measurement/project/annotation schemas and historical development implementations.


## 18.0.0 — 2026-11-12

- Added independent R2026b native Shape Matching: template/ROI, rotation/scale search, pose results, settings and reports.
- Added six-card workspace pages with Previous/Next navigation and room for more tools.
- Unified current portal, vision, annotation, semantic/instance/keypoint, evaluation and measurement frontends to V18; Home returns to the current portal.
- Retained compatible project, annotation and measurement backends and preserved historical development implementations.
- Synchronized the illustrated bilingual release README back to the development root; added the shape-placement assessment and new workspace screenshots.
- Shape-based automatic gauging/alignment and image change detection remain future work.


## 17.0.0 — 2026-11-04

- Clean distribution: remove unused historical launchers/implementations and archived README; retain only current runtime/test dependencies.

- Add independent Measurement Studio and homepage entry.
- Add native caliper edge-pair, circle and angle measurements plus geometric and mask measurements.
- Add physical scale/reference calibration and existing lens/perspective profile import.
- Add inclusive tolerances and explicit NOT_MEASURED/NaN failure handling.
- Add editing, undo/redo, portable sessions, recipes and batch exports.
- Fix native viewer annotation cleanup when switching images or calibration.
- Add Chinese/English release documentation and screenshots from the actual application.
- Package source and tests independently from development datasets, models and histories.
- Keep existing vision project and model workflows on stable versioned components.
- Defer image change detection to a later release.

This is a MATLAB source release, not a compiled application. See README and validation scope for requirements and known limits.
