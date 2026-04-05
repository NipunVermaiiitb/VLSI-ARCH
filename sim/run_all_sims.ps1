# ============================================================
# run_all_sims.ps1 - DPDAC Simulation Runner
# Usage:  .\run_all_sims.ps1 [optional: test_name]
#   e.g.  .\run_all_sims.ps1 stage3
#         .\run_all_sims.ps1 stage4
#         .\run_all_sims.ps1 full
#         .\run_all_sims.ps1          (runs all)
# ============================================================

$ErrorActionPreference = "Continue"
if (Get-Variable -Name PSNativeCommandUseErrorActionPreference -ErrorAction SilentlyContinue) {
    $PSNativeCommandUseErrorActionPreference = $false
}

$IVERILOG = "C:\iverilog\bin\iverilog.exe"
$VVP      = "C:\iverilog\bin\vvp.exe"
$ROOT     = Split-Path -Parent $MyInvocation.MyCommand.Path
$RTL      = "$ROOT\..\rtl"
$TB       = "$ROOT\testbenches"
$BIN      = "$ROOT\bin"

# Create bin dir if needed
if (-not (Test-Path $BIN)) { New-Item -ItemType Directory -Path $BIN | Out-Null }

$pass   = 0
$fail   = 0
$skip   = 0
$filter = if ($args.Count -gt 0) { $args[0].ToLower() } else { "all" }

# ---------------------------------------------------------------------------
# RTL source lists
# ---------------------------------------------------------------------------
$RTL_SHARED = @(
    "$RTL\shared\CSA_4to2.v"
)

$RTL_S1 = @(
    "$RTL\stage1\mult14_radix4_booth.v",
    "$RTL\stage1\multiplier_array.v",
    "$RTL\stage1\component_formatter.v",
    "$RTL\stage1\exponent_comparison.v",
    "$RTL\stage1\addend_alignment_shifter.v",
    "$RTL\stage1\sign_logic.v",
    "$RTL\stage1\Stage1_pipeline_register.v",
    "$RTL\stage1\Input_Register_Module.v"
)

$RTL_S2 = @(
    "$RTL\stage2\Stage2_adder.v",
    "$RTL\stage2\Products_alignment_shifter.v",
    "$RTL\stage2\Stage2_top.v",
    "$RTL\stage2\Stage2_pipeline_register.v"
)

$RTL_S3 = @(
    "$RTL\stage3\Final_adder.v",
    "$RTL\stage3\Leading_zero_anticipation_counter.v",
    "$RTL\stage3\Sign_generator.v",
    "$RTL\stage3\Complementer.v",
    "$RTL\stage3\INC_plus1.v",
    "$RTL\stage3\Stage3_pipeline_register.v",
    "$RTL\stage3\Stage3_top.v"
)

$RTL_S4 = @(
    "$RTL\stage4\Normalization_shifter.v",
    "$RTL\stage4\Rounder.v",
    "$RTL\stage4\Output_formatter.v",
    "$RTL\stage4\Stage4_pipeline_register.v",
    "$RTL\stage4\Stage4_top.v"
)

$RTL_TOP = @(
    "$RTL\DPDAC_top.v"
)

