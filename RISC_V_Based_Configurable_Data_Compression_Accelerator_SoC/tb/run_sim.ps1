<#
.SYNOPSIS
    Windows Build and Simulation Runner for VeeR EL2 SoC.

.DESCRIPTION
    Automates tool detection, VeeR configuration generation, firmware compilation,
    ModelSim RTL compilation, and simulation execution for the RISC-V SoC.

.PARAMETER Target
    The simulation target: 'boot', 'periph', 'uart', 'dma_firmware', or 'all'. Defaults to 'boot'.

.PARAMETER Clean
    Removes generated work libraries, logs, and simulation artifacts before running.

.PARAMETER Gui
    Launches ModelSim in GUI mode instead of command-line batch mode.

.EXAMPLE
    .\run_sim.ps1 -Target boot
    .\run_sim.ps1 -Target periph
    .\run_sim.ps1 -Target uart
    .\run_sim.ps1 -Target dma_firmware
    .\run_sim.ps1 -Target all
    .\run_sim.ps1 -Clean
#>

[CmdletBinding()]
param (
    [Parameter(Position = 0)]
    [ValidateSet('boot', 'periph', 'uart', 'dma_firmware', 'all')]
    [string]$Target = 'boot',

    [switch]$Clean,
    [switch]$Gui
)

$ErrorActionPreference = 'Stop'

# =============================================================================
# Path Definitions
# =============================================================================
$ScriptDir    = $PSScriptRoot
$RepoRoot     = (Resolve-Path "$ScriptDir\..").Path
$RtlDir       = "$RepoRoot\rtl"
$TbDir        = "$RepoRoot\tb"
$FirmwareDir  = "$RepoRoot\firmware"
$WorkspaceDir = (Resolve-Path "$RepoRoot\..").Path
$VeerDir      = "$WorkspaceDir\Cores-VeeR-EL2"
$UartIpDir    = "$WorkspaceDir\Reliable_Data_Transport_System\rtl\ip\uart"

Write-Host "================================================================" -ForegroundColor Cyan
Write-Host " VeeR EL2 SoC Simulation Runner (Windows Native)" -ForegroundColor Cyan
Write-Host " Target : $Target" -ForegroundColor Cyan
Write-Host " Repo   : $RepoRoot" -ForegroundColor Cyan
Write-Host "================================================================" -ForegroundColor Cyan

# =============================================================================
# Tool Detection
# =============================================================================
function Find-Tool {
    param ([string]$Name, [string[]]$Fallbacks)
    $cmd = Get-Command $Name -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    foreach ($fb in $Fallbacks) {
        if (Test-Path $fb) { return (Resolve-Path $fb).Path }
    }
    return $null
}

$VlogTool = Find-Tool "vlog" @(
    "C:\intelFPGA\20.1\modelsim_ase\win32aloem\vlog.exe",
    "C:\intelFPGA_lite\20.1\modelsim_ase\win32aloem\vlog.exe"
)
$VsimTool = Find-Tool "vsim" @(
    "C:\intelFPGA\20.1\modelsim_ase\win32aloem\vsim.exe",
    "C:\intelFPGA_lite\20.1\modelsim_ase\win32aloem\vsim.exe"
)
$VlibTool = Find-Tool "vlib" @(
    "C:\intelFPGA\20.1\modelsim_ase\win32aloem\vlib.exe",
    "C:\intelFPGA_lite\20.1\modelsim_ase\win32aloem\vlib.exe"
)
$VdirTool = Find-Tool "vdir" @(
    "C:\intelFPGA\20.1\modelsim_ase\win32aloem\vdir.exe",
    "C:\intelFPGA_lite\20.1\modelsim_ase\win32aloem\vdir.exe"
)
$PerlTool = Find-Tool "perl" @(
    "C:\Program Files\Git\usr\bin\perl.exe",
    "C:\Strawberry\perl\bin\perl.exe"
)
$RiscvGcc = Find-Tool "riscv64-unknown-elf-gcc" @(
    "H:\2025.1\gnu\riscv\nt\riscv64-unknown-elf\bin\riscv64-unknown-elf-gcc.exe",
    "C:\SysGCC\riscv\bin\riscv64-unknown-elf-gcc.exe"
)
$RiscvObjcopy = Find-Tool "riscv64-unknown-elf-objcopy" @(
    "H:\2025.1\gnu\riscv\nt\riscv64-unknown-elf\bin\riscv64-unknown-elf-objcopy.exe",
    "C:\SysGCC\riscv\bin\riscv64-unknown-elf-objcopy.exe"
)

if (-not $VlogTool -or -not $VsimTool) {
    Write-Error "ModelSim (vlog/vsim) not found! Ensure Intel FPGA ModelSim is installed and on PATH."
}
Write-Host "[Tools] ModelSim vlog : $VlogTool" -ForegroundColor Green
Write-Host "[Tools] ModelSim vsim : $VsimTool" -ForegroundColor Green

