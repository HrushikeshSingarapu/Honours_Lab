<#
.SYNOPSIS
    Unified Master Regression Runner for RISC-V Compression SoC Verification.

.DESCRIPTION
    Executes ModelSim Starter Edition verification across all active verification layers:
      - standalone    : IP-level & SoC-structural standalone testbenches (13 TBs)
      - interconnect  : 4x8 AXI4 Interconnect stress & protocol assertions TB
      - vip           : Reusable UART / GPIO / Reset / IRQ VIP sanity testbench
      - rle_uvm       : RLE Accelerator IP UVM 1.2 environment + assertions
      - dma_uvm       : DMA Controller IP UVM 1.2 environment + assertions
      - firmware      : VeeR EL2 bare-metal firmware tests (boot, periph, uart, dma)
      - soc_uvm       : Integrated VeeR EL2 SoC 4-agent UVM environment tests

    All build artifacts and WLF dumps are stored outside the repository under the system
    temp directory (override via -BuildRoot), while readable logs are stored in simulation/logs/.
    Exits with code 0 only if all executed suites pass with 0 UVM/assertion/TB errors.

.PARAMETER Suite
    'all', 'standalone', 'interconnect', 'vip', 'rle_uvm', 'dma_uvm', 'firmware', 'soc_uvm'.
    Defaults to 'all'.

.PARAMETER Seed
    Deterministic simulation seed passed via -sv_seed. Defaults to 12345.

.PARAMETER IncludeLongUvm
    Also run long 115200-baud integrated SoC UVM tests (soc_smoke_test ~5m, uart_echo_test ~23m).

.PARAMETER FailFast
    Stop immediately on first failing test case.
#>

[CmdletBinding()]
param (
    [ValidateSet('all', 'standalone', 'interconnect', 'vip', 'rle_uvm', 'dma_uvm', 'firmware', 'soc_uvm')]
    [string]$Suite = 'all',

    [int]$Seed = 12345,

    [switch]$IncludeLongUvm,

    [switch]$FailFast,

    [string]$BuildRoot = (Join-Path ([System.IO.Path]::GetTempPath()) "riscv_soc_sim\full_reg")
)

$ErrorActionPreference = 'Stop'

# Discover ModelSim
if (-not (Get-Command vlog -ErrorAction SilentlyContinue)) {
    $candidates = @(
        "C:\intelFPGA\20.1\modelsim_ase\win32aloem",
        "C:\intelFPGA_lite\20.1\modelsim_ase\win32aloem",
        "C:\intelFPGA\19.1\modelsim_ase\win32aloem"
    )
    foreach ($c in $candidates) {
        if (Test-Path "$c\vlog.exe") {
            $env:Path = "$c;$env:Path"
            break
        }
    }
}

foreach ($tool in @("vlib", "vmap", "vlog", "vsim")) {
    if (-not (Get-Command $tool -ErrorAction SilentlyContinue)) {
        throw "Required ModelSim tool '$tool' not found in PATH."
    }
}

$ScriptDir    = $PSScriptRoot
$RepoRoot     = (Resolve-Path (Join-Path $ScriptDir "..\..")).Path
$LogDir       = Join-Path $RepoRoot "simulation\logs"
$TempDir      = Join-Path $BuildRoot "temp"
$ModelSimRoot = Split-Path (Split-Path (Get-Command vlog).Source -Parent) -Parent
$UvmSrc       = (Join-Path $ModelSimRoot "verilog_src\uvm-1.2\src") -replace '\\', '/'
$ModelSimIni  = Join-Path $ModelSimRoot "modelsim.ini"
if (-not (Test-Path $UvmSrc)) { throw "UVM 1.2 source directory not found at $UvmSrc" }

New-Item -ItemType Directory -Force $BuildRoot, $TempDir, $LogDir | Out-Null
$env:TEMP = $TempDir
$env:TMP  = $TempDir

Set-Location $RepoRoot

$script:Results    = [ordered]@{}
$script:AllPassed  = $true

function Init-WorkLib([string]$Name) {
    $libDir = Join-Path $BuildRoot $Name
    $work   = Join-Path $libDir "work"
    $ini    = Join-Path $libDir "modelsim.ini"
    New-Item -ItemType Directory -Force $libDir | Out-Null
    if (Test-Path $work) { Remove-Item -Recurse -Force $work }
    & vlib $work | Out-Null
    if (Test-Path $ModelSimIni) {
        Copy-Item $ModelSimIni $ini -Force
        (Get-Item $ini).IsReadOnly = $false
    } else {
        Push-Location $libDir
        try { & vmap -c | Out-Null } finally { Pop-Location }
    }
    $workFwd = $work -replace '\\', '/'
    $iniFwd  = $ini -replace '\\', '/'
    $env:MODELSIM = $iniFwd
    & vmap work $workFwd | Out-Null
    return @{ Dir = $libDir; Work = $workFwd; Ini = $iniFwd }
}

