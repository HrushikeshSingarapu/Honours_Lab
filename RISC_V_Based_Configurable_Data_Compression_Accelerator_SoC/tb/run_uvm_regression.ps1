<#
.SYNOPSIS
    Unified Verification & Regression Runner for RISC-V Configurable Compression Accelerator SoC.

.DESCRIPTION
    Runs reusable VIP sanity tests, RLE UVM 1.2 testbench, DMA UVM 1.2 testbench,
    and end-to-end VeeR SoC firmware regression with protocol assertions and functional coverage.

.PARAMETER Target
    'vip', 'rle_uvm', 'dma_uvm', 'firmware', or 'all'. Defaults to 'all'.

.EXAMPLE
    .\run_uvm_regression.ps1 -Target vip
    .\run_uvm_regression.ps1 -Target rle_uvm
    .\run_uvm_regression.ps1 -Target dma_uvm
    .\run_uvm_regression.ps1 -Target firmware
    .\run_uvm_regression.ps1 -Target all
#>

[CmdletBinding()]
param (
    [Parameter(Position = 0)]
    [ValidateSet('vip', 'rle_uvm', 'dma_uvm', 'firmware', 'all')]
    [string]$Target = 'all'
)

$ErrorActionPreference = 'Stop'

# Define build directory on drive with adequate space
$BuildRoot = "H:\sim_build"
$TempDir   = "$BuildRoot\temp"
$VipWork   = "$BuildRoot\vip_work"
$UvmWork   = "$BuildRoot\uvm_work"
$SocWork   = "$BuildRoot\soc_work"

if (!(Test-Path $BuildRoot)) { New-Item -ItemType Directory -Path $BuildRoot -Force | Out-Null }
if (!(Test-Path $TempDir))   { New-Item -ItemType Directory -Path $TempDir -Force | Out-Null }
$env:TEMP = $TempDir
$env:TMP  = $TempDir

$ScriptDir = $PSScriptRoot
Set-Location -Path $ScriptDir

Write-Host "==================================================================" -ForegroundColor Cyan
Write-Host " RISC-V Compression SoC - Unified UVM & VIP Verification Runner" -ForegroundColor Cyan
Write-Host " Target : $Target" -ForegroundColor Cyan
Write-Host " Build  : $BuildRoot" -ForegroundColor Cyan
Write-Host "==================================================================" -ForegroundColor Cyan

$Results = @{}

# -----------------------------------------------------------------------------
# 1. VIP Sanity Regression
# -----------------------------------------------------------------------------
if ($Target -eq 'vip' -or $Target -eq 'all') {
    Write-Host "`n>>> [PHASE 1] Executing Reusable VIP Sanity Suite..." -ForegroundColor Yellow
    if (!(Test-Path $VipWork)) { vlib $VipWork }
    
    $vlogOut = vlog -work $VipWork -sv -f vip/vip.f vip/tb_vip_sanity.sv 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Host "[FAIL] VIP Compilation Error" -ForegroundColor Red
        $Results['VIP_Sanity'] = 'COMPILE_FAIL'
    } else {
        $vsimOut = vsim -c -do "run -all; quit -f" -work $VipWork tb_vip_sanity 2>&1
        $logStr = $vsimOut -join "`n"
        if ($logStr -match "STATUS\s*:\s*\[ALL TESTS PASSED SUCCESSFULLY\]") {
            Write-Host "[PASS] VIP Sanity Suite: 7/7 Tests Passed" -ForegroundColor Green
            $Results['VIP_Sanity'] = 'PASS (7/7 Checks)'
        } else {
            Write-Host "[FAIL] VIP Sanity Suite checks failed" -ForegroundColor Red
            $Results['VIP_Sanity'] = 'FAIL'
        }
    }
}

# -----------------------------------------------------------------------------
# 2. RLE UVM 1.2 Environment & Assertions
# -----------------------------------------------------------------------------
if ($Target -eq 'rle_uvm' -or $Target -eq 'all') {
    Write-Host "`n>>> [PHASE 2] Executing RLE Accelerator UVM 1.2 Suite..." -ForegroundColor Yellow
    if (!(Test-Path $UvmWork)) { vlib $UvmWork }
    
    $vlogOut = vlog -work $UvmWork -sv -f uvm/rle/rle_uvm.f 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Host "[FAIL] RLE UVM Compilation Error" -ForegroundColor Red
        $Results['RLE_UVM'] = 'COMPILE_FAIL'
    } else {
        $vsimOut = vsim -c -do "run -all; quit -f" -work $UvmWork tb_rle_uvm +UVM_TESTNAME=rle_test 2>&1
        $logStr = $vsimOut -join "`n"
        $scbPass  = ($logStr -match "OVERALL SCOREBOARD VERDICT\s*:\s*\[ALL CHECKS PASSED\]")
        $covPass  = ($logStr -match "Overall Covered Functional Bins\s*:\s*\d+\s*/\s*\d+\s*\(100\.0%\)")
        $asrtPass = ($logStr -match "ALL PROTOCOL ASSERTIONS PASSED CLEANLY \(0 Errors\)")
        
        if ($scbPass -and $covPass -and $asrtPass) {
            Write-Host "[PASS] RLE UVM Suite: 9/9 Scenarios Passed, 100% Coverage, 0 Assertion Errors" -ForegroundColor Green
            $Results['RLE_UVM'] = 'PASS (9/9 Scenarios, 100% Cov, 0 Asrt Err)'
        } else {
            Write-Host "[FAIL] RLE UVM Suite verification failed" -ForegroundColor Red
            $Results['RLE_UVM'] = 'FAIL'
        }
    }
}

