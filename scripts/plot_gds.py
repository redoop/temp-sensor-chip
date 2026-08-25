#!/usr/bin/env python3
"""Render a GDSII layout to PNG (gdspy + matplotlib)."""
import sys
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib.patches import Polygon
import gdspy

def main():
    infile, outfile = sys.argv[1], sys.argv[2]
    lib = gdspy.GdsLibrary(infile=infile)
    cell = lib.top_level()[0]
    polys = cell.get_polygons()
    layers = set()
    for el in cell.polygons:
        l = el.layers[0] if isinstance(el.layers, list) else el.layers
        layers.add(l)
    colors = ["#6096ff","#e6c850","#50dc78","#ff8c5a","#b478ff",
              "#78ffff","#ff78d2","#d2d2d2","#ffd278","#78a8ff"]
    cmap = {l: colors[i % len(colors)] for i, l in enumerate(sorted(layers))}
    fig, ax = plt.subplots(figsize=(11, 8.5))
    ax.set_facecolor("#12101e"); fig.patch.set_facecolor("#12101e")
    for el in cell.polygons:
        l = el.layers[0] if isinstance(el.layers, list) else el.layers
        c = cmap[l]
        for pts in el.polygons:
            ax.add_patch(Polygon(pts, closed=True, facecolor=c, edgecolor=c, lw=0.4))
    ax.autoscale_view(); ax.set_aspect("equal")
    bb = cell.get_bounding_box()
    ax.set_title(f"PTAT analog cell layout -- sky130A (GDS, {len(polys)} polygons, {len(layers)} layers)",
                 color="#e0e0e0")
    ax.set_xlabel("um"); ax.set_ylabel("um")
    ax.tick_params(colors="#999")
    for sp in ax.spines.values(): sp.set_color("#444")
    fig.tight_layout()
    fig.savefig(outfile, dpi=150)
    print(f"saved {outfile} ({len(polys)} polygons, bbox {bb[0]}..{bb[1]})")

if __name__ == "__main__":
    main()
