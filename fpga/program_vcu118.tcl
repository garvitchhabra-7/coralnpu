# ==============================================================================
# Script: program_vcu118.tcl
# Description: Programs a CoralNPU bitstream onto one specific VCU118 over JTAG.
#              The board is selected by its Digilent cable serial, never by
#              position in get_hw_targets -- this host has several boards
#              attached and a positional pick can grab the wrong one.
#              Refuses to program unless the JTAG chain reports an xcvu9p and
#              the bitstream header matches it.
#
# Usage:
#   vivado -mode batch -source fpga/program_vcu118.tcl
#   vivado -mode batch -source fpga/program_vcu118.tcl -tclargs <bitfile>
#   vivado -mode batch -source fpga/program_vcu118.tcl -tclargs <bitfile> <serial>
#
# Run from the repo root (the default bitstream path is relative to it).
# ==============================================================================

set default_bit    "bazel-bin/fpga/build.build_chip_vcu118_bitstream_highmem/com.google.coralnpu_fpga_chip_vcu118_0.1/synth-vivado/com.google.coralnpu_fpga_chip_vcu118_0.1.bit"
set default_serial "210308B76D4D"
set expected_part  "xcvu9p"

set bitfile [expr {[llength $argv] > 0 ? [lindex $argv 0] : $default_bit}]
set serial  [expr {[llength $argv] > 1 ? [lindex $argv 1] : $default_serial}]

puts "\n========================================================="
puts " CoralNPU VCU118 programmer"
puts "========================================================="

# ------------------------------------------------------------------ bitstream
if {![file exists $bitfile]} {
    puts "ERROR: bitstream not found: $bitfile"
    puts "       Build it with: bazel build //fpga:build_chip_vcu118_bitstream_highmem"
    exit 1
}
set bitfile [file normalize $bitfile]

# Parse the .bit header so we fail here rather than after pushing bits at the
# wrong silicon. Header fields are NUL-terminated strings in the first ~200 B.
set fh [open $bitfile rb]
set hdr [read $fh 256]
close $fh

set bit_design "unknown"
set bit_part   "unknown"
set bit_date   "unknown"
regexp {([A-Za-z0-9_]+);UserID=} $hdr -> bit_design
regexp {(xc[A-Za-z0-9]+-[A-Za-z0-9]+-[A-Za-z0-9]+-[A-Za-z0-9]+)} $hdr -> bit_part
regexp {([0-9]{4}/[0-9]{2}/[0-9]{2})} $hdr -> bit_date

puts "Bitstream : $bitfile"
puts "  design  : $bit_design"
puts "  part    : $bit_part"
puts "  built   : $bit_date"
puts "  size    : [file size $bitfile] bytes"

if {![string match "$expected_part*" $bit_part]} {
    puts "ERROR: bitstream targets '$bit_part', expected an $expected_part part."
    puts "       This does not look like a VCU118 bitstream. Refusing to program."
    exit 1
}

# Pick up matching debug probes if they sit next to the bitstream. Vivado names
# the LTX after the top module (chip_vcu118.ltx), not after the Bazel-named .bit,
# so fall back to that when the rootname-derived path is missing.
set ltxfile ""
foreach candidate [list \
        "[file rootname $bitfile].ltx" \
        [file join [file dirname $bitfile] chip_vcu118.ltx] \
        [file join "[file rootname $bitfile].runs" impl_1 chip_vcu118.ltx]] {
    if {[file exists $candidate]} {
        set ltxfile $candidate
        break
    }
}
if {$ltxfile eq ""} {
    puts "Probes    : none found for $bitfile"
}

# ------------------------------------------------------------------- hardware
open_hw_manager
connect_hw_server -quiet

set all_targets [get_hw_targets -quiet]
set targets     [get_hw_targets -quiet *$serial*]

if {[llength $targets] != 1} {
    if {[llength $targets] == 0} {
        puts "ERROR: no JTAG target matching serial '$serial'."
    } else {
        puts "ERROR: serial '$serial' matched [llength $targets] targets: $targets"
    }
    puts "Targets visible on this hw_server:"
    foreach t $all_targets { puts "  $t" }
    puts "NOTE: some of these belong to other users on this host."
    disconnect_hw_server -quiet
    close_hw_manager -quiet
    exit 1
}

set target [lindex $targets 0]
puts "\nTarget    : $target"
foreach t $all_targets {
    if {$t ne $target} { puts "  (skipping other board on this host: $t)" }
}

if {[catch {open_hw_target $target} msg]} {
    puts "ERROR: could not open $target"
    puts "       $msg"
    puts "       The cable is probably held open by another Vivado session."
    disconnect_hw_server -quiet
    close_hw_manager -quiet
    exit 1
}

# --------------------------------------------------------------- device check
set device ""
foreach d [get_hw_devices] {
    if {[string match "$expected_part*" [get_property PART $d]]} {
        set device $d
        break
    }
}

if {$device eq ""} {
    puts "ERROR: no $expected_part device on the JTAG chain of $target."
    puts "Devices found:"
    foreach d [get_hw_devices] { puts "  $d  (part [get_property PART $d])" }
    puts "       Wrong board for this bitstream. Refusing to program."
    close_hw_target
    disconnect_hw_server -quiet
    close_hw_manager -quiet
    exit 1
}

current_hw_device $device
refresh_hw_device -quiet -update_hw_probes false $device
puts "Device    : $device  (part [get_property PART $device])"

# ------------------------------------------------------------------ programming
set_property PROGRAM.FILE $bitfile $device
if {[file exists $ltxfile]} {
    puts "Probes    : $ltxfile"
    set_property PROBES.FILE      $ltxfile $device
    set_property FULL_PROBES.FILE $ltxfile $device
}

puts "\nProgramming..."
if {[catch {program_hw_devices $device} msg]} {
    puts "ERROR: programming failed: $msg"
    close_hw_target
    disconnect_hw_server -quiet
    close_hw_manager -quiet
    exit 1
}

refresh_hw_device -quiet -update_hw_probes false $device
set done [get_property -quiet REGISTER.IR.BIT5_DONE $device]
if {$done eq ""} {
    puts "Programmed. (DONE status not reported by this device driver.)"
} elseif {$done} {
    puts "Programmed. DONE = 1."
} else {
    puts "ERROR: programming returned OK but DONE = 0 -- the device did not configure."
    close_hw_target
    disconnect_hw_server -quiet
    close_hw_manager -quiet
    exit 1
}

close_hw_target
disconnect_hw_server -quiet
close_hw_manager -quiet

puts "\n========================================================="
puts " $bit_design -> $serial : OK"
puts "========================================================="
exit 0
