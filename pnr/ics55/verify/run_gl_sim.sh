#!/bin/bash
# =====================================================================
# run_gl_sim.sh -- gate-level functional verification of the hardened
# ICS55 netlist for temp_sensor_block.
#
# Runs the post-route netlist against the same closed loop the RTL tests
# use (t2f_model -> t2f_in -> design -> I2C read-back) using the PDK's
# Verilog cell models.
#
# Usage:
#   PDK_ROOT=<icsprout55 pdk root> ./run_gl_sim.sh [rtl|syn|route]
#     rtl    simulate the RTL instead of a netlist (control run)
#     syn    simulate the synthesis netlist   (default)
#     route  simulate the post-route netlist
#
# Requirements: verilator >= 5.050, the ICS55 PDK verilog models.
# =====================================================================
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
PKG="$(cd "$HERE/.." && pwd)"
WHICH="${1:-syn}"

PDK_ROOT="${PDK_ROOT:-$HOME/.local/share/ecc/pdks/icsprout55/v1.10.102}"
STD="$PDK_ROOT/IP/STD_cell/ics55_LLSC_H7C_V1p10C100"
if [ ! -d "$STD" ]; then
    echo "[ERROR] ICS55 std cell dir not found: $STD" >&2
    echo "        set PDK_ROOT to the icsprout55 PDK root" >&2
    exit 1
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
cd "$WORK"

# ---- PDK cell models -------------------------------------------------
# The PDK model for the inverting 2:1 mux cells is self-referencing
# (udp_mux2 drives Y and a not gate takes Y as its own input), which
# makes any zero-delay simulator fail to converge.  Strip those 14
# modules and use the liberty-accurate replacements instead.
python3 - "$STD" << 'PY'
import re, sys, pathlib
std = pathlib.Path(sys.argv[1])
for lib in ('ics55_LLSC_H7CL', 'ics55_LLSC_H7CR'):
    src = (std / lib / 'verilog' / f'{lib}.v').read_text()
    for m in re.finditer(r'(?ms)^module\s+\w+\b.*?^endmodule', src):
        if 'not      u1(Y, Y);' in m.group(0):
            src = src.replace(m.group(0), '')
    pathlib.Path(f'{lib}_fixed.v').write_text(src)
PY
cp "$HERE/muxi2_fix.v" "$HERE/fillers_stub.v" .

# ---- design sources --------------------------------------------------
case "$WHICH" in
  rtl)
    cp "$PKG/rtl/temp_sensor_block.v" "$PKG/rtl/i2c_slave.v" .
    cp "$PKG/../rtl/temp_engine.v" "$PKG/../rtl/temp_regs.v" .
    DESIGN="temp_sensor_block.v i2c_slave.v temp_engine.v temp_regs.v"
    ;;
  syn)
    gzip -dc "$PKG/netlist/temp_sensor_block_Synthesis.v.gz" > design.v
    DESIGN="design.v"
    ;;
  route)
    gzip -dc "$PKG/netlist/temp_sensor_block_route.v.gz" > design.v
    DESIGN="design.v"
    ;;
  *) echo "[ERROR] unknown target: $WHICH (rtl|syn|route)" >&2; exit 2 ;;
esac

# ---- testbench models ------------------------------------------------
BASE="$PKG/../tb"
cp "$HERE/tb_gl.sv" .
cp "$BASE/t2f_model.v" "$BASE/i2c_master_model.v" "$BASE/t2f_model_params.vh" .

echo "=== gate-level verification ($WHICH) ==="
verilator --binary --timing -Wno-fatal \
    -Wno-TIMESCALEMOD -Wno-UNUSEDSIGNAL -Wno-UNUSEDPARAM -Wno-DECLFILENAME \
    -Wno-BLKSEQ -Wno-WIDTH -Wno-CASEINCOMPLETE -Wno-UNDRIVEN -Wno-MULTIDRIVEN \
    -Wno-LATCH -Wno-INITIALDLY -Wno-UNOPTFLAT \
    --top-module tb_gl --Mdir obj -o tb_gl \
    tb_gl.sv $DESIGN fillers_stub.v muxi2_fix.v \
    ics55_LLSC_H7CL_fixed.v ics55_LLSC_H7CR_fixed.v \
    t2f_model.v i2c_master_model.v

./obj/tb_gl
