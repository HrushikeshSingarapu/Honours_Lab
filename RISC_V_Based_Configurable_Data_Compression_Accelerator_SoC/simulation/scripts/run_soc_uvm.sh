#!/usr/bin/env bash
# =============================================================================
# run_soc_uvm.sh — Build and Execute Unified SoC UVM Verification Suite
# =============================================================================
set -euo pipefail

# Determine Project Directories
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SOC_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

# VCS Environment Setup
export VCS_HOME="${VCS_HOME:-/home/student/snps_tools_target/vcs/U-2023.03}"
export PATH="${VCS_HOME}/bin:${PATH}"
export SNPSLMD_LICENSE_FILE="${SNPSLMD_LICENSE_FILE:-27021@14.139.1.126}"

TESTNAME="${1:-soc_smoke_test}"
EXTRA_ARGS="${@:2}"

# Set default firmware for uart_echo_test if not explicitly specified
if [ "${TESTNAME}" = "uart_echo_test" ] && [[ "${EXTRA_ARGS}" != *"+FIRMWARE="* ]]; then
    EXTRA_ARGS="+FIRMWARE=firmware/images/uart_echo.hex ${EXTRA_ARGS}"
fi

echo "========================================================================"
echo " VeeR EL2 Data Compression Accelerator SoC — UVM Verification Runner"
echo " Project Root : ${SOC_ROOT}"
echo " Test Name    : ${TESTNAME}"
echo " Extra Args   : ${EXTRA_ARGS}"
echo " VCS Version  : $(vcs -id 2>&1 | head -n 1 || echo 'VCS U-2023.03')"
echo "========================================================================"

mkdir -p "${SOC_ROOT}/simulation/logs"
mkdir -p "${SOC_ROOT}/simulation/waveforms"

cd "${SOC_ROOT}"

# 1. Compilation
echo "[VCS] Compiling Unified SoC UVM Environment..."
vcs -full64 -sverilog -timescale=1ns/1ps -ntb_opts uvm \
    -f verification/uvm/filelists/soc_uvm.f \
    -o "${SOC_ROOT}/simulation/simv_soc_uvm" \
    -l simulation/logs/vcs_compile.log

echo "[VCS] Compilation Successful. Executing Simulation..."

# 2. Simulation Execution
"${SOC_ROOT}/simulation/simv_soc_uvm" \
    +UVM_TESTNAME="${TESTNAME}" \
    +DUMP_WAVE \
    +VCD_FILE=simulation/waveforms/soc_uvm.vcd \
    -l "simulation/logs/sim_${TESTNAME}.log" \
    ${EXTRA_ARGS}

echo "========================================================================"
echo " Simulation Complete!"
echo " Compile Log : simulation/logs/vcs_compile.log"
echo " Sim Log     : simulation/logs/sim_${TESTNAME}.log"
echo " Waveform    : simulation/waveforms/soc_uvm.vcd"
echo "========================================================================"

# 3. Waveform Evidence Generation (VCD and FSDB for Verdi)
if [ -f "${SOC_ROOT}/simulation/waveforms/soc_uvm.vcd" ]; then
    export VERDI_HOME="${VERDI_HOME:-/home/student/snps_tools_target/verdi/U-2023.03-SP1}"
    export PATH="${VERDI_HOME}/bin:${PATH}"
    if command -v vcd2fsdb &>/dev/null; then
        echo "[TOOLS] Converting VCD to Verdi Fast Signal Database (FSDB)..."
        vcd2fsdb "${SOC_ROOT}/simulation/waveforms/soc_uvm.vcd" -o "${SOC_ROOT}/simulation/waveforms/soc_uvm.fsdb" >/dev/null 2>&1 || true
        rm -rf "${SOC_ROOT}/vcd2fsdbLog"
    fi
fi