function Record-Result([string]$Key, [string]$Status, [bool]$IsFailure) {
    $script:Results[$Key] = $Status
    if ($IsFailure) {
        $script:AllPassed = $false
        Write-Host ("  [FAIL] {0,-34} : {1}" -f $Key, $Status) -ForegroundColor Red
        if ($FailFast) { throw "Aborting due to -FailFast on '$Key' ($Status)" }
    } elseif ($Status -match "^SKIP|^NOT RUN") {
        Write-Host ("  [SKIP] {0,-34} : {1}" -f $Key, $Status) -ForegroundColor Yellow
    } else {
        Write-Host ("  [PASS] {0,-34} : {1}" -f $Key, $Status) -ForegroundColor Green
    }
}

function Invoke-SimCheck {
    param(
        [hashtable]$LibEnv,
        [string]$Key,
        [string]$Top,
        [string]$PassRegex,
        [string[]]$ExtraArgs = @(),
        [switch]$IsUvm,
        [switch]$RequireAsrtZero,
        [switch]$VeerSuppress
    )

    $logFile = (Join-Path $LogDir "reg_${Key}.log") -replace '\\', '/'
    $wlfFile = (Join-Path $LibEnv.Dir "${Key}.wlf") -replace '\\', '/'
    $args = @("-c", "-modelsimini", $LibEnv.Ini, "-lib", $LibEnv.Work, "-sv_seed", "$Seed", "-wlf", $wlfFile, "-l", $logFile)
    if ($VeerSuppress) { $args += @("-suppress", "3999,12036,19") }
    else { $args += @("-suppress", "19") }
    $args += @($Top) + $ExtraArgs + @("-do", "run -all; quit -f")

    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    & vsim @args | Out-Null
    $exitCode = $LASTEXITCODE
    $sw.Stop()
    $elapsed = [math]::Round($sw.Elapsed.TotalSeconds, 1)

    if (-not (Test-Path $logFile)) {
        Record-Result $Key "NO_LOG (exit=$exitCode)" $true
        return
    }
    $log = Get-Content $logFile -Raw

    $passHit = ($log -match $PassRegex)
    $realFatal = ($log -match "\*\* Fatal:") -or ($log -match "Error loading design")
    $uvmClean = $true
    if ($IsUvm) {
        $uvmClean = ($log -match "UVM_ERROR\s*:\s*0") -and ($log -match "UVM_FATAL\s*:\s*0")
    }
    $asrtClean = $true
    if ($RequireAsrtZero) {
        $asrtClean = -not ($log -match "\[\S* ERROR\]|ASSERTION ERRORS\s*:\s*[1-9]\d*|\(TOTAL=[1-9]\d*\)")
    }

    if ($exitCode -eq 0 -and $passHit -and -not $realFatal -and $uvmClean -and $asrtClean) {
        Record-Result $Key "PASS (${elapsed}s)" $false
    } else {
        $reason = "FAIL (exit=$exitCode, banner=$passHit, fatal=$realFatal, uvmClean=$uvmClean, asrtClean=$asrtClean, ${elapsed}s)"
        Record-Result $Key $reason $true
    }
}

Write-Host "========================================================================" -ForegroundColor Cyan
Write-Host " RISC-V Compression SoC - Full Verification Regression Runner" -ForegroundColor Cyan
Write-Host " Suite : $Suite | Seed : $Seed | IncludeLongUvm : $IncludeLongUvm" -ForegroundColor Cyan
Write-Host "========================================================================" -ForegroundColor Cyan

