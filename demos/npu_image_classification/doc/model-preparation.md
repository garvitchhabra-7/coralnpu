# Model Preparation

How we got from a public MobileNet V1 model to one that actually runs on the Coral NPU.

## The problem

Google publishes pre-trained MobileNet V1 0.25 models at:
```
https://storage.googleapis.com/download.tensorflow.org/models/mobilenet_v1_2018_08_02/mobilenet_v1_0.25_224_quant.tgz
```

This model uses **uint8 quantization** — the original TFLite quantization scheme from 2017-2018. But TFLite Micro (the inference engine that runs on the Coral NPU) only supports **int8 quantization**. Attempting to run a uint8 model on TFLite Micro produces:

```
Hybrid models are not supported on TFLite Micro.
Node CONV_2D (number 0f) failed to prepare with status 1
```

This isn't a Coral NPU limitation — it's a TFLite Micro design decision. The int8 scheme (introduced later) is more efficient for integer-only hardware.

## uint8 vs int8 quantization

Both represent the same mathematical idea: map floating-point values to 8-bit integers using a scale and zero point.

| | uint8 (old) | int8 (new) |
|---|---|---|
| Range | 0 to 255 | -128 to 127 |
| Zero point | typically 128 | typically -128 or 0 |
| TFLite support | TFLite (mobile) | TFLite + TFLite Micro |
| Pixel mapping | pixel value used directly | `int8_value = pixel - 128` |

The weights and math are equivalent — it's just a shift in representation.

## The conversion

No prebuilt int8 MobileNet V1 0.25 exists publicly. We converted one from the Keras pretrained weights using TensorFlow's post-training quantization:

```python
import tensorflow as tf
import numpy as np

# Load the float model from Keras (downloads ~2MB of weights)
model = tf.keras.applications.MobileNet(
    input_shape=(224, 224, 3),
    alpha=0.25,
    weights="imagenet",
)

# Representative dataset for calibration (random images are fine here —
# the quantizer just needs to see the activation ranges)
def representative_dataset():
    for _ in range(100):
        data = np.random.uniform(0, 1, (1, 224, 224, 3)).astype(np.float32)
        yield [data]

converter = tf.lite.TFLiteConverter.from_keras_model(model)
converter.optimizations = [tf.lite.Optimize.DEFAULT]
converter.representative_dataset = representative_dataset
converter.target_spec.supported_ops = [tf.lite.OpsSet.TFLITE_BUILTINS_INT8]
converter.inference_input_type = tf.int8
converter.inference_output_type = tf.int8

tflite_model = converter.convert()

with open("mobilenet_v1_0.25_224_int8.tflite", "wb") as f:
    f.write(tflite_model)
```

This requires `tensorflow` (not just `tflite-runtime`). The host demo's uv environment has it installed; you can run this conversion from `demos/image_classification/`:

```bash
cd demos/image_classification
uv run python <the_script_above>
```

## What the conversion produces

| Property | Value |
|---|---|
| File | `mobilenet_v1_0.25_224_int8.tflite` |
| Size | 597 KB |
| Input | `[1, 224, 224, 3]` int8, scale=0.00392, zero_point=-128 |
| Output | `[1, 1000]` int8, scale=0.00391, zero_point=-128 |
| Ops needed | CONV_2D, DEPTHWISE_CONV_2D, RESHAPE, SOFTMAX, STRIDED_SLICE, PAD, MEAN, SHAPE, PACK |

Note: the Keras model outputs **1000** classes (no background class), while the older TF-hosted uint8 model outputs **1001**. The labels file has 1001 entries (index 0 = "background"), so when reading the int8 model's output we offset by +1 to match.

## Why not convert the old .tflite directly?

We tried. TensorFlow's converter chokes on re-quantizing an already-quantized `.tflite` file — it hits a reshape scale constraint error. Starting from the Keras float model and doing a fresh post-training quantization is cleaner and produces a model that TFLite Micro accepts.

## Ops: custom vs stock

The Coral NPU has RVV-optimized kernels for Conv2D and DepthwiseConv2D (`sw/opt/litert-micro/`). These custom kernels are registered for those two ops. The remaining 7 ops (Reshape, Softmax, StridedSlice, Pad, Mean, Shape, Pack) use stock TFLite Micro reference implementations.

During inference you'll see "Fallback kernel" messages for Conv2D layers whose dimensions don't match the RVV tiling — these still work, just without SIMD acceleration.

A scalar-only build (`classify_npu_scalar_binary`) disables the RVV kernels entirely and uses reference C implementations for all 9 ops. This is useful for measuring the RVV speedup — see the [overview](overview.md#scalar-only-vs-rvv) for cycle count comparison.
