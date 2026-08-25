`timescale 1ns/1ps
// =====================================================================
// temp_sensor_top.v -- smart temperature sensor chip (top level)
//
//   - Analog front end (off-chip): PTAT + T2F oscillator -> t2f_in
//   - Digital core: gate counter + calibration (temp_engine),
//     LM75-style register file (temp_regs), I2C slave (i2c_slave)
//   - os_int: overtemperature alert (comparator/interrupt mode)
//
// Pin list (chip-level):
//   clk   : system clock (e.g. 10 MHz; also the measurement timebase)
//   rstn  : active-low reset
//   t2f_in: temperature-to-frequency input from the analog front end
//   scl, sda : I2C bus
//   os_int: open-drain alert output
//
// SPDX-License-Identifier: Apache-2.0
// =====================================================================
module temp_sensor_top #(
    parameter [6:0]  I2C_ADDR = 7'h48,
    parameter [31:0] GATE_CYCLES = 32'd100000,
    // piecewise-linear calibration (see scripts/gen_t2f_model.py)
    parameter integer NSEC = 9,
    parameter [NSEC*16-1:0] BP_CNT = 288'h000000000000000000000000000000000000000000000000000000000000000000000000,
    parameter [NSEC*16-1:0] BP_T   = 160'h0000000000000000000000000000000000000000,
    parameter [NSEC*12-1:0] GAIN   = 108'h000000000000000000000000000
)(
    input  wire clk,
    input  wire rstn,
    input  wire t2f_in,
    inout  wire scl,
    inout  wire sda,
    output wire os_int
);

    wire [7:0] temp_msb, temp_lsb;
    wire [3:0] reg_addr;
    wire [7:0] reg_wdata, reg_rdata;
    wire       reg_we;
    wire       engine_done;

    // temperature thresholds for the alert comparator
    wire [7:0] thyst, tos;
    wire       cfg_shutdown, cfg_comparator;

    temp_engine #(
        .GATE_CYCLES (GATE_CYCLES),
        .NSEC        (NSEC),
        .BP_CNT      (BP_CNT),
        .BP_T        (BP_T),
        .GAIN        (GAIN)
    ) u_engine (
        .clk      (clk),
        .rstn     (rstn),
        .t2f_in   (t2f_in),
        .shutdown (cfg_shutdown),
        .temp_msb (temp_msb),
        .temp_lsb (temp_lsb),
        .done     (engine_done)
    );

    temp_regs u_regs (
        .clk           (clk),
        .rstn          (rstn),
        .addr          (reg_addr),
        .wdata         (reg_wdata),
        .we            (reg_we),
        .rdata         (reg_rdata),
        .temp_msb      (temp_msb),
        .temp_lsb      (temp_lsb),
        .cfg_shutdown  (cfg_shutdown),
        .cfg_comparator(cfg_comparator),
        .cfg_resolution(),
        .thyst         (thyst),
        .tos           (tos)
    );

    i2c_slave #(
        .I2C_ADDR (I2C_ADDR)
    ) u_i2c (
        .clk       (clk),
        .rstn      (rstn),
        .scl       (scl),
        .sda       (sda),
        .reg_addr  (reg_addr),
        .reg_wdata (reg_wdata),
        .reg_we    (reg_we),
        .reg_rdata (reg_rdata)
    );

    // -----------------------------------------------------------------
    // Alert output: compare measured temp against TOS/Thyst
    // 9-bit comparison on the half-step value (temp_msb, temp_lsb[7]).
    // Comparator mode: os low while T >= TOS, high once T < Thyst.
    // Interrupt mode: latched low on T >= TOS until cleared (config write
    // or address match) -- simplified to a level for this demo.
    // -----------------------------------------------------------------
    wire [8:0] temp_val  = {temp_msb, temp_lsb[7]};
    wire [8:0] tos_val   = {tos, 1'b0};
    wire [8:0] thyst_val = {thyst, 1'b0};

    reg os_state;
    always @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            os_state <= 1'b1;   // inactive (open-drain released)
        end else if (engine_done) begin
            if (temp_val >= tos_val)
                os_state <= 1'b0;
            else if (temp_val < thyst_val)
                os_state <= 1'b1;
            // between Thyst and TOS: keep previous state (hysteresis)
        end
    end

    // open-drain alert
    assign os_int = os_state ? 1'bz : 1'b0;

endmodule
