# Open-CD BIT-R18 pretrained attribution

Publisher: Open-CD contributors / likyoo (Kaiyu Li), https://huggingface.co/likyoo/Open-CD_Model_Zoo

The publisher's model card declares Apache-2.0. Exact source revision, URLs, original and converted hashes are in MANIFEST.json. The full license is in LICENSE-APACHE-2.0.txt. Training imagery and upstream Python implementation are not bundled.

BIT paper: Hao Chen, Zipeng Qi and Zhenwei Shi, Remote Sensing Image Change Detection with Transformers, IEEE TGRS, https://arxiv.org/abs/2103.00208

Open-CD: Kaiyu Li et al., Open-CD: A Comprehensive Toolbox for Change Detection, https://arxiv.org/abs/2407.15317

MODIFIED by VIStudio: independently implemented native MATLAB ResNetV1c-18 three-stage backbone and Open-CD improved BITHead, including semantic tokenization, positional embedding, one encoder and eight cross-attention decoder blocks. Tensor layouts are converted; learned weights and BN state are preserved without retraining. Bilinear interpolation, normalization, normalized-zero pad32 and output cropping are native. This is the Open-CD variant, not the original BIT author implementation/checkpoint.

The original BIT author repository states noncommercial/research terms. Its code/checkpoints are not included here; the weight source is the separately published Open-CD model card. Publisher licensing is recorded as supplied, without asserting ownership of training imagery or industrial suitability. Native MATLAB inference is Python-free; Python was used only for one-time extraction and reference comparison.
