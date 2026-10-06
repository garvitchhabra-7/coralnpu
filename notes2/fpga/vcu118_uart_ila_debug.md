# VCU118 — Silent UART on ROM-Boot Bitstream (RESOLVED)

Opened 2026-10-05, resolved 2026-10-06. Read the **Working rules** before touching anything.

---

## Working rules (from the user)

- **Do not run Bazel builds, bitstream builds, or touch the board without asking.** Prepare file
  changes and hand the user the commands; the user runs them.
- The host `synthesia` is **shared**: three Digilent JTAG cables, other users' Vivado sessions.
  Always select the cable by serial **`210308B76D4D`** (scripts already do this).
- Run Verilator / RISC-V Bazel builds **inside the FHS shell** (`nix develop`), Vivado flows
  **outside** it after `module load Vivado/2025.2`.
- **Bazel actions run in the environment of the Bazel server, not of the client.** A server started
  inside FHS keeps running Vivado inside FHS even when `bazelisk` is typed outside
  (`hostname: command not found`, `libncurses.so.5` missing, `/etc/os-release` missing). A server
  started outside FHS breaks the RISC-V/Verilator builds (`exec: clang: not found`). Always
  `bazelisk shutdown` when switching environments. Check with
  `readlink /proc/<bazel-server-pid>/ns/mnt` vs `readlink /proc/self/ns/mnt`.
- Bitstream builds take ~3.5 h. Always do the elab check first:
  `bazelisk build //fpga:build_chip_vcu118_elab_only_highmem_rom`.
- After a build, archive outputs (`.bit`, `.ltx`, routed `.dcp`, timing/utilization/io reports,
  synth+impl `runme.log`, ROM `.vmem`) into `fpga/bitstreams/<name>/` (gitignored) — the Bazel
  cache is not safe storage. Since the Bzlmod switch, `bazel-bin` points to `execroot/_main`;
  `execroot/coralnpu_hw` holds only pre-Bzlmod leftovers.
- Watch disk space on `/` (899 GB, shared): a bitstream run leaves ~1.5 GB of checkpoints in the
  Bazel cache. At 100% full, tools fail with `ENOSPC`.

---

## Symptom

ROM-boot bitstream `fpga/bitstreams/vcu118_highmem_rom_2026-09-29/chip_vcu118.bit`
(`//fpga:build_chip_vcu118_bitstream_highmem_rom`, ROM = `fpga/sw/rom_hello_test.c`) programmed
fine, but **nothing at all** appeared on the board UART (`/dev/ttyUSB4`, 115200 8N1). LED0
(`io_halted`) and LED1 (`io_fault`) were off. The same `.vmem` printed correctly in the Verilator
ROM simulation.

## Root cause

`fpga/rtl/coralnpu_soc.sv` connected the autoboot FSM's reset to `rst_main_nqq` **before** that
signal was declared (~300 lines further down):

```systemverilog
if (EnableAutoboot) begin : gen_autoboot
  autoboot i_autoboot (.rst_ni(rst_main_nqq), ...);   // used here
end
...
logic rst_main_nq, rst_main_nqq;                      // declared here
```

- **Vivado** does not resolve the forward reference: it creates an undriven implicit net inside the
  generate block (`WARNING: [Synth 8-3848] Net gen_autoboot.rst_main_nqq ... does not have driver`).
  The FSM's reset is then held permanently, so Vivado removes the whole FSM (0 cells under
  `i_autoboot`) and the reset synchroniser. Autoboot never writes the CSR → the core stays
  clock-gated and in reset → no ROM fetch, no UART write.
- **Verilator** resolves the name to the real signal, so simulation worked.

Fix (commit "Fix autoboot reset forward reference"): declare `rst_main_nq/nqq` and its synchroniser
above `gen_autoboot`. The same file is used by `chip_nexus`, so the Nexus build had the same bug.

### Wrong inferences made during the hunt (don't repeat)

- **"LED0 off ⇒ core released."** Wrong. LED0 is `score/csr/halted_reg` (`Csr.scala`:
  `RegInit(false.B)`, set only by a halt instruction). A core held in reset also shows LED0 off.
  LED0 was on with the ITCM bitstream because that program finished and halted.
- **"The ROM is missing from the bitstream."** Wrong. With only 399 non-zero words, Vivado builds
  the 8192×32 ROM as LUT logic, and pushes those LUTs across the hierarchy into
  `xbar/deviceInterfaces_rom_bridge/req_fifo/mslice/`. Nothing remains under `i_rom` except the 32
  `rdata_o` flops + `rvalid`, and no BRAM appears in the utilization report.
