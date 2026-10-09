# Copyright 2026 Google LLC
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0

# Offline CDC check on a routed VCU118 checkpoint. Does NOT touch hardware.
#
# Gate for the "group A" constraint in notes2/fpga/vcu118_timing_fixes.md:
# set_max_delay -datapath_only between clk_main and clk_aon / clk_spim_unbuf is
# only safe if every crossing between them goes through a synchroniser (the
# Chisel async FIFOs). This script writes:
#   cdc_main_to_x.rpt, cdc_x_to_main.rpt  report_cdc -details, both directions
#   cdc_summary.txt                       report_cdc severity counts, plus
#                                         every timed path between the clocks
#                                         grouped by endpoint cell pattern
#
# Usage (repo root, outside the FHS shell, after `module load Vivado/2025.2`):
#   vivado -mode batch -nojournal -nolog -source fpga/report_cdc_vcu118.tcl \
#     -tclargs <chip_vcu118_routed.dcp> [out_dir]
#
# Opening the checkpoint needs ~15-20 GB RAM (shared host).

set dcp [expr {[llength $argv] > 0 ? [lindex $argv 0] : \
    "fpga/bitstreams/vcu118_highmem_rom_2026-10-06_201108/chip_vcu118_routed.dcp"}]
set out [expr {[llength $argv] > 1 ? [lindex $argv 1] : [file dirname $dcp]}]

if {![file exists $dcp]} {
    puts "ERROR: file not found: $dcp"
    exit 1
}
file mkdir $out
open_checkpoint $dcp

# clk_main = CLKOUT0, clk_aon = CLKOUT4 (named in pins_vcu118.xdc). The 100 MHz
# SPI master clock on CLKOUT2 has a Vivado-derived name (clk_spim_unbuf), so
# look it up by pin.
set pll i_clkgen/i_clkgen/pll
set main  [get_clocks clk_main]
set other [get_clocks -of_objects [get_pins "$pll/CLKOUT4 $pll/CLKOUT2"]]
puts "clk_main: [get_property NAME $main]"
puts "others:   [get_property NAME $other]"

report_cdc -from $main -to $other -details -file "$out/cdc_main_to_x.rpt"
report_cdc -from $other -to $main -details -file "$out/cdc_x_to_main.rpt"

set sum [open "$out/cdc_summary.txt" "w"]
proc out {msg} {
    global sum
    puts $msg
    puts $sum $msg
}

out "Checkpoint: $dcp"
out "clk_main: [get_property NAME $main]; others: [get_property NAME $other]"
out ""
out "=== report_cdc summary ==="
out "Go ahead with the XDC change only if there are no Critical (Unsafe/"
out "Unknown) rows below. Warnings for CDC-1/CDC-2 style \"no ASYNC_REG\" can be"
out "reviewed in the .rpt files."
foreach {from to} [list $main $other $other $main] {
    out [report_cdc -from $from -to $to -return_string]
}

# Every timed path between the clocks, grouped by endpoint cell with indices
# stripped. All of them should be async FIFO sink registers (*cdc_reg*) or
# pointer synchronisers. Anything else is a crossing the constraint would hide.
proc group_paths {label from to} {
    set paths [get_timing_paths -from $from -to $to -max_paths 50000 \
        -nworst 1 -unique_pins]
    set failing 0
    array set groups {}
    foreach p $paths {
        if {[get_property SLACK $p] < 0} { incr failing }
        set cell [get_cells -of_objects [get_property ENDPOINT_PIN $p]]
        regsub -all {\[[0-9]+\]|_[0-9]+(?=_|/|$)} $cell {*} key
        if {![info exists groups($key)]} { set groups($key) 0 }
        incr groups($key)
    }
    out ""
    out "=== $label: [llength $paths] timed paths, $failing failing ==="
    foreach key [lsort [array names groups]] {
        set tag [expr {[string match {*cdc_reg*} $key] || \
            [string match {*sync*} $key] ? "  " : "??"}]
        out [format "%s %6d  %s" $tag $groups($key) $key]
    }
}
group_paths "clk_main -> others" $main $other
group_paths "others -> clk_main" $other $main
out ""
out "Rows marked ?? are not obviously synchronisers: check them in the .rpt."

close $sum
puts "Wrote $out/cdc_main_to_x.rpt, cdc_x_to_main.rpt, cdc_summary.txt"
exit 0
