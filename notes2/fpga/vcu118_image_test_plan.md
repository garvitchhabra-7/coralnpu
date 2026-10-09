# VCU118 — Image Tests (Phase 8): Handoff

Written 2026-10-07, rewritten 2026-10-09 for the agent picking this up. The program-loading problem
is solved; the next job is running MobileNet on the board.

## Working rules

**First read the "Working rules" section of `notes2/fpga/vcu118_uart_ila_debug.md`.** In short:
- Don't run Bazel or bitstream builds, Vivado, or touch the board without asking the user. Prepare
  the changes and give the user the commands.
- Verilator/RISC-V builds run inside the FHS shell; Vivado runs outside it. Run
  `bazelisk shutdown` when switching between the two.
- The host `synthesia` is shared. Always select the JTAG cable by serial **`210308B76D4D`**.
- Do the elab check (`bazelisk build //fpga:build_chip_vcu118_elab_only_highmem_rom`) before any
  3.5 h bitstream build. Build and archive in one step with
  `bazelisk run //fpga:archive_chip_vcu118_bitstream_highmem_rom`
  (→ `fpga/bitstreams/vcu118_highmem_rom_<build time>/`).
- **Commit messages: no links of any kind.** No `Claude-Session: https://...` trailer, no URLs.
  The user had them stripped from the whole branch on 2026-10-09. `Co-Authored-By:` is fine.
- The user prefers 115200 baud for the UART loader (known to work). Don't switch the default.

---

## Where things stand (2026-10-09)

| | |
|---|---|
| Board bitstream | `fpga/bitstreams/vcu118_highmem_rom_2026-10-07_183310/`: ROM UART loader, group A timing fix |
| Program loading | **Works on the board.** `fpga/uart_loader.py` loads ELFs into ITCM/DTCM and raw files into SRAM/DDR over `/dev/ttyUSB4` at 115200 (~11 KB/s), checks every region with a read-back CRC, starts the program and shows its output. See `vcu118_uart_loader.md` |
| Board tests passed | hello program (ITCM+DTCM), 256 KB random data → DDR with CRC, CPU_RESET → reload |
| Core | `RvvCoreMiniHighmemAxi` (RVV enabled), `clk_main` 35 MHz (clock table reports 35) |
| Memory | ITCM 1 MB @ `0x00000000`; DTCM 1 MB @ `0x00100000` (**top 64 KB, `0x001F0000`+, belongs to the loader**: never put loadable data there); ROM 32 KB @ `0x10000000`; SRAM 4 MB @ `0x20000000`; DDR4 2 GB @ `0x80000000` |
| DDR calibration | `gpio_i[0]` (GPIO `DATA_IN` at `0x40030000`, bit 0). The loader refuses DDR until it's set. A program that touches DDR itself must poll it first |
| Timing | Not met: WNS −1.557 ns, 614 endpoints, all in the DDR/MIG side (groups B and C in `vcu118_timing_fixes.md`) |

Workflow for every run: program the FPGA once (`fpga/program_vcu118.tcl`), then
`python3 fpga/uart_loader.py --elf <prog.elf> [--data <file>@<addr>]`. After a program finishes the
core halts: press **CPU_RESET** to get the loader back. No bitstream rebuild is needed for software
changes.

## Next task: MobileNet v1 on the board

### What exists

| Item | Where |
|---|---|
| Trained MobileNet v1 0.25 224 int8 (597 KB), labels, test image | `demos/image_classification/models/`, `demos/image_classification/test_images/grace_hopper.jpg` |
| TFLite Micro runner for the software simulator (npusim) | `demos/npu_image_classification/classify_npu.cc`, target `classify_npu_binary` (1 MB/1 MB TCM, RVV-optimised conv kernels; `classify_npu_scalar_binary` = reference kernels). Measured on npusim: ~446 M cycles (RVV), ~653 M (scalar) |
| Image preprocessing and top-5 printing | `demos/npu_image_classification/run_on_npusim.py`: `preprocess_image()` (resize 224×224 bilinear, uint8 − 128 → int8, flattened HWC), `print_top_k()` (labels are offset by one: `labels[idx + 1]`) |
| Host reference result | `demos/image_classification/classify.py`, `demos/npu_image_classification/compare.py` |
| Board helpers | `fpga/sw/uart.h` (UART1 console), `clk.h` (clock table), `gpio.h` (DDR calibration bit); `fpga/sw/uart_loader_hello.c` is a minimal loaded program |