if ($PerlTool) {
    Write-Host "[Tools] Perl runtime  : $PerlTool" -ForegroundColor Green
} else {
    Write-Warning "[Tools] Perl not found! Required only if VeeR snapshot headers need regeneration."
}

if ($RiscvGcc) {
    Write-Host "[Tools] RISC-V GCC    : $RiscvGcc" -ForegroundColor Green
} else {
    Write-Warning "[Tools] RISC-V GCC not found! Required for compiling firmware target."
}

# =============================================================================
# Clean Handling
# =============================================================================
if ($Clean) {
    Write-Host "`n[Clean] Removing work library and simulation artifacts..." -ForegroundColor Yellow
    Set-Location $TbDir
    if (Test-Path "$TbDir\work") { Remove-Item -Recurse -Force "$TbDir\work" }
    Get-ChildItem -Path $TbDir -Include *.wlf, transcript, *.vcd, *.log -File | Remove-Item -Force
    Write-Host "[Clean] Done." -ForegroundColor Green
    if ($PSBoundParameters.Count -eq 1 -and $PSBoundParameters.ContainsKey('Clean')) {
        return
    }
}

# =============================================================================
# Step 1: Verify / Generate VeeR EL2 Snapshot Headers
# =============================================================================
$DefaultSnapDir = "$VeerDir\snapshots\default"
$SocSimSnapDir  = "$VeerDir\snapshots\soc_sim"
$RequiredHeaders = @("common_defines.vh", "el2_param.vh", "el2_pdef.vh", "pic_map_auto.svh")
$NeedGenerate = $false

foreach ($hdr in $RequiredHeaders) {
    if (-not (Test-Path "$DefaultSnapDir\$hdr")) {
        $NeedGenerate = $true
        break
    }
}

if ($NeedGenerate) {
    if (-not $PerlTool) {
        Write-Error "VeeR snapshot headers missing in $DefaultSnapDir and Perl is not available to generate them!"
    }
    Write-Host "`n[VeeR Config] Generating VeeR configuration headers using official veer.config..." -ForegroundColor Yellow
    if (-not (Test-Path $DefaultSnapDir)) { New-Item -ItemType Directory -Path $DefaultSnapDir -Force | Out-Null }
    
    $ConfigScript = "$VeerDir\configs\veer.config"
    $PicmapScript = "$VeerDir\tools\picmap"
    
    Push-Location $VeerDir
    try {
        & $PerlTool $ConfigScript -target=default
        if (-not (Test-Path "$DefaultSnapDir\pic_map_auto.svh")) {
            & $PerlTool $PicmapScript -total_int 31 | Out-File -FilePath "$DefaultSnapDir\pic_map_auto.svh" -Encoding ascii
        }
    } finally {
        Pop-Location
    }

    if (-not (Test-Path $SocSimSnapDir)) { New-Item -ItemType Directory -Path $SocSimSnapDir -Force | Out-Null }
    Copy-Item -Path "$DefaultSnapDir\*" -Destination $SocSimSnapDir -Recurse -Force
    Write-Host "[VeeR Config] Headers generated successfully in snapshots/default and mirrored to snapshots/soc_sim." -ForegroundColor Green
} else {
    Write-Host "[VeeR Config] Verified snapshot headers in $DefaultSnapDir." -ForegroundColor Green
}

# =============================================================================
# Step 2: Firmware Compilation (Required for 'uart' and 'all' targets)
# =============================================================================
function Build-Firmware {
    if (-not $RiscvGcc -or -not $RiscvObjcopy) {
        Write-Error "RISC-V GCC toolchain is required to build firmware for target '$Target'!"
    }
    Write-Host "`n[Firmware] Compiling C firmware with MRAC CSR 0x7C0 initialization..." -ForegroundColor Yellow
    Push-Location $FirmwareDir
    try {
        $ElfOut = "firmware.elf"
        $BinOut = "firmware.bin"
        $HexOut = "uart_test_word.hex"

        # Compile with -march=rv32imc_zicsr_zifencei for CSR/FENCE access on GCC 13+
        & $RiscvGcc -march=rv32imc_zicsr_zifencei -mabi=ilp32 -O2 -nostartfiles -T linker.ld -o $ElfOut start.S main.c
        if ($LASTEXITCODE -ne 0) { throw "RISC-V GCC compilation failed with code $LASTEXITCODE" }

        & $RiscvObjcopy -O binary $ElfOut $BinOut
        if ($LASTEXITCODE -ne 0) { throw "objcopy failed with code $LASTEXITCODE" }

        # Convert binary payload to 32-bit hex word file for Verilog $readmemh
        $bytes = [System.IO.File]::ReadAllBytes("$FirmwareDir\$BinOut")
        $lines = [System.Collections.Generic.List[string]]::new()
        for ($i = 0; $i -lt $bytes.Length; $i += 4) {
            $word = [BitConverter]::ToUInt32($bytes, $i)
            $lines.Add(("{0:x8}" -f $word))
        }
        [System.IO.File]::WriteAllLines("$FirmwareDir\$HexOut", $lines)
        Write-Host "[Firmware] Successfully built $HexOut ($($lines.Count) words)." -ForegroundColor Green
    } finally {
        Pop-Location
    }
}

