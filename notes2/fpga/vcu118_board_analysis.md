# VCU118 Board Analysis for CoralNPU

## Verdict

**Strong fit — no architectural compromises, 2–4 days porting effort.**

The VCU118 (XCVU9P) is an excellent match for prototyping the CoralNPU. Same FPGA family as the Nexus board means zero primitive porting risk. Resources are massively overprovisioned. The only real constraint — 2 PMODs instead of 4 — is cleanly mitigated by FMC connectors.

## Board Specs

- **FPGA**: XCVU9P-L2FLGA2104E (Virtex UltraScale+, -2 speed grade)
- **LUTs**: 1,182,240
- **Flip-Flops**: 2,364,480
- **36Kb BRAM**: 2,160
- **URAM (288Kb)**: 960
- **DSP48E2**: 6,840
- **DDR4**: 2× 2.5 GB channels (component-based, 5× Micron MT40A256M16GE per channel, 80-bit = 64-bit data + 16-bit ECC)
- **PMOD**: 2 headers (J52, J53) — LVCMOS18 on FPGA side, 3.3V level shifted
- **FMC**: FMC+ HSPC (80 diff pairs + GTY) + FMC HPC1 (58 diff pairs)
- **UART**: 2-channel USB-to-UART bridge (Silicon Labs CP2105)
- **JTAG**: 14-pin header + Zynq-7000 system controller (XC7Z010)
- **SPI Flash**: Dual 1 Gb QSPI (Micron MT25Q, rev 2.0+ boards)
- **Clocks**: SI5335A (100 MHz diff pair), Si570 programmable (156.25 MHz default), 300 MHz DDR4 ref
- **GPIO**: 8 user LEDs, 5 pushbuttons, 4 DIP switches

## FPGA Family Compatibility

Both the VCU118 (XCVU9P) and the Nexus (XCVU13P) are Virtex UltraScale+ with -2 speed grade. Every Xilinx primitive used by the design is identical:

| Primitive | Used In | Purpose |
|---|---|---|
| `STARTUPE3` | `chip_nexus.sv` | SPI flash configuration, startup sequencing |
| `MMCME2_ADV` | `clkgen_xilultrascaleplus.sv` | Clock management (100MHz → 50/100/1 MHz) |
| `BUFGCE` | `clkgen_xilultrascaleplus.sv` | Clock output buffers |
| `IBUFDS` | `clkgen_xilultrascaleplus.sv` | Differential input buffer |
| `IOBUF` | `chip_nexus.sv` | Tri-state GPIO and I2C |
| `DSP48E2` | FPU, vector MUL/FALU | Multiply-accumulate |

The packages differ (FLGA vs FHGA) — **not pin-compatible**, but this only affects the XDC constraint file, not any RTL.

## Resource Utilization Estimate

For the full RVV-enabled design with highmem (1MB ITCM + 1MB DTCM):

| Resource | Available | Estimated Need | Utilization |
|---|---|---|---|
| CLB LUTs | 1,182,240 | ~80,000 | ~7% |
| Flip-Flops | 2,364,480 | ~80,000 | ~3% |
| 36Kb BRAM | 2,160 | ~560 | ~26% |
| URAM (288Kb) | 960 | 0 | 0% |
| DSP48E2 | 6,840 | ~120 | ~2% |

### BRAM Breakdown (binding constraint)

| Consumer | BRAMs |
|---|---|
| ITCM 1 MB (128-bit wide) | ~256 |
| DTCM 1 MB (128-bit wide) | ~256 |
| Boot ROM 32 KB | ~16 |
| L1I + L1D caches (256 slots × 4-way) | ~32 |
| **Total** | **~560 / 2,160** |

The vector register file (32 × 128-bit) is flip-flop-based (byte-enable FFs in `rvv_backend_vrf_reg.sv`), not BRAMs. DSP usage comes from scalar FPU, 2× vector MUL, 2× vector FALU (FPnew FMA).

