# Offline inspection of a routed VCU118 checkpoint. Does NOT touch hardware.
# Checks the things the silent-UART ROM-boot bitstream could get wrong:
#   1. What drives the reset of the autoboot FSM (gen_autoboot.rst_main_nqq bug).
#   2. Whether the boot ROM was mapped to initialized BRAM, and whether the
#      BRAM INIT contents match the .vmem image.
#   3. Whether UART1 / clock table logic survived and what drives uart_tx_o[1].
#
# Usage (repo root, outside the FHS shell, after `module load Vivado/2025.2`):
#   vivado -mode batch -nojournal -nolog -source fpga/inspect_routed_dcp.tcl \
#     -tclargs <chip_vcu118_routed.dcp> <rom.vmem> [report.txt]
#
# Opening the checkpoint needs ~15-20 GB RAM (shared host).

set archive "fpga/bitstreams/vcu118_highmem_rom_2026-09-29"
set dcp     [expr {[llength $argv] > 0 ? [lindex $argv 0] : "$archive/chip_vcu118_routed.dcp"}]
set vmem    [expr {[llength $argv] > 1 ? [lindex $argv 1] : "$archive/rom_hello_highmem.vmem"}]
set report  [expr {[llength $argv] > 2 ? [lindex $argv 2] : "[file dirname $dcp]/inspect_routed_dcp.txt"}]

foreach f [list $dcp $vmem] {
    if {![file exists $f]} {
        puts "ERROR: file not found: $f"
        exit 1
    }
}

set rpt [open $report "w"]
proc out {msg} {
    global rpt
    puts $msg
    puts $rpt $msg
}

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

# Describe what drives a net, following up to `depth` levels of LUT1/BUF
# (inverters and buffers inserted for active-low resets).
proc describe_driver {net {depth 3} {indent "      "}} {
    if {$net eq ""} {
        out "${indent}<pin unconnected>"
        return
    }
    set type [get_property TYPE $net]
    if {$type eq "GROUND" || $type eq "POWER"} {
        out "${indent}net $net : constant $type"
        return
    }
    set drv_pins [get_pins -quiet -of_objects $net -leaf -filter {DIRECTION == OUT}]
    set drv_ports [get_ports -quiet -of_objects $net -filter {DIRECTION == IN}]
    if {[llength $drv_pins] == 0 && [llength $drv_ports] == 0} {
        out "${indent}net $net : NO DRIVER"
        return
    }
    foreach p $drv_ports {
        out "${indent}net $net <- top port $p"
    }
    foreach p $drv_pins {
        set c [get_cells -of_objects $p]
        set ref [get_property REF_NAME $c]
        out "${indent}net $net <- $p ($ref)"
        if {$depth > 0 && [regexp {^(LUT1|BUFG.*|BUF|INV|OBUF|OBUFT)$} $ref]} {
            if {$ref eq "LUT1"} {
                out "${indent}  LUT1 INIT = [get_property INIT $c] (2'h1 = inverter, 2'h2 = buffer)"
            }
            foreach ip [get_pins -of_objects $c -filter {DIRECTION == IN}] {
                describe_driver [get_nets -quiet -of_objects $ip] [expr {$depth - 1}] "${indent}  "
            }
        }
    }
}

