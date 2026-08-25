# RTL Frontend Signoff Checklist

Checklist for RTL/logic design frontend verification before tapeout.

## Already in Place

- RTL lint via VCS (`--config=vcs` lint target)
- Functional simulation: cocotb (Verilator + VCS), Chisel unit tests
- Verilog emission: Chisel to SystemVerilog pipeline working

## Lint Hardening

- Consider running Spyglass Lint or Ascent Lint in addition to VCS lint (catches synthesis vs. simulation mismatches, STARC rules, foundry-specific rule decks)
- Treat all warnings as errors before tapeout
- Key categories: inferred latches, width mismatches, multi-driven nets, undriven signals, case statement defaults

## CDC / RDC

- Audit for clock-domain crossings (AXI interface clock vs. core clock, DMA engine, etc.)
- If crossings exist, run Spyglass CDC or equivalent
- Verify synchronizers, gray-coded FIFOs, pulse stretchers
- Reset-domain crossings need similar analysis

## Formal Verification

- **Bus protocol compliance**: prove AXI4 and TileLink-UL interfaces never violate protocol (no response without request, no overlapping IDs violating ordering)
- **Deadlock freedom**: especially in `TlulSocket1N`, `TlulSocketM1`, and the DMA engine
- **Pipeline invariants**: scoreboard never loses a hazard, fetch never issues to a stalled decode, CSR read/write atomicity
- **Equivalence checking**: Chisel to SystemVerilog output matches intent (especially after any manual edits to generated Verilog)

## X-Propagation

- Run simulation with x-prop mode (VCS `-xprop` or Verilator `--x-assign`)
- Catches uninitialized registers, reset sequencing bugs, undefined behavior on first boot
- A common source of silicon bugs that behavioral sim masks

## Synthesis Trial Runs

- Run Design Compiler or Yosys (for open PDK) early and iteratively to catch:
  - Constructs that don't map (Chisel sometimes emits simulation-only patterns)
  - Unreachable logic / constant propagation surprises
  - Gross area/timing feasibility at target node
- Define SDC constraints early: clock definitions, IO delays, false/multicycle paths, clock groups

## STA Prep

- Write SDC file: clock period, input/output delays, load/drive assumptions
- Identify multicycle paths (e.g., divider unit `Dvu.scala`, multi-cycle multiplier) and constrain properly
- Identify false paths (e.g., configuration registers static after reset)

## Coverage Closure

- Measure code coverage (line, branch, toggle, FSM) on existing test suite
- Target >95% on all metrics; investigate uncovered logic for dead code or missing tests
- Toggle coverage on ports is especially important: untoggled signals may indicate unexercised hardware

## Gate-Level Simulation

- After synthesis, re-run a subset of cocotb tests on the post-synthesis netlist with SDF timing back-annotation
- Catches synthesis tool misinterpretations and timing-dependent functional bugs

## Suggested Order

1. Lint cleanup (fast, high ROI)
2. X-prop simulation (reuses existing tests)
3. Coverage measurement (reuses existing tests)
4. CDC/RDC analysis (blocks everything if crossings exist)
5. Formal on bus protocols (highest-risk logic)
6. Trial synthesis + SDC constraints
7. Gate-level sim
