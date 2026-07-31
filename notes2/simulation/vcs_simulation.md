# Simulating Design with VCS

All VCS commands require `--config=vcs` and a VCS license.

## Run Cocotb test suite

```bash
bazel test --config=vcs //tests/cocotb:vcs_core_mini_axi_sim_cocotb
```

### Run a single test case

```bash
bazel test --config=vcs //tests/cocotb:vcs_core_mini_axi_sim_cocotb_core_mini_axi_basic_write_read_memory
```

## Build a binary

```bash
bazel build //examples:coralnpu_v2_hello_world_add_floats
```

## Build the VCS simulator

```bash
bazel build --config=vcs //tests/vcs_sim:core_mini_axi_sim
```

## Run binary on VCS simulator

```bash
bazel-bin/tests/vcs_sim/core_mini_axi_sim +binary=bazel-out/k8-fastbuild-ST-dd8dc713f32d/bin/examples \ coralnpu_v2_hello_world_add_floats.elf
```

## Troubleshooting

```bash
# Workaround for ccache conflicts
bazel test --config=vcs --action_env=CCACHE_DISABLE=1 //...
```
