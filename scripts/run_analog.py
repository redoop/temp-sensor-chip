#!/usr/bin/env python3
# =====================================================================
# Analog front-end simulation driver.
#
# For each corner x temperature: generate the testbench, run ngspice in
# batch mode, parse the measurements, and collect f(T) data.
#
# Outputs:
#   analog/sim/results_<corner>.csv   : f(T) per corner
#   analog/sim/freq_vs_temp.png       : plot (if matplotlib available)
#   scripts/t2f_model_params.py       : fitted model + calibration data
#                                       consumed by the digital co-sim
#
# Usage: python3 scripts/run_analog.py [--corners tt,ss,ff] [--temps ...]
# =====================================================================
import argparse
import math
import os
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
ANALOG = ROOT / "analog"
SPICE = ANALOG / "spice"
SIM = ANALOG / "sim"
PDK_NGSPICE = os.environ.get("PDK_NGSPICE", "/foss/pdks/sky130A/libs.tech/ngspice")

SIM.mkdir(parents=True, exist_ok=True)


def run_ngspice(netlist: Path, log: Path):
    """Run ngspice -b, return stdout text."""
    r = subprocess.run(
        ["ngspice", "-b", str(netlist)],
        capture_output=True, text=True, cwd=str(SPICE), timeout=600,
    )
    log.write_text(r.stdout + "\n--- STDERR ---\n" + r.stderr)
    return r.stdout


def parse_meas(stdout: str, name: str):
    """Parse '.meas ... name=value' from ngspice stdout."""
    m = re.search(rf"{name}\s*=\s*([-+0-9.eE]+)", stdout)
    if not m:
        return None
    return float(m.group(1))