function Build-DmaFirmware {
    if (-not $RiscvGcc -or -not $RiscvObjcopy) {
        Write-Error "RISC-V GCC toolchain is required to build firmware for target '$Target'!"
    }
    Write-Host "`n[Firmware] Compiling C DMA/RLE/CRC firmware..." -ForegroundColor Yellow
    Push-Location $FirmwareDir
    try {
        $ElfOut = "dma_firmware.elf"
        $BinOut = "dma_firmware.bin"
        $HexOut = "dma_test_word.hex"

        # Compile with -march=rv32imc_zicsr_zifencei for CSR/FENCE access on GCC 13+
        & $RiscvGcc -march=rv32imc_zicsr_zifencei -mabi=ilp32 -O2 -nostartfiles -T linker.ld -o $ElfOut start.S main_dma.c
        if ($LASTEXITCODE -ne 0) { throw "RISC-V GCC compilation failed with code $LASTEXITCODE" }

        & $RiscvObjcopy -O binary $ElfOut $BinOut
        if ($LASTEXITCODE -ne 0) { throw "objcopy failed with code $LASTEXITCODE" }

        # Convert binary payload to 32-bit hex word file for Verilog readmemh
        $bytes = [System.IO.File]::ReadAllBytes("$FirmwareDir\$BinOut")
        $lines = [System.Collections.Generic.List[string]]::new()
        for ($i = 0; $i -lt $bytes.Length; $i += 4) {
            $word = [BitConverter]::ToUInt32($bytes, $i)
            $lines.Add(("{0:x8}" -f $word))
        }
        [System.IO.File]::WriteAllLines("$FirmwareDir\$HexOut", $lines)
        Write-Host "[Firmware] Successfully built $HexOut ($($lines.Count) words)." -ForegroundColor Green
    } finally {
        Pop-Location
    }
}

if ($Target -eq 'uart' -or $Target -eq 'all') {
    Build-Firmware
}

if ($Target -eq 'dma_firmware' -or $Target -eq 'all') {
    Build-DmaFirmware
}

# =============================================================================
# Step 3: ModelSim Compilation & Simulation Execution
# =============================================================================
Set-Location $TbDir

# Create ModelSim work library if missing
if (-not (Test-Path "$TbDir\work")) {
    Write-Host "`n[ModelSim] Initializing work library in $TbDir..." -ForegroundColor Yellow
    & $VlibTool work
}

# Common vlog compilation flags
$VlogIncDirs = @(
    "+incdir+$VeerDir/design/include",
    "+incdir+$VeerDir/snapshots/default",
    "+incdir+$RtlDir/include",
    "+incdir+$UartIpDir",
    "+incdir+."
)

$DesignCompiled = $false

function Ensure-DesignCompiled {
    param (
        [string]$Filelist = "dma_firmware.f"
    )

    if ($script:DesignCompiled) {
        return
    }

    $needsCompile = $true
    if (Test-Path "$TbDir\work") {
        if ($VdirTool) {
            $vdirOut = & $VdirTool -lib work soc_core_top 2>&1
            if ($vdirOut -match "MODULE soc_core_top") {
                $needsCompile = $false
            }
        }
    }

    if ($needsCompile) {
        Write-Host "`n----------------------------------------------------------------" -ForegroundColor Magenta
        Write-Host " Pre-compiling SoC Design Infrastructure ($Filelist)" -ForegroundColor Magenta
        Write-Host "----------------------------------------------------------------" -ForegroundColor Magenta
        $VlogArgs = @("-sv", "-mfcu", "+define+RV_OPENSOURCE") + $VlogIncDirs + @("-f", $Filelist)
        if (-not (Test-Path $Filelist)) {
            throw "Design filelist '$Filelist' not found in $TbDir!"
        }
        Write-Host "[Vlog] Compiling $Filelist..." -ForegroundColor Cyan
        & $VlogTool @VlogArgs
        if ($LASTEXITCODE -ne 0) {
            throw "Pre-compilation of $Filelist failed with exit code $LASTEXITCODE"
        }
    }
    $script:DesignCompiled = $true
}