**Optimization opportunity**: The 960 URAMs (288Kb each, totaling ~34 MB) are completely unused. Migrating TCMs from BRAM to URAM would free ~500 BRAMs, but requires RTL changes to the memory wrapper.

**SLR note**: The XCVU9P has 3 SLRs. The entire design fits in a single SLR. If Vivado spreads placement across SLRs, `PBLOCK` constraints may be needed to avoid SLR-crossing timing issues.

## Criteria Evaluation

### Pass — Clock Architecture
VCU118's SI5335A provides 100 MHz differential — the exact same input frequency `clkgen_xilultrascaleplus.sv` expects. The MMCME2_ADV configuration stays **unchanged**: CLKOUT0 → 50 MHz core, CLKOUT2 → 100 MHz SPI master, CLKOUT4 → 1 MHz ISP. Only XDC pin locations change. The Si570 (156.25 MHz programmable) is available as a second independent clock if needed.

### Pass — DDR4 Memory
VCU118 has 2× 2.5 GB DDR4 channels. The CoralNPU needs one channel with a 256-bit AXI interface (path: 128-bit TileLink → TlulWidthBridge → 256-bit TL → TLUL2Axi → 256-bit AXI). One channel is more than sufficient. The second is free for model weights or frame buffers.

**Action required**: The DDR4 MIG IP (`ddr_system_bd_ddr4_0_0`) must be regenerated in Vivado for VCU118's DDR4 component pinout and 300 MHz reference clock. The open-source repo has a `ddr4_stub` fallback but not the actual MIG — you'll generate it fresh for VCU118.

### Pass — UART
2-channel USB-to-UART (CP2105) matches the CoralNPU's 2× OpenTitan UART exactly. Connect via USB cable to host PC.

### Pass — JTAG Debug
Standard 14-pin JTAG header. The RISC-V debug module (DMI JTAG with `dmi_jtag` in `chip_nexus.sv`) works directly.

### Pass — SPI Flash
Dual 1 Gb QSPI (rev 2.0+ boards). Sufficient for bitstream + boot ROM image + model weights. **Check your board revision** — earlier revisions use BPI flash which needs a different configuration flow.

### Pass — I/O Voltage
PMOD banks 47/67 at LVCMOS18 with level shifters to 3.3V on connectors. Matches the Nexus design's IOSTANDARD.

### Pass — No ARM SoC Needed
The CoralNPU is a self-contained RISC-V processor. It boots and runs independently — program loaded via SPI from host PC, or autonomously from SPI flash (ROM boot). The VCU118's Zynq-7000 system controller is only for board management (FPGA programming, power), not NPU runtime control.

### Compromise — PMOD Count (2 vs 4)
The Nexus board routes camera (PMOD1/2), SPI master + display (PMOD4), and I2C (PMOD2) through 4 PMOD headers. VCU118 has only 2.

**Mitigations:**

1. **For demo with pre-stored images** (loaded via DDR4 or SPI flash): Camera interface isn't needed. Two PMODs cover SPI master + I2C + display. No compromise at all.

2. **For live camera**: Route the 8-bit DVP + sync signals through the FMC connector instead of PMOD. FMC camera daughter cards provide proper differential signaling — actually an **upgrade** over DVP-on-PMOD-wires.

3. **Suggested assignment**: PMOD J52 → SPI slave (host loader) + I2C, PMOD J53 → SPI master + display, FMC HPC1 → camera DVP.

## I/O Mapping: Nexus → VCU118

| Interface | Nexus Source | VCU118 Target | Status |
|---|---|---|---|
| UART (2×) | Direct pins | USB-UART CP2105 | Match |
| JTAG | Debug header | 14-pin header | Match |
| SPI slave (host load) | FTDI MPSSE pins | → PMOD J52 | Remap |
| SPI master + display | PMOD4 | → PMOD J53 | Remap |
| I2C (camera ctrl) | PMOD2 | → PMOD J52 (share) | Remap |
| GPIO (4 bidir) | PMOD4 | → on-board LEDs/buttons | Remap |
| Camera DVP (8-bit) | PMOD1 + PMOD2 | → FMC HPC1 | Upgrade |
| DDR4 | Component (internal IP) | 2× 2.5 GB component | Match |
| SPI Flash | Board QSPI | Dual QSPI (256 MB) | Match |

