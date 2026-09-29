# VCU118 — OpenOCD / GDB over the RISC-V Debug Module (PMOD0 JTAG)

Status: **analysis only, not tested.** Written 2026-09-29 from the RTL and OpenOCD's
`src/target/riscv/riscv-013.c` (master). Upstream has no OpenOCD config and only tests the debug
module in cocotb by driving the DMI directly — never through the JTAG DTM, never with OpenOCD.

Primary load path remains the SPI slave + `nexus_loader` (see `vcu118_progress.md`). This is the
fallback, and the only path that gives GDB (breakpoints, single-step).

---

## Debug path in the current bitstream

```
PMOD0 pins ──> dmi_jtag (pulp riscv-dbg, JTAG DTM, IDCODE 0x04f5484d, IR len 5)
            ──> dm_req / dm_rsp ──> coralnpu_soc io_dm_* ──> Chisel DebugModule
                                                            (hdl/chisel/src/coralnpu/scalar/Debug.scala)
```

`chip_vcu118.sv` instantiates `dmi_jtag`; no rebuild needed to use it.

---

## What the Chisel DebugModule supports

| OpenOCD needs | CoralNPU | Where |
|---|---|---|
| `dmstatus.version` 2 (0.13) or 3 (1.0) | reports **3** ✓ | `Debug.scala` dmstatus |
| `dmcontrol`, `dmstatus`, `hartinfo`, `abstractcs`, `command`, `data0`, `data1`, `sbcs` | implemented ✓ | `DebugModuleAddress` |
| haltreq / resumereq / resumeack / ndmreset | ✓ | |
| Single step, breakpoints, triggers | ✓ — covered by `tests/cocotb/core_mini_axi_debug.py` | |
| Access Register (cmdtype 0): GPR `0x1000+`, FPR `0x1020+`, CSR `0x000-0xfff` | ✓, 32-bit only (`aarsize=2`) | 64-bit probe → `cmderr=2`, OpenOCD falls back to XLEN 32 |
| CSRs OpenOCD reads: `misa`, `dcsr`, `dpc`, `tselect`, `tdata1`, `tinfo`, `vlenb` | implemented | `Csr.scala` |
| Unknown CSR | reads 0, completes (`csr.io.rd.valid := req.valid`) — no hang | `Csr.scala:861` |
| Access Memory (cmdtype 2), `aamsize` 0/1/2, `aampostincrement` | ✓ **ITCM + DTCM only** | |
| Program buffer | **none** (`progbufsize = 0`) | |
| System Bus Access | **none** (`sbcs` reads 0 → sbversion 0) | |
| `abstractauto`, `haltsum*`, `nextdm`, `dmcs2`, `progbuf*` | **not implemented** | |

OpenOCD's memory access order is progbuf → sysbus → abstract; the first two are absent, so it will
use abstract memory commands.

---

## Limitations and risks

1. **Memory access is ITCM/DTCM only.** Any other address sets `cmderr = 5` (`Debug.scala:273`).
   DDR (`0x80000000`), peripherals (UART, CSR block, DMA) are **not** reachable from the debugger.
   GDB `load` into ITCM/DTCM works; data in DDR must be written by the program itself.
2. **Unimplemented DM registers answer `BUSY`** (default in the response mux). `dmi_jtag.sv` turns
   `DTM_BUSY` into a sticky `DMIBusy`; OpenOCD will back off and retry forever. From OpenOCD source,
   the only extra registers it would touch are:
   - `progbuf0` — only if `progbufsize > 0` (ours is 0) → safe
   - `nextdm` — only with a custom `-dbgbase` → **do not set**
   - `dmcs2` — only for SMP / halt groups → **do not configure SMP**
   `haltsum*` and `abstractauto` are not used by OpenOCD's abstract paths.
3. **OpenOCD will count 2 harts.** `LegalizeDmcontrol` clamps `hartsel` to `Min(x, 1)`, so
   hartsellen reads as 1, and `anynonexistent` is hardwired 0, so the enumeration loop
   (`for i <= hartsel`) never stops early. Configure a single target on hart 0 (`-coreid 0`);
   expect a warning, should be harmless (DM has `nHart = 1`).
4. **Register / CSR access while the core is running hangs the DMI.** Completion for CSR reads needs
   `io.csr_rd.valid`, which needs a CSR request, which is gated on `halted`; scalar writes likewise.
   `cmderr=4` is set, but `busy` never clears → `req.ready` never → DMI busy forever. OpenOCD halts
   before register access, so normal use is fine; never force register access on a running target.
   (Abstract *memory* reads while running complete but return stale `data0`.)
