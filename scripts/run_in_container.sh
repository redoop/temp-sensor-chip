#!/bin/bash
# =====================================================================
# Run a command inside a throwaway IIC-OSIC-TOOLS container with the
# project mounted at /foss/designs/temp-sensor-chip.
#
# Usage: ./scripts/run_in_container.sh "make sim"
#        IIC_IMG=... ./scripts/run_in_container.sh "make synth"
# =====================================================================
set -euo pipefail

IMG="${IIC_IMG:-hpretl/iic-osic-tools:latest}"
PROJ_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PROJ_NAME="$(basename "${PROJ_DIR}")"

exec docker run --rm --user "$(id -u):$(id -g)" \
    -v "${PROJ_DIR}:/foss/designs/${PROJ_NAME}" \
    "${IMG}" --skip \
    bash -lc "cd /foss/designs/${PROJ_NAME} && $*"
