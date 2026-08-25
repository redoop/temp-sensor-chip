#!/bin/bash
# =====================================================================
# Generate an absolute-path wrapper around the SkyWater 130nm PDK
# ngspice model collection (all.spice), so that ngspice simulations can
# be launched from any working directory.
#
# Input : PDK ngspice lib dir (default: IIC-OSIC-TOOLS container path)
# Output: analog/spice/sky130_models.spice
# =====================================================================
set -euo pipefail

PDK_NGSPICE="${PDK_NGSPICE:-/foss/pdks/sky130A/libs.tech/ngspice}"
HERE="$(cd "$(dirname "$0")/.." && pwd)"
OUT="${HERE}/analog/spice/sky130_models.spice"

if [ ! -f "${PDK_NGSPICE}/all.spice" ]; then
    echo "[ERROR] all.spice not found under ${PDK_NGSPICE}" >&2
    exit 1
fi

# Rewrite every relative .include into an absolute path:
#   "parameters/..."  -> "<PDK_NGSPICE>/parameters/..."
#   "../../libs.ref/..." -> "<PDK_ROOT>/libs.ref/..."  (PDK_ROOT = ngspice/../..)
PDK_ROOT="$(cd "${PDK_NGSPICE}/../.." && pwd)"

sed -e "s|\.include \"\\.\\./\\.\\./libs\\.ref/|.include \"${PDK_ROOT}/libs.ref/|g" \
    -e "s|\.include \"\(parameters\|parasitics\|capacitors\|sonos_p\|sonos_e\)/|.include \"${PDK_NGSPICE}/\1/|g" \
    -e "s|\.include \"head\.spice\"|.include \"${PDK_NGSPICE}/head.spice\"|g" \
    -e "s|\.include \"sky130_fd_pr__model__linear\.model\.spice\"|.include \"${PDK_NGSPICE}/sky130_fd_pr__model__linear.model.spice\"|g" \
    "${PDK_NGSPICE}/all.spice" > "${OUT}"

# The model files themselves may contain relative includes that must be
# resolved against the ngspice lib dir; rewrite those too.
sed -i -e "s|\.include \"\\.\\./\\.\\./libs\\.ref/|.include \"${PDK_ROOT}/libs.ref/|g" \
       -e "s|\.include \"\(parameters\|parasitics\|capacitors\|sonos_p\|sonos_e\)/|.include \"${PDK_NGSPICE}/\1/|g" \
       -e "s|\.include \"head\.spice\"|.include \"${PDK_NGSPICE}/head.spice\"|g" \
       -e "s|\.include \"\(sky130_fd_pr__[a-z_]*\.model\.spice\|sky130_fd_pr__model__linear\.model\.spice\)\"|.include \"${PDK_NGSPICE}/\1\"|g" \
       "${OUT}"

echo "[OK] Generated ${OUT}"
grep -c '^\.include' "${OUT}" | xargs echo "[INFO] include directives:"