# Parse a $readmemh-style 32-bit .vmem (srecord output) into an array addr -> word.
proc load_vmem {path arrname} {
    upvar $arrname mem
    set fh [open $path r]
    set text [read $fh]
    close $fh
    regsub -all {/\*.*?\*/} $text "" text
    regsub -all {//[^\n]*} $text "" text
    set addr 0
    foreach tok [regexp -all -inline {\S+} $text] {
        if {[string index $tok 0] eq "@"} {
            scan [string range $tok 1 end] %x addr
        } else {
            scan $tok %x mem($addr)
            incr addr
        }
    }
    return [array size mem]
}

# Bit `pos` of a BRAM's data INIT space (INIT_00 holds bits 0..255).
proc init_bit {cell pos} {
    set idx [expr {$pos / 256}]
    set off [expr {$pos % 256}]
    set val [get_property [format "INIT_%02X" $idx] $cell]
    regsub {^[0-9]*'h} $val "" hex
    set hex [string range [string repeat 0 64]$hex end-63 end]
    set nib [string index $hex [expr {63 - $off / 4}]]
    scan $nib %x n
    return [expr {($n >> ($off % 4)) & 1}]
}

# ---------------------------------------------------------------------------
open_checkpoint $dcp
out "Checkpoint : [file normalize $dcp]"
out "VMEM       : [file normalize $vmem]"
out ""

# ---------------------------------------------------------------------------
out "================ 1. Autoboot FSM reset ================"
set ab_regs [get_cells -quiet -hierarchical -filter {NAME =~ *i_autoboot/state_q_reg* && IS_PRIMITIVE}]
if {[llength $ab_regs] == 0} {
    out "  No i_autoboot/state_q_reg* cells found (FSM optimized away or renamed)."
    set ab_any [get_cells -quiet -hierarchical -filter {NAME =~ *i_autoboot/* && IS_PRIMITIVE}]
    out "  Primitive cells under i_autoboot: [llength $ab_any]"
    foreach c [lrange $ab_any 0 19] {
        out "    $c ([get_property REF_NAME $c])"
    }
}
foreach c $ab_regs {
    out "  $c ([get_property REF_NAME $c]) INIT=[get_property -quiet INIT $c]"
    foreach pn {CLR PRE R S} {
        set p [get_pins -quiet $c/$pn]
        if {$p eq ""} { continue }
        out "    pin $pn:"
        describe_driver [get_nets -quiet -of_objects $p]
    }
}
out ""
out "  Reset synchroniser (rst_main_nqq) cells:"
foreach c [get_cells -quiet -hierarchical -filter {NAME =~ *rst_main_nq*_reg* && IS_PRIMITIVE}] {
    set q [get_nets -quiet -of_objects [get_pins -quiet $c/Q]]
    set loads [get_pins -quiet -of_objects $q -leaf -filter {DIRECTION == IN}]
    out "    $c ([get_property REF_NAME $c]) -> [llength $loads] loads"
    foreach l [lrange $loads 0 9] {
        out "      $l"
    }
}
out ""

# ---------------------------------------------------------------------------
out "================ 2. Boot ROM ================"
set rom_cells [get_cells -quiet -hierarchical -filter {NAME =~ *i_rom/* && IS_PRIMITIVE}]
set groups [dict create]
foreach c $rom_cells {
    dict incr groups [get_property PRIMITIVE_GROUP $c]
}
out "  Primitive cells under i_rom by group: $groups"

set brams [lsort -dictionary [get_cells -quiet -hierarchical \
    -filter {NAME =~ *i_rom/* && PRIMITIVE_TYPE =~ BLOCKRAM.*}]]
set urams [get_cells -quiet -hierarchical -filter {NAME =~ *i_rom/* && PRIMITIVE_TYPE =~ BLOCKRAM.URAM.*}]
if {[llength $urams] > 0} {
    out "  WARNING: ROM mapped to URAM ([llength $urams] cells) -- URAM cannot be initialized!"
}
if {[llength $brams] == 0} {
    out "  No BRAM under i_rom (LUT ROM or optimized away) -- INIT check skipped."
}

set nwords [load_vmem $vmem expected]
out "  VMEM words: $nwords"

set total_bad 0
foreach b $brams {
    set ref     [get_property REF_NAME $b]
    set a_begin [get_property -quiet RAM_ADDR_BEGIN $b]
    set a_end   [get_property -quiet RAM_ADDR_END $b]
    set s_begin [get_property -quiet RAM_SLICE_BEGIN $b]
    set s_end   [get_property -quiet RAM_SLICE_END $b]
    set rw      [get_property -quiet READ_WIDTH_A $b]
    if {$rw eq "" || $rw == 0} { set rw [get_property -quiet READ_WIDTH_B $b] }
    out "  $b ($ref) LOC=[get_property LOC $b] addr=\[$a_begin:$a_end\] slice=\[$s_end:$s_begin\] READ_WIDTH=$rw"
    out "    INIT_00 = [get_property INIT_00 $b]"

    if {$a_begin eq "" || $s_begin eq ""} {
        out "    (no RAM_ADDR/RAM_SLICE properties -- cannot compare)"
        continue
    }
    # Data bits per word in the INIT space (parity bits live in INITP).
    set dbits [expr {$rw >= 9 ? ($rw / 9) * 8 : $rw}]
    set swidth [expr {$s_end - $s_begin + 1}]
    if {$swidth > $dbits} {
        out "    (slice uses parity bits -- comparison not implemented)"
        continue
    }
    set bad 0
    set shown 0
    for {set a $a_begin} {$a <= $a_end} {incr a} {
        set word [expr {[info exists expected($a)] ? $expected($a) : 0}]
        set local [expr {$a - $a_begin}]
        for {set k 0} {$k < $swidth} {incr k} {
            set want [expr {($word >> ($s_begin + $k)) & 1}]
            set got  [init_bit $b [expr {$local * $dbits + $k}]]
            if {$want != $got} {
                incr bad
                if {$shown < 5} {
                    out [format "    MISMATCH addr 0x%04X bit %d: expected %d got %d" \
                        $a [expr {$s_begin + $k}] $want $got]
                    incr shown
                }
            }
        }
    }
    out "    mismatching bits: $bad"
    incr total_bad $bad
}
if {[llength $brams] > 0} {
    out "  ROM INIT check: [expr {$total_bad == 0 ? "PASS" : "FAIL ($total_bad bits)"}]"
}
out ""

# ---------------------------------------------------------------------------
out "================ 3. UART1 / clock table ================"
foreach inst {i_uart1 i_clk_table} {
    set n [llength [get_cells -quiet -hierarchical -filter "NAME =~ *$inst/* && IS_PRIMITIVE"]]
    out "  primitive cells under $inst: $n"
}
set tx [get_ports -quiet {uart_tx_o[1]}]
if {$tx eq ""} {
    out "  port uart_tx_o\[1\] not found"
} else {
    out "  uart_tx_o\[1\] PACKAGE_PIN=[get_property PACKAGE_PIN $tx] IOSTANDARD=[get_property IOSTANDARD $tx]"
    describe_driver [get_nets -quiet -of_objects $tx] 4
}

out ""

# ---------------------------------------------------------------------------
# Why was the ROM array removed? A constant read path (req/addr/data) lets
# Vivado fold the whole memory into its output registers.
out "================ 4. ROM read path / autoboot traces ================"
out "  Cells under i_rom:"
foreach c [lsort -dictionary [get_cells -quiet -hierarchical -filter {NAME =~ *i_rom/* && IS_PRIMITIVE}]] {
    out "    $c ([get_property REF_NAME $c])"
    foreach pn {D CE} {
        set p [get_pins -quiet $c/$pn]
        if {$p eq ""} { continue }
        out "      pin $pn:"
        describe_driver [get_nets -quiet -of_objects $p] 1 "        "
    }
}
foreach pat {*i_coralnpu_soc/rom_req *i_coralnpu_soc/rom_addr* *i_coralnpu_soc/rom_rdata*
             *i_coralnpu_soc/tl_rom_o_32*a_valid* *gen_autoboot*rst_main_nqq*
             *i_coralnpu_soc/tl_autoboot_h2d*a_valid*} {
    set nets [get_nets -quiet -hierarchical -filter "NAME =~ \"$pat\""]
    if {[llength $nets] == 0} {
        out "  net $pat : not found"
        continue
    }
    foreach n [lrange $nets 0 1] {
        out "  net $n:"
        describe_driver $n 1 "    "
    }
}
foreach port {io_halted io_fault} {
    set p [get_ports -quiet $port]
    if {$p eq ""} { continue }
    out "  port $port:"
    describe_driver [get_nets -quiet -of_objects $p] 2 "    "
}

out ""
out "Report written to [file normalize $report]"
close $rpt
close_design
exit 0
