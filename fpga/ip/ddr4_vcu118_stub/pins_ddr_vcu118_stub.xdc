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

# VCU118 DDR4 stub pin constraints.
# Real pin locations come from MIG-generated XDC; only IOSTANDARD needed here.

set_property IOSTANDARD SSTL12_DCI [get_ports "C0_DDR4_0_adr[*]"]
set_property IOSTANDARD SSTL12_DCI [get_ports "C0_DDR4_0_ba[*]"]
set_property IOSTANDARD SSTL12_DCI [get_ports "C0_DDR4_0_bg[*]"]
set_property IOSTANDARD DIFF_SSTL12_DCI [get_ports "C0_DDR4_0_ck_c[0]"]
set_property IOSTANDARD DIFF_SSTL12_DCI [get_ports "C0_DDR4_0_ck_t[0]"]
set_property IOSTANDARD SSTL12_DCI [get_ports "C0_DDR4_0_cke[*]"]
set_property IOSTANDARD SSTL12_DCI [get_ports "C0_DDR4_0_cs_n[*]"]
set_property IOSTANDARD SSTL12_DCI [get_ports "C0_DDR4_0_odt[*]"]
set_property IOSTANDARD SSTL12_DCI [get_ports "C0_DDR4_0_act_n"]
set_property IOSTANDARD LVCMOS12 [get_ports "C0_DDR4_0_reset_n"]
set_property IOSTANDARD POD12_DCI [get_ports "C0_DDR4_0_dq[*]"]
set_property IOSTANDARD POD12_DCI [get_ports "C0_DDR4_0_dm_n[*]"]
set_property IOSTANDARD DIFF_POD12_DCI [get_ports "C0_DDR4_0_dqs_c[*]"]
set_property IOSTANDARD DIFF_POD12_DCI [get_ports "C0_DDR4_0_dqs_t[*]"]

# DDR4 reference clock (250 MHz, C1 on VCU118)
set_property IOSTANDARD LVDS [get_ports "C0_SYS_CLK_0_clk_p"]
set_property IOSTANDARD LVDS [get_ports "C0_SYS_CLK_0_clk_n"]
