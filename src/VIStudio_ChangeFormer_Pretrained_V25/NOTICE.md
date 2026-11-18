# Open-CD ChangeFormer MiT-B0 variant attribution

Publisher: Open-CD contributors / likyoo, https://huggingface.co/likyoo/Open-CD_Model_Zoo

Publisher model-card license: Apache-2.0. Exact source revision, original checkpoint URL/SHA-256 and converted MAT hash are in MANIFEST.json. The full license text is in LICENSE-APACHE-2.0.txt. Training imagery and upstream Python implementation are not bundled.

IMPORTANT VARIANT DISCLOSURE: Open-CD explicitly describes this model as a Siamese SegFormer variant that does not strictly reproduce the original ChangeFormer. It is not ChangeFormer V6. See https://github.com/likyoo/open-cd/tree/main/configs/changeformer

Architecture credits: OpenMMLab MMSegmentation MixVisionTransformer/SegformerHead and Open-CD. SegFormer: Enze Xie et al., https://arxiv.org/abs/2105.15203 . ChangeFormer paper: Wele Gedara Chaminda Bandara and Vishal M. Patel, https://arxiv.org/abs/2201.01293 . Open-CD: Kaiyu Li et al., https://arxiv.org/abs/2407.15317 .

MODIFIED by VIStudio: independently implemented native MATLAB shared MiT-B0, spatial-reduction attention, MixFFN depthwise convolution/GELU and multi-scale SegFormer head. Tensor layouts are converted without retraining; learned weights and BN statistics are preserved. RGB normalization, normalized-zero pad32, half-pixel bilinear interpolation and original-frame cropping are native. Python was used only for one-time extraction/reference comparison, not runtime loading/inference.

The original ChangeFormer repository displays MIT labeling and also research/noncommercial README terms. Its implementation/checkpoints are not included. The bundled checkpoint is from the separately published Open-CD model card. Publisher terms are recorded as provided, without asserting ownership of training imagery or industrial suitability.