## Porting Effort

**No RTL changes required.** All work is at the board integration layer:

| Task | Effort | Description |
|---|---|---|
| `chip_vcu118.sv` | Medium | New board-level top modeled on `chip_nexus.sv`. Adapt DDR4 MIG instantiation, JTAG IOBUFs, GPIO mapping. |
| `pins_vcu118.xdc` | Medium | From-scratch pin constraints per UG1224. Clock, PMOD, UART, JTAG, DDR4, SPI. |
| DDR4 MIG IP | Medium | Regenerate in Vivado IP Integrator for VCU118 DDR4 components and 300 MHz ref clock. |
| `chip_vcu118.core` | Low | FuseSoC core — set part to `xcvu9p-flga2104-2-e`. |
| `fpga/BUILD` | Low | Add VCU118 targets alongside Nexus — template-based. |
| Clock generation RTL | None | Same 100 MHz input, same MMCME2_ADV config. |
| `coralnpu_soc.sv` / Chisel core | None | Board-agnostic, fully reused. |
| SW HALs / TFLite Micro | None | Same memory map, same peripherals. |

**Estimated total: 2–4 days** for someone familiar with the Nexus design and Vivado MIG IP generation. The bulk is DDR4 MIG regeneration and XDC pin assignment, both well-documented for VCU118 in Xilinx reference designs (XTP433).

## Gotchas

1. **Board revision**: Rev 2.0+ has QSPI flash; earlier has BPI. Check yours.
2. **PMOD level shifters**: Add propagation delay. Fine for SPI/I2C/GPIO speeds, don't route high-speed signals through PMODs.
3. **SLR crossing**: XCVU9P is 3-SLR. Design fits in one, but may need PBLOCK constraints if Vivado spreads placement.
4. **DDR4 reference clock**: VCU118 uses 300 MHz diff pair for DDR4 — handled during MIG IP generation.
5. **DDR calibration**: Takes ~1 second after bitstream load. Accessing DDR before calibration completes stalls the TLUL-to-AXI bridge and hangs the crossbar (same as Nexus — use soft reset to recover).

## Why Not Other Boards

| Alternative | Issue |
|---|---|
| **ZeBu emulator** | Overkill — CoralNPU is small enough for real FPGA. ZeBu doesn't give real I/O (camera, display, DDR). Orders of magnitude more expensive. |
| **Arty A7-100T** (~$250) | Only 135 BRAMs — too few for highmem (needs ~560). RVV might not fit in 63K LUTs. No DDR4. |
| **Nexys Video** (XC7A200T, ~$500) | 365 BRAMs — tight for highmem. `STARTUPE3` → `STARTUPE2` porting needed (7-series). DDR3 instead of DDR4 — different MIG. |
| **KCU116** (XCKU5P, ~$2K) | Viable alternative — UltraScale+, 528 BRAMs, DDR4. Slightly tighter than VCU118 but would work. |
| **VCU118** | Best option if available. Same family, massive headroom, 2× DDR4 channels, FMC for expansion. |

## For the ML Demo

Key points for running an image classifier:

1. **Use highmem variant** (1MB ITCM + 1MB DTCM). Default 8KB ITCM is too small for any real model.
2. **TFLite Micro** is already integrated at `sw/opt/litert-micro/`.
3. **RVV is enabled** in the FPGA build (`VLEN_128`, `ZVE32F_ON`). Vector ops can accelerate inference.
4. **DDR4** at `0x80000000` for model weights that don't fit in TCM. Second channel available for frame buffers.
5. **Camera input path exists**: ISP with DVP + I2C camera control. Route through FMC on VCU118.
6. **Display output exists**: Waveshare SPI display with DMA-accelerated rendering via `display_renderer`.
7. **ROM boot** enables autonomous operation: flash model + binary to SPI flash, NPU boots and runs on power-up.