# =============================================================================
# 1 & 2. Standalone IP/SoC Tests + 4x8 Interconnect Verification
# =============================================================================
if ($Suite -in @('all', 'standalone', 'interconnect')) {
    Write-Host "`n>>> [SUITE] Standalone RTL / Bridge / Interconnect / Audit Suites..." -ForegroundColor Yellow
    $stEnv = Init-WorkLib "standalone"
    $stInc = @(
        "+incdir+rtl/soc",
        "+incdir+rtl/interconnect",
        "+incdir+rtl/peripherals/uart",
        "+incdir+rtl/peripherals/timer",
        "+incdir+rtl/peripherals/gpio",
        "+incdir+rtl/peripherals/crc",
        "+incdir+rtl/accelerators/rle",
        "+incdir+rtl/accelerators/dma",
        "+incdir+verification/assertions",
        "+incdir+verification/standalone/soc"
    )
    $rtlAndAsrt = @(
        "rtl/peripherals/uart/axi_uart_top.v",
        "rtl/peripherals/uart/axi_internal_fifo.v",
        "rtl/peripherals/uart/uart_controller.v",
        "rtl/peripherals/uart/uart_parity_bit_compute.v",
        "rtl/peripherals/uart/uart_receiver.v",
        "rtl/peripherals/uart/uart_transmitter.v",
        "rtl/peripherals/timer/timer_top.v",
        "rtl/peripherals/gpio/gpio_top.v",
        "rtl/peripherals/crc/crc32_top.v",
        "rtl/accelerators/rle/rle_top.v",
        "rtl/accelerators/rle/rle_controller.v",
        "rtl/accelerators/rle/rle_decoder.v",
        "rtl/accelerators/rle/rle_encoder.v",
        "rtl/accelerators/rle/rle_reg_block.v",
        "rtl/accelerators/dma/dma_reg_file.v",
        "rtl/accelerators/dma/dma_master_engine.v",
        "rtl/accelerators/dma/dma_sequencer.v",
        "rtl/accelerators/dma/dma_top.v",
        "rtl/interconnect/priority_encoder.v",
        "rtl/interconnect/arbiter.v",
        "rtl/interconnect/axi_interconnect.v",
        "rtl/interconnect/axi_interconnect_wrap_4x8.v",
        "rtl/interconnect/axi64_to_32_bridge.v",
        "rtl/soc/soc_top.v"
    )
    $stCompileLog = Join-Path $LogDir "reg_standalone_compile.log"
    & vlog -work $stEnv.Work -modelsimini $stEnv.Ini -sv @stInc @rtlAndAsrt -f "verification/assertions/assertions.f" > $stCompileLog 2>&1
    if ($LASTEXITCODE -ne 0) {
        Record-Result "standalone_rtl_compile" "COMPILE_FAIL (see $stCompileLog)" $true
    } else {
        $stTests = @()
        if ($Suite -in @('all', 'standalone')) {
            $stTests += @(
                @{ Key = "st_dma_reg_file";   File = "verification/standalone/dma/tb_dma_reg_file.sv";            Top = "tb_dma_reg_file";           Pass = "ALL STAGE 1 DMA REGISTER INTERFACE CHECKS PASSED!"; Asrt = $false },
                @{ Key = "st_dma_master";     File = "verification/standalone/dma/tb_dma_master_engine.sv";       Top = "tb_dma_master_engine";      Pass = "ALL STAGE 2 DMA AXI MASTER ENGINE CHECKS PASSED!";  Asrt = $false },
                @{ Key = "st_dma_sequencer";  File = "verification/standalone/dma/tb_dma_sequencer.sv";           Top = "tb_dma_sequencer";          Pass = "ALL DMA SEQUENCER CHECKS PASSED!";                   Asrt = $false },
                @{ Key = "st_dma_unit";       File = "verification/standalone/dma/tb_dma_unit.sv";                Top = "tb_dma_unit";               Pass = "ALL DMA INTEGRATED UNIT CHECKS PASSED!";             Asrt = $true  },
                @{ Key = "st_crc32";          File = "verification/standalone/crc32/tb_crc32.sv";                 Top = "tb_crc32";                  Pass = "ALL CRC-32 TESTS PASSED SUCCESSFULLY!";              Asrt = $false },
                @{ Key = "st_uart_top";       File = "verification/standalone/uart/tb_uart_top.sv";               Top = "tb_uart_top";               Pass = "ALL UART TESTS PASSED SUCCESSFULLY!";                Asrt = $false },
                @{ Key = "st_gpio_top";       File = "verification/standalone/gpio/tb_gpio_top.sv";               Top = "tb_gpio_top";               Pass = "ALL GPIO TESTS PASSED SUCCESSFULLY!";                Asrt = $false },
                @{ Key = "st_timer_top";      File = "verification/standalone/timer/tb_timer_top.sv";             Top = "tb_timer_top";              Pass = "ALL TIMER TESTS PASSED SUCCESSFULLY!";               Asrt = $false },
                @{ Key = "st_rle_top";        File = "verification/standalone/rle/tb_rle_top.sv";                 Top = "tb_rle_top";                Pass = "OVERALL STATUS: ALL TESTS PASSED!";                  Asrt = $false },
                @{ Key = "st_axi_bridge";     File = "verification/standalone/interconnect/tb_axi64_to_32_bridge.sv"; Top = "tb_axi64_to_32_bridge"; Pass = "STATUS: ALL TESTS PASSED SUCCESSFULLY!";           Asrt = $false },
                @{ Key = "st_soc_mem";        File = "verification/standalone/soc/tb_soc_mem_access.sv";          Top = "tb_soc_mem_access";         Pass = "\[RESULT\] ALL TESTS PASSED SUCCESSFULLY!";          Asrt = $false },
                @{ Key = "st_soc_dma_int";    File = "verification/standalone/soc/tb_soc_dma_integration.sv";     Top = "tb_soc_dma_integration";    Pass = "ALL SoC DMA INTEGRATION CHECKS PASSED SUCCESSFULLY!"; Asrt = $false },
                @{ Key = "st_addr_audit";     File = "verification/standalone/soc/tb_soc_address_map_audit.sv";   Top = "tb_soc_address_map_audit";  Pass = "STATUS: ALL ADDRESS MAP AUDIT CHECKS PASSED!";       Asrt = $true  }
            )
        }
        if ($Suite -in @('all', 'interconnect')) {
            $stTests += @(
                @{ Key = "ic_4x8_stress";     File = "verification/standalone/interconnect/tb_axi_interconnect_4x8.sv"; Top = "tb_axi_interconnect_4x8"; Pass = "STATUS: ALL INTERCONNECT TESTS & ASSERTIONS PASSED!"; Asrt = $true }
            )
        }
        foreach ($t in $stTests) {
            $cLog = Join-Path $LogDir "reg_$($t.Key)_compile.log"
            & vlog -work $stEnv.Work -modelsimini $stEnv.Ini -sv @stInc $t.File > $cLog 2>&1
            if ($LASTEXITCODE -ne 0) {
                Record-Result $t.Key "COMPILE_FAIL (see $cLog)" $true
            } else {
                Invoke-SimCheck -LibEnv $stEnv -Key $t.Key -Top $t.Top -PassRegex $t.Pass -RequireAsrtZero:$($t.Asrt)
            }
        }
    }
}

