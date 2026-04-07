import os, subprocess

ROOT = r'C:\Users\ASUS\OneDrive\Desktop\Current projects\VLSI arch\Github\VLSI-ARCH'
RTL  = os.path.join(ROOT, 'rtl')
TB   = os.path.join(ROOT, 'sim', 'testbenches')
BIN  = os.path.join(ROOT, 'sim', 'bin')
IVER = r'C:\iverilog\bin\iverilog.exe'
VVP  = r'C:\iverilog\bin\vvp.exe'

def s1f(*names): return [os.path.join(RTL,'stage1',n) for n in names]
def s2f(*names): return [os.path.join(RTL,'stage2',n) for n in names]
def s3f(*names): return [os.path.join(RTL,'stage3',n) for n in names]
def s4f(*names): return [os.path.join(RTL,'stage4',n) for n in names]

SH  = [os.path.join(RTL,'shared','CSA_4to2.v')]
S1  = s1f('mult14_radix4_booth.v','multiplier_array.v','component_formatter.v','exponent_comparison.v','addend_alignment_shifter.v','sign_logic.v','Input_Register_Module.v')
S2  = s2f('Stage2_adder.v','Products_alignment_shifter.v','Stage2_top.v','Stage2_pipeline_register.v')
S3  = s3f('Final_adder.v','Leading_zero_anticipation_counter.v','Sign_generator.v','Complementer.v','INC_plus1.v','Stage3_pipeline_register.v','Stage3_top.v')
S4  = s4f('Normalization_shifter.v','Rounder.v','Output_formatter.v','Stage4_pipeline_register.v','Stage4_top.v')
TOP = [os.path.join(RTL,'DPDAC_top.v')]

files = SH + S1 + S2 + S3 + S4 + TOP + [os.path.join(TB, 'tb_metrics_eval.sv')]
vvp_out = os.path.join(BIN, 'sim_metrics.vvp')

configs = [
    (64, 2, "DP",   "FMA"),
    (32, 5, "SP",   "2-term DPDAC"),
    (32, 5, "TF32", "2-term DPDAC"),
    (16, 9, "HP",   "4-term DPDAC"),
    (16, 9, "BF16", "4-term DPDAC")
]

log_file = 'metrics_output.txt'
with open(log_file, 'w', encoding='utf-8') as f:
    f.write("-" * 75 + "\n")
    f.write(f"{'Format':<8} {'Function':<16} {'Delay':<6} {'Freq':<6} {'Lat':<4} {'OP':<4} {'TF':<6} {'Width':<6} {'GB/s':<6} {'B/OP':<6}\n")
    f.write("-" * 75 + "\n")

print("Starting performance sweep...")

for (dw, macs, fmt, func) in configs:
    print(f"  Testing {fmt}...")
    flags = [
        '-g2012',
        f'-DDATA_WIDTH={dw}',
        f'-DNUM_PARALLEL_MAC={macs}',
        f'-DFORMAT_STR="{fmt}"',
        f'-DFUNC_STR="{func}"'
    ]
    
    cp = subprocess.run([IVER] + flags + ['-o', vvp_out] + files, capture_output=True, text=True)
    if cp.returncode != 0:
        print(f"    Compile FAIL: {fmt}")
        continue
        
    sp = subprocess.run([VVP, vvp_out], capture_output=True, text=True, timeout=60)
    out = sp.stdout
    
    # Simple line-by-line grep for the result line
    result_line = ""
    for line in out.splitlines():
        # The result line starts with the Format string
        if line.startswith(fmt) or (f" {fmt}" in line and len(line.split()) >= 10):
            result_line = line.strip()
            break
    
    if result_line:
        print(f"    RESULT: {result_line}")
        with open(log_file, 'a', encoding='utf-8') as f:
            f.write(result_line + "\n")
    else:
        print(f"    ERROR: Could not find output for {fmt}")
        # print(out) # DEBUG

with open(log_file, 'a', encoding='utf-8') as f:
    f.write("-" * 75 + "\n")
print("Sweep complete. Results in metrics_output.txt")