# ---------------------------------------------------------------------------
# Helper: compile + run a single testbench
# ---------------------------------------------------------------------------
function Run-TB {
    param(
        [string]$Name,
        [string]$TB_File,
        [string[]]$RTL_Files
    )

    Write-Host ""
    Write-Host "============================================================" -ForegroundColor Cyan
    Write-Host "  $Name" -ForegroundColor Cyan
    Write-Host "============================================================" -ForegroundColor Cyan

    $vvp_out = "$BIN\sim_$($Name -replace ' ','_').vvp"
    $log_out = "$BIN\log_$($Name -replace ' ','_').txt"

    # Build iverilog command
    $all_files = $RTL_Files + @($TB_File)
    $compile_args = @("-g2012", "-o", $vvp_out, "-Wall") + $all_files

    Write-Host "[COMPILE] iverilog $($all_files[-1])" -ForegroundColor Yellow
    $oldErrPref = $ErrorActionPreference
    $ErrorActionPreference = "SilentlyContinue"
    $compile_output = & $IVERILOG @compile_args 2>&1
    $ErrorActionPreference = $oldErrPref
    $compile_output | Tee-Object -FilePath $log_out

    if ($LASTEXITCODE -ne 0) {
        Write-Host "[ERROR] Compilation FAILED for $Name" -ForegroundColor Red
        $script:fail++
        return
    }

    Write-Host "[SIM] Running $Name ..." -ForegroundColor Yellow
    $oldErrPref = $ErrorActionPreference
    $ErrorActionPreference = "SilentlyContinue"
    $sim_output = & $VVP $vvp_out 2>&1
    $ErrorActionPreference = $oldErrPref
    $sim_output | Tee-Object -FilePath $log_out -Append

    # Check for PASS/FAIL keywords
    $passed = $sim_output | Select-String -Pattern "ALL .*PASSED|RESULT: PASS|PASS \(|PASS \[" -Quiet
    $failed = $sim_output | Select-String -Pattern "FAILED|FAIL \[|ERROR:" -Quiet

    if ($failed) {
        Write-Host "[RESULT] $Name - FAIL" -ForegroundColor Red
        $script:fail++
    }
    elseif ($passed) {
        Write-Host "[RESULT] $Name - PASS" -ForegroundColor Green
        $script:pass++
    }
    else {
        Write-Host "[RESULT] $Name - UNKNOWN (check log: $log_out)" -ForegroundColor Magenta
        $script:skip++
    }
}

# ---------------------------------------------------------------------------
# Simulation targets
# ---------------------------------------------------------------------------

# ---- Stage 3 unit test ----
if ($filter -eq "all" -or $filter -eq "stage3") {
    $s3_rtl = $RTL_SHARED + $RTL_S2 + $RTL_S3
    Run-TB "Stage3_Unit_Test" "$TB\tb_stage3_top.v" $s3_rtl
}

# ---- Stage 4 unit test ----
if ($filter -eq "all" -or $filter -eq "stage4") {
    $s4_rtl = $RTL_S4
    Run-TB "Stage4_Unit_Test" "$TB\tb_stage4_top.v" $s4_rtl
}

# ---- Full pipeline test ----
if ($filter -eq "all" -or $filter -eq "full") {
    $full_rtl = $RTL_SHARED + $RTL_S1 + $RTL_S2 + $RTL_S3 + $RTL_S4 + $RTL_TOP
    Run-TB "DPDAC_Full_Pipeline" "$TB\tb_DPDAC_top.v" $full_rtl
}

# ---- Existing Stage1 testbench ----
if ($filter -eq "all" -or $filter -eq "stage1") {
    $s1_rtl = $RTL_SHARED + $RTL_S1
    Run-TB "Stage1_Unit_Test" "$TB\tb_Stage1_Module.v" $s1_rtl
}

# ---- Existing Stage1+2 integration ----
if ($filter -eq "all" -or $filter -eq "s1s2") {
    $s1s2_rtl = $RTL_SHARED + $RTL_S1 + $RTL_S2
    Run-TB "Stage1_Stage2_Integration" "$TB\tb_integration_stage1_stage2.v" $s1s2_rtl
}

# ---------------------------------------------------------------------------
# Final summary
# ---------------------------------------------------------------------------
Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "  SIMULATION SUMMARY" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "  PASSED : $pass" -ForegroundColor Green
Write-Host "  FAILED : $fail" -ForegroundColor $(if ($fail -gt 0) { 'Red' } else { 'Green' })
Write-Host "  UNKNOWN: $skip" -ForegroundColor Magenta
Write-Host ""
Write-Host "  Logs saved to: $BIN" -ForegroundColor Gray

if ($fail -gt 0) { exit 1 } else { exit 0 }
