#!/usr/bin/env python3
# =====================================================================
# Recursively flatten a SPICE netlist: every ".include" is resolved
# against the directory of the file that contains it (NOT the CWD, whose
# semantics differ across ngspice versions), producing one self-contained
# file with only absolute paths / inlined content.
#
# Usage:
#   python3 scripts/flatten_spice.py <root.spice> <out.spice>
#
# The SkyWater corner files (corners/tt.spice ...) reference the device
# models via "../../../libs.ref/..." chains; flattening them this way is
# immune to ngspice's relative-include resolution quirks.
# =====================================================================
import re
import sys
from pathlib import Path

INCLUDE_RE = re.compile(r'^\.include\s+"([^"]+)"\s*$', re.IGNORECASE)
LIB_RE = re.compile(r'^\.lib\s+"([^"]+)"', re.IGNORECASE)

seen = set()          # absolute paths already flattened
emit = []             # collected lines


def flatten(path: Path):
    path = path.resolve()
    if path in seen:
        return
    seen.add(path)
    lines = path.read_text(errors="replace").splitlines()
    for ln in lines:
        m = INCLUDE_RE.match(ln.strip()) or LIB_RE.match(ln.strip())
        if m:
            target = (path.parent / m.group(1)).resolve()
            if not target.exists():
                print(f"[WARN] include target missing: {target} (from {path})",
                      file=sys.stderr)
                continue
            flatten(target)
        else:
            emit.append(ln)


def main():
    if len(sys.argv) != 3:
        print(__doc__)
        sys.exit(1)
    root = Path(sys.argv[1])
    out = Path(sys.argv[2])
    if not root.exists():
        print(f"[ERROR] {root} not found", file=sys.stderr)
        sys.exit(1)
    flatten(root)
    out.write_text("\n".join(emit) + "\n")
    print(f"[OK] flattened {len(seen)} file(s) -> {out} "
          f"({len(emit)} lines)")


if __name__ == "__main__":
    main()
