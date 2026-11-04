# Changelog

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
