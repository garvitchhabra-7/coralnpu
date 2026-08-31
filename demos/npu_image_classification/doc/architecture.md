# Architecture

How the C++ binary, Bazel build, and Python simulator driver fit together.

## The big picture

```
                        Bazel build
                            |
  .tflite model -----> generate_cc_arrays -----> model as C array
                            |
  classify_npu.cc -----> coralnpu_v2_binary -----> classify_npu_binary.elf
                            |                        (RISC-V ELF)
                            |
  run_on_npusim.py -----> loads ELF into npusim
       |                    |
   preprocesses         runs simulation
   image (PIL)          (~446M cycles)
       |                    |
   writes pixels        reads output
   to memory            from memory
       |                    |
       +-----> prints top-5 predictions
```

## The C++ binary (`classify_npu.cc`)

This runs _on the NPU_ (compiled to RISC-V). It's a bare-metal program that:

1. **Loads the model** — the `.tflite` bytes are embedded in the binary as a C array by `generate_cc_arrays`. At runtime, `tflite::GetModel()` wraps this array as a FlatBuffer.

2. **Registers 9 TFLite ops** — Conv2D and DepthwiseConv2D use the custom RVV-optimized kernels from `sw/opt/litert-micro/`. The other 7 use stock TFLite Micro.

3. **Reads input from a fixed buffer** — `inference_input[224*224*3]` is an `int8_t` array in `.data` (DTCM). The Python driver writes image pixels here before starting the CPU.

4. **Runs inference** — `interpreter.Invoke()` executes all 31 layers of MobileNet.

5. **Writes output to a fixed buffer** — `inference_output[1000]` is an `int8_t` array. The Python driver reads this after the CPU halts.

### Memory layout

| Symbol | Type | Section | Memory region | Size |
|---|---|---|---|---|
| `inference_input` | `int8_t[150528]` | `.data` | DTCM (0x00100000) | 147 KB |
| `inference_output` | `int8_t[1000]` | `.data` | DTCM | 1 KB |
| `inference_status` | `int8_t` | `.data` | DTCM | 1 byte |
| `tensor_arena` | `uint8_t[4MB]` | `.extdata` | EXTMEM (0x20000000) | 4 MB |
| model weights | `const unsigned char[]` | `.rodata` | ITCM (0x00000000) | ~597 KB |

The ITCM holds code and the embedded model weights (total ~700KB, fits in 1MB). DTCM holds the input/output buffers and stack. The tensor arena — TFLite Micro's working memory — is in external memory accessed over AXI.

## The BUILD file

Three Bazel rules do the work:

**`generate_cc_arrays`** — Converts the `.tflite` binary into a `.cc` file (a `const unsigned char[]`) and a matching `.h` header. The generated variable name is derived from the output filename (e.g., `mobilenet_v1_0_25_224_int8.h` → `g_25_224_int8_model_data`).

**`coralnpu_v2_binary`** — Cross-compiles for RISC-V with:
- `itcm_size_kbytes = 1024` / `dtcm_size_kbytes = 1024` — selects the "highmem" linker layout (DTCM at 0x00100000 instead of 0x00010000)
- `semihosting = True` — enables `printf` output via HTIF (Host-Target Interface)
- Produces `.elf`, `.bin`, and `.vmem` outputs

There are two binary targets:
- **`classify_npu_binary`** — uses RVV-optimized Conv2D/DepthwiseConv2D kernels
- **`classify_npu_scalar_binary`** — uses stock TFLite Micro reference kernels (passes `-DSCALAR_ONLY` via `copts`)

Both share the same `classify_npu.cc` source. The `#ifdef SCALAR_ONLY` blocks switch between the RVV and reference kernel registrations, and between `coralnpu_v2::opt::Memcpy` and `std::memcpy`.

**`py_binary`** — Two simulator driver targets (`run_on_npusim` and `run_on_npusim_scalar`), each bundling the corresponding ELF. The driver auto-detects which ELF is available in its runfiles.

## The Python driver (`run_on_npusim.py`)

This runs _on your PC_. It:

1. **Preprocesses the image** — PIL resizes to 224x224. Pixel values are converted from uint8 `[0, 255]` to int8 `[-128, 127]` by subtracting 128. This matches the model's quantization parameters (scale=0.00392, zero_point=-128).

2. **Boots the simulator** — `CoralNPUV2Simulator(highmem_ld=True, exit_on_ebreak=True)` creates an instance of the npusim software ISS (instruction-set simulator based on mpact-sim).

3. **Loads the ELF** — `load_program()` reads the ELF segments into the simulator's memory. Code goes into simulated ITCM, data into DTCM, and the `.extdata` section into a flat external memory region.

4. **Writes input pixels** — `write_memory(symbol_map["inference_input"], input_data)` copies the preprocessed image bytes to the address of the `inference_input` symbol.

5. **Runs** — `run()` / `wait()` executes until the CPU hits an `ebreak` instruction (the CRT's halt sequence).

6. **Reads results** — Reads 1000 bytes from `inference_output`, interprets as int8, finds the top-K indices, and maps to ImageNet labels.

### Label offset

The ImageNet labels file has 1001 entries (index 0 = "background"). The Keras-converted int8 model outputs 1000 classes with no background entry. So we offset by +1 when printing: `labels[idx + 1]`.

## The simulator: npusim

npusim is a software instruction-set simulator (ISS) built on the mpact-sim framework. It executes RISC-V instructions one at a time — no RTL, no timing, just functional correctness. It runs the same ELF binary that would run on real hardware or the RTL simulator.

Key properties:
- **Instruction-accurate**, not cycle-accurate
- **Fast**: ~446M instructions in minutes (vs hours for RTL)
- **Memory model**: flat (no bus protocol simulation)
- **Semihosting**: `printf` calls are intercepted and printed to the host terminal
