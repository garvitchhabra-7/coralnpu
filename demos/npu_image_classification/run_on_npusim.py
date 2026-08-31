# Copyright 2026 Google LLC
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     https://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

"""Run MobileNet V1 0.25 image classification on the Coral NPU simulator.

Usage:
    bazel run //demos/npu_image_classification:run_on_npusim -- \
        --image /path/to/image.jpg

    # With comparison against host reference:
    bazel run //demos/npu_image_classification:run_on_npusim -- \
        --image /path/to/image.jpg \
        --compare /path/to/demos/image_classification/last_output.npy
"""

import argparse
import pathlib

from bazel_tools.tools.python.runfiles import runfiles
from coralnpu_v2_sim_utils import CoralNPUV2Simulator
import numpy as np
from PIL import Image

INPUT_SIZE = 224
NUM_CLASSES = 1000
TOP_K = 5


def load_labels(labels_path):
    return pathlib.Path(labels_path).read_text().strip().splitlines()


def preprocess_image(image_path):
    """Resize to 224x224 and convert uint8 [0,255] to int8 [-128,127]."""
    img = Image.open(image_path).convert("RGB")
    img = img.resize((INPUT_SIZE, INPUT_SIZE), Image.BILINEAR)
    pixels = np.array(img, dtype=np.int16) - 128
    return pixels.astype(np.int8).flatten()


def print_top_k(output_data, labels, k=TOP_K, prefix=""):
    top_k_indices = output_data.argsort()[-k:][::-1]
    print(f"\n{prefix}Top-{k} predictions:")
    for i, idx in enumerate(top_k_indices):
        print(f"  {i+1}. {labels[idx + 1]:30s}  (raw score: {output_data[idx]})")
    return top_k_indices


def compare_outputs(npu_output, host_output_path, labels):
    """Compare NPU simulator output against host CPU reference."""
    host_output = np.load(host_output_path)

    if host_output.shape != npu_output.shape:
        print(f"\n--- Comparison FAILED ---")
        print(f"Shape mismatch: host={host_output.shape}, npu={npu_output.shape}")
        return

    exact_match = np.array_equal(host_output, npu_output)
    diff = npu_output.astype(np.int16) - host_output.astype(np.int16)
    max_diff = np.max(np.abs(diff))
    num_differ = np.count_nonzero(diff)

    host_top5 = set(host_output.argsort()[-TOP_K:][::-1].tolist())
    npu_top5 = set(npu_output.argsort()[-TOP_K:][::-1].tolist())
    top5_match = host_top5 == npu_top5

    print(f"\n{'='*60}")
    print(f"  Comparison: NPU vs Host Reference")
    print(f"{'='*60}")
    print(f"  Host reference: {host_output_path}")
    print(f"  Byte-exact match:  {'YES' if exact_match else 'NO'}")
    print(f"  Max abs difference: {max_diff}")
    print(f"  Differing values:   {num_differ} / {NUM_CLASSES}")
    print(f"  Top-5 classes match: {'YES' if top5_match else 'NO'}")

    if not top5_match:
        only_host = host_top5 - npu_top5
        only_npu = npu_top5 - host_top5
        if only_host:
            print(f"  In host top-5 only: {[labels[i+1] for i in only_host]}")
        if only_npu:
            print(f"  In NPU top-5 only:  {[labels[i+1] for i in only_npu]}")

    if not exact_match and max_diff > 0:
        worst_idx = np.argmax(np.abs(diff))
        print(f"\n  Worst mismatch at class {worst_idx} ({labels[worst_idx+1]}):")
        print(f"    host={host_output[worst_idx]}, npu={npu_output[worst_idx]}, diff={diff[worst_idx]}")

    print(f"{'='*60}")


def main():
    parser = argparse.ArgumentParser(
        description="Classify an image on the Coral NPU simulator"
    )
    parser.add_argument("--image", required=True, help="Path to input image")
    parser.add_argument(
        "--compare",
        help="Path to host reference output (last_output.npy from classify.py)",
    )
    parser.add_argument(
        "--output",
        help="Save raw output array to this path (absolute recommended)",
    )
    parser.add_argument(
        "--elf",
        help="Override the ELF binary to load (absolute path)",
    )
    args = parser.parse_args()

    r = runfiles.Create()
    labels_path = r.Rlocation(
        "coralnpu_hw/demos/npu_image_classification/models/imagenet_labels.txt"
    )
    labels = load_labels(labels_path)

    input_data = preprocess_image(args.image)
    print(f"Input image: {args.image} (preprocessed to {INPUT_SIZE}x{INPUT_SIZE} int8)")

    npu_sim = CoralNPUV2Simulator(highmem_ld=True, exit_on_ebreak=True)
    if args.elf:
        elf_file = args.elf
    else:
        elf_file = r.Rlocation(
            "coralnpu_hw/demos/npu_image_classification/classify_npu_binary.elf"
        )
        if elf_file is None:
            elf_file = r.Rlocation(
                "coralnpu_hw/demos/npu_image_classification/classify_npu_scalar_binary.elf"
            )

    entry_point, symbol_map = npu_sim.get_elf_entry_and_symbol(
        elf_file, ["inference_status", "inference_input", "inference_output"]
    )
    npu_sim.load_program(elf_file, entry_point)

    if symbol_map.get("inference_input"):
        npu_sim.write_memory(symbol_map["inference_input"], input_data)
    else:
        print("ERROR: inference_input symbol not found")
        return

    print("Running simulation...", flush=True)
    npu_sim.run()
    npu_sim.wait()
    print(f"Simulation complete. Cycles: {npu_sim.get_cycle_count()}")

    if symbol_map.get("inference_status"):
        status = npu_sim.read_memory(symbol_map["inference_status"], 1)[0]
        if status != 0:
            print(f"ERROR: inference failed with status {status}")
            return

    if symbol_map.get("inference_output"):
        raw = npu_sim.read_memory(symbol_map["inference_output"], NUM_CLASSES)
        output_data = np.array(raw, dtype=np.uint8).view(np.int8)

        print_top_k(output_data, labels, prefix="NPU ")

        output_path = args.output if args.output else "npusim_output.npy"
        np.save(output_path, output_data)
        print(f"\nSaved raw output to {output_path}")

        if args.compare:
            compare_outputs(output_data, args.compare, labels)


if __name__ == "__main__":
    main()
