#!/usr/bin/env python3
"""Plot PTAT current vs temperature (all corners) with ideal linear reference."""
import csv
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt

data = {}
with open("analog/sim/ptat_results.csv") as f:
    for r in csv.DictReader(f):
        try:
            t = float(r["temp_c"]); i = float(r["iptat_a"])
        except (ValueError, KeyError):
            continue
        data.setdefault(r["corner"], []).append((t, i))

fig, ax = plt.subplots(figsize=(9, 5.5))
for corner, pts in sorted(data.items()):
    pts.sort()
    xs = [p[0] for p in pts]; ys = [p[1]*1e6 for p in pts]
    ax.plot(xs, ys, "o-", lw=1.6, label=f"simulated corner {corner}")

# ideal PTAT reference: linear through (27 C, I(27)) with slope I(300K)/300 per K
if "tt" in data:
    ref = {t: i for t, i in data["tt"]}
    i27 = ref[27.0]
    t0 = min(ref); t1 = max(ref)
    slope = i27 / (273.15 + 27.0)           # dI/dT = I/T (linear PTAT)
    ax.plot([t0, t1], [(i27 + slope*(t0-27))*1e6, (i27 + slope*(t1-27))*1e6],
            "k--", lw=1.4, label="ideal PTAT reference (through 27C)")
    err = max(abs(i - (i27 + slope*(t-27)))/i for t, i in ref.items())
    ax.set_title(f"PTAT current vs temperature -- sky130A 1.8V\n"
                 f"max deviation from ideal PTAT: {err*100:.1f}%")

ax.set_xlabel("Temperature (C)")
ax.set_ylabel("Iptat (uA)")
ax.legend(); ax.grid(True, alpha=0.3)
fig.tight_layout()
fig.savefig("analog/sim/ptat_i_vs_temp.png", dpi=150)
print("saved analog/sim/ptat_i_vs_temp.png")