function Run-TestTarget {
    param (
        [string]$TestName,
        [string]$TbSource,
        [string]$ExpectedSignature,
        [string]$Filelist = $null
    )

    Write-Host "`n----------------------------------------------------------------" -ForegroundColor Magenta
    Write-Host " Running Test Target: $TestName ($TbSource)" -ForegroundColor Magenta
    Write-Host "----------------------------------------------------------------" -ForegroundColor Magenta

    # 1. Compile testbench and dependencies
    $VlogArgs = @("-sv", "-mfcu", "+define+RV_OPENSOURCE") + $VlogIncDirs
    if ($Filelist -and (Test-Path $Filelist)) {
        $VlogArgs += @("-f", $Filelist)
    } else {
        $VlogArgs += $TbSource
    }

    Write-Host "[Vlog] Compiling $TbSource..." -ForegroundColor Cyan
    & $VlogTool @VlogArgs
    if ($LASTEXITCODE -ne 0) {
        Write-Error "Compilation of $TbSource failed with exit code $LASTEXITCODE"
    }

    # 2. Run simulation in vsim
    $TopModule = [System.IO.Path]::GetFileNameWithoutExtension($TbSource)
    $LogFile   = "$TbDir\sim_${TopModule}.log"
    $VsimArgs  = @("-suppress", "3999,12036")

    if ($Gui) {
        $VsimArgs += @("work.$TopModule")
        & $VsimTool @VsimArgs
        return
    }

    $VsimArgs += @("-c", "-do", "run -all; quit", "work.$TopModule")
    Write-Host "[Vsim] Executing simulation batch: $TopModule..." -ForegroundColor Cyan
    & $VsimTool @VsimArgs | Tee-Object -FilePath $LogFile

    # 3. Analyze Results
    $LogContent = Get-Content $LogFile -Raw
    $Passed = $false

    if ($ExpectedSignature -and ($LogContent -match [regex]::Escape($ExpectedSignature))) {
        $Passed = $true
    } elseif ($LogContent -match "PASSED" -and -not ($LogContent -match "FAILED")) {
        $Passed = $true
    }

    if ($Passed) {
        Write-Host "`n>>> [RESULT: PASS] $TestName successfully verified! <<<`n" -ForegroundColor Green
        return $true
    } else {
        Write-Host "`n>>> [RESULT: FAIL] $TestName failed or signature not detected! <<<`n" -ForegroundColor Red
        return $false
    }
}

$Results = @{}

if ($Target -eq 'boot' -or $Target -eq 'all') {
    Ensure-DesignCompiled -Filelist "dma_firmware.f"
    $Results['boot'] = Run-TestTarget -TestName "CPU Core Boot Test" `
                                      -TbSource "tb_soc_core_boot.sv" `
                                      -ExpectedSignature "Signature 0xCAFEBABE verified at DMEM[0]"
}

if ($Target -eq 'periph' -or $Target -eq 'all') {
    Ensure-DesignCompiled -Filelist "dma_firmware.f"
    $Results['periph'] = Run-TestTarget -TestName "VeeR EL2 Peripheral Test" `
                                        -TbSource "tb_soc_periph_test.sv" `
                                        -ExpectedSignature "ALL 5 PERIPHERALS PASSED! Signature 0xCAFEF00D"
}

if ($Target -eq 'uart' -or $Target -eq 'all') {
    $Results['uart'] = Run-TestTarget -TestName "VeeR EL2 UART Firmware Test" `
                                      -TbSource "tb_soc_uart_firmware.sv" `
                                      -ExpectedSignature "RESULT: [SUCCESS] UART transmitted 'H' (0x48) followed by 'I' (0x49)!" `
                                      -Filelist "uart_firmware.f"
}

if ($Target -eq 'dma_firmware' -or $Target -eq 'all') {
    $Results['dma_firmware'] = Run-TestTarget -TestName "VeeR EL2 DMA+RLE+CRC Firmware Test" `
                                              -TbSource "tb_soc_dma_firmware.sv" `
                                              -ExpectedSignature "FIRMWARE COMPLETION SIGNATURE 0xCAFED00D DETECTED!" `
                                              -Filelist "dma_firmware.f"
}

# =============================================================================
# Summary Report
# =============================================================================
Write-Host "`n================================================================" -ForegroundColor Cyan
Write-Host " FINAL REGRESSION SUMMARY" -ForegroundColor Cyan
Write-Host "================================================================" -ForegroundColor Cyan
$AllPassed = $true
foreach ($k in $Results.Keys) {
    $status = if ($Results[$k]) { "PASS" } else { "FAIL"; $AllPassed = $false }
    $color  = if ($Results[$k]) { "Green" } else { "Red" }
    Write-Host ("  Target {0,-10} : {1}" -f $k, $status) -ForegroundColor $color
}
Write-Host "================================================================" -ForegroundColor Cyan

if (-not $AllPassed) {
    exit 1
} else {
    exit 0
}

