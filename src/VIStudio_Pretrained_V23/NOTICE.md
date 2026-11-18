# Open-CD pretrained FC-Siam weight attribution

Publisher: Open-CD contributors / likyoo (Kaiyu Li), https://huggingface.co/likyoo/Open-CD_Model_Zoo

The publisher model card declares Apache-2.0. The exact revision, original checkpoint URLs/SHA-256 and converted MAT hashes are in MANIFEST.json. See LICENSE-APACHE-2.0.txt for the publisher's license text. Dataset files are not included.

Architecture citation: Rodrigo Caye Daudt, Bertrand Le Saux and Alexandre Boulch, Fully Convolutional Siamese Networks for Change Detection, ICIP 2018, https://arxiv.org/abs/1810.08462

Toolbox citation: Kaiyu Li et al., Open-CD: A Comprehensive Toolbox for Change Detection, https://arxiv.org/abs/2407.15317

MODIFIED by VIStudio: tensor layouts converted to MATLAB; the final linear 16-channel transposed convolution and linear 1x1 classifier are algebraically folded into a two-class layer. All other learned parameters and BN statistics are retained. ImageNet RGB normalization and zero padding to multiples of 32 are applied natively, then the output is cropped to the input frame. No retraining was performed. Cross-framework probability parity is checked on original synthetic pairs; this does not establish real industrial accuracy.

The original checkpoint files and upstream Python implementation are not included. Native MATLAB inference does not require Python. Publisher licensing is recorded as provided; this notice does not assert ownership of third-party training imagery or validate industrial suitability.
