# Running the CoralNPU UVM Testbench

## Prerequisites

- Synopsys VCS with UVM 1.2
- Java 11+ (ANTLR in mpact-sim requires it)
- Bazel 7.4.1
- RISC-V toolchain (for building test ELFs)

## Java Version Setup

The mpact-sim dependency uses ANTLR which requires Java 11+. If your default
`java -version` shows 1.8, override it before running anything:

```bash
export JAVA_HOME=/usr/lib/jvm/java-11-openjdk-11.0.25.0.9-7.el9.x86_64
export PATH=$JAVA_HOME/bin:$PATH
```

You may get `WARNING: Ignoring JAVA_HOME, because it must point to a JDK, not a JRE.`
This is non-fatal — Bazel still picks up the Java 11 runtime, which is what ANTLR needs.
To eliminate the warning, install the full JDK: `sudo dnf install java-11-openjdk-devel`.

## Step 1: Build a Test ELF

```bash
cd /home/garvit/workspace/coralnpu

bazel build //tests/cocotb/tutorial:coralnpu_v2_program

mkdir -p tests/uvm/bin
cp bazel-bin/tests/cocotb/tutorial/coralnpu_v2_program.elf tests/uvm/bin/
```

Note: The default DUT variant (`RvvCoreMiniVerificationAxi`) has 8KB ITCM and
32KB DTCM. Make sure your ELF fits within those limits.

## Step 2: Compile the UVM Testbench

```bash
cd tests/uvm
make compile
```

This does three things:
1. Builds the MPACT co-simulation C++ library via Bazel
2. Generates the DUT RTL from Chisel (`RvvCoreMiniVerificationAxi.sv`)
3. Compiles everything with VCS into `sim_work/simv`

First compile takes a while (MPACT C++ build). Subsequent compiles are faster.

## Step 3: Run the Simulation

```bash
# Basic run (use absolute path for the ELF to avoid path issues)
make run TEST_ELF=$(pwd)/bin/coralnpu_v2_program.elf

# With more verbose UVM output
make run TEST_ELF=$(pwd)/bin/coralnpu_v2_program.elf UVM_VERBOSITY=UVM_HIGH

# With longer timeout (default is 100000 ns)
make run TEST_ELF=$(pwd)/bin/coralnpu_v2_program.elf TEST_TIMEOUT_NS=20000000

# Combined compile + run
make all TEST_ELF=$(pwd)/bin/coralnpu_v2_program.elf
```

### Available Makefile Variables

| Variable | Default | Description |
|---|---|---|
| `TEST_ELF` | `./bin/rvv_aadd_int16_m1.elf` | Path to the ELF binary to run |
| `UVM_TESTNAME` | `coralnpu_base_test` | UVM test class name |
| `UVM_VERBOSITY` | `UVM_MEDIUM` | `UVM_NONE` / `UVM_LOW` / `UVM_MEDIUM` / `UVM_HIGH` / `UVM_FULL` |
| `TEST_TIMEOUT_NS` | `100000` | Simulation timeout in nanoseconds |
| `MISA_VALUE` | `'h40201120` | Initial MISA CSR value |

## Step 4: Check Results

- Look for `** UVM TEST PASSED **` or `** UVM TEST FAILED **` at the end
- Detailed log: `sim_work/logs/<testname>.log`
- Waveforms (Verdi): `sim_work/waves/<testname>.fsdb`

To capture both stdout and stderr (C++ DPI errors go to stderr):

```bash
make run TEST_ELF=$(pwd)/bin/your.elf 2>&1 | tee sim_work/logs/full_output.log
```

## Running Regression Tests

The regression test runs multiple ELFs sequentially from a list file:

```bash
make run UVM_TESTNAME=coralnpu_regression_test \
         EXTRA_PLUSARGS="+REGRESSION_LIST=/path/to/regression_list.txt"
```

The regression list format is:
```
# ELF TOHOST ENTRY TIMEOUT SPIKE_LOG TARGET
/path/to/test1.elf 00010100 00000000 500000 NONE test1_name
/path/to/test2.elf 00010100 00000000 500000 /path/to/spike.log test2_name
```

## 3-Way Co-Simulation (with Spike)

```bash
make run_3way TEST_ELF=$(pwd)/bin/your.elf SPIKE_LOG=/path/to/spike.log
```

This enables the Spike trace checker in addition to MPACT, giving three-way
comparison: RTL vs MPACT vs Spike.

## Cleaning Up

```bash
make clean
```

This removes `sim_work/`, VCS artifacts, and cleans Bazel caches for both
the main repo and MPACT.

## Known Issues

### ELF path not reaching co-sim checker (fixed)

The `coralnpu_base_test` had a config_db key mismatch: it set `"elf_file_for_iss"`
but the cosim checker reads `"current_test_elf"`. Fixed by adding a
`current_test_elf` config_db entry in the base test's `build_phase`.
Without this fix, co-simulation silently runs with an empty ELF path
and reports `MPACT simulator DPI load program failed.`

### ccache conflicts with VCS

If compilation fails with ccache errors:

```bash
make compile CCACHE_DISABLE=1
```
