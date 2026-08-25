#!/bin/bash
# =====================================================================
# run_synth.sh -- Yosys logic synthesis of the digital core to
# sky130_fd_sc_hd (SkyWater 130 nm standard cells)
#
# Outputs: syn/out/temp_sensor_top_synth.v  (gate-level netlist)
#          syn/out/synth.log               (log + stats)
# =====================================================================
set -euo pipefail

HERE="$(cd "$(dirname "$0")/.." && pwd)"
LIB=""

# auto-detect a sky130_fd_sc_hd liberty file
for c in \
    "/foss/pdks/sky130A/libs.ref/sky130_fd_sc_hd/lib/sky130_fd_sc_hd__tt_025C_1v80.lib" \
    "$PDK_ROOT/sky130A/libs.ref/sky130_fd_sc_hd/lib/sky130_fd_sc_hd__tt_025C_1v80.lib"; do
    if [ -f "$c" ]; then LIB="$c"; break; fi
done

if [ -z "$LIB" ]; then
    # fall back to any tt lib found in the filesystem
    LIB="$(find / -name 'sky130_fd_sc_hd__tt_025C_1v80.lib' 2>/dev/null | head -1 || true)"
fi
if [ -z "$LIB" ] || [ ! -f "$LIB" ]; then
    echo "[ERROR] sky130_fd_sc_hd timing lib not found" >&2
    exit 1
fi
echo "[INFO] using liberty: $LIB"

mkdir -p "${HERE}/syn/out"

yosys -q -l "${HERE}/syn/out/synth.log" -p "
read_verilog -sv ${HERE}/rtl/i2c_slave.v ${HERE}/rtl/temp_engine.v ${HERE}/rtl/temp_regs.v ${HERE}/rtl/temp_sensor_top.v
hierarchy -top temp_sensor_top
proc; opt; fsm; opt; memory; opt
techmap; opt
abc -liberty ${LIB}
dfflibmap -liberty ${LIB}
opt; clean
stat -liberty ${LIB}
write_verilog ${HERE}/syn/out/temp_sensor_top_synth.v
"

echo "[OK] netlist: ${HERE}/syn/out/temp_sensor_top_synth.v"
echo "[OK] log:     ${HERE}/syn/out/synth.log"
grep -A5 "Chip area" "${HERE}/syn/out/synth.log" | head -8
