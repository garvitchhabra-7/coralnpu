# CoralNPU UVM Testbench Analysis

## Why UVM exists alongside cocotb

| | cocotb (Python + Verilator/VCS) | UVM (SystemVerilog + VCS only) |
|---|---|---|
| **Primary strength** | Fast iteration, easy to write | ISS co-simulation, coverage collection |
| **Simulator** | Verilator or VCS | VCS only |
| **Test approach** | Functional: load ELF, run, check output | Instruction-level: compare every retired instruction against ISS |
| **When to use** | Development-time verification | Signoff-quality verification |

The UVM testbench does two things cocotb does not:

1. **Instruction-level co-simulation** via RVVI trace port — compares GPR/FPR/VPR writebacks against MPACT and Spike ISS on every retired instruction.
2. **Functional coverage** — ~16K lines of covergroups across 7 ISA extensions (I, M, F, V, Zbb, Zicsr, Zifencei) track which instructions and operand combinations have been exercised.

## Architecture

```
coralnpu_tb_top
├── DUT: RvvCoreMiniVerificationAxi
│
├── coralnpu_env (UVM Environment)
│   ├── AXI Master Agent          ← drives DUT slave port
│   │   ├── Sequencer
│   │   ├── Driver
│   │   └── (no monitor)
│   │
│   ├── AXI Slave Agent           ← responds to DUT master port
│   │   ├── Slave Model (sparse memory + address decode)
│   │   └── (no monitor)
│   │
│   ├── IRQ Agent
│   │   ├── Sequencer
│   │   └── Driver (irq, te, halted, fault, wfi)
│   │
│   ├── RVVI Agent (passive)      ← watches RVVI trace port
│   │   ├── Monitor (decodes retired instructions)
│   │   ├── Coverage (per-ISA covergroups)
│   │   └── Instruction Decode + Transaction Factory
│   │
│   └── Co-Simulation Checker
│       ├── MPACT ISS (via DPI-C)
│       ├── Spike Trace Checker (optional)
│       ├── Dirty Register Tracker (mcycle/minstret taint propagation)
│       └── step_and_compare: GPR/FPR/VPR writeback verification
│
└── Tests
    ├── coralnpu_base_test        ← single ELF run
    └── coralnpu_regression_test  ← runs a list of ELFs sequentially
```

### Data flow

1. DUT retires instructions → RVVI trace port captures them
2. RVVI Monitor decodes and broadcasts to coverage collector + cosim checker
3. Cosim checker steps MPACT with the same instruction, compares writeback values
4. Dirty register tracker skips comparison for registers tainted by mcycle/minstret reads (which naturally diverge between RTL and ISS)

## UVM Concepts (for reference)

- **Agent**: A reusable bundle of driver + sequencer + monitor for one interface. Can be active (drives signals) or passive (observe only).
- **Sequencer**: Queues transaction objects and feeds them to the driver.
- **Driver**: Converts abstract transactions into pin-level signal wiggling.
- **Monitor**: Passively observes an interface and broadcasts what it sees via analysis ports.
- **Scoreboard**: Receives transactions from monitors and checks correctness. Missing here for AXI.
- **Functional coverage**: Defines bins of interesting scenarios and tracks which get hit during simulation. Answers "have we tested enough?"
- **config_db**: A global key-value store for passing configuration between UVM components.

## Quality Assessment

### Strengths

- **Co-simulation with dirty-register taint tracking**: Handles mcycle/minstret divergence by propagating taint through register dependencies and even stack spills/reloads. Non-trivial and well-designed.
- **Comprehensive per-ISA coverage model**: Covergroups decode and cross-cover instruction fields for all seven extensions.
- **Clean reset handling**: All agents handle mid-transaction resets with `disable fork` and re-initialization. Regression test resets DUT between ELFs correctly.
- **Slave model validates memory-map boundaries**: Flags internal ITCM/DTCM addresses that leak to the external AXI bus.

### Gaps

- **No AXI protocol monitors or scoreboards**: Neither AXI agent has a monitor. No independent observation of bus traffic, no protocol-compliance checking (signal stability during handshake, etc.).
- **No constrained-random stimulus**: All tests run pre-compiled ELFs. The AXI master agent could drive random reads/writes, back-pressure, and interleaving to stress the DUT.

### Notes

- **`uvm_config_db` used for runtime state**: Config DB is meant for build-time configuration. Runtime communication (e.g., `cosim_mismatch_detected`, `final_tohost_data`) would be more idiomatic via analysis ports or TLM FIFOs.
- **tohost monitor in procedural `tb_top`**: Would be more reusable as a proper UVM monitor component rather than an `initial` block.
- **WRAP burst not implemented**: The slave model handles FIXED and INCR bursts but treats WRAP as FIXED.

## Verdict

A solid intermediate-quality UVM testbench focused on instruction-level ISS co-simulation with comprehensive functional coverage. It complements cocotb (fast functional iteration) with deep correctness checking and coverage measurement needed for signoff.
