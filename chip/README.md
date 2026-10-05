# Full-chip merged netlist

Chip-level structural netlist that binds the analog front-end, the level
conditioner, the hardened digital macro, the pad ring and the always-on
support blocks into one elaboratable design, plus the macro views that
make a mixed-signal assembly simulatable.

> **Read this first: the chip cannot be built as configured.**
> The analog front-end is **sky130** and the digital harden we produced is
> **ICS55**, and the installed ICS55 PDK has no analog device library.
> See [Process mismatch](#blocking-issue-process-mismatch). Everything
> below is real design work, but it describes a chip that needs the
> process question resolved before it can exist.

## What "merged netlist" means

A transistor-level SPICE netlist and a gate-level Verilog netlist are
different abstract domains; they cannot be concatenated into one file.
A mixed-signal chip does not have "one true netlist". It has:

* one **structural top** that instantiates every block and wires them
  (`rtl/chip_top.v`),
* a **behavioural view** per analog block, so the top elaborates and the
  digital regression runs without SPICE (`rtl/t2f_afe.v`, `rtl/clkgen.v`,
  `rtl/por.v`, `rtl/pad_signal.v`),
* the **real content** per analog block: SPICE schematic plus layout
  (`analog/t2f_afe.spice` and the existing `../analog/spice/*`).

Chip-level LVS must compare the layout against both views. The structural
top is the contract that keeps them in step.

## Block diagram

```
                     VDDA VSSA            VDDD VSSD          VDDIO VSSIO
                        |                    |                   |
                  +-----+-----+        +-----+-----+       +-----+------+
                  |  u_clkgen |        |   u_por   |       |  pad ring  |
                  |  10 MHz   |        |  reset    |       | structure  |
                  +-----+-----+        +-----+-----+       +------------+
                        | clk                | rstn
                        |                    |
   +------------+  fout_ana  +-----------+   |        +-------------------+
   |   u_afe    +----------->| u_inbuf   +---+------->|      u_dig        |
   | PTAT+CSRO  |   analog   | level     | t2f_dig   | temp_sensor_block |
   | (sky130)   |            | shifter   |           | (ICS55 hardened)  |
   +------------+            +-----------+           +---+----+----+-----+
                                                          |    |    |
                                          scl_i <---------+    |    |
                                          sda_i <--------------+    |
                                          sda_o/oe ------------>    |
                                          os_int_o/oe ---------------+
                                                          |    |    |
   +----------+  +----------+  +------------+  +----------+ |    |    |
   | pad_in   |  |pad_bidir |  | pad_out_od |  |pad_analog| |    |    |
   |  SCL     |  |   SDA    |  |  OS_INT    |  | T2F_MON  | |    |    |
   +----+-----+  +----+-----+  +-----+------+  +----+-----+ |    |    |
        |             |              |              |       |    |    |
       SCL           SDA           OS_INT        T2F_MON     |    |    |
                                                             |    |    |
   ------------------- package pins ------------------------+----+----+
```

## Package pinout

| Pin | Dir | Domain | Function |
| --- | --- | --- | --- |
| `VDDD` / `VSSD` | pwr | 1.2 V | digital core |
| `VDDA` / `VSSA` | pwr | 1.2 V | analog front-end, **separate net** |
| `VDDIO` / `VSSIO` | pwr | 3.3 V | pad ring |
| `SCL` | in | 3.3 V | I2C clock |
| `SDA` | bidi, open drain | 3.3 V | I2C data |
| `OS_INT` | out, open drain | 3.3 V | over-temperature alert |
| `T2F_MON` | analog out | — | raw oscillator, for in-situ trim |

Design choices worth defending:

* **Separate analog supply.** The sensor output *is* a frequency. Digital
  switching noise coupling into the PTAT or the CSRO shifts that frequency
  and is read back as a temperature error, with nothing to distinguish it
  from a real temperature change. Sharing one 1.2 V rail would put every
  core switching event onto the sensor's supply.
* **`T2F_MON` exists on purpose.** The SPICE corners span roughly ±7 % in
  frequency at a given temperature. A calibration table fitted from
  schematic simulation cannot be right for every die, so the bring-up plan
  has to measure the real oscillator and re-derive the table. Without a
  monitor pin that is impossible.
* **Open-drain only at the pins.** SDA and OS_INT are pulled low or
  released; nothing on this chip drives a high level onto either. The I2C
  bus and the alert line both rely on pull-ups, which is what makes the
  wired-OR behaviour in `temp_sensor_block` legal.

## Blocking issue: process mismatch

| Domain | Process | Evidence |
| --- | --- | --- |
| Analog front-end | **sky130** | `analog/spice/*.spice` instantiate `sky130_fd_pr__pnp_05v5_*`, `sky130_fd_pr__pfet_01v8`, `sky130_fd_pr__nfet_01v8` |
| Digital harden | **ICS55** | `pnr/ics55/` — ICS55 standard cells, ICS55 techLEF |

And the installed ICS55 PDK contains **no analog devices**:

```
IP/  ->  IO  SRAM  STD_cell          (plus prtech/)
```

No PNP, no resistors, no capacitors. So today neither direction works:

* you cannot put this PTAT/CSRO on ICS55 with the installed PDK, and
* you cannot use the ICS55 digital harden in a sky130 chip.

The structural netlist in this directory is process-agnostic: `u_dig` is
only a port list, so the fix is to change which harden fills that slot.
Two ways forward:

1. **Re-harden the digital core on sky130** (recommended). sky130 has full
   analog support and the repo already synthesises the digital design to
   `sky130_fd_sc_hd` (`syn/run_synth.sh`, 561 cells / 5558 µm² in the
   README). The ICS55 P&R was a valid exercise with the toolchain that was
   available, but it is not the process the analog uses. sky130 is well
   served by OpenROAD/OpenLane for P&R.
2. Obtain the ICS55 analog device library and redesign the front-end.
   That means re-doing the PTAT (the topology depends on a substrate PNP
   with a controlled area ratio) and re-fitting the whole calibration
   table. Much larger effort, and it is not clear ICS55 offers a suitable
   PNP.

Until this is decided, treat `pnr/ics55/` as a tooling baseline, not as
the chip's digital block.

## What is real and what is not

| Instance | Status | Note |
| --- | --- | --- |
| `u_inbuf` | **real** | ICS55 1.2 V inverter chain, real cells, real pins |
| `u_dig` | **real but defective** | netlist/DEF/GDS exist; `sda_oe` never drives, so I2C does not answer (see `../pnr/ics55/README.md`) |
| `u_afe` | **partial** | SPICE schematic exists; the CSRO has **no layout**, the PTAT cell layout has 8 spacing DRC violations; never LVS'd or PEX'd |
| `u_clkgen` | **missing** | specification only |
| `u_por` | **missing** | specification only |
| pads | **missing** | installed IO library has only ring structure, no signal cells |

## Verification

```sh
PDK_ROOT=<icsprout55 pdk root> sim/run_chip_sim.sh rtl     # chip wiring
PDK_ROOT=<icsprout55 pdk root> sim/run_chip_sim.sh route   # known defect
```

The test drives the **package pins** and reads temperature back over I2C,
so it covers POR, the clock, the behavioural AFE, the T2F level shifter,
the pad models and the bus:

```
u_afe (CHIP_SIM model) -> fout_ana -> u_inbuf -> t2f_dig -> u_dig
  -> temp_engine -> temp_regs -> i2c_slave -> pad SDA -> master read-back
```

With the **RTL** digital core (verifies the chip wiring):

```
-- chip out of reset, running from the behavioural AFE --
PASS  chip TOS default = 0x64
PASS  chip Thyst default = 0x4b
PASS  chip T=25.00 C  half-steps=50
PASS  chip T=125.00 C  half-steps=250
PASS  chip OS_INT asserted at 125 C
PASS  chip T=0.00 C   half-steps=0
PASS  chip OS_INT released at 0 C
PASS  T2F_MON toggling
CHIP-LEVEL MERGED NETLIST TEST PASS
```

With the **hardened ICS55** netlist it must fail, and it does:

```
=== chip-level simulation (digital macro: route) ===
-- chip out of reset, running from the behavioural AFE --
FAIL  chip TOS default = 0xff (expect 0x64)
FAIL  chip Thyst default = 0xff (expect 0x4b)
FAIL  chip T=25.00 C  half-steps=-1 (expect 50)
FAIL  chip T=125.00 C  half-steps=-1 (expect 250)
FAIL  chip OS_INT = 1 at 125 C (expect 0)
PASS  chip T=0.00 C  half-steps=-1 (expect 0)
PASS  chip OS_INT released at 0 C
PASS  T2F_MON toggling
CHIP-LEVEL MERGED NETLIST TEST FAIL: 5 error(s)
```

Every register read returns `0xFF`: the slave never pulls SDA low, because
`sda_oe` is stuck at 0 in the hardened netlist. That is the documented
defect appearing at chip level, which also confirms the chip-level test
has real diagnostic power rather than passing vacuously. The two `PASS`
lines are the checks that do not depend on I2C (`0 C` reads `-1`, which
happens to be within the ±1 LSB tolerance of the expected `0`).

What this test does **not** cover:

* the real analog front-end: PTAT/CSRO behaviour, start-up, corners,
  mismatch — all replaced by the fitted behavioural model
* the real pads: ESD, level shifting, drive strength, leakage
* the real clock: `clkgen.v` is behavioural
* any parasitic, IR drop or coupling

## Clock accuracy: the constraint that dominates the system budget

The 10 ms measurement gate is *derived from the clock*, so the clock is
part of the temperature reference, not just digital housekeeping. A
relative clock error `e` scales every count and biases the reading:

```
raw_count  ~= f(T) * T_gate          f(25 C) ~= 610 kHz -> ~6100 counts
sensitivity ~= 15.6 counts per degC  (over -40..125 C)

temperature error ~= 6100 * e / 15.6 ~= 390 * e  [degC]

  e = 1 %    -> ~3.9 degC    (untuned on-chip RC oscillator)
  e = 0.1 %  -> ~0.39 degC
  e = 0.05 % -> ~0.20 degC
```

The analog front-end can otherwise deliver roughly ±0.5 °C, so a plain RC
oscillator would throw away most of the achievable accuracy. Options are
listed in `rtl/clkgen.v`; the cheapest that actually works is probably a
**ratiometric** scheme: count the T2F against a reference oscillator built
from the same devices, so supply and temperature drift of the timebase
largely cancel. That changes `temp_engine`, not just `clkgen`.

This is the single most important system-level finding of the chip
assembly exercise.

## Open items

| # | Item | Why it matters |
| --- | --- | --- |
| 1 | Resolve the process mismatch | nothing can be taped out until this is settled |
| 2 | Digital macro `sda_oe` defect | I2C does not answer; blocks all software bring-up |
| 3 | Clock accuracy / ratiometric gate | dominates the achievable temperature accuracy |
| 4 | CSRO layout + LVS + PEX | the analog front-end is schematic-only |
| 5 | Signal IO cells | no pad ring can be built; pads are placeholders |
| 6 | Hysteresis on `t2f_inbuf` | a slow, high-impedance input without hysteresis can double-edge |
| 7 | `u_afe` power-down behaviour | with `en=0` the CSRO output floats; needs a pull-down or gating with the digital domain |
| 8 | Calibration trim strategy | the table is compile-time; silicon spread needs a writable table or OTP |
| 9 | Analog/digital isolation plan | guard rings, separate supplies, `fout` routing away from switching nets |

## File map

| Path | Contents |
| --- | --- |
| `rtl/chip_top.v` | structural top: blocks, pads, supplies |
| `rtl/t2f_afe.v` | AFE macro, behavioural view + electrical notes |
| `rtl/t2f_inbuf.v` | T2F level conditioner, real ICS55 cells |
| `rtl/clkgen.v` | clock spec + clock-accuracy analysis |
| `rtl/por.v` | POR spec + requirement |
| `rtl/pad_signal.v` | abstract pad and ring models, with the library gap documented |
| `analog/t2f_afe.spice` | AFE analogue netlist wrapper (sky130), adds `en` |
| `sim/chip_tb.sv` | package-pin I2C read-back test |
| `sim/run_chip_sim.sh` | elaborate + run, `rtl` / `syn` / `route` targets |
| `chip_top.f` | filelist |
