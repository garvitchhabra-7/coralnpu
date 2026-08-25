# Coral NPU — Scalar Core Simulation Instructions

Step-by-step build / simulation commands for the **scalar** `CoreMiniAxi`
variant (non-RVV). Two simulator flows are documented below: **Verilator** and
**VCS**. Pick one.

> Note: For simulation, Bazel auto-generates the RTL as a dependency of the sim
> target. The explicit RTL emit (Step 1 in each flow) is run anyway to
> sanity-check Chisel elaboration and to produce the `.sv` files for the later
> synthesis step.

---

# Flow A — Verilator

## A1 — Emit scalar RTL (SystemVerilog)

```bash
bazel build //hdl/chisel/src/coralnpu:core_mini_axi_cc_library_verilog
```

## A2 — Build the Verilator simulator (standalone, non-RVV)

```bash
bazel build //tests/verilator_sim:core_mini_axi_sim
```

## A3 — Build a test binary

```bash
bazel build //examples:coralnpu_v2_hello_world_add_floats
```

## A4a — Run the binary on the standalone simulator

```bash
bazel-bin/tests/verilator_sim/core_mini_axi_sim --binary bazel-out/k8-fastbuild-ST-dd8dc713f32d/bin/examples/coralnpu_v2_hello_world_add_floats.elf
```

A clean exit (code 0) with only the SystemC copyright banner and
`Simulation stopped by user` is normal — it means the binary ran to
completion successfully.

### Optional flags

Log each retired instruction to stdout:

```bash
bazel-bin/tests/verilator_sim/core_mini_axi_sim \
  --binary bazel-out/k8-fastbuild-ST-dd8dc713f32d/bin/examples/coralnpu_v2_hello_world_add_floats.elf \
  --instr_trace
```

Dump a waveform (FST format) to `/tmp/VCoreMiniAxi.core.fst`:

```bash
bazel-bin/tests/verilator_sim/core_mini_axi_sim \
  --binary bazel-out/k8-fastbuild-ST-dd8dc713f32d/bin/examples/coralnpu_v2_hello_world_add_floats.elf \
  --trace
```

Open the waveform in GTKWave:

```bash
gtkwave /tmp/VCoreMiniAxi.core.fst
```

## A4b — Run the cocotb regression suite (Verilator)

```bash
bazel run //tests/cocotb:core_mini_axi_sim_cocotb
```

---

# Flow B — VCS

> Notes:
> - The default `.bazelrc` excludes `vcs`-tagged targets (`-vcs` tag filter),
>   so `--config=vcs` is **required** on every VCS command.
> - The VCS cocotb targets are **prefixed** with `vcs_` (e.g.
>   `vcs_core_mini_axi_sim_cocotb`); the un-prefixed name is the Verilator
>   suite and its members aren't `vcs`-tagged, so `--config=vcs` excludes them
>   ("All specified test targets were excluded by filters").
> - `CCACHE_DISABLE=1` avoids ccache conflicts with VCS.
> - Use the **cocotb** VCS path, not `//tests/vcs_sim:core_mini_axi_sim` — the
>   standalone binary needs the proprietary `@synthesis_internal` TSMC libs.
>   The cocotb path uses behavioral SRAM + the backdoor loader instead.

## B0 — Load the VCS module

```bash
module load snps/vcs
```

## B1 — Emit scalar RTL (SystemVerilog)

```bash
bazel build //hdl/chisel/src/coralnpu:core_mini_axi_cc_library_verilog
```

## B2 — Build a test binary to run on the sim

```bash
bazel build //examples:coralnpu_v2_hello_world_add_floats
```

## B3 — Run the cocotb regression suite under VCS

Builds the VCS sim (pulls in the RTL from B1 automatically) and runs the full
scalar cocotb suite.

```bash
bazel test --config=vcs --action_env=CCACHE_DISABLE=1 //tests/cocotb:vcs_core_mini_axi_sim_cocotb
```

### Optional — run a single VCS testcase

VCS targets are named `vcs_core_mini_axi_sim_cocotb_<testcase>`. List them with:

```bash
bazel query '//tests/cocotb:vcs_core_mini_axi_sim_cocotb_*'
```

Then run one, e.g.:

```bash
bazel test --config=vcs --action_env=CCACHE_DISABLE=1 \
  //tests/cocotb:vcs_core_mini_axi_sim_cocotb_core_mini_axi_basic_write_read_memory
```
