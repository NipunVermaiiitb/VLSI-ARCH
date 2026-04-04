# DPDAC: Dot-Product-Dual-Accumulate Architecture

This repository contains a high-performance, multi-precision Floating-Point Dot-Product-Dual-Accumulate (DPDAC) unit. The architecture is designed for HPC-enabled AI workloads, supporting multiple IEEE 754 precision modes within a unified 163-bit accumulator datapath.

The implementation is a 4-stage pipeline capable of computing:
**Σ(Aᵢ × Bᵢ) + Σ(Cⱼ)**

## Supported Precision Modes
- **DP**: Double Precision (64-bit) - 1 lane
- **SP**: Single Precision (32-bit) - 2 lanes
- **HP**: Half Precision (16-bit) - 4 lanes
- **BF16**: Bfloat16 (16-bit) - 4 lanes
- **TF32**: TensorFloat-32 (19-bit) - 2 lanes

## Directory Structure

```text
RTL_code/
├── rtl/
│   ├── DPDAC_top.v                 # Top-level integration module
│   ├── shared/                     # Shared arithmetic components (CSA, etc.)
│   ├── stage1/                     # Input formatting, Exponent Comparison, Multipliers
│   ├── stage2/                     # Product Alignment & First Reduction
│   ├── stage3/                     # Final Addition, LZA, Sign Generation
│   └── stage4/                     # Normalization, Rounding, Output Formatting
├── sim/
│   ├── testbenches/                # Verilog testbenches
│   │   └── tb_DPDAC_top.v          # Full pipeline integration testbench
│   └── bin/                        # Simulation binaries and logs (auto-generated)
└── docs/                           # Architecture documentation and papers
```

## Architecture Summary
- **Stage 1 (S1)**: Formats operands, performs exponent comparison for alignment, determines signs, and executes the first part of the multiplication using a Radix-4 Booth Multiplier array.
- **Stage 2 (S2)**: Aligns products based on the maximum exponent, performs the second part of the multiplication reduction, and applies the initial sign-magnitude logic.
- **Stage 3 (S3)**: Executes the final 163-bit Carrie-Propagate Addition (CPA), performs Leading Zero Anticipation (LZA) for normalization, and generates the final result sign.
- **Stage 4 (S4)**: Normalizes the result based on LZA counts, performs IEEE 754 Round-to-Nearest-Even (RNE) logic, and formats the output word based on the selected precision mode.

## Running the Simulation

### Prerequisites
- **Icarus Verilog**: Ensure `iverilog` and `vvp` are in your system PATH.
- **PowerShell** (for the provided commands).

### Run Full Integration Testbench
To compile and run the complete pipeline test suite (covering DP, SP, HP, BF16, and back-to-back pipelining):

```powershell
# Define source files
$files = @(
  "rtl\shared\CSA_4to2.v",
  "rtl\stage1\mult14_radix4_booth.v", "rtl\stage1\multiplier_array.v",
  "rtl\stage1\component_formatter.v", "rtl\stage1\exponent_comparison.v",
  "rtl\stage1\addend_alignment_shifter.v", "rtl\stage1\sign_logic.v",
  "rtl\stage1\Stage1_pipeline_register.v", "rtl\stage1\Input_Register_Module.v",
  "rtl\stage2\Stage2_adder.v", "rtl\stage2\Products_alignment_shifter.v",
  "rtl\stage2\Stage2_top.v", "rtl\stage2\Stage2_pipeline_register.v",
  "rtl\stage3\Final_adder.v", "rtl\stage3\Leading_zero_anticipation_counter.v",
  "rtl\stage3\Sign_generator.v", "rtl\stage3\Complementer.v", "rtl\stage3\INC_plus1.v",
  "rtl\stage3\Stage3_pipeline_register.v", "rtl\stage3\Stage3_top.v",
  "rtl\stage4\Normalization_shifter.v", "rtl\stage4\Rounder.v",
  "rtl\stage4\Output_formatter.v", "rtl\stage4\Stage4_pipeline_register.v",
  "rtl\stage4\Stage4_top.v", "rtl\DPDAC_top.v", "sim\testbenches\tb_DPDAC_top.v"
)

# Create bin directory if missing
if (!(Test-Path "sim\bin")) { New-Item -ItemType Directory "sim\bin" }

# Compile
iverilog -g2012 -o "sim\bin\sim_full.vvp" $files

# Run Simulation
vvp "sim\bin\sim_full.vvp"
```

### Verification Status
The design has been verified to pass 7/7 comprehensive integration tests:
1. **DP Normal**: 1.5 * 2.0 + 0.5 = 3.5
2. **DP Negative**: -1.5 * 2.0 = -3.0
3. **DP Zero**: 0.0 * 2.0 = 0.0
4. **SP Dual-Lane**: Structural check for two-lane SP throughput
5. **HP Quad-Lane**: Structural check for four-lane HP throughput
6. **BF16 Quad-Lane**: Structural check for four-lane BF16 throughput
7. **Back-to-Back DP**: Verifies pipeline ordering and hazard-free DP execution
