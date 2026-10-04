# temp_sensor_chip — mpc-frame design

[中文](README.md)

This is the mpc-frame-adapted version of `temp-sensor-chip`. It brings the
chip's digital core onto `FrameTop`'s 66-bit bidirectional payload interface.

## Files

| File | Purpose |
| --- | --- |
| `rtl/TempSensorTop.sv` | Top-level module (fixed 5-port Frame contract) |
| `rtl/frame_bridge.sv` | Pad input sampling (`t2f_in` / `scl` / `sda`) |
| `rtl/temp_engine.v` | Piecewise-linear conversion engine (from chip RTL) |
| `rtl/temp_regs.v` | Register file (from chip RTL) |
| `rtl/i2c_slave.v` | I2C slave (from chip RTL) |
| `tests/TempSensorTopTb.sv` | Unit test (no FrameTop) |
| `tests/FrameTempSensorTopTb.sv` | Frame integration test |
| `design.json` | Build tool configuration |

## Pin Mapping

`design io_*[n] ↔ user_io[n + 7]` (the low 7 bits carry the design ID).

| Frame port | Chip signal | Direction | Notes |
| --- | --- | --- | --- |
| `clock` | `clk` | input | 10 MHz system clock |
| `reset` | — | input | **Active-high** reset (Frame contract) |
| `io_in[0]` | `t2f_in` | input | Temperature-to-frequency pulse train |
| `io_in[1]` | `scl` | input | I2C clock sample |
| `io_in[2]` | `sda` | input | I2C data sample (wired-OR bus) |
| `io_out[0]` | `os_int` | output (open-drain) | Overtemp alert: `oe=1` pulls low, `oe=0` releases |
| `io_out[3]` | `shutdown` | output (push-pull) | Shutdown state from the config register |
| `io_out[4]` | `heartbeat` | output (push-pull) | Activity indicator, toggles every cycle |

`io_out[1]`, `io_out[2]`, and everything from `io_out[5]` up stay high-Z.
SCL is only ever driven by the external master; the slave pulls SDA low
open-drain.

## Contract Details

* **Reset polarity**: Frame's `design_reset` is active-high
  (`reset | ~selection_valid | ~design_selected`). The chip RTL is active-low,
  so the top derives `wire rst_n = ~reset;` and feeds that to `temp_engine`,
  `temp_regs` and `i2c_slave`.
* **Single driver**: the whole payload bus is driven from one `always_comb`
  in the top level, and unused bits are explicitly released with `io_oe = 0`.
  `frame_bridge` only samples inputs and never drives outputs, so no payload
  bit has two drivers.
* **No `timescale`**: the design sources contain no `` `timescale ``. Neither
  do mpc-frame's own modules, so mixing them raises no `TIMESCALEMOD`.
* **Calibration**: `NSEC` / `BP_CNT` / `BP_T` / `GAIN` in `design.json` come
  straight from the chip's `tb/t2f_model_params.vh`, so temperature conversion
  matches the chip.

## Running Tests

```sh
make check DESIGN=designs/temp_sensor_chip
make trace DESIGN=designs/temp_sensor_chip
make wave  DESIGN=designs/temp_sensor_chip
```

`make check` runs lint, the unit test, and the Frame integration test in
order. The Frame test asks the build tool for a free ID and generates a
temporary registry under `build/`; the committed `designs/registry.json` is
never modified.
