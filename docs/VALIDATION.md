# Validation / 驗證範圍

**104/104 checks passed**, zero failed/incomplete, Windows and MATLAB R2026b `26.2.0.3386108`.

- 84 current regressions: measurement (18), project/frontends (14), shape matching (9), structured annotation (20), paging/routing (2), pose measurement (12) and video extraction (9).
- 10 stitching checks: native overlap/coordinate recovery including a three-view chain, all four transformation models, mean/feather blending, uniform-image rejection, memory limit, projective horizon, source mutation, RNG restoration, coverage/transform export, invalidation, UI and mixed grayscale/RGB 16-bit sources.
- 10 synthesis checks: all four types, exact changed-pixel masks, reproducibility/global RNG preservation, strict allowed regions after blur, float-to-16-bit representation, seed wraparound/source grouping, PNG round trips, cancellation, invisible-defect rejection, missing donor/invalid mask, UI and RGB 16-bit donor evidence.

The 102-check suite passed first. The two new suites were then expanded to 10 checks each and rerun; their previous results were replaced, yielding 104 unique passing results. `run_validation` repeats the final nine suites directly.

Additional fresh-path smoke opens all **13** current workspaces and checks **V20** labels, including supported English switching. Three pages use at most six cards and retain every entry.

## Limits

Tests use original synthetic images/videos. They do not establish production accuracy, physical metrology traceability, defect realism, improved real-model performance, large-image throughput, all codecs/OS versions, every mouse/dialog/cancel path, GPU or all pretrained model paths.

Stitching tests cover controlled overlapping planar views, not severe parallax, reflections, moving scenes or arbitrary unrelated images. Native inlier/error gates are not a general accuracy guarantee. Physical calibration does not automatically transfer to mosaics.

Synthesis masks describe actual synthetic appearance changes, not reviewed physical-defect truth. Real independent testing and source-aware dataset splits remain necessary. No task-specific training adapter or example library is implemented. The library is deferred for future consideration.

## Evidence

- [Summary](../validation/summary.json)
- [Per-test results](../validation/test-results.json)
- [Workspace smoke](../validation/package-smoke.json)
- [Source preservation](../validation/source-preservation.json)
