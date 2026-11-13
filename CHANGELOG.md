# Changelog

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