# =============================================================================
# 3. VIP Sanity Suite
# =============================================================================
if ($Suite -in @('all', 'vip')) {
    Write-Host "`n>>> [SUITE] Reusable VIP Sanity Suite..." -ForegroundColor Yellow
    $vipEnv = Init-WorkLib "vip"
    Push-Location (Join-Path $RepoRoot "tb")
    try {
        $cLog = Join-Path $LogDir "reg_vip_compile.log"
        & vlog -work $vipEnv.Work -modelsimini $vipEnv.Ini -sv -f "vip/vip.f" "vip/tb_vip_sanity.sv" > $cLog 2>&1
        $compileOk = ($LASTEXITCODE -eq 0)
    } finally {
        Pop-Location
    }
    if (-not $compileOk) {
        Record-Result "vip_sanity" "COMPILE_FAIL (see $cLog)" $true
    } else {
        Invoke-SimCheck -LibEnv $vipEnv -Key "vip_sanity" -Top "tb_vip_sanity" -PassRegex "STATUS\s*:\s*\[ALL TESTS PASSED SUCCESSFULLY\]"
    }
}

# =============================================================================
# 4. RLE UVM 1.2 IP Suite
# =============================================================================
if ($Suite -in @('all', 'rle_uvm')) {
    Write-Host "`n>>> [SUITE] RLE Accelerator IP UVM 1.2 Suite..." -ForegroundColor Yellow
    $rleEnv = Init-WorkLib "rle_uvm"
    $cLog = Join-Path $LogDir "reg_rle_uvm_compile.log"
    & vlog -work $rleEnv.Work -modelsimini $rleEnv.Ini -sv "+define+UVM_NO_DPI" "+incdir+$UvmSrc" "$UvmSrc/uvm_pkg.sv" > $cLog 2>&1
    $ok1 = ($LASTEXITCODE -eq 0)
    Push-Location (Join-Path $RepoRoot "tb")
    try {
        & vlog -work $rleEnv.Work -modelsimini $rleEnv.Ini -sv "+define+UVM_NO_DPI" "+incdir+$UvmSrc" -f "uvm/rle/rle_uvm.f" >> $cLog 2>&1
        $ok2 = ($LASTEXITCODE -eq 0)
    } finally {
        Pop-Location
    }
    if (-not ($ok1 -and $ok2)) {
        Record-Result "rle_uvm_test" "COMPILE_FAIL (see $cLog)" $true
    } else {
        Invoke-SimCheck -LibEnv $rleEnv -Key "rle_uvm_test" -Top "tb_rle_uvm" -ExtraArgs @("+UVM_TESTNAME=rle_test", "+UVM_NO_RELNOTES") -PassRegex "OVERALL SCOREBOARD VERDICT\s*:\s*\[ALL CHECKS PASSED\]" -IsUvm -RequireAsrtZero
    }
}

