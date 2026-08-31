# Cocotb RTL Simulation — Findings for Future Work

Everything needed to run the MobileNet V1 0.25 image classification demo on the cycle-accurate RTL simulator (Verilator or VCS) instead of the npusim software ISS.

## What exists today

The npusim demo (`demos/npu_image_classification/`) runs the full model on the software ISS in ~446M cycles. The RTL path would use the same ELF binary but simulate it through the actual Verilog, giving cycle-accurate results.

### Existing cocotb pattern to follow

`tests/cocotb/tutorial/tfmicro/cocotb_run_mobilenet_v1.py` runs a partial MobileNet on RTL:

```python
fixture = await Fixture.Create(dut, highmem=True)
await fixture.load_elf_and_lookup_symbols(elf_path, ['inference_status', ...])
cycle_count = await fixture.run_to_halt(timeout_cycles=130_000_000)
result = await fixture.read_word('inference_status')
```

## Key files

| File | Role |
|---|---|
| `coralnpu_test_utils/sim_test_fixture.py` | `Fixture` class — creates DUT driver, handles highmem config |
| `coralnpu_test_utils/core_mini_axi_interface.py` | AXI driver, ELF loader, external memory simulation |
| `tests/cocotb/tutorial/tfmicro/cocotb_run_mobilenet_v1.py` | Reference cocotb test for TFLite Micro |
| `tests/cocotb/tutorial/tfmicro/BUILD` | BUILD patterns for cocotb test suites |

## RTL variant

Use `RvvCoreMiniHighmemAxi` — the RVV-enabled highmem variant with AXI master port. This is what the existing partial MobileNet test uses.

When `Fixture.Create(dut, highmem=True)` is called, it sets `csr_base_addr=0x200000` to match the highmem memory layout.

## How external memory works in RTL simulation

The tensor arena lives in `.extdata` at `0x20000000` (4MB region). In simulation:

1. **ELF loading**: The Python testbench checks each PT_LOAD segment. Segments in `[0x20000000, 0x20400000)` are loaded into a Python-side numpy array (`self.memory`), not into DUT SRAMs.
2. **Runtime**: The CPU's AXI master transactions are serviced by Python `memory_read_agent` / `memory_write_agent` that read/write `self.memory`. This is cycle-accurate — every access goes through the real AXI protocol in RTL.
3. **Testbench shortcuts**: `fixture.read()` / `fixture.write()` bypass AXI for direct numpy access (for loading input data and reading results).

## What to adapt

1. **New cocotb test** in `demos/npu_image_classification/`:
   - Load `classify_npu_binary.elf`
   - Write preprocessed image data (int8, 224x224x3) to `inference_input` symbol
   - `run_to_halt(timeout_cycles=600_000_000)` — budget ~600M cycles (npusim took 446M, RTL may differ slightly)
   - Read `inference_output` (1000 bytes, int8) and verify top-K classes

2. **BUILD rules**: Follow the pattern in `tests/cocotb/tutorial/tfmicro/BUILD`:
   - `verilator_cocotb_model` for the RTL model
   - `cocotb_test_suite` with `highmem=True` variant
   - Tag as `manual` and `enormous` (this will be very slow)

3. **Image preprocessing**: Either embed a test image as a numpy array in the Python test, or load from a file via runfiles.

## Performance expectations

- The partial MobileNet (2 layers) takes ~130M cycles on RTL
- Full MobileNet took 446M cycles on npusim
- RTL simulation wall-clock: expect **hours** on Verilator, faster on VCS
- Tag the test `manual` so it doesn't run in CI by default

## Input format

The int8 model expects input quantized as: `int8_value = uint8_pixel - 128`. The `inference_input` buffer is `int8_t[224*224*3]` in `.data` (DTCM). The `inference_output` buffer is `int8_t[1000]` also in DTCM. The 4MB tensor arena is in `.extdata` (AXI external memory).

## Differences from npusim path

| | npusim | cocotb RTL |
|---|---|---|
| Simulator | Software ISS (mpact-sim) | Verilator or VCS |
| Speed | Minutes | Hours |
| Accuracy | Instruction-accurate | Cycle-accurate |
| Memory model | Flat | Real AXI bus protocol |
| Image loading | `npu_sim.write_memory()` | `fixture.write()` / backdoor |
| Output reading | `npu_sim.read_memory()` | `fixture.read()` / `fixture.read_word()` |
