#!/usr/bin/env bash
#
# run_sim.sh - Compile and run CORDIC logarithm simulation with Icarus Verilog
#
# Usage:
#   ./scripts/run_sim.sh            # compile + run
#   ./scripts/run_sim.sh --wave     # compile + run + open VCD waveform
#   ./scripts/run_sim.sh --clean    # remove generated files
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJ_DIR="$(dirname "$SCRIPT_DIR")"

RTL_DIR="$PROJ_DIR/rtl"
TB_DIR="$PROJ_DIR/tb"
OUT_DIR="$PROJ_DIR/sim_out"

SIM_EXEC="$OUT_DIR/cordic_log_sim"
VCD_FILE="$OUT_DIR/cordic_log.vcd"

# ----------------------------------------------------------------
# Handle --clean
# ----------------------------------------------------------------
if [[ "${1:-}" == "--clean" ]]; then
    echo "Cleaning simulation outputs..."
    rm -rf "$OUT_DIR"
    echo "Done."
    exit 0
fi

# ----------------------------------------------------------------
# Ensure output directory exists
# ----------------------------------------------------------------
mkdir -p "$OUT_DIR"

# ----------------------------------------------------------------
# Compile
# ----------------------------------------------------------------
echo "=== Compiling with Icarus Verilog ==="
iverilog -g2012 -Wall \
    -o "$SIM_EXEC" \
    -I "$RTL_DIR" \
    "$RTL_DIR/cordic_log2.v" \
    "$RTL_DIR/cordic_log_top.v" \
    "$TB_DIR/cordic_log_tb.v"

echo "Compilation successful: $SIM_EXEC"

# ----------------------------------------------------------------
# Run simulation
# ----------------------------------------------------------------
echo ""
echo "=== Running Simulation ==="
cd "$OUT_DIR"
vvp "$SIM_EXEC"

echo ""
echo "VCD waveform: $VCD_FILE"

# ----------------------------------------------------------------
# Optionally open waveform viewer
# ----------------------------------------------------------------
if [[ "${1:-}" == "--wave" ]]; then
    if command -v gtkwave &>/dev/null; then
        echo "Opening GTKWave..."
        gtkwave "$VCD_FILE" &
    else
        echo "GTKWave not found. VCD file is at: $VCD_FILE"
    fi
fi