# =============================================================================
# 5. DMA UVM 1.2 IP Suite
# =============================================================================
if ($Suite -in @('all', 'dma_uvm')) {
    Write-Host "`n>>> [SUITE] DMA Controller IP UVM 1.2 Suite..." -ForegroundColor Yellow
    $dmaEnv = Init-WorkLib "dma_uvm"
    $cLog = Join-Path $LogDir "reg_dma_uvm_compile.log"
    & vlog -work $dmaEnv.Work -modelsimini $dmaEnv.Ini -sv "+define+UVM_NO_DPI" "+incdir+$UvmSrc" "$UvmSrc/uvm_pkg.sv" > $cLog 2>&1
    $ok1 = ($LASTEXITCODE -eq 0)
    Push-Location (Join-Path $RepoRoot "tb")
    try {
        & vlog -work $dmaEnv.Work -modelsimini $dmaEnv.Ini -sv "+define+UVM_NO_DPI" "+incdir+$UvmSrc" -f "uvm/dma/dma_uvm.f" >> $cLog 2>&1
        $ok2 = ($LASTEXITCODE -eq 0)
    } finally {
        Pop-Location
    }
    if (-not ($ok1 -and $ok2)) {
        Record-Result "dma_uvm_test" "COMPILE_FAIL (see $cLog)" $true
    } else {
        Invoke-SimCheck -LibEnv $dmaEnv -Key "dma_uvm_test" -Top "tb_dma_uvm" -ExtraArgs @("+UVM_TESTNAME=dma_test", "+UVM_NO_RELNOTES") -PassRegex "OVERALL SCOREBOARD VERDICT\s*:\s*\[ALL CHECKS PASSED\]" -IsUvm -RequireAsrtZero
    }
}

# =============================================================================
# 6. VeeR EL2 Bare-Metal Firmware Tests
# =============================================================================
if ($Suite -in @('all', 'firmware')) {
    Write-Host "`n>>> [SUITE] VeeR EL2 Bare-Metal Firmware Tests..." -ForegroundColor Yellow
    $fwEnv = Init-WorkLib "firmware"
    $fwInc = @(
        "+incdir+third_party/RISC-V-VeeR-EL2/design/include",
        "+incdir+third_party/RISC-V-VeeR-EL2/snapshots/soc_sim",
        "+incdir+rtl/peripherals/uart",
        "+incdir+firmware/images",
        "+incdir+verification/standalone/soc"
    )
    $cLog = Join-Path $LogDir "reg_fw_compile.log"
    & vlog -work $fwEnv.Work -modelsimini $fwEnv.Ini -sv -mfcu "+define+RV_OPENSOURCE" @fwInc -f "verification/standalone/filelists/dma_firmware.f" > $cLog 2>&1
    $ok = ($LASTEXITCODE -eq 0)
    if ($ok) {
        & vlog -work $fwEnv.Work -modelsimini $fwEnv.Ini -sv -mfcu "+define+RV_OPENSOURCE" @fwInc "verification/standalone/soc/tb_soc_core_boot.sv" >> $cLog 2>&1
        $ok = $ok -and ($LASTEXITCODE -eq 0)
        & vlog -work $fwEnv.Work -modelsimini $fwEnv.Ini -sv -mfcu "+define+RV_OPENSOURCE" @fwInc "verification/standalone/soc/tb_soc_periph_test.sv" >> $cLog 2>&1
        $ok = $ok -and ($LASTEXITCODE -eq 0)
        & vlog -work $fwEnv.Work -modelsimini $fwEnv.Ini -sv -mfcu "+define+RV_OPENSOURCE" @fwInc -f "verification/standalone/filelists/uart_firmware.f" >> $cLog 2>&1
        $ok = $ok -and ($LASTEXITCODE -eq 0)
    }
    if (-not $ok) {
        Record-Result "fw_compile" "COMPILE_FAIL (see $cLog)" $true
    } else {
        Invoke-SimCheck -LibEnv $fwEnv -Key "fw_core_boot"  -Top "tb_soc_core_boot"     -PassRegex "TEST RESULT\s*:\s*>>> PASSED <<<" -VeerSuppress
        Invoke-SimCheck -LibEnv $fwEnv -Key "fw_periph"     -Top "tb_soc_periph_test"   -PassRegex ">>> ALL 5 PERIPHERALS PASSED <<<" -VeerSuppress
        Invoke-SimCheck -LibEnv $fwEnv -Key "fw_uart"       -Top "tb_soc_uart_firmware" -PassRegex "RESULT:\s*\[SUCCESS\] UART transmitted 'H'" -VeerSuppress
        Invoke-SimCheck -LibEnv $fwEnv -Key "fw_dma"        -Top "tb_soc_dma_firmware"  -PassRegex "OVERALL COMPLETION STATUS:\s*>>> ALL TESTS PASSED <<<" -VeerSuppress
    }
}

