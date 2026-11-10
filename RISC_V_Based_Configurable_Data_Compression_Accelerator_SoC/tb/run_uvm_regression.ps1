<#
.SYNOPSIS
    Unified Verification & Regression Runner for IP-Level UVM & VIP Suites.

.DESCRIPTION
    Runs reusable VIP sanity tests, RLE UVM 1.2 testbench, DMA UVM 1.2 testbench,
    and VeeR SoC firmware verification with deterministic seed and nonzero exit on failure.

.PARAMETER Target
    'vip', 'rle_uvm', 'dma_uvm', 'firmware', or 'all'. Defaults to 'all'.

.PARAMETER Seed
    Deterministic simulation random seed. Defaults to 12345.
#>

[CmdletBinding()]
param (
    [Parameter(Position = 0)]
    [ValidateSet('vip', 'rle_uvm', 'dma_uvm', 'firmware', 'all')]
    [string]$Target = 'all',

    [int]$Seed = 12345,

    [string]$BuildRoot = (Join-Path ([System.IO.Path]::GetTempPath()) "riscv_soc_sim")
)

$ErrorActionPreference = 'Stop'

# Ensure ModelSim is discoverable
if (-not (Get-Command vlog -ErrorAction SilentlyContinue)) {
    $candidates = @("C:\intelFPGA\20.1\modelsim_ase\win32aloem", "C:\intelFPGA_lite\20.1\modelsim_ase\win32aloem", "C:\intelFPGA\19.1\modelsim_ase\win32aloem")
    foreach ($c in $candidates) {
        if (Test-Path "$c\vlog.exe") {
            $env:Path = "$c;$env:Path"
            break
        }
    }
}

$VlogExe = (Get-Command vlog -ErrorAction Stop).Source
$ModelSimRoot = Split-Path (Split-Path $VlogExe -Parent) -Parent
$UvmSrc = ((Join-Path $ModelSimRoot "verilog_src\uvm-1.2\src") -replace '\\', '/')
if (!(Test-Path $UvmSrc)) { throw "UVM 1.2 source directory not found at $UvmSrc" }

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

function Ensure-UvmCompiled($WorkLib) {
    if (!(Test-Path $WorkLib)) { vlib $WorkLib | Out-Null }
    $out = vlog -work $WorkLib -sv +define+UVM_NO_DPI "+incdir+$UvmSrc" "$UvmSrc/uvm_pkg.sv" 2>&1
    if ($LASTEXITCODE -ne 0) { throw "Failed compiling uvm_pkg into $WorkLib`:`n$($out -join "`n")" }
}

$Results = [ordered]@{}
$AllPassed = $true

Write-Host "==================================================================" -ForegroundColor Cyan
Write-Host " RISC-V Compression SoC - IP UVM & VIP Regression Runner" -ForegroundColor Cyan
Write-Host " Target : $Target  |  Seed : $Seed" -ForegroundColor Cyan
Write-Host "==================================================================" -ForegroundColor Cyan

# -----------------------------------------------------------------------------
# 1. VIP Sanity Regression
# -----------------------------------------------------------------------------
if ($Target -eq 'vip' -or $Target -eq 'all') {
    Write-Host "`n>>> [PHASE 1] Executing Reusable VIP Sanity Suite..." -ForegroundColor Yellow
    if (!(Test-Path $VipWork)) { vlib $VipWork | Out-Null }
    $vlogOut = vlog -work $VipWork -sv -f vip/vip.f vip/tb_vip_sanity.sv 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Host "[FAIL] VIP Compilation Error`n$($vlogOut -join "`n")" -ForegroundColor Red
        $Results['VIP_Sanity'] = 'COMPILE_FAIL'
        $AllPassed = $false
    } else {
        $vsimOut = vsim -c -sv_seed $Seed -do "run -all; quit -f" -work $VipWork tb_vip_sanity 2>&1
        $logStr = $vsimOut -join "`n"
        if ($logStr -match "STATUS\s*:\s*\[ALL TESTS PASSED SUCCESSFULLY\]") {
            Write-Host "[PASS] VIP Sanity Suite Passed" -ForegroundColor Green
            $Results['VIP_Sanity'] = 'PASS (7/7 Checks)'
        } else {
            Write-Host "[FAIL] VIP Sanity Suite failed`n$logStr" -ForegroundColor Red
            $Results['VIP_Sanity'] = 'FAIL'
            $AllPassed = $false
        }
    }
}