def make_tb(template: Path, out: Path, tsim: float, corner: str):
    text = template.read_text()
    text = text.replace("{{TSIM}}", f"{tsim:g}")
    text = text.replace("{{CORNER}}", corner)
    text = text.replace("{{PDK_NGSPICE}}", PDK_NGSPICE)
    out.write_text(text)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--corners", default="tt", help="comma-separated corners")
    ap.add_argument("--temps", default="-40,-20,0,20,27,40,60,80,100,125",
                    help="comma-separated temperatures (C)")
    ap.add_argument("--skip-ptat", action="store_true")
    ap.add_argument("--quick", action="store_true",
                    help="single temp only, for smoke testing")
    args = ap.parse_args()

    corners = [c.strip() for c in args.corners.split(",")]
    temps = [float(t) for t in args.temps.split(",")]
    if args.quick:
        temps = [27.0]

    # ---------- PTAT DC ----------
    if not args.skip_ptat:
        print("[1/2] PTAT DC characterization")
        ptat_rows = []
        for corner in corners:
            for t in temps:
                tb = SIM / f"_tb_ptat_{corner}_{t:g}.spice"
                make_tb(SPICE / "tb_ptat.spice", tb, t, corner)
                out = run_ngspice(tb, SIM / f"log_ptat_{corner}_{t:g}.txt")
                iptat = parse_meas(out, "iptat")
                vgmir = parse_meas(out, "vgmir")
                ptat_rows.append((t, corner, iptat, vgmir))
                if iptat is None:
                    print(f"  WARN T={t:6.1f}C {corner}: no iptat measured (check log)")
                else:
                    vg = "n/a" if vgmir is None else f"{vgmir:.4f}"
                    print(f"  T={t:6.1f}C {corner}: Iptat={iptat:.4e} A  Vgmir={vg} V")
        with open(SIM / "ptat_results.csv", "w") as f:
            f.write("temp_c,corner,iptat_a,vgmir_v\n")
            for t, c, i, v in ptat_rows:
                f.write(f"{t:g},{c},{i if i is not None else 'nan'},"
                        f"{v if v is not None else 'nan'}\n")
        print(f"  -> {SIM / 'ptat_results.csv'}")

    # ---------- T2F transient ----------
    print("[2/2] T2F frequency extraction")
    results = {}
    for corner in corners:
        rows = []
        for t in temps:
            tb = SIM / f"_tb_t2f_{corner}_{t:g}.spice"
            make_tb(SPICE / "tb_t2f.spice", tb, t, corner)
            out = run_ngspice(tb, SIM / f"log_t2f_{corner}_{t:g}.txt")
            freq = parse_meas(out, "freq")
            period = parse_meas(out, "period")
            t1 = parse_meas(out, "t1")
            if freq is None:
                print(f"  WARN T={t:6.1f}C {corner}: no freq measured (check log)")
                rows.append((t, corner, math.nan, math.nan, math.nan))
            else:
                rows.append((t, corner, freq, period, t1))
                print(f"  T={t:6.1f}C {corner}: f={freq/1e3:9.3f} kHz  period={period*1e6:8.3f} us")
        results[corner] = rows
        with open(SIM / f"results_{corner}.csv", "w") as f:
            f.write("temp_c,corner,freq_hz,period_s,t1_s\n")
            for t, c, fr, pe, t1v in rows:
                f.write(f"{t:g},{c},{fr:e},{pe:e},{t1v:e}\n")

    # ---------- fit + model params ----------
    print("\n[fit] f(T) linear fit (tt corner, primary calibration):")
    fit_out = {}
    for corner, rows in results.items():
        pts = [(t, fr) for t, c, fr, pe, t1v in rows
               if fr is not None and not math.isnan(fr)]
        if len(pts) < 2:
            continue
        # least squares: f = a*T + b
        n = len(pts)
        sx = sum(t for t, _ in pts)
        sy = sum(f for _, f in pts)
        sxx = sum(t * t for t, _ in pts)
        sxy = sum(t * f for t, f in pts)
        a = (n * sxy - sx * sy) / (n * sxx - sx * sx)
        b = (sy - a * sx) / n
        # residuals
        errs = [abs(f - (a * t + b)) / f for t, f in pts]
        maxerr = max(errs) if errs else float("nan")
        fit_out[corner] = {"a": a, "b": b, "n": n, "maxerr_pct": maxerr * 100.0}
        print(f"  {corner}: f(T) = {a:.6e}*T + {b:.6e}  Hz"
              f"  (n={n}, max rel err {maxerr*100:.3f}%)")

    # Calibration model: count pulses in a gate window of GATE_S.
    # raw_count = f(T) * GATE_S  ->  T = (raw_count - off) / gain
    gate_s = 10e-3
    if "tt" in fit_out and fit_out["tt"]["n"] >= 2:
        a, b = fit_out["tt"]["a"], fit_out["tt"]["b"]
        gain = a * gate_s           # counts per kelvin
        off = b * gate_s            # counts at T=0
        # counts at calibration points -40C and +125C
        c40 = (a * (-40) + b) * gate_s
        c125 = (a * 125 + b) * gate_s
        res_k = 1.0 / gain          # kelvin per count
        print(f"\n[calib] gate={gate_s*1e3:g} ms")
        print(f"  gain={gain:.6f} counts/K, off={off:.6f} counts")
        print(f"  count(-40C)={c40:.1f}, count(125C)={c125:.1f}")
        print(f"  resolution={res_k*1000:.1f} mK/count")

        # two-point calibration constants (LM75-style 9-bit, 0.5 C/count)
        # raw = round(f(T)*gate); T_c = (raw - C0) / (C1 - C0) * (T1 - T0) + T0
        cal = {"gate_s": gate_s, "gain_counts_per_k": gain, "off_counts": off,
               "t0_c": -40.0, "t1_c": 125.0,
               "count0": c40, "count1": c125, "resolution_k_per_count": res_k}
        with open(ROOT / "scripts" / "t2f_model_params.py", "w") as f:
            f.write("# Auto-generated by scripts/run_analog.py -- do not edit\n")
            f.write(f"CAL = {cal!r}\n")
            f.write(f"FIT = {fit_out!r}\n")
        print(f"  -> {ROOT / 'scripts' / 't2f_model_params.py'}")

    # ---------- plot ----------
    try:
        import matplotlib
        matplotlib.use("Agg")
        import matplotlib.pyplot as plt
        fig, ax = plt.subplots(figsize=(8, 5))
        for corner, rows in results.items():
            pts = [(t, fr / 1e3) for t, c, fr, pe, t1v in rows
                   if fr is not None and not math.isnan(fr)]
            if pts:
                pts.sort()
                xs = [p[0] for p in pts]
                ys = [p[1] for p in pts]
                ax.plot(xs, ys, "o-", label=f"corner {corner}")
        ax.set_xlabel("Temperature (C)")
        ax.set_ylabel("Oscillation frequency (kHz)")
        ax.set_title("T2F front-end: f(T) -- SkyWater 130nm, 1.8 V")
        ax.legend()
        ax.grid(True)
        fig.tight_layout()
        fig.savefig(SIM / "freq_vs_temp.png", dpi=150)
        print(f"  -> {SIM / 'freq_vs_temp.png'}")
    except Exception as e:  # matplotlib may be missing
        print(f"  [skip plot] {e}")

    print("\nDone.")


if __name__ == "__main__":
    main()