# =============================================================================
# 7. Integrated 4-Agent SoC UVM Verification Suite
# =============================================================================
if ($Suite -in @('all', 'soc_uvm')) {
    Write-Host "`n>>> [SUITE] Integrated VeeR EL2 SoC UVM 1.2 Suite..." -ForegroundColor Yellow
    $socEnv = Init-WorkLib "soc_uvm"
    $cLog = Join-Path $LogDir "reg_soc_uvm_compile.log"
    & vlog -work $socEnv.Work -modelsimini $socEnv.Ini -sv "+define+UVM_NO_DPI" "+incdir+$UvmSrc" "$UvmSrc/uvm_pkg.sv" > $cLog 2>&1
    $ok1 = ($LASTEXITCODE -eq 0)
    & vlog -work $socEnv.Work -modelsimini $socEnv.Ini -sv -mfcu "+define+UVM_NO_DPI" "+incdir+$UvmSrc" -f "verification/uvm/filelists/soc_uvm.f" >> $cLog 2>&1
    $ok2 = ($LASTEXITCODE -eq 0)
    if (-not ($ok1 -and $ok2)) {
        Record-Result "soc_uvm_compile" "COMPILE_FAIL (see $cLog)" $true
    } else {
        $uvmTests = @("soc_decerr_trap_test", "soc_e2e_flow_test", "soc_reset_recovery_test")
        foreach ($ut in $uvmTests) {
            Invoke-SimCheck -LibEnv $socEnv -Key "uvm_$ut" -Top "tb_soc_top" -ExtraArgs @("+UVM_TESTNAME=$ut", "+UVM_NO_RELNOTES") -PassRegex "OVERALL SOC SCOREBOARD VERDICT:\s*\[ALL CHECKS PASSED\]" -IsUvm -RequireAsrtZero -VeerSuppress
        }
        $longTests = @("soc_smoke_test", "uart_echo_test")
        foreach ($lt in $longTests) {
            if ($IncludeLongUvm) {
                Invoke-SimCheck -LibEnv $socEnv -Key "uvm_$lt" -Top "tb_soc_top" -ExtraArgs @("+UVM_TESTNAME=$lt", "+UVM_NO_RELNOTES") -PassRegex "OVERALL SOC SCOREBOARD VERDICT:\s*\[ALL CHECKS PASSED\]" -IsUvm -RequireAsrtZero -VeerSuppress
            } else {
                Record-Result "uvm_$lt" "NOT RUN (pass -IncludeLongUvm; long 115200-baud run)" $false
            }
        }
    }
}

Write-Host "`n========================================================================" -ForegroundColor Cyan
Write-Host " FULL REGRESSION SUMMARY" -ForegroundColor Cyan
Write-Host "========================================================================" -ForegroundColor Cyan
foreach ($k in $script:Results.Keys) {
    $v = $script:Results[$k]
    $color = if ($v -match "^PASS") { "Green" } elseif ($v -match "^NOT RUN|^SKIP") { "Yellow" } else { "Red" }
    Write-Host ("  {0,-34} : {1}" -f $k, $v) -ForegroundColor $color
}
Write-Host "========================================================================" -ForegroundColor Cyan

if (-not $script:AllPassed) { exit 1 } else { exit 0 }