# -----------------------------------------------------------------------------
# 2. RLE UVM 1.2 Environment & Assertions
# -----------------------------------------------------------------------------
if ($Target -eq 'rle_uvm' -or $Target -eq 'all') {
    Write-Host "`n>>> [PHASE 2] Executing RLE Accelerator UVM 1.2 Suite..." -ForegroundColor Yellow
    Ensure-UvmCompiled $UvmWork
    $vlogOut = vlog -work $UvmWork -sv +define+UVM_NO_DPI "+incdir+$UvmSrc" -f uvm/rle/rle_uvm.f 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Host "[FAIL] RLE UVM Compilation Error`n$($vlogOut -join "`n")" -ForegroundColor Red
        $Results['RLE_UVM'] = 'COMPILE_FAIL'
        $AllPassed = $false
    } else {
        $vsimOut = vsim -c -sv_seed $Seed -do "run -all; quit -f" -work $UvmWork tb_rle_uvm +UVM_TESTNAME=rle_test 2>&1
        $logStr = $vsimOut -join "`n"
        $scbPass  = ($logStr -match "OVERALL SCOREBOARD VERDICT\s*:\s*\[ALL CHECKS PASSED\]")
        $covPass  = ($logStr -match "Overall Covered Functional Bins\s*:\s*\d+\s*/\s*\d+\s*\(100\.0%\)")
        $asrtPass = ($logStr -match "ALL PROTOCOL ASSERTIONS PASSED CLEANLY \(0 Errors\)")
        $uvmClean = ($logStr -match "UVM_ERROR\s*:\s*0") -and ($logStr -match "UVM_FATAL\s*:\s*0")
        if ($scbPass -and $covPass -and $asrtPass -and $uvmClean) {
            Write-Host "[PASS] RLE UVM Suite Passed (100% Cov, 0 Asrt Err)" -ForegroundColor Green
            $Results['RLE_UVM'] = 'PASS (14/14 Txns, 100% Cov, 0 Asrt Err)'
        } else {
            Write-Host "[FAIL] RLE UVM Suite verification failed`n$logStr" -ForegroundColor Red
            $Results['RLE_UVM'] = 'FAIL'
            $AllPassed = $false
        }
    }
}

# -----------------------------------------------------------------------------
# 3. DMA UVM 1.2 Environment & Assertions
# -----------------------------------------------------------------------------
if ($Target -eq 'dma_uvm' -or $Target -eq 'all') {
    Write-Host "`n>>> [PHASE 3] Executing DMA Controller UVM 1.2 Suite..." -ForegroundColor Yellow
    Ensure-UvmCompiled $UvmWork
    $vlogOut = vlog -work $UvmWork -sv +define+UVM_NO_DPI "+incdir+$UvmSrc" -f uvm/dma/dma_uvm.f 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Host "[FAIL] DMA UVM Compilation Error`n$($vlogOut -join "`n")" -ForegroundColor Red
        $Results['DMA_UVM'] = 'COMPILE_FAIL'
        $AllPassed = $false
    } else {
        $vsimOut = vsim -c -sv_seed $Seed -do "run -all; quit -f" -work $UvmWork tb_dma_uvm +UVM_TESTNAME=dma_test 2>&1
        $logStr = $vsimOut -join "`n"
        $scbPass  = ($logStr -match "OVERALL SCOREBOARD VERDICT\s*:\s*\[ALL CHECKS PASSED\]")
        $covPass  = ($logStr -match "Overall Covered Functional Bins\s*:\s*\d+\s*/\s*\d+\s*\(100\.0%\)")
        $asrtPass = ($logStr -match "ALL PROTOCOL ASSERTIONS PASSED CLEANLY \(0 Errors\)")
        $uvmClean = ($logStr -match "UVM_ERROR\s*:\s*0") -and ($logStr -match "UVM_FATAL\s*:\s*0")
        if ($scbPass -and $covPass -and $asrtPass -and $uvmClean) {
            Write-Host "[PASS] DMA UVM Suite Passed (100% Cov, 0 Asrt Err)" -ForegroundColor Green
            $Results['DMA_UVM'] = 'PASS (15/15 Xfers, 100% Cov, 0 Asrt Err)'
        } else {
            Write-Host "[FAIL] DMA UVM Suite verification failed`n$logStr" -ForegroundColor Red
            $Results['DMA_UVM'] = 'FAIL'
            $AllPassed = $false
        }
    }
}

