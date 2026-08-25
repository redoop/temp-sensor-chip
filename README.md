**[中文](README_CN.md) | English**

# Temperature Sensor Chip (温度传感器芯片) — TS130

A smart temperature sensor chip developed with the **IIC-OSIC-TOOLS container**
(server 192.168.100.102) and the **SkyWater 130nm (sky130A)** PDK: an analog
front-end (PTAT + temperature-to-frequency converter) plus a digital core
(I2C interface + calibration), covering a complete flow through ngspice analog
verification, Verilog digital simulation, Yosys synthesis and magic layout.

## Highlights

- **True PTAT current source** (Banba OTA-forced topology): the OTA forces the two
  branches to equal voltage, giving exactly `I = ΔVbe/R1 ∝ T`. Measured across
  -40~125 °C, linearity is <5% (0.473→0.850 µA vs. ideal 0.473→0.808 µA).
- **Found and worked around a key PDK trap**: sky130 PNP subcircuits **ignore the
  `mult` parameter** — the area ratio must be realized with two differently sized
  devices (W3p40 vs W0p68), otherwise ΔVbe = 0 and the PTAT completely fails.
- **I2C slave interface** (LM75-style): address 0x48, auto-incrementing register
  pointer, multi-byte read, NACK handling — all 6 protocol tests pass.
- **Two-point calibration**: 9-bit / 0.5 °C temperature output; calibration
  constants are auto-generated from ngspice characterization.
- **Full toolchain**: ngspice all-corner sweep → iverilog digital simulation →
  Yosys sky130 synthesis (561 cells / 5558 µm²) → magic sky130A layout
  (PDK device geometry + DRC + GDS export).

## Directory Layout

```
temp-sensor-chip/
├── analog/
│   ├── spice/            # PTAT(T2F) netlists: ptat/csro/t2f + testbenches
│   └── sim/              # ngspice results: results_{tt,ss,ff}.csv, freq_vs_temp.png
├── rtl/
│   ├── i2c_slave.v       # I2C slave (address 0x48, 400 kHz)
│   ├── temp_engine.v     # T2F gated counter + two-point calibration → 9-bit temp
│   ├── temp_regs.v       # register file (config/Thyst/TOS/temperature)
│   └── temp_sensor_top.v # chip top (incl. os_int over-temperature alarm)
├── tb/
│   ├── i2c_master_model.v # bit-level I2C master model
│   ├── t2f_model.v        # analog front-end behavioral model (f(T) from ngspice data)
│   ├── tb_i2c.v           # I2C protocol tests (6 PASS)
│   ├── tb_top.v           # full-chip test (temperature read-back accuracy)
│   └── t2f_model_params.vh # auto-generated calibration parameters
├── scripts/
│   ├── run_analog.py      # ngspice temperature/corner sweep driver + fit
│   ├── gen_t2f_model.py   # generate calibration constants + t2f behavioral model params
│   └── run_in_container.sh # IIC-OSIC-TOOLS container runner
├── syn/                   # Yosys synthesis (run_synth.sh, out/)
├── layout/                # magic layout (ptat_cell.mag/.gds, DRC report)
├── docs/architecture.md   # architecture design document
└── Makefile               # sim-analog / sim-rtl / model / synth
```

## Getting Started (on the server)

```bash
# Analog front-end all-corner sweep (ngspice, in container)
./scripts/run_in_container.sh "make sim-analog"

# Generate calibration model params (driven by analog/sim/results_tt.csv)
./scripts/run_in_container.sh "make model"

# Digital RTL simulation (iverilog)
make sim-rtl          # locally (OSS CAD Suite) or in the container

# Synthesis (yosys → sky130_fd_sc_hd)
./scripts/run_in_container.sh "make synth"

# magic layout + DRC + GDS
./scripts/run_in_container.sh "cd layout && magic -noconsole -dnull \
  -rcfile /foss/pdks/sky130A/libs.tech/magic/sky130A.tcl ptat_cell.tcl"
```

## Verification Summary

### Analog front-end (ngspice, sky130A)
| Temp | tt freq | ss freq | ff freq | Iptat(tt) |
|---|---|---|---|---|
| -40 °C | 507 kHz | 535 kHz | 467 kHz | 0.473 µA |
| -20 °C | 546 kHz | 580 kHz | 502 kHz | 0.520 µA |
| 0 °C | 580 kHz | 617 kHz | 534 kHz | 0.565 µA |
| 20 °C | 612 kHz | 653 kHz | 565 kHz | 0.610 µA |
| 27 °C | 623 kHz | 664 kHz | 576 kHz | 0.625 µA |
| 40 °C | 642 kHz | 684 kHz | 594 kHz | 0.654 µA |
| 60 °C | 672 kHz | 716 kHz | 621 kHz | 0.698 µA |
| 80 °C | 700 kHz | 748 kHz | 647 kHz | 0.743 µA |
| 100 °C | 729 kHz | 777 kHz | 673 kHz | 0.789 µA |
| 125 °C | 765 kHz | 815 kHz | 702 kHz | 0.850 µA |

**Test plots:**

![T2F temperature-frequency characteristic (tt/ss/ff corners, ngspice)](analog/sim/freq_vs_temp.png)

![PTAT current-linearity verification (with ideal PTAT reference)](analog/sim/ptat_i_vs_temp.png)

Full data is in `analog/sim/results_*.csv` and `analog/sim/ptat_results.csv`.

### Digital (iverilog)
- `tb_i2c`: write config/read back, Thyst/TOS read-write, wrong-address NACK,
  temperature register — **6/6 PASS**
- `tb_top`: full-chip temperature read-back at T=25/-40/125/0 °C
  (using ngspice calibration parameters)

### Synthesis (Yosys)
- sky130_fd_sc_hd, `temp_sensor_top` totals **561 cells / 5558 µm²**
  (`syn/out/temp_sensor_top_synth.v`)

### Layout (magic)
- `layout/ptat_cell.mag`: dual PNP (PDK device geometry) + p+ poly resistor +
  metal routing
- DRC: 8 spacing-type violations (hand-assembled layout); `ptat_cell.gds` exported

![PTAT analog cell layout (magic → GDS render, sky130A)](layout/ptat_cell.png)

## Key Design Points

1. **PTAT**: Banba OTA topology, `I = VT·ln(N)/R1`, N≈10 (W3p40/W0p68 area ratio),
   R1=100 kΩ.
2. **T2F**: 5-stage current-starved ring oscillator, f ∝ Iptat, 10 ms gated counting
   → ~6000 counts @27 °C.
3. **Calibration**: `temp = ((raw-C0)·GAIN)>>8 + T0`, C0/C1 are the -40/125 °C
   calibration counts.
4. **I2C**: open-drain SDA, 3-tap glitch filter, byte state machine, stop on NACK.

See [docs/architecture.md](docs/architecture.md) for details.

## Licensing
RTL and scripts: Apache-2.0.
