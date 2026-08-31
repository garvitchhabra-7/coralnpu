# Reproducing the Host Demo from Scratch

Step-by-step reproduction of the host CPU classification demo. Follow this if you're setting it up in a new environment or want to understand what each piece is.

## 1. Create the project

```bash
mkdir -p demos/image_classification
cd demos/image_classification
uv init
# Add to pyproject.toml dependencies: tflite-runtime, numpy, Pillow
uv sync
```

## 2. Download the model

MobileNet V1 0.25, quantized uint8, pre-trained on ImageNet. Google hosts it as a tarball — we only need the `.tflite` file.

```bash
mkdir -p models

curl -L -o /tmp/mobilenet_v1_0.25_224_quant.tgz \
  "https://storage.googleapis.com/download.tensorflow.org/models/mobilenet_v1_2018_08_02/mobilenet_v1_0.25_224_quant.tgz"

tar -xzf /tmp/mobilenet_v1_0.25_224_quant.tgz -C models/ ./mobilenet_v1_0.25_224_quant.tflite
```

The tarball also contains checkpoints and frozen graphs — ignore those.

## 3. Download ImageNet labels

1001 lines — one label per output index. Index 0 is "background".

```bash
curl -L -o models/imagenet_labels.txt \
  "https://storage.googleapis.com/download.tensorflow.org/data/ImageNetLabels.txt"
```

## 4. Get a test image

```bash
mkdir -p test_images

curl -L -o test_images/grace_hopper.jpg \
  "https://storage.googleapis.com/download.tensorflow.org/example_images/grace_hopper.jpg"
```

## 5. Verify

```bash
uv run python classify.py test_images/grace_hopper.jpg
```

Expected top predictions: "suit", "military uniform", "bow tie". If you see those, setup is correct.

## Swapping the model

Replace the `.tflite` in `models/` and update `MODEL_PATH` in `classify.py`. All ImageNet MobileNet variants share the same I/O contract: `[1, 224, 224, 3]` uint8 in, `[1, 1001]` uint8 out.