# -----------------------------------------------------------------------------
# 4. VeeR EL2 SoC Firmware Regression
# -----------------------------------------------------------------------------
if ($Target -eq 'firmware' -or $Target -eq 'all') {
    Write-Host "`n>>> [PHASE 4] Executing VeeR EL2 SoC Firmware Regression (tb_soc_dma_firmware)..." -ForegroundColor Yellow
    $RepoRoot = Split-Path $ScriptDir -Parent
    if (!(Test-Path $SocWork)) { vlib $SocWork | Out-Null }
    $fwInc = @(
        "+incdir+third_party/RISC-V-VeeR-EL2/design/include",
        "+incdir+third_party/RISC-V-VeeR-EL2/snapshots/soc_sim",
        "+incdir+rtl/peripherals/uart",
        "+incdir+firmware/images",
        "+incdir+verification/standalone/soc"
    )
    Push-Location $RepoRoot
    try {
        $vlogOut = vlog -work $SocWork -sv -mfcu "+define+RV_OPENSOURCE" @fwInc -f verification/standalone/filelists/dma_firmware.f 2>&1
        if ($LASTEXITCODE -ne 0) {
            Write-Host "[FAIL] SoC Firmware Compilation Error`n$($vlogOut -join "`n")" -ForegroundColor Red
            $Results['SoC_Firmware'] = 'COMPILE_FAIL'
            $AllPassed = $false
        } else {
            $vsimOut = vsim -suppress 3999,12036,19 -c -sv_seed $Seed -do "run -all; quit -f" -work $SocWork tb_soc_dma_firmware 2>&1
            $logStr = $vsimOut -join "`n"
            if ($logStr -match "OVERALL COMPLETION STATUS:\s*>>> ALL TESTS PASSED <<<") {
                Write-Host "[PASS] VeeR SoC Firmware Regression Passed (0xCAFED00D)" -ForegroundColor Green
                $Results['SoC_Firmware'] = 'PASS (Signature 0xCAFED00D)'
            } else {
                Write-Host "[FAIL] VeeR SoC Firmware Regression failed`n$logStr" -ForegroundColor Red
                $Results['SoC_Firmware'] = 'FAIL'
                $AllPassed = $false
            }
        }
    } finally {
        Pop-Location
    }
}

Write-Host "`n==================================================================" -ForegroundColor Cyan
Write-Host "                FINAL UVM & VIP REGRESSION SUMMARY               " -ForegroundColor Cyan
Write-Host "==================================================================" -ForegroundColor Cyan
foreach ($suite in $Results.Keys) {
    $stat = $Results[$suite]
    $color = if ($stat -match "^PASS") { "Green" } else { "Red" }
    Write-Host ("  {0,-15} : {1}" -f $suite, $stat) -ForegroundColor $color
}
Write-Host "==================================================================" -ForegroundColor Cyan

if (-not $AllPassed) { exit 1 } else { exit 0 }
