#!/bin/bash
# =====================================================================
# run_chip_sim.sh -- elaborate and simulate the merged chip netlist
#
# Builds chip_top (structural netlist + pad models + macro views) and runs
# the package-pin I2C read-back test.
#
# Usage:
#   PDK_ROOT=<icsprout55 pdk root> ./run_chip_sim.sh [rtl|syn|route]
#
#   rtl    digital macro built from RTL        -> verifies the CHIP WIRING
#   syn    digital macro = synthesis netlist    -> shows the known defect
#   route  digital macro = post-route netlist   -> shows the known defect
#
# Why both: the chip-level test exercises POR, the clock, the behavioural
# AFE, the T2F level shifter, the pads and the I2C bus.  Running it with
# the RTL core isolates those from the separate, already-documented defect
# in the ICS55 hardened netlist (sda_oe never drives, so the slave never
# ACKs).  With the RTL core the chip wiring should pass; with either
# netlist it must fail for that documented reason.
#
# Requirements: verilator >= 5.050, the ICS55 PDK (cell models).
# =====================================================================
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
PKG="$(cd "$HERE/.." && pwd)"          # chip/
REPO="$(cd "$PKG/.." && pwd)"          # repository root
WHICH="${1:-rtl}"

PDK_ROOT="${PDK_ROOT:-$HOME/.local/share/ecc/pdks/icsprout55/v1.10.102}"
STD="$PDK_ROOT/IP/STD_cell/ics55_LLSC_H7C_V1p10C100"
[ -d "$STD" ] || { echo "[ERROR] ICS55 std cell dir not found: $STD" >&2; exit 1; }

WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT
cd "$WORK"
cp "$PKG"/rtl/*.v .
cp "$REPO/tb/t2f_model.v" "$REPO/tb/i2c_master_model.v" "$REPO/tb/t2f_model_params.vh" .

# ---- PDK cell models, with the broken MUXI2 modules removed ----------
# (the PDK model for the inverting 2:1 mux is self-referencing; see
#  pnr/ics55/README.md)
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
cp "$REPO/pnr/ics55/verify/muxi2_fix.v" "$REPO/pnr/ics55/verify/fillers_stub.v" .

# ---- digital macro ---------------------------------------------------

case "$WHICH" in
  rtl)
    cp "$REPO/pnr/ics55/rtl/temp_sensor_block.v" .
    cp "$REPO/pnr/ics55/rtl/i2c_slave.v" .
    cp "$REPO/rtl/temp_engine.v" "$REPO/rtl/temp_regs.v" .
    DESIGN="temp_sensor_block.v i2c_slave.v temp_engine.v temp_regs.v"
    ;;
  syn)
    gzip -dc "$REPO/pnr/ics55/netlist/temp_sensor_block_Synthesis.v.gz" > dig.v
    DESIGN="dig.v"
    ;;
  route)
    gzip -dc "$REPO/pnr/ics55/netlist/temp_sensor_block_route.v.gz" > dig.v
    DESIGN="dig.v"
    ;;
  *) echo "[ERROR] unknown target: $WHICH (rtl|syn|route)" >&2; exit 2 ;;
esac

CHIP="chip_top.v t2f_afe.v t2f_inbuf.v clkgen.v por.v pad_signal.v"

echo "=== chip-level simulation (digital macro: $WHICH) ==="
verilator --binary --timing -Wno-fatal \
    +define+CHIP_SIM +define+CHIP_SIM_POR_NS=20000 \
    -Wno-TIMESCALEMOD -Wno-UNUSEDSIGNAL -Wno-UNUSEDPARAM -Wno-DECLFILENAME \
    -Wno-BLKSEQ -Wno-WIDTH -Wno-CASEINCOMPLETE -Wno-UNDRIVEN -Wno-MULTIDRIVEN \
    -Wno-LATCH -Wno-INITIALDLY -Wno-UNOPTFLAT -Wno-SPECIFYIGN \
    --top-module chip_tb --Mdir obj -o chip_tb \
    "$PKG/sim/chip_tb.sv" $CHIP $DESIGN \
    fillers_stub.v muxi2_fix.v ics55_LLSC_H7CL_fixed.v ics55_LLSC_H7CR_fixed.v \
    t2f_model.v i2c_master_model.v

./obj/chip_tb
