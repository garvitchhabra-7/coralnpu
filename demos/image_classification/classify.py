"""Reference MobileNet V1 0.25 224x224 int8 image classifier.

Runs on the host PC via tflite-runtime. Produces a reference output
that can be compared byte-for-byte against the Coral NPU simulator.

Usage:
    uv run python classify.py <image_path>
    uv run python classify.py test_images/grace_hopper.jpg
"""

import sys
import pathlib

import numpy as np
from PIL import Image
from tflite_runtime.interpreter import Interpreter

MODEL_PATH = pathlib.Path(__file__).parent / "models" / "mobilenet_v1_0.25_224_int8.tflite"
LABELS_PATH = pathlib.Path(__file__).parent / "models" / "imagenet_labels.txt"
INPUT_SIZE = 224
NUM_CLASSES = 1000
TOP_K = 5


def load_labels(path: pathlib.Path) -> list[str]:
    return path.read_text().strip().splitlines()


def preprocess(image_path: str) -> np.ndarray:
    img = Image.open(image_path).convert("RGB")
    img = img.resize((INPUT_SIZE, INPUT_SIZE), Image.BILINEAR)
    pixels = np.array(img, dtype=np.int16) - 128
    return np.expand_dims(pixels.astype(np.int8), axis=0)


def classify(image_path: str):
    labels = load_labels(LABELS_PATH)
    interpreter = Interpreter(model_path=str(MODEL_PATH))
    interpreter.allocate_tensors()

    input_details = interpreter.get_input_details()
    output_details = interpreter.get_output_details()

    print(f"Input:  shape={input_details[0]['shape']} dtype={input_details[0]['dtype']}")
    print(f"Output: shape={output_details[0]['shape']} dtype={output_details[0]['dtype']}")

    input_data = preprocess(image_path)
    interpreter.set_tensor(input_details[0]["index"], input_data)
    interpreter.invoke()

    output_data = interpreter.get_tensor(output_details[0]["index"]).flatten()

    top_k_indices = output_data.argsort()[-TOP_K:][::-1]
    print(f"\nImage: {image_path}")
    print(f"Top-{TOP_K} predictions:")
    for i, idx in enumerate(top_k_indices):
        # labels[0] is "background"; Keras int8 model has 1000 classes offset by 1
        print(f"  {i+1}. {labels[idx + 1]:30s}  (raw score: {output_data[idx]})")

    np.save("last_input.npy", input_data)
    np.save("last_output.npy", output_data)
    print(f"\nSaved raw input/output to last_input.npy / last_output.npy")


if __name__ == "__main__":
    if len(sys.argv) < 2:
        print(f"Usage: {sys.argv[0]} <image_path>")
        sys.exit(1)
    classify(sys.argv[1])
