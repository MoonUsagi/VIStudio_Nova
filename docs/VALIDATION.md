# 驗證範圍 / Validation Scope

This source release targets Windows and MATLAB R2026b. Machine-readable final results are included in `../validation/`.

## New measurement checks

- Native `caliper` edge-pair measurement and physical scaling.
- Native `fitcircle`, fitted diameter, deterministic RANSAC and restoration of the caller's RNG.
- Native `fitangle` against synthetic image edges.
- Manual endpoint distance, angle and point-to-line geometry.
- Native canvas construction/capture for uicaliper, uifitcircle, uifitangle and uitsquare.
- Physical anisotropic distances, area and rotated rectangle dimensions; isotropic circle guard.
- Known-length reference and identity-plane perspective calibration.
- Inclusive tolerance decisions, unconfigured tolerances and no-edge failure values.
- Update/delete/Undo/Redo and calibration-induced record clearing.
- Portable session reload, recomputation of edited stored values and source-image integrity checks.
- Transactional recipe application and resolution mismatch.
- Batch continuation across valid, no-edge and wrong-resolution images, including report exports.
- Visible-viewer image replacement and cleanup of native annotations.
- V17 homepage measurement routing and English help.

## Existing workflow regression

The packaged project-hub and structured-annotation tests cover project metadata, split guidance, review progress, model/report mismatch, missing references, synchronization, existing vision UI entry points, instance/pose export, candidate review gates, metrics, recovery and integration.

## Clean-package verification

The release is launched from its staged source directory with MATLAB's default toolbox path and the packaged `src`, rather than relying on the original workspace. Package verification checks required assets, documentation links and the file inventory.

## Not established by this release

- Physical accuracy, measurement uncertainty, gauge R&R or production acceptance.
- Every mouse placement/drag/file-dialog path or long-running production workloads.
- Every pretrained model, large-model training/inference or GPU configuration.
- Other MATLAB releases or operating systems.
- Automatic alignment or image change detection.
- A compiled executable, installer or MATLAB Runtime deployment.

All distributed example images are original synthetic fixtures. API presence is distinct from successful execution; only the listed native measurement paths are included in the new numerical verification.

## Release result

**52/52 packaged checks passed**, with zero failures/incomplete checks. The clean-package smoke launch also passed. **265 pre-existing source/document files remained unchanged.** See `../validation/summary.json` and `../validation/package-smoke.json`.

## Latest-only distribution cleanup

Removed 72 unused historical source files and the archived README. 70 current source/dependency files remain. The clean distribution passed all 52 packaged checks again.