5. **TCK ≤ 500 kHz.** `pins_vcu118.xdc` constrains `tck_i` at 2000 ns. Load time ≈ 2 DMI scans per
   32-bit word → roughly 1 minute per MB. Fine for test programs.
6. **Not proven.** First real test will be on hardware.

---

## Wiring — C232HM-DDHSL-0 (same cable as for SPI) → PMOD0 (J53)

| C232HM wire | FTDI pin | Signal | FPGA pin | Net |
|---|---|---|---|---|
| orange | ADBUS0 | TCK | AY14 | PMOD0_0 |
| brown | ADBUS3 | TMS | AY15 | PMOD0_1 |
| yellow | ADBUS1 | TDI → `td_i` | AW15 | PMOD0_2 |
| green | ADBUS2 | TDO ← `td_o` | AV15 | PMOD0_3 |
| grey | ADBUS4 (GPIOL0) | TRST (drive **high**) | AV16 | PMOD0_4 |
| black | GND | ground | — | GND |
| red | VCC | **leave unconnected** | — | — |

- **TRST must be driven high.** `trst_ni` (AV16) has no `PULLTYPE` in the XDC; floating low holds the
  TAP in reset. TCK/TMS/TDI/TDO have `PULLDOWN`.
- PMOD0 is bank 67, `LVCMOS18`, nets named `*_LS` (level-shifted). Header-side voltage and the
  header pin numbering are **unverified** — check J53 in UG1224. With the standard Digilent layout,
  PMOD0_0..3 = pins 1–4, PMOD0_4 = pin 7, GND = pin 5/11.
- PMOD0_5..7 (AU16/AT15/AT16) were the SPI-flash pins; those ports are removed, pins unused.

---

## OpenOCD config (draft, untested)

OpenOCD is not installed on this host; available via Nix (`nix-shell -p openocd`). Needs the same
`dialout` group membership as `nexus_loader`.

```tcl
# vcu118_coralnpu.cfg — CoralNPU debug module over PMOD0, C232HM-DDHSL-0
adapter driver ftdi
ftdi vid_pid 0x0403 0x6014
ftdi channel 0
# REQUIRED on this shared host: three Digilent JTAG cables share 0403:6014
adapter serial <C232HM-serial>

# ADBUS0 TCK, 1 TDI, 2 TDO, 3 TMS, 4 GPIOL0 = TRST
#               value  direction
ftdi layout_init 0x0018 0x001b
ftdi layout_signal nTRST -data 0x0010

transport select jtag
adapter speed 500

jtag newtap coralnpu cpu -irlen 5 -expected-id 0x04f5484d
target create coralnpu.cpu riscv -chain-position coralnpu.cpu -coreid 0

# Abstract commands only: no progbuf, no system bus
riscv set_mem_access abstract
# Do NOT: -dbgbase, SMP / target smp, halt groups

gdb_port 3333
init
halt
```

Usage sketch:
```bash
openocd -f vcu118_coralnpu.cfg
riscv32-unknown-elf-gdb trivial_pass_test.elf \
  -ex 'target extended-remote :3333' -ex 'load' -ex 'continue'
```

Before trusting it:
- Check the ELF only has sections in ITCM (`0x0`) / DTCM (`0x100000` highmem) — anything else fails.
- Confirm the `ftdi layout_init` / nTRST lines match the C232HM (GPIOL0 = ADBUS4).
- Expect the 2-hart warning.

---

## Program load: JTAG debug vs. SPI

| | SPI slave (`nexus_loader`) | JTAG debug (OpenOCD) |
|---|---|---|
| Header | PMOD1 (J52) | PMOD0 (J53) |
| Write ITCM / DTCM | ✓ | ✓ |
| Write DDR / peripherals | ✓ (full TL-UL access) | ✗ |
| Start core | `--set_entry_point --start_core` | `load` + `continue` (sets `dpc`) |
| Breakpoints / step / register view | ✗ | ✓ |
| Speed | up to 30 MHz SCK (VCU118: ≤ 12 MHz, needs `--spi_divisor`) | ≤ 500 kHz TCK |
| Tested upstream | ✓ (Nexus, `trivial_pass_sim_test`) | ✗ |
| Tool fixes needed | `--pid`, `--spi_divisor`, Nix build | OpenOCD config only |