At 35 MHz, 446 M cycles is about **13 s per image** (RVV). Scalar would be about 19 s.

### Step 1: an FPGA version of the runner

Add `fpga/sw/mobilenet_vcu118.cc` with its target in `fpga/BUILD`. The `fpga/sw` libraries are
private to `fpga/`, so keep the target there, with `dtcm_size_kbytes = 1024` and
`itcm_size_kbytes = 1024`. Start from `classify_npu.cc` and change:

1. **Console:** `printf` doesn't reach the board UART. Call `uart_init()` and print with
   `uart_puts` / `uart_puthex32`. Print, in this order:
   - a banner;
   - `interpreter.arena_used_bytes()` after `AllocateTensors()`;
   - `mcycle` before and after `Invoke()` (read the CSR as in `fpga/sw/rom_ddr_test.c`);
   - the top-5 class indices with their int8 scores, and the input buffer's CRC32 so the host can
     check that the image arrived intact;
   - a final `MOBILENET DONE` line for `--expect`.
2. **Input image from DDR:** don't keep `inference_input` in `.data`.
   - Read the image from a fixed DDR address, e.g. `0x80100000`, 150528 bytes of int8 HWC.
   - Poll `gpio_read() & 1` first. Touching DDR before calibration hangs the crossbar.
   - The host loads the image with `--data image.bin@0x80100000`, and the loader verifies it with a
     read-back CRC.
3. **Keep large zero buffers out of the ELF's loaded data.** `uart_loader.py` sends every
   `PT_LOAD` segment's file contents. A zero-initialised array with
   `__attribute__((section(".extdata")))` or `section(".data")` is (very likely) stored in the
   ELF as real zeros. The 4 MB arena would then take about 6 minutes to send.
   - Put the arena in **`.extbss`** (NOLOAD, in SRAM).
   - Put other scratch buffers in `.bss` / `.noinit`.
   - Check with `readelf -lW <elf>` that the `FileSiz` of every segment is small. Expect about
     597 KB of model plus a few hundred KB of code in ITCM.
   - Note that the CRT clears only the DTCM `.bss`. Nothing clears `.extbss`; TFLite Micro doesn't
     need a zeroed arena.
4. **Arena size:** start at 2 MB in `.extbss`, then shrink to `arena_used_bytes()` plus margin once
   it's measured. If it fits in about 900 KB, try DTCM (`.bss`) as well: faster, and it decides
   the SRAM size question below.
5. **Model:** keep it compiled in (`mobilenet_v1_0_25_224_int8_lib`, `.rodata` → ITCM). It linked
   into 1 MB of ITCM for npusim with the same TCM sizes. If the link fails with
   `region ITCM overflowed`, put the model array in `.ddr_data` (loaded to DDR automatically), or
   load the `.tflite` with `--data` into DDR and pass its address to `tflite::GetModel`.
6. **Kernels:** use the RVV path (the board core has RVV). If results look wrong, rebuild with
   `-DSCALAR_ONLY` and compare. That separates kernel problems from memory or DDR problems.

### Step 2: host side

1. **Preprocessing:** write a small script, e.g. `fpga/mobilenet_prep.py`, that reuses
   `preprocess_image()` and writes the int8 image as a raw `.bin`. The host's `/usr/bin/python3`
   (3.6) has no PIL/numpy. Either run the script in the demos' Python environment
   (`demos/*/pyproject.toml`) or in Nix, or produce the `.bin` files once and keep them.
   `uart_loader.py` itself must stay stdlib-only.
