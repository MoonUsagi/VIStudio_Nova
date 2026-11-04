# Contributing / 回報與協作

Use GitHub Issues for bugs or feature requests. Include:

1. MATLAB version and relevant toolbox versions (`ver`).
2. Operating system and display scaling for UI issues.
3. Exact steps and expected/actual behavior.
4. Error text and a small synthetic or otherwise shareable image/recipe.
5. Whether the issue reproduces with the built-in Demo.

Please avoid private images, model weights, credentials and patient/customer information in attachments. Keep changes scoped and explain why they are needed.

For code changes, run `run_validation` from the repository root. Add meaningful tests for numerical behavior, state changes and failure handling. Do not change existing session/project formats without a migration strategy. Preserve the distinction between manual geometry, native edge fitting, an unmeasured result and an acceptance decision.

The release has not selected a new open-source license; consult LICENSE_STATUS and the repository owner regarding permitted contributions and reuse.
