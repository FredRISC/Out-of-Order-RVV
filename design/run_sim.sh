#!/bin/bash
# ============================================================================
# run_sim.sh - Simulation Execution Script
# ============================================================================

echo "================================"
echo "RISC-V RV32 OoO Processor"
echo "Simulation Script"
echo "================================"
echo ""

# Check if compiled binary exists
if [ ! -f "riscv_sim" ]; then
    echo "Compiled binary not found. Compiling..."
    make compile
    if [ $? -ne 0 ]; then
        echo "Compilation failed!"
        exit 1
    fi
fi

echo "Running simulation..."
echo "---"
vvp riscv_sim

if [ $? -eq 0 ]; then
    echo ""
    echo "================================"
    echo "Simulation completed successfully"
    echo "================================"
else
    echo ""
    echo "================================"
    echo "Simulation failed!"
    echo "================================"
    exit 1
fi
