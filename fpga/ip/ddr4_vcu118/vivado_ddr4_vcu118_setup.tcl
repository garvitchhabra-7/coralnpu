# Copyright 2025 Google LLC
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     https://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# Load pre-synthesized DDR4 MIG and SmartConnect design checkpoints.
# Sourced from vivado_setup_hooks.tcl; $workroot is set by the caller.

set ddr4_dcp_dir "${workroot}/ddr4_vcu118_dcp"
set ddr4_xdc_dir "${workroot}/ddr4_vcu118_xdc"

if {[file exists "${ddr4_dcp_dir}/ddr_system_bd_ddr4_0_0.dcp"]} {
    puts "INFO: Loading VCU118 DDR4 MIG IP from DCPs"

    # Add pre-synthesized checkpoints to the project
    add_files -quiet ${ddr4_dcp_dir}/ddr_system_bd_ddr4_0_0.dcp
    add_files -quiet ${ddr4_dcp_dir}/ddr_system_bd_smartconnect_0_0.dcp

    # Mark them as OOC (do not re-synthesize)
    set_property USED_IN {synthesis implementation} [get_files ${ddr4_dcp_dir}/ddr_system_bd_ddr4_0_0.dcp]
    set_property USED_IN {synthesis implementation} [get_files ${ddr4_dcp_dir}/ddr_system_bd_smartconnect_0_0.dcp]

    # Add MIG timing constraints (pin locations are in ddr4_vcu118_pins.xdc loaded by FuseSoC)
    add_files -fileset constrs_1 -quiet ${ddr4_xdc_dir}/ddr_system_bd_ddr4_0_0.xdc

    # Note: no post-bitstream hook needed — calibration FW is already in the DCP.
    # The Nexus flow uses vivado_hook_write_bitstream_post.tcl to stitch
    # calibration_ddr.elf, but the VCU118 DCP includes it pre-stitched.
} else {
    puts "INFO: VCU118 DDR4 DCPs not found — using stub"
}
