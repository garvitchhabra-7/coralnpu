#!/bin/bash
# Copyright 2026 Google LLC
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# Copies a VCU118 bitstream build out of the Bazel cache into
# fpga/bitstreams/<name>_<timestamp>/. The timestamp is the bitstream's build
# time, so rerunning on an unchanged build does not create a second copy.
#
# Run through Bazel, which builds the bitstream first if needed:
#   bazelisk run //fpga:archive_chip_vcu118_bitstream_highmem_rom
#
# Usage: archive_vcu118_bitstream.sh <name> <fusesoc build dir> [rom vmem]

set -ue -o pipefail

if [[ "$#" -lt 2 || "$#" -gt 3 ]]; then
    echo "Usage: $0 <name> <fusesoc build dir> [rom vmem]" >&2
    exit 1
fi
if [[ -z "${BUILD_WORKSPACE_DIRECTORY:-}" ]]; then
    echo "ERROR: run this with 'bazel run', not directly." >&2
    exit 1
fi

NAME="$1"
BUILD_DIR="$2"
VMEM="${3:-}"

VIVADO_DIR="${BUILD_DIR}/synth-vivado"
RUNS_DIR="$(find -L "${VIVADO_DIR}" -maxdepth 1 -name "*.runs" -type d | head -1)"
IMPL_DIR="${RUNS_DIR}/impl_1"
BIT="${IMPL_DIR}/chip_vcu118.bit"

if [[ -z "${RUNS_DIR}" || ! -f "${BIT}" ]]; then
    echo "ERROR: no bitstream found under ${VIVADO_DIR}" >&2
    exit 1
fi

STAMP="$(date -r "${BIT}" +%Y-%m-%d_%H%M%S)"
DEST="${BUILD_WORKSPACE_DIRECTORY}/fpga/bitstreams/${NAME}_${STAMP}"

if [[ -e "${DEST}" ]]; then
    echo "Already archived: ${DEST}"
    exit 0
fi
mkdir -p "${DEST}"

copy() {
    if [[ -f "$1" ]]; then
        cp -L "$1" "${DEST}/$2"
        chmod 644 "${DEST}/$2"
    else
        echo "WARNING: missing $1" >&2
    fi
}

copy "${BIT}" chip_vcu118.bit
copy "${IMPL_DIR}/chip_vcu118.ltx" chip_vcu118.ltx
copy "${IMPL_DIR}/chip_vcu118_routed.dcp" chip_vcu118_routed.dcp
copy "${IMPL_DIR}/chip_vcu118_timing_summary_routed.rpt" chip_vcu118_timing_summary_routed.rpt
copy "${IMPL_DIR}/chip_vcu118_utilization_placed.rpt" chip_vcu118_utilization_placed.rpt
copy "${IMPL_DIR}/chip_vcu118_io_placed.rpt" chip_vcu118_io_placed.rpt
copy "${IMPL_DIR}/runme.log" impl_runme.log
copy "${RUNS_DIR}/synth_1/runme.log" synth_runme.log
if [[ -n "${VMEM}" ]]; then
    copy "${VMEM}" "$(basename "${VMEM}")"
fi

# Record which source tree the bitstream came from.
{
    echo "target:  ${NAME}"
    echo "built:   ${STAMP}"
    echo "archived: $(date +%Y-%m-%d_%H%M%S)"
    echo "commit:  $(git -C "${BUILD_WORKSPACE_DIRECTORY}" rev-parse HEAD)"
    echo "branch:  $(git -C "${BUILD_WORKSPACE_DIRECTORY}" rev-parse --abbrev-ref HEAD)"
    echo
    echo "Uncommitted changes at archive time (may differ from build time):"
    git -C "${BUILD_WORKSPACE_DIRECTORY}" status --short
} > "${DEST}/BUILD_INFO.txt"

echo "Archived to ${DEST}"
grep -m1 -E "Timing constraints are (not )?met|All user specified timing constraints are met" \
    "${DEST}/chip_vcu118_timing_summary_routed.rpt" || true
