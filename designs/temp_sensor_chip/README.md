# temp_sensor_chip (温度传感器芯片) — mpc-frame 设计

[English](README.en.md)

这是 `temp-sensor-chip` 经 mpc-frame 适配的版本，把芯片的数字部分接入
`FrameTop` 的 66 位双向 payload 接口。

## 文件

| 文件 | 用途 |
| --- | --- |
| `rtl/TempSensorTop.sv` | 顶层模块（固定 5 端口 Frame 契约） |
| `rtl/frame_bridge.sv` | 焊盘输入采样（`t2f_in` / `scl` / `sda`） |
| `rtl/temp_engine.v` | 分段线性温度转换引擎（来自芯片 RTL） |
| `rtl/temp_regs.v` | 寄存器文件（来自芯片 RTL） |
| `rtl/i2c_slave.v` | I2C 从机（来自芯片 RTL） |
| `tests/TempSensorTopTb.sv` | 单元测试（不经过 FrameTop） |
| `tests/FrameTempSensorTopTb.sv` | Frame 集成测试 |
| `design.json` | 构建工具配置 |

## 接口映射

payload 位映射为 `设计 io_*[n] ↔ user_io[n + 7]`（低 7 位是设计 ID）。

| Frame 端口 | 芯片信号 | 方向 | 说明 |
| --- | --- | --- | --- |
| `clock` | `clk` | 输入 | 10 MHz 系统时钟 |
| `reset` | — | 输入 | **高有效**复位（Frame 契约） |
| `io_in[0]` | `t2f_in` | 输入 | 温度-频率脉冲输入 |
| `io_in[1]` | `scl` | 输入 | I2C 时钟采样 |
| `io_in[2]` | `sda` | 输入 | I2C 数据采样（线或总线） |
| `io_out[0]` | `os_int` | 输出（开漏） | 过温告警：`oe=1` 拉低，`oe=0` 释放 |
| `io_out[3]` | `shutdown` | 输出（推挽） | 关机状态，来自配置寄存器 |
| `io_out[4]` | `heartbeat` | 输出（推挽） | 活动指示，每周期翻转 |

`io_out[1]`、`io_out[2]` 及 `io_out[5]` 以上全部保持高阻：SCL 只由外部
主设备驱动，SDA 由从机开漏拉低。

## 契约要点

* **复位极性**：Frame 的 `design_reset` 是高有效
  （`reset | ~selection_valid | ~design_selected`）。芯片内部逻辑原本是低
  有效，顶层用 `wire rst_n = ~reset;` 转换后再送给 `temp_engine`、
  `temp_regs`、`i2c_slave`。
* **单一驱动**：整条 payload 总线只在顶层的一个 `always_comb` 里驱动，
  未使用的位显式置 `io_oe = 0`。`frame_bridge` 只采样输入，不再驱动输出，
  避免多驱动冲突。
* **无 `timescale`**：设计源码不含 `` `timescale ``。mpc-frame 自身模块也没有，
  两者混编时不会触发 `TIMESCALEMOD`。
* **标定参数**：`design.json` 的 `NSEC` / `BP_CNT` / `BP_T` / `GAIN` 直接取自
  芯片的 `tb/t2f_model_params.vh`，保证温度换算与芯片一致。

## 运行测试

```sh
make check DESIGN=designs/temp_sensor_chip
make trace DESIGN=designs/temp_sensor_chip
make wave  DESIGN=designs/temp_sensor_chip
```

`make check` 依次执行 lint、单元测试和 Frame 集成测试。Frame 测试由构建
工具自动分配空闲 ID 并在 `build/` 下生成临时 registry，不修改正式
`designs/registry.json`。
