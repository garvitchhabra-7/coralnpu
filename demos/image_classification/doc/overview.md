# Host CPU Image Classification

Reference image classifier running MobileNet V1 on your PC. This produces a ground-truth output to compare against the Coral NPU simulator.

## How it works

MobileNet V1 0.25 is a lightweight CNN trained on ImageNet (1000 object classes). The "0.25" means it uses 25% of the full channel width — small enough at ~500KB to fit on a microcontroller.

```
JPEG/PNG image
    |  resize to 224x224, keep as uint8
[1, 224, 224, 3] tensor
    |  MobileNet V1 0.25 (quantized uint8)
[1, 1001] scores
    |  argmax -> top-K
"military uniform", "suit", ...
```

The model outputs 1001 uint8 scores (1000 classes + background). Higher score = more confident. These are quantized logits, not probabilities — only relative ordering matters.

## Quick start

```bash
cd demos/image_classification
uv sync
uv run python classify.py test_images/grace_hopper.jpg
```

## Try your own images

Drop any JPEG or PNG into `test_images/` and run:

```bash
uv run python classify.py test_images/your_photo.jpg
```

Images are resized to 224x224 automatically.

## What gets saved

Each run writes two numpy files for later comparison with the NPU:

| File | Contents |
|---|---|
| `last_input.npy` | Preprocessed input `[1, 224, 224, 3]` uint8 |
| `last_output.npy` | Raw output scores `[1001]` uint8 |

## File layout

```
demos/image_classification/
├── classify.py              # The classifier script
├── models/
│   ├── mobilenet_v1_0.25_224_quant.tflite
│   └── imagenet_labels.txt
├── test_images/
│   └── grace_hopper.jpg
├── pyproject.toml           # uv project (dependencies)
└── uv.lock
```
