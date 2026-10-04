# temp_sensor_chip (温度传感器芯片) — mpc-frame 设计

[English](README.en.md)

这是 `temp-sensor-chip` 经 mpc-frame 适配的版本，把芯片的**完整数字通路**接入
`FrameTop` 的 66 位双向 payload 接口，并带有端到端的闭环测试。

## 文件

| 文件 | 用途 |
| --- | --- |
| `rtl/TempSensorTop.sv` | 顶层模块（固定 5 端口 Frame 契约） |
| `rtl/frame_bridge.sv` | 焊盘输入采样（`t2f_in` / `scl` / `sda`） |
| `rtl/temp_engine.v` | 分段线性温度转换引擎（来自芯片 RTL） |
| `rtl/temp_regs.v` | 寄存器文件（来自芯片 RTL） |
| `rtl/i2c_slave.v` | I2C 从机（来自芯片 RTL，见下方修正） |
| `tests/t2f_model.v` | 模拟前端行为模型（ngspice 标定曲线） |
| `tests/i2c_master_model.v` | I2C 主机 BFM |
| `tests/include/t2f_model_params.vh` | 自动生成的标定参数 |
| `tests/TempSensorTopTb.sv` | 单元测试（不经过 FrameTop） |
| `tests/FrameTempSensorTopTb.sv` | Frame 集成测试 |
| `design.json` | 构建工具配置 |

## 接口映射

payload 位映射为 `设计 io_*[n] ↔ user_io[n + 7]`（低 7 位是设计 ID）。

| bit | user_io | 方向 | 信号 | 说明 |
| --- | --- | --- | --- | --- |
| 0 | 7 | 输入 | `t2f_in` | 温度-频率脉冲，外部推挽驱动 |
| 1 | 8 | 输入 | `scl` | I2C 时钟，从机不做时钟拉伸 |
| 2 | 9 | 双向 | `sda` | I2C 数据，线或开漏 |
| 3 | 10 | 输出 | `os_int` | 过温告警，开漏（`oe=1` 拉低） |
| 4 | 11 | 输出 | `shutdown` | 测量门控，推挽 |
| 5 | 12 | 输出 | `heartbeat` | 活动指示，推挽，每周期翻转 |
| 6+ | 13+ | — | — | 全部释放 |

**输入与输出必须占用不同的 payload 位**：外部模拟前端以推挽方式驱动 `t2f_in`，
若与开漏的 `os_int` 共用一位，告警拉低时会与脉冲源直接冲突。

## 契约要点

* **复位极性**：Frame 的 `design_reset` 是高有效
  （`reset | ~selection_valid | ~design_selected`）。芯片内部逻辑原本低有效，
  顶层用 `wire rst_n = ~reset;` 转换后再送给各子模块。
* **单一驱动**：整条 payload 总线只在顶层的一个 `always_comb` 里驱动，未使用
  的位显式 `io_oe = 0`。
* **SDA 线或**：从机的拉低方向经 `sda_oe` 导出并反映到 `io_oe[2]`，总线值
  `sda_bus = sda_oe ? 0 : sda_i` 在片内先解析一次，避免从机采样到悬空节点。
* **10 MHz 约束**：`GATE_CYCLES`(100000) 与标定表都按 10 MHz / 10 ms 门控窗口
  标定，测试台时钟必须保持 10 MHz（`CLK_HALF = 50ns`）。改频率会按比例缩放
  脉冲计数并使标定失效。
* **标定来源**：`tests/include/t2f_model_params.vh` 由 `scripts/gen_t2f_model.py`
  从 ngspice 实测曲线生成；单元测试把它同时喂给 `t2f_model` 和被测设计，保证
  模型与查找表同源。
* **无 `timescale`**：设计源码不含 `` `timescale ``，与 mpc-frame 自身模块一致，
  混编不会触发 `TIMESCALEMOD`。

## 对芯片 RTL 的两处修正

`rtl/i2c_slave.v` 相对芯片原版有两处改动，都是为了让设计在共享双向焊盘上真正
可用：

1. **导出 `sda_oe`**（新增输出端口）。原版把 `sda_oe` 藏在模块内部，顶层无法
   得知从机何时拉低 SDA，也就无法驱动 `io_oe[2]` 去拉低共享焊盘。
2. **修正地址应答**。原版 `addr_ok` 只被赋 0、从未置 1，从机会对**包括自己地址
   在内**的所有地址回 NACK。芯片自带 TB 只验证了"错地址不 ACK"，没有验证
   "对地址应 ACK"，所以漏掉了这个缺陷。现在在地址字节末沿锁存
   `addr_ok <= (rx_shift[7:1] == I2C_ADDR)`。

## 测试流程

```sh
make check DESIGN=designs/temp_sensor_chip
make trace DESIGN=designs/temp_sensor_chip
make wave  DESIGN=designs/temp_sensor_chip
```

`make check` 依次执行 lint、单元测试和 Frame 集成测试，全流程闭环：

```
t2f_model（模拟前端行为模型）→ t2f 焊盘 → 设计
  → temp_engine（10 ms 门控计数 + 分段线性查表）
  → temp_regs → i2c_slave → 焊盘 → i2c_master_model 读回
```

**单元测试**（直接驱动 payload 焊盘）覆盖：

| 检查 | 结果 |
| --- | --- |
| 复位时 payload 总线状态 | PASS |
| 25 / −40 / 0 / 85 / 125 °C 温度读回（±1 LSB） | PASS |
| TOS / Thyst 默认值读回（0x64 / 0x4B） | PASS |
| TOS / Thyst 写入后读回 | PASS |
| 本机地址 0x48 被 ACK、外来地址 0x50 被 NACK | PASS |
| 温度超过 TOS 时 `os_int` 拉低 | PASS |

85 °C 读回 169（期望 170），误差 +0.5 °C，在 ±1 LSB 容差内，属分段线性化的
正常取整误差。

**Frame 集成测试**（全部经过 `user_io` / FrameTop）覆盖：设计 ID 选择、
`shutdown` 推挽输出、`heartbeat` 翻转、以及 25 / 125 / 0 °C 经 I2C 的闭环
温度读回和 `os_int` 在 Frame 焊盘上的置位与释放。

> 注意：`make check` 用 Verilator `--binary`（二态）编译，`1'bz` 字面量会退化成
> `1'b0`，因此测试里不能用 `=== 1'bz` 判断高阻；Frame 测试改为检查焊盘是否为
> 干净的 0/1 以及是否翻转。

## 运行环境

需要 Verilator 5.050（启动时会校验版本）。Frame 测试由构建工具自动分配空闲 ID
并在 `build/` 下生成临时 registry，不修改正式 `designs/registry.json`。
