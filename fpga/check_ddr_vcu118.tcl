# Read-only DDR4 MIG calibration check on an already-programmed VCU118.
# Does NOT program anything. Selects the JTAG cable by serial (shared host).
#
# Usage (repo root):
#   vivado -mode batch -source fpga/check_ddr_vcu118.tcl
#   vivado -mode batch -source fpga/check_ddr_vcu118.tcl -tclargs <ltxfile> <serial>

set default_ltx    "fpga/bitstreams/vcu118_highmem_2026-09-25/chip_vcu118.ltx"
set default_serial "210308B76D4D"

set ltxfile [expr {[llength $argv] > 0 ? [lindex $argv 0] : $default_ltx}]
set serial  [expr {[llength $argv] > 1 ? [lindex $argv 1] : $default_serial}]

if {![file exists $ltxfile]} {
    puts "ERROR: probes file not found: $ltxfile"
    exit 1
}
set ltxfile [file normalize $ltxfile]

open_hw_manager
connect_hw_server -quiet

set targets [get_hw_targets -quiet *$serial*]
if {[llength $targets] != 1} {
    puts "ERROR: expected exactly one JTAG target matching '$serial', got: $targets"
    disconnect_hw_server -quiet
    exit 1
}
if {[catch {open_hw_target [lindex $targets 0]} msg]} {
    puts "ERROR: could not open target: $msg"
    disconnect_hw_server -quiet
    exit 1
}

set device ""
foreach d [get_hw_devices -quiet] {
    if {[string match "xcvu9p*" [get_property PART $d]]} { set device $d }
}
if {$device eq ""} {
    puts "ERROR: no xcvu9p on this chain"
    close_hw_target
    disconnect_hw_server -quiet
    exit 1
}
current_hw_device $device

puts "Device : $device"
puts "Probes : $ltxfile"
set_property PROBES.FILE      $ltxfile $device
set_property FULL_PROBES.FILE $ltxfile $device
refresh_hw_device $device

set migs [get_hw_migs -quiet]
if {[llength $migs] == 0} {
    puts "ERROR: no MIG debug core found (wrong .ltx, or device not programmed with this bitstream?)"
} else {
    foreach m $migs {
        puts "\n================ $m ================"
        report_hw_mig $m
    }
}

close_hw_target
disconnect_hw_server -quiet
close_hw_manager -quiet
exit 0