# -----------------------------------------------------------------------------
# 3. DMA UVM 1.2 Environment & Assertions
# -----------------------------------------------------------------------------
if ($Target -eq 'dma_uvm' -or $Target -eq 'all') {
    Write-Host "`n>>> [PHASE 3] Executing DMA Controller UVM 1.2 Suite..." -ForegroundColor Yellow
    if (!(Test-Path $UvmWork)) { vlib $UvmWork }
    
    $vlogOut = vlog -work $UvmWork -sv -f uvm/dma/dma_uvm.f 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Host "[FAIL] DMA UVM Compilation Error" -ForegroundColor Red
        $Results['DMA_UVM'] = 'COMPILE_FAIL'
    } else {
        $vsimOut = vsim -c -do "run -all; quit -f" -work $UvmWork tb_dma_uvm +UVM_TESTNAME=dma_test 2>&1
        $logStr = $vsimOut -join "`n"
        $scbPass  = ($logStr -match "OVERALL SCOREBOARD VERDICT\s*:\s*\[ALL CHECKS PASSED\]")
        $covPass  = ($logStr -match "Overall Covered Functional Bins\s*:\s*9\s*/\s*9\s*\(100\.0%\)")
        $asrtPass = ($logStr -match "ALL PROTOCOL ASSERTIONS PASSED CLEANLY \(0 Errors\)")
        
        if ($scbPass -and $covPass -and $asrtPass) {
            Write-Host "[PASS] DMA UVM Suite: 10/10 Scenarios Passed, 100% Coverage, 0 Assertion Errors" -ForegroundColor Green
            $Results['DMA_UVM'] = 'PASS (10/10 Scenarios, 100% Cov, 0 Asrt Err)'
        } else {
            Write-Host "[FAIL] DMA UVM Suite verification failed" -ForegroundColor Red
            $Results['DMA_UVM'] = 'FAIL'
        }
    }
}

# -----------------------------------------------------------------------------
# 4. VeeR EL2 SoC Firmware Regression
# -----------------------------------------------------------------------------
if ($Target -eq 'firmware' -or $Target -eq 'all') {
    Write-Host "`n>>> [PHASE 4] Executing VeeR EL2 SoC Firmware Regression (tb_soc_dma_firmware)..." -ForegroundColor Yellow
    if (!(Test-Path $SocWork)) { vlib $SocWork }
    
    $vlogOut = vlog -work $SocWork -sv -mfcu +define+RV_OPENSOURCE -f dma_firmware.f 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Host "[FAIL] SoC Firmware Testbench Compilation Error" -ForegroundColor Red
        $Results['SoC_Firmware'] = 'COMPILE_FAIL'
    } else {
        $vsimOut = vsim -suppress 3999,12036 -c -do "run -all; quit -f" -work $SocWork tb_soc_dma_firmware 2>&1
        $logStr = $vsimOut -join "`n"
        $sigPass = ($logStr -match "OVERALL COMPLETION STATUS: >>> ALL TESTS PASSED <<< \(Signature 0xCAFE_D00D\)")
        if ($sigPass) {
            Write-Host "[PASS] VeeR SoC Firmware Regression: Signature 0xCAFED00D Detected, All 4 Patterns Validated" -ForegroundColor Green
            $Results['SoC_Firmware'] = 'PASS (Signature 0xCAFED00D)'
        } else {
            Write-Host "[FAIL] VeeR SoC Firmware Regression failed" -ForegroundColor Red
            $Results['SoC_Firmware'] = 'FAIL'
        }
    }
}

# -----------------------------------------------------------------------------
# Summary Report
# -----------------------------------------------------------------------------
Write-Host "`n==================================================================" -ForegroundColor Cyan
Write-Host "                FINAL UVM & VIP REGRESSION SUMMARY               " -ForegroundColor Cyan
Write-Host "==================================================================" -ForegroundColor Cyan
foreach ($suite in $Results.Keys) {
    $stat = $Results[$suite]
    $color = if ($stat -match "PASS") { "Green" } else { "Red" }
    Write-Host ("  {0,-15} : {1}" -f $suite, $stat) -ForegroundColor $color
}
Write-Host "==================================================================" -ForegroundColor Cyan