- **"The Verilator sim hangs after `alive 0x00000000`."** It was only extremely slow: one heartbeat
  is 50 M cycles (sim clock table says 50 MHz), and two multithreaded sim instances on the loaded
  16-core host got ~120 M preemptions each. Run only one sim instance at a time.

## Result

Bitstream `fpga/bitstreams/vcu118_highmem_rom_2026-10-05/` (md5 `533785de…`) prints on `ttyUSB4`:

```
CoralNPU ROM boot OK
main clk MHz: 0x00000028
alive 0x00000000
alive 0x00000001      (once per second)
```

## Open items

Timing of the 2026-10-05 build (not the cause; placement changed between runs):

| Clock | WNS | Path | Relevance |
|---|---|---|---|
| sys clk → MIG clocks | −1.673 / −0.967 ns | MIG-internal reset synchroniser (`rst_async_riu_div` → `rst_*_sync_r[0]`) | Same in previous build (−1.49 ns), DDR calibration passed |
| `clk_main` (40 MHz) | −0.347 ns, 37 endpoints | `rvv_core/hostBridge/read_addr_q` → TCM BRAM `ADDRARDADDR` | Host (AXI) loads into TCM — matters for loading images/models |
| `mmcm_clkout0` (DDR UI, 300 MHz) | −0.687 ns, 58 endpoints | DDR TL→AXI converter → xbar DDR response FIFO | Matters once DDR is used |

Clean these up before relying on DDR / host loading for the MobileNet demo.

---

## Tools

### `fpga/inspect_routed_dcp.tcl` — offline netlist check (no hardware)

Opens a routed checkpoint and reports: what drives the autoboot FSM's reset pins, ROM
implementation (BRAM INIT vs `.vmem` bit-for-bit when it is in BRAM), UART1/clock-table presence and
the `uart_tx_o[1]` driver chain, and the ROM read path / `io_halted` / `io_fault` drivers.
Needs ~15–20 GB RAM.

```bash
vivado -mode batch -nojournal -nolog -source fpga/inspect_routed_dcp.tcl \
  -tclargs <chip_vcu118_routed.dcp> <rom.vmem> [report.txt]
```

A healthy build shows `state_q_reg` cells under `i_autoboot` whose CLR pins trace back to
`rst_main_nqq_reg`.

### If an ILA is needed later

Mark nets with `(* mark_debug = "true" *)` in `coralnpu_soc.sv` (guarded by a define such as
`VCU118_ILA`), insert the core in `fpga/vivado_pre_opt_hooks_vcu118.tcl` (`create_debug_core u_ila_0
ila`, clock `clk_main`), and read it over the existing JTAG cable (the MIG's `dbg_hub`). Useful
probes: autoboot `state_q`, `tl_rom_o_32.a_valid/a_address`, `rom_rdata`, `tl_uart1_o.a_valid/a_address`,
`uart_sideband_o[1].cio_tx`. Model a capture script on `fpga/check_ddr_vcu118.tcl`.

### Useful commands (user runs)

```bash
# Program (outside FHS, after `module load Vivado/2025.2`)
vivado -mode batch -source fpga/program_vcu118.tcl -tclargs <path/to/chip_vcu118.bit>

# DDR / liveness check (read-only)
vivado -mode batch -source fpga/check_ddr_vcu118.tcl -tclargs <path/to/chip_vcu118.ltx>

# UART console — open BEFORE programming (banner prints once at boot)
screen /dev/ttyUSB4 115200

# Simulation reference (inside FHS; one instance at a time)
bazel-bin/fpga/build.build_chip_verilator_highmem_rom/com.google.coralnpu_fpga_chip_verilator_0.1/sim-verilator/Vchip_verilator \
  +UARTDPI_LOG_uart1=uart1.log \
  --meminit=rom,$PWD/fpga/bitstreams/vcu118_highmem_rom_2026-09-29/rom_hello_highmem.vmem
```

## Related notes

- `notes2/fpga/vcu118_progress.md` — overall bring-up log
- `notes2/fpga/vcu118_ddr_check.md` — remote MIG check
- `notes2/fpga/vcu118_openocd_jtag_debug.md` — alternative visibility via the RISC-V debug module
  (needs an external adapter on PMOD0)
