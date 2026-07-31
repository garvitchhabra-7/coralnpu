# Running the VCS Simulator with Verdi

VCS is a commercial RTL simulator from Synopsys. It requires a VCS license and appropriate environment variables to be set. Use `--config=vcs` to enable VCS targets (they are excluded from default builds via `.bazelrc`).

## 1. Build a RISC-V ELF

```bash
bazel build //examples:coralnpu_v2_hello_world_add_floats
```

The output ELF lands at:
```
bazel-bin/examples/coralnpu_v2_hello_world_add_floats.elf
```

## 2. Build the VCS Simulator

```bash
bazel build --config=vcs //tests/vcs_sim:core_mini_axi_sim
```

If you hit ccache conflicts (common when mixing VCS and Verilator builds):
```bash
bazel build --config=vcs --action_env=CCACHE_DISABLE=1 //tests/vcs_sim:core_mini_axi_sim
```

The VCS simulator target is defined in `tests/vcs_sim/BUILD`. There are two variants:

| Target | RTL module |
|---|---|
| `//tests/vcs_sim:core_mini_axi_sim` | `CoreMiniAxi` (scalar + float) |
| `//tests/vcs_sim:rvv_core_mini_axi_sim` | `RvvCoreMiniAxi` (+ RVV) |

## 3. Run the Simulation

Use `bazel run` (not `bazel-bin` directly) so the runner script can find its `_simv` binary and `.daidir` runfiles:

```bash
bazel run --config=vcs //tests/vcs_sim:core_mini_axi_sim -- \
  --binary=$(realpath bazel-bin/examples/coralnpu_v2_hello_world_add_floats.elf) \
  --trace
```

The runner script translates flags for VCS:
- `--binary=` becomes `+binary=`
- `--trace` becomes `+trace`

## 4. Open Verdi for Waveforms

```bash
verdi -dbdir bazel-bin/tests/vcs_sim/core_mini_axi_sim_simv.daidir
```

This gives you the full module hierarchy tree, signal browser, and schematic view. Load FSDB waveforms into Verdi's nWave window.

## 5. Running Cocotb Tests with VCS

Instead of the standalone simulator, you can run the cocotb test suite backed by VCS:

```bash
bazel test --config=vcs //tests/cocotb:core_mini_axi_sim_cocotb
```

Or a single testcase:
```bash
bazel test --config=vcs //tests/cocotb:core_mini_axi_sim_cocotb_<testcase_name>_vcs
```

The ccache workaround applies here too:
```bash
bazel test --config=vcs --action_env=CCACHE_DISABLE=1 //tests/cocotb:core_mini_axi_sim_cocotb
```

## Runtime Flags

| Flag | Effect |
|---|---|
| `--binary=<path>` | Path to ELF binary to execute |
| `--trace` | Enable FSDB waveform dumping |
| `--cycles=<N>` | Override cycle timeout (default: 100M cycles) |
| `+vcdfile+simulation.vcd` | Dump waveforms to VCD (pass as raw plusarg) |

## Related Files

| Path | Description |
|---|---|
| `tests/vcs_sim/BUILD` | VCS simulator Bazel targets |
| `tests/vcs_sim/top.sv` | Top-level VCS testbench wrapper |
| `.bazelrc` | `build:vcs` config definition |
| `rules/vcs.bzl` | VCS-specific Bazel rules |
