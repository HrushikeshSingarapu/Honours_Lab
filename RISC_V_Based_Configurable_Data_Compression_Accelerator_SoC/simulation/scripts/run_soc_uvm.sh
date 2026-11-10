#!/usr/bin/env bash
# =============================================================================
# run_soc_uvm.sh — Build and Execute Unified SoC UVM Verification Suite
# =============================================================================
set -euo pipefail

# Determine Project Directories
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SOC_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

# VCS Environment Setup (expects VCS_HOME or `vcs` in PATH, and SNPSLMD_LICENSE_FILE in env)
if [ -n "${VCS_HOME:-}" ]; then
    export PATH="${VCS_HOME}/bin:${PATH}"
fi
if ! command -v vcs >/dev/null 2>&1; then
    echo "Error: Synopsys 'vcs' not found in PATH (set VCS_HOME or add vcs/bin to PATH)." >&2
    exit 1
fi

TESTNAME="${1:-soc_smoke_test}"
EXTRA_ARGS="${*:2}"

resolve_firmware_arg() {
    local tname="$1"
    if [[ "${EXTRA_ARGS}" == *"+FIRMWARE="* ]]; then
        echo ""
        return
    fi
    case "${tname}" in
        uart_echo_test)
            echo "+FIRMWARE=firmware/images/uart_echo.hex"
            ;;
        soc_e2e_flow_test|soc_reset_recovery_test)
            echo "+FIRMWARE=firmware/images/soc_e2e_uvm.hex"
            ;;
        soc_decerr_trap_test)
            echo "+FIRMWARE=firmware/images/soc_decerr_test.hex"
            ;;
        *)
            echo ""
            ;;
    esac
}

echo "========================================================================"
echo " VeeR EL2 Data Compression Accelerator SoC — UVM Verification Runner"
echo " Project Root : ${SOC_ROOT}"
echo " Test Name    : ${TESTNAME}"
echo " Extra Args   : ${EXTRA_ARGS}"
echo " VCS Version  : $(vcs -id 2>&1 | head -n 1 || echo 'VCS U-2023.03')"
echo "========================================================================"

mkdir -p "${SOC_ROOT}/simulation/logs"
mkdir -p "${SOC_ROOT}/simulation/waveforms"
mkdir -p "${SOC_ROOT}/simulation/coverage"

cd "${SOC_ROOT}"

# 1. Compilation
echo "[VCS] Compiling Unified SoC UVM Environment..."
vcs -full64 -sverilog -timescale=1ns/1ps -ntb_opts uvm \
    +define+ENABLE_SV_COVERGROUP \
    -cm line+cond+fsm+branch+tgl \
    -f verification/uvm/filelists/soc_uvm.f \
    -o "${SOC_ROOT}/simulation/simv_soc_uvm" \
    -l simulation/logs/vcs_compile.log

run_single_test() {
    local tname="$1"
    local fw_arg
    fw_arg="$(resolve_firmware_arg "${tname}")"
    local log_file="simulation/logs/sim_${tname}.log"
    local vcd_file="simulation/waveforms/${tname}.vcd"

    echo "[VCS] Executing ${tname}..."
    "${SOC_ROOT}/simulation/simv_soc_uvm" \
        +UVM_TESTNAME="${tname}" \
        +DUMP_WAVE \
        +VCD_FILE="${vcd_file}" \
        -cm line+cond+fsm+branch+tgl \
        -cm_dir "${SOC_ROOT}/simulation/coverage/simv_soc_uvm.vdb" \
        -cm_name "${tname}" \
        -l "${log_file}" \
        ${fw_arg} ${EXTRA_ARGS}

    if grep -qE "UVM_ERROR\s*:\s*[1-9]|UVM_FATAL\s*:\s*[1-9]|_ASSERT.*ERROR" "${log_file}"; then
        echo "[VCS] FAIL: Errors detected in ${log_file}"
        return 1
    fi
    if ! grep -q "OVERALL SOC SCOREBOARD VERDICT: \[ALL CHECKS PASSED\]" "${log_file}"; then
        echo "[VCS] FAIL: Scoreboard PASS verdict missing in ${log_file}"
        return 1
    fi
    echo "[VCS] PASS: ${tname}"
}

if [ "${TESTNAME}" = "all" ]; then
    for t in soc_smoke_test soc_e2e_flow_test soc_decerr_trap_test soc_reset_recovery_test uart_echo_test; do
        run_single_test "${t}"
    done
else
    run_single_test "${TESTNAME}"
fi

echo "========================================================================"
echo " Simulation Complete!"
echo " Compile Log : simulation/logs/vcs_compile.log"
echo " Coverage DB : simulation/coverage/simv_soc_uvm.vdb"
echo "========================================================================"

# 3. Optional Waveform Evidence Conversion (VCD -> FSDB for Verdi)
if [ -f "${SOC_ROOT}/simulation/waveforms/soc_smoke_test.vcd" ]; then
    if [ -n "${VERDI_HOME:-}" ]; then
        export PATH="${VERDI_HOME}/bin:${PATH}"
    fi
    if command -v vcd2fsdb &>/dev/null; then
        echo "[TOOLS] Converting VCD to Verdi Fast Signal Database (FSDB)..."
        vcd2fsdb "${SOC_ROOT}/simulation/waveforms/soc_smoke_test.vcd" -o "${SOC_ROOT}/simulation/waveforms/soc_uvm.fsdb" >/dev/null 2>&1 || true
        rm -rf "${SOC_ROOT}/vcd2fsdbLog"
    fi
fi
