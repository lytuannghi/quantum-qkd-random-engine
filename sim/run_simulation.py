#!/usr/bin/env python3
"""
Automated Simulation Runner for Quantum QKD & NIST TRNG ASIC
Runs Icarus Verilog compilation and VVP execution, verifying 10/10 testbench assertions.
"""

import subprocess
import os
import sys

def main():
    proj_dir = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    os.chdir(proj_dir)

    os.makedirs("sim/waves", exist_ok=True)
    vvp_out = os.path.join("sim", "qkd_sim.vvp")

    # Source files list
    sources = [
        "rtl/sifting/qkd_bb84_sifting_engine.v",
        "rtl/reconciliation/cascade_error_reconciler.v",
        "rtl/privacy/toeplitz_privacy_amplification.v",
        "rtl/trng/nist_sp800_90b_health_test.v",
        "rtl/bus/qkd_regs_apb.v",
        "rtl/quantum_qkd_top.v",
        "tb/tb_quantum_qkd_top.v"
    ]

    print("[INFO] Compiling Quantum QKD & NIST TRNG ASIC RTL and Testbench...")
    compile_cmd = ["iverilog", "-g2012", "-o", vvp_out] + sources
    res = subprocess.run(compile_cmd, capture_output=True, text=True)
    if res.returncode != 0:
        print("[ERROR] Compilation failed:")
        print(res.stderr)
        sys.exit(1)
    print("[INFO] Compilation successful!")

    print("[INFO] Running VVP simulation...")
    run_cmd = ["vvp", vvp_out]
    sim_res = subprocess.run(run_cmd, capture_output=True, text=True)
    print(sim_res.stdout)
    if sim_res.returncode != 0 or "ALL 10 VERIFICATION TESTS COMPLETED WITH 100% PASS RATE" not in sim_res.stdout:
        print("[FAILURE] Simulation failed assertion checks.")
        sys.exit(1)

    print("[SUCCESS] All 10 Quantum QKD & NIST TRNG test cases PASSED!")

if __name__ == "__main__":
    main()
