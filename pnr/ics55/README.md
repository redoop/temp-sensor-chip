# ICS55 digital implementation (RTL → DEF + netlist)

Place-and-route result for the temp-sensor-chip digital core on the
**ICsprout 55 nm (ICS55) PDK**, produced with the ECC RTL-to-GDS flow on
`fireflyer@192.168.100.103`.

> **Status: the flow completes cleanly, but the hardened netlist is NOT
> functionally equivalent to the RTL.** The I2C slave never drives SDA in
> either the synthesis or the post-route netlist, while the RTL passes the
> same test. See [Known defect](#known-defect-the-netlist-does-not-match-the-rtl).
> Treat the artefacts below as a working P&R baseline, not as signoff data.

## What was run

| Item | Value |
| --- | --- |
| Tool | `ecc 0.1.0a12` (yOSys 0.68+slang, DreamPlace, Sizer, klayout) |
| PDK | `icsprout55` v1.10.102, std cell library `ics55_LLSC_H7C_V1p10C100` |
| Flow | `--preset rtl2gds` (15 steps: synth → LEC → floorplan → place → CTS → legalize → timing opt → route → filler → RCX → STA → LVS → postroute LEC → DRC → harden) |
| Synthesis strategy | `YOSYS_SYNTH_STRATEGY='AREA 0'` (no ABC retiming) |
| Clock target | 10 MHz (`frequency_mhz = 10.0`), the frequency `GATE_CYCLES` is calibrated for |

### Why a wrapper top

`rtl/temp_sensor_top.v` models the I2C pads and the alert as Verilog
tri-state (`inout scl, sda` and `assign os_int = os_state ? 1'bz : 1'b0`).
A standard-cell block has no tri-state cells, and yosys's `tribuf` pass
drops the whole SDA driver cone when it meets them — the first attempt
produced a **completely empty netlist** (one tie cell, 11 components in
the floorplan DEF).

`rtl/temp_sensor_block.v` therefore splits every open-drain pad into a
value + output-enable pair, and `rtl/i2c_slave.v` is the patched slave
(`sda` is an input, `sda_oe` is exported) that was already validated in
the mpc-frame design package.

## Results

All steps report success except `lec` (see the defect below).

| Metric | Value |
| --- | --- |
| Die area | 82.6 µm × 83.8 µm = **6921.9 µm²** |
| Core utilisation | 40.4 % (die 36.6 %) |
| Instances | **1372** (1124 logic + 156 flops + 248 filler/tap) |
| Setup WNS / TNS / NVP | **+92.222 ns** / 0.0 / 0 — at the WCL (−40 °C, Cworst) corner |
| Hold WNS / TNS / NVP | **+0.256 ns** / 0.0 / 0 |
| Estimated Fmax | ~129 MHz (target was 10 MHz) |
| DRC | **0 violations** |
| LVS | **clean** — 9 IO, 3252 instances, 1130 nets, 0 opens, 0 shorts |
| post-route LEC | **pass** (synthesis netlist ≡ post-route netlist) |
| RTL-vs-synthesis LEC | **FAIL** — `sda_oe`, `os_int_oe` unproven |

## Artefacts

| Path | Contents |
| --- | --- |
| `def/temp_sensor_top_pnr_route.def.gz` | routed DEF (gzipped) |
| `netlist/temp_sensor_block_route.v.gz` | post-route gate netlist |
| `netlist/temp_sensor_block_Synthesis.v.gz` | post-synthesis gate netlist |
| `harden/temp_sensor_block_route_layout.gds` | **full layout GDSII** (1.76 MB, 1214 structures, 79 standard-cell masters) |
| `harden/temp_sensor_block_Harden.gds` | *abstract* macro view only (5 structures: DIEAREA + pins + obstructions) |
| `harden/temp_sensor_block_Harden.lef` | abstract LEF for chip-level integration |
| `harden/temp_sensor_block_Harden.lib` | timing LIB |
| `harden/temp_sensor_block_Harden.png` | layout snapshot |
| `reports/qor_summary_WCL_m40.rpt` | STA QoR summary |
| `reports/lvs.rpt` | LVS report |
| `reports/drc.rpt` | DRC report |
| `rtl/`, `ecc.toml` | the exact sources and project config used |
| `verify/` | gate-level testbench + PDK model fixes + reproduction script |

The design is named `temp_sensor_top_pnr` because that was the ECC project
name; the module is `temp_sensor_block`.

## Scope: this is the digital block only

**Neither the netlist nor the layout contains any analog circuit.** Verified
on the artefacts:

* Netlist: every instance is an ICS55 standard cell (names ending `H7R` /
  `H7L`, i.e. the H7CR / H7CL libraries). No PNP, resistor, capacitor or
  other analog device appears.
* Layout GDS: 1214 structures = 79 `Master_<stdcell>` definitions plus the
  top-level routing; **0 non-standard-cell masters**.

The analog front-end enters this block as a plain digital input. The port
list makes the boundary explicit:

```
input  clk, rstn, t2f_in, scl_i, sda_i
output sda_o, sda_oe, os_int_o, os_int_oe
```

`t2f_in` **is** the divide. Everything left of it — the PTAT current source,
the current-starved ring oscillator, and the level/drive conditioning of the
resulting square wave — is analog and lives outside this netlist:

| Analog asset | Form | In the netlist? |
| --- | --- | --- |
| `analog/spice/ptat.spice` | SPICE schematic (Banba OTA PTAT) | no |
| `analog/spice/csro.spice` | SPICE schematic (5-stage CSRO) | no |
| `analog/spice/t2f.spice` | SPICE top (PTAT + CSRO) | no |
| `analog/sim/*.csv`, `*.png` | ngspice characterization (f(T), Iptat) | no |
| `layout/ptat_cell.mag/.gds` | magic layout of the PTAT cell only | no — separate GDS |
| `tests/t2f_model.v` | behavioral T2F model (digital sim only) | no |

Consequences worth being explicit about:

* There is **no single merged full-chip netlist** in this repo, and this
  step does not create one. A full-chip netlist would be a chip-level
  assembly (pad ring + analog block + this hardened macro), which does not
  exist yet.
* The analog side is far from tapeout in its own right: the PTAT cell has
  a layout with 8 spacing DRC violations, and **the CSRO has no layout at
  all**. The SPICE netlists are schematics, not layout.
* `t2f_in` is treated as a digital signal. The real CSRO output is a
  ~0.5–0.8 MHz, 1.8 V square wave; any chip-level integration must
  guarantee adequate swing, slope and noise margin at this pin, and the
  2-flop synchronizer in `i2c_slave.v` / the engine's edge detector are the
  only conditioning on the digital side.

## Reproducing

On a host with the ECC toolchain and the ICS55 PDK:

```sh
ecc init temp_sensor_top_pnr
cd temp_sensor_top_pnr
cp <this directory>/rtl/*.v rtl/
ecc project set design.top    temp_sensor_block
ecc project set design.rtl    rtl/temp_sensor_block.v rtl/i2c_slave.v \
                              rtl/temp_engine.v rtl/temp_regs.v
ecc project set design.clock_port clk
ecc project set design.frequency_mhz 10.0
YOSYS_SYNTH_STRATEGY='AREA 0' ecc run --overwrite --preset rtl2gds
```

`ecc run --from floorplan` resumes past the failing `lec` step.

## Known defect: the netlist does not match the RTL

### Evidence

1. **LEC (RTL vs synthesis) fails** on exactly two signals, both output
   enables: `sda_oe` and `os_int_oe`. Post-route LEC passes, so the P&R
   steps preserve the synthesis netlist — the divergence is introduced by
   synthesis.
2. **Gate-level simulation** (`verify/run_gl_sim.sh`) closes the same loop
   the RTL tests close. Result:

   | DUT | address ACK | TOS read | temp @25 C | temp @125 C | os_int @125 C |
   | --- | --- | --- | --- | --- | --- |
   | RTL (`run_gl_sim.sh rtl`) | **1** | 0x64 | 50 | 250 | asserted |
   | synthesis netlist (`syn`) | 0 | 0xFF | −1 | −1 | never |
   | post-route netlist (`route`) | 0 | 0xFF | −1 | −1 | never |

   The RTL passes the *same testbench*, so the testbench and the bus model
   are not the problem.
3. In the netlist the temperature engine still runs (`engine_done` toggles
   every 10 ms) but **`sda_oe` never transitions**, so the slave never
   ACKs, and every register read returns 0xFF from the bus pull-up.

### What was ruled out

* **ABC retiming** — re-ran with the retime-free `AREA 0` strategy; the
  failure is identical.
* **`opt_demorgan` / `opt_ffinv` / the aggressive ABC script** — three
  hand-built synthesis variants (with and without those passes, and with a
  minimal `+strash;dch;map,-a` ABC script) all fail identically.
* **P&R** — the synthesis netlist fails the same way, and post-route LEC
  passes.
* **Combinational loops in the design** — none. Verilator reports no
  `UNOPTFLAT` for either the RTL or the netlist once the PDK cell-model
  bug below is patched.
* **Clock tree / reset** — CTS connects `clk` through buffers to every
  flop `CK` with no clock gating, and the flops demonstrably clock
  (`engine_done` toggles).

### Separate finding: broken PDK cell model

`MUXI2*` (14 cells across H7CL/H7CR) is modelled as

```verilog
udp_mux2 u0(Y, A, B, S0);   // non-inverting mux
not      u1(Y, Y);          // Y = ~Y : takes Y as its own input
```

which is self-referencing. Any zero-delay simulator either yields X or
fails to converge — Verilator aborts with `DIDNOTCONVERGE`. The liberty
function is `Y = (!A * !S0) + (!B * S0)`, i.e. an inverting 2:1 mux;
`verify/muxi2_fix.v` provides liberty-accurate replacements and the
reproduction script strips the broken modules. This is a **PDK model
bug**, independent of the defect above.

### Next step

Bisect the yosys `synth` flow itself (the common path shared by all three
variants: `synth -run :fine`, `flatten`, `opt -full`, `synth -run fine:`,
`tribuf`, `techmap`, `splitnets`, `dfflibmap`) and compare `sda_oe`'s cone
against the RTL, or synthesise `i2c_slave` standalone and simulate it in
isolation. The netlist's `sda_oe_reg_p_D` cone is real logic (not tied
off), so the divergence is upstream of the flop.
