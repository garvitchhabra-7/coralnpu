# NPU Image Classification

Runs MobileNet V1 0.25 image classification on the Coral NPU software simulator (npusim). Takes a real image, classifies it on simulated NPU hardware, and prints the top-5 ImageNet predictions.

## Quick start

```bash
# Build (first time takes a few minutes)
bazel build //demos/npu_image_classification:run_on_npusim

# Classify an image
bazel run //demos/npu_image_classification:run_on_npusim -- \
  --image /absolute/path/to/demos/npu_image_classification/test_images/grace_hopper.jpg
```

Output:

```
Input image: .../grace_hopper.jpg (preprocessed to 224x224 int8)
Running simulation...
Op resolver ready
Interpreter created
Invoke successful
Simulation complete. Cycles: 446577272

Top-5 predictions:
  1. academic gown                   (raw score: -103)
  2. bow tie                         (raw score: -103)
  3. mortarboard                     (raw score: -103)
  4. military uniform                (raw score: -103)
  5. suit                            (raw score: -103)
```

The image argument must be an absolute path because Bazel runs in a sandboxed directory.

## Compare against host CPU

`compare.py` runs the same image through both the host CPU (via tflite-runtime) and the NPU simulator, then reports differences:

```bash
cd demos/npu_image_classification
uv sync --python 3.11
uv run python compare.py --image test_images/grace_hopper.jpg
```

Output includes side-by-side top-5 predictions, byte-exact match status, max absolute difference, and the worst-case mismatch class. Small differences (max diff ~9, ~17 values out of 1000) are expected due to rounding differences between the RVV-optimized kernels and the reference TFLite implementation.

## Scalar-only vs RVV

A scalar-only build uses stock TFLite Micro reference kernels (pure C, no vector instructions) instead of the RVV-optimized Conv2D/DepthwiseConv2D. This lets you measure exactly what the vector extension buys you.

```bash
# Scalar only (~653M cycles)
bazel run //demos/npu_image_classification:run_on_npusim_scalar -- \
  --image $(pwd)/demos/npu_image_classification/test_images/grace_hopper.jpg

# RVV optimized (~446M cycles)
bazel run //demos/npu_image_classification:run_on_npusim -- \
  --image $(pwd)/demos/npu_image_classification/test_images/grace_hopper.jpg
```

| Variant | Cycles | Speedup |
|---|---|---|
| Scalar only | 653,468,489 | 1.0x |
| RVV optimized | 446,577,272 | 1.46x |

Both produce the same top-5 classes. The difference comes entirely from Conv2D and DepthwiseConv2D — these two ops dominate MobileNet's compute. The C++ source (`classify_npu.cc`) uses `#ifdef SCALAR_ONLY` to switch between the two kernel sets, controlled by `-DSCALAR_ONLY` in the BUILD rule's `copts`.

## What's happening

1. **`run_on_npusim.py`** loads your image, resizes it to 224x224, converts pixel values from uint8 to int8
2. It boots the Coral NPU software simulator with the compiled ELF binary
3. It writes the preprocessed image bytes into the NPU's memory at the `inference_input` symbol
4. The NPU executes the full MobileNet V1 inference (~446 million instructions)
5. The script reads back 1000 output scores from `inference_output` and maps them to ImageNet labels

## Try your own images

Drop any JPEG or PNG into `test_images/` and pass its absolute path:

```bash
bazel run //demos/npu_image_classification:run_on_npusim -- \
  --image $(pwd)/demos/npu_image_classification/test_images/your_photo.jpg
```

## File layout

```
demos/npu_image_classification/
├── classify_npu.cc          # C++ inference program (runs on the NPU)
├── run_on_npusim.py         # Python driver (loads image, drives simulator)
├── compare.py               # Runs both host + NPU, reports differences
├── pyproject.toml           # uv project config for compare.py
├── BUILD                    # Bazel build rules
├── models/
│   ├── mobilenet_v1_0.25_224_int8.tflite   # Int8 quantized model (~597KB)
│   └── imagenet_labels.txt                 # 1001 class labels
├── test_images/
│   └── grace_hopper.jpg
└── doc/
    ├── overview.md           # This file
    ├── model-preparation.md  # Why int8, how the model was converted
    ├── architecture.md       # How the pieces fit together
    └── cocotb-rtl.md         # Notes for future cycle-accurate RTL simulation
```

## Further reading

- [Model preparation](model-preparation.md) — why we needed an int8 model and how it was converted
- [Architecture](architecture.md) — how the C++ binary, simulator, and Python driver work together
- [Cocotb RTL](cocotb-rtl.md) — notes for running this on the cycle-accurate RTL simulator