2. **Run** (user runs it on the board):
   ```bash
   D=bazel-out/k8-fastbuild-ST-dd8dc713f32d/bin/fpga   # find -L bazel-out -name '<target>.elf' if it moved
   python3 fpga/uart_loader.py --elf $D/mobilenet_vcu118.elf \
     --data grace_hopper.bin@0x80100000 --expect "MOBILENET DONE" --monitor 120
   ```
   Loading takes about 1–2 min (the model's ~600 KB in ITCM plus the 150 KB image).
3. **Check:** map the printed top-5 indices to `imagenet_labels.txt` (index + 1) and compare them
   with the host reference (`demos/image_classification/classify.py` on the same image). The scores
   should match npusim exactly (both run the same kernels on the same int8 input).
4. **Later, several images per load:** loop over N images at consecutive DDR addresses, so the
   model is loaded only once.

### Step 3: decisions to bring back to the user

1. **SRAM size.** Report the measured `arena_used_bytes()`. Shrinking the 4 MB SRAM (VCU118 build
   only) is the planned fix for timing group B. The size must change consistently in
   `hdl/chisel/src/soc/SoCChiselConfig.scala:265`, `hdl/chisel/src/soc/CrossbarConfig.scala:118`,
   `SRAM_END` in `fpga/sw/rom_uart_loader.c`, `SRAM` in `fpga/uart_loader.py`, and `EXTMEM` in
   `toolchain/coralnpu_tcm.ld.tpl` (shared: VCU118 builds need their own value, so don't break the
   cocotb tests that use 4 MB). Ask the user before changing anything.
2. **Which images to demo.** Only `grace_hopper.jpg` exists.

### Don't

- Don't run the full MobileNet in the Verilator FPGA sim. It runs at about 2,300 cycles/s, so one
  inference (~446 M cycles) would take days. Debug logic on npusim (`run_on_npusim`), then go
  straight to the board.
- Don't change the ROM loader or rebuild the bitstream for this task. Everything above is software
  loaded over UART.

## Timing work (parallel, lower priority)

See `vcu118_timing_fixes.md`, section "Status (2026-10-09)". The open lead:
`impl_runme.log` of the 2026-10-07 build shows `CRITICAL WARNING [Vivado 12-4739]` for
`set_false_path` / `set_max_delay` in the MIG's own `ddr_system_bd_ddr4_0_0.xdc` (lines 257, 258,
277, ...). Their `*/*/*/*/*/...` pin patterns don't match the MIG's depth in our hierarchy, so
some MIG timing exceptions aren't applied. That probably explains group C and may account for part
of group B. You can investigate this read-only on the routed checkpoint, without a build.

## Risks

- **DDR data path is not timing-clean (group B).** The loader's read-back CRC covers loaded data.
  If inference results look wrong, first rerun the 256 KB DDR CRC test from
  `vcu118_uart_loader.md`, and compare with an input placed in DTCM instead of DDR.
- **Don't touch `0x80000000` before calibration:** an early access hangs the crossbar.
- **The loader banner prints once,** at configuration or after CPU_RESET. It doesn't matter for
  loading: `uart_loader.py` doesn't need it.
- **Only one program may hold `/dev/ttyUSB4`.** Close `screen` before running `uart_loader.py`.

## History: how loading was chosen (2026-10-07)

The options were an FTDI MPSSE adapter with `nexus_loader` over SPI (no adapter on hand), a
JTAG-to-AXI master in the DDR block design (IP regeneration, Vivado for every load), or baking
everything into ROM (a 3.5 h rebuild per change). The user chose a fourth option, the ROM UART
loader: no new hardware, no block design change. If faster loading is ever needed, the SPI path
(`spi2tlul` can reach TCMs, SRAM and DDR; details in `vcu118_progress.md`, "7.4 `nexus_loader`")
is still available with an FT232H on PMOD1 (`spi_clk_i` N28, `spi_csb_i` M30, `spi_mosi_i` N30,
`spi_miso_o` P30).
