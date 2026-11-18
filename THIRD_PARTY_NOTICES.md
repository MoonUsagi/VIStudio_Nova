# Third-party and asset notices

- **MATLAB and MathWorks toolboxes:** invoked through installed public APIs. No MathWorks toolbox implementation or binaries are included. Each recipient needs the relevant installed products and licenses.
- **Optional COCO bridge:** the existing bridge imports numpy/pycocotools from the user's configured Python environment. Those packages and their binaries are not bundled. Their upstream licenses apply when separately installed.
- **VIStudio logo:** generated for this project using the built-in image generation tool. The packaged asset is a navy-background PNG, not an SVG or a transparent master.
- **Workspace illustrations and measurement icon:** original programmatic drawings created for this project.
- **Documentation screenshots and metrology fixture:** captured from the app using original generated geometric images. The fixture does not represent a real product, a trained model prediction, or a certified measurement artifact.
- **Existing VIStudio code:** retained from the working project with its versioned source files and notices. The initial-build attribution recorded in the original README is retained in the current README and license-status notice.

No new license is selected for the project by this release packaging step. Refer to LICENSE_STATUS.


## V23 Open-CD pretrained FC-Siam

Two converted native MAT checkpoints are included under the publisher-declared Apache-2.0 model-card license. Full attribution, modification notice and license text are in `src/VIStudio_Pretrained_V23/NOTICE.md` and `LICENSE-APACHE-2.0.txt` (development: `VIStudio_Pretrained_V23`). Original/converted hashes and pinned provenance are in that folder’s `MANIFEST.json`. Training data and upstream Python implementation are not bundled. See [pretrained documentation](docs/FC_SIAM_PRETRAINED.md).


## V24 Open-CD improved BIT-R18

A converted native BIT checkpoint is bundled under the publisher model card’s Apache-2.0 declaration. Source revision, hashes, license text and modification/attribution notice are in `src/VIStudio_BIT_Pretrained_V24` (development: the same folder at root). This is the Open-CD improved variant; original BIT author code/checkpoints are not bundled. See [BIT documentation](docs/BIT_NATIVE.md).


## V25 Open-CD ChangeFormer MiT-B0 variant

The converted checkpoint in `src/VIStudio_ChangeFormer_Pretrained_V25` uses the publisher model card’s Apache-2.0 declaration. Full license, modification/attribution notice and source/native hashes accompany it. Open-CD describes this as Siamese SegFormer, not a strict original ChangeFormer reproduction; original-author code/V6 checkpoints are not bundled. See [variant documentation](docs/CHANGEFORMER_NATIVE.md).
