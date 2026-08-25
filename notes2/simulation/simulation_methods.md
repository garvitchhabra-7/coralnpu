# Simulation Methods

## RTL Simulation (Verilator)

Cycle-accurate simulation of the actual hardware. Chisel-generated SystemVerilog is compiled by Verilator into a fast C++ model. Every signal, flip-flop, and bus transaction is simulated as defined in the RTL.

Two ways to drive it:

- **Verilator sim** (`tests/verilator_sim/`): C++ testbench. Self-contained — load ELF, run to completion. Black-box.
- **Cocotb** (`tests/cocotb/`): Python testbench. Injects inputs and reads outputs via AXI. White-box.

See `verilator_simulation.md` and `vcs_simulation.md` for details.

## ISS — MPACT (Instruction Set Simulator)

Pure software model of the CPU, no RTL involved. Executes instructions functionally — much faster but not cycle-accurate.

- Lives in an external repo: `@coralnpu_mpact//sim:coralnpu_simulator`
- Exposed to Python via pybind: `sw/coralnpu_sim/coralnpu_v2_sim_pybind.cc`
- Python wrapper: `sw/coralnpu_sim/coralnpu_v2_sim_utils.py` (`CoralNPUV2Simulator` class)
- Supports stepping, breakpoints, register/memory read-write

Both implement the same abstract interface (`CoralNPUSimulator`) but with different backends.
