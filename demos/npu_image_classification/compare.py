"""Compare MobileNet V1 0.25 inference: host CPU vs Coral NPU simulator.

Runs the same image through both paths and reports the difference.
Guarantees the same image and preprocessing for both — no stale files.

Usage:
    cd demos/npu_image_classification
    uv run python compare.py --image test_images/grace_hopper.jpg
"""

import argparse
import pathlib
import subprocess
import sys
import tempfile

import numpy as np
from PIL import Image
from tflite_runtime.interpreter import Interpreter

HERE = pathlib.Path(__file__).resolve().parent
REPO_ROOT = HERE.parent.parent
MODEL_PATH = HERE / "models" / "mobilenet_v1_0.25_224_int8.tflite"
LABELS_PATH = HERE / "models" / "imagenet_labels.txt"
INPUT_SIZE = 224
NUM_CLASSES = 1000
TOP_K = 5


def load_labels():
    return LABELS_PATH.read_text().strip().splitlines()


def preprocess(image_path):
    img = Image.open(image_path).convert("RGB")
    img = img.resize((INPUT_SIZE, INPUT_SIZE), Image.BILINEAR)
    pixels = np.array(img, dtype=np.int16) - 128
    return pixels.astype(np.int8)


def run_host(input_data):
    interpreter = Interpreter(model_path=str(MODEL_PATH))
    interpreter.allocate_tensors()
    interpreter.set_tensor(
        interpreter.get_input_details()[0]["index"],
        np.expand_dims(input_data, 0),
    )
    interpreter.invoke()
    return interpreter.get_tensor(
        interpreter.get_output_details()[0]["index"]
    ).flatten()


def run_npusim(image_path):
    """Run the NPU simulator via bazel and return its output."""
    with tempfile.NamedTemporaryFile(suffix=".npy", delete=False) as tmp:
        output_path = tmp.name

    try:
        cmd = [
            "bazel", "run",
            "//demos/npu_image_classification:run_on_npusim", "--",
            "--image", str(image_path),
            "--output", output_path,
        ]
        print(f"  $ {' '.join(cmd)}")
        result = subprocess.run(
            cmd,
            cwd=str(REPO_ROOT),
            capture_output=True,
            text=True,
        )

        for line in result.stdout.splitlines():
            if any(kw in line for kw in [
                "Simulation complete", "Invoke", "ERROR",
                "Op resolver", "Interpreter", "Input image",
            ]):
                print(f"  [npusim] {line}")

        if result.returncode != 0:
            print(f"\n  npusim FAILED (exit code {result.returncode})")
            for line in result.stderr.splitlines()[-10:]:
                print(f"  [stderr] {line}")
            return None

        if pathlib.Path(output_path).exists():
            return np.load(output_path)

        print("  WARNING: Could not locate npusim output at", output_path)
        return None
    finally:
        pathlib.Path(output_path).unlink(missing_ok=True)


def print_top_k(output, labels, tag):
    top_k = output.argsort()[-TOP_K:][::-1]
    print(f"\n  {tag} Top-{TOP_K}:")
    for i, idx in enumerate(top_k):
        print(f"    {i+1}. {labels[idx + 1]:30s}  (score: {output[idx]})")
    return set(top_k.tolist())


def compare(host_output, npu_output, labels):
    diff = npu_output.astype(np.int16) - host_output.astype(np.int16)
    exact = np.array_equal(host_output, npu_output)
    max_diff = int(np.max(np.abs(diff)))
    num_differ = int(np.count_nonzero(diff))

    host_top5 = print_top_k(host_output, labels, "Host")
    npu_top5 = print_top_k(npu_output, labels, "NPU ")
    top5_match = host_top5 == npu_top5

    print(f"\n  {'='*56}")
    print(f"  Byte-exact match:    {'YES' if exact else 'NO'}")
    print(f"  Max abs difference:  {max_diff}")
    print(f"  Differing values:    {num_differ} / {NUM_CLASSES}")
    print(f"  Top-5 classes match: {'YES' if top5_match else 'NO'}")

    if not top5_match:
        only_host = host_top5 - npu_top5
        only_npu = npu_top5 - host_top5
        if only_host:
            print(f"  Only in host top-5:  {[labels[i+1] for i in only_host]}")
        if only_npu:
            print(f"  Only in NPU top-5:   {[labels[i+1] for i in only_npu]}")

    if not exact and max_diff > 0:
        worst = int(np.argmax(np.abs(diff)))
        print(f"\n  Worst mismatch: class {worst} ({labels[worst+1]})")
        print(f"    host={host_output[worst]}, npu={npu_output[worst]}, diff={int(diff[worst])}")

    print(f"  {'='*56}")


def main():
    parser = argparse.ArgumentParser(
        description="Compare image classification: host CPU vs Coral NPU"
    )
    parser.add_argument("--image", required=True, help="Path to input image")
    args = parser.parse_args()

    image_path = pathlib.Path(args.image).resolve()
    if not image_path.exists():
        print(f"Image not found: {image_path}")
        sys.exit(1)

    labels = load_labels()
    print(f"Image: {image_path}\n")

    print("Step 1: Running host CPU inference...")
    input_data = preprocess(str(image_path))
    host_output = run_host(input_data)
    print("  Done.")

    print("\nStep 2: Running NPU simulator inference...")
    npu_output = run_npusim(image_path)

    if npu_output is None:
        print("\nCould not retrieve NPU output. Check npusim logs above.")
        sys.exit(1)

    print("\nStep 3: Comparing outputs...")
    compare(host_output, npu_output, labels)


if __name__ == "__main__":
    main()
