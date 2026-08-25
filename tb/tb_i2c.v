// =====================================================================
// tb_i2c.v -- I2C slave protocol tests
//
//  1. Write configuration register (pointer 0x01 -> config)
//  2. Read it back (should equal written value)
//  3. Verify ACK behavior + wrong-address NACK
//  4. Write/read Thyst (0x02) and TOS (0x03)
//
// SPDX-License-Identifier: Apache-2.0
// =====================================================================
`timescale 1ns/1ps
`include "t2f_model_params.vh"

module tb_i2c;

    reg        clk = 0;
    reg        rstn = 0;
    wire       scl, sda;
    pullup(scl);
    pullup(sda);
    wire       os_int;

    always #50 clk = ~clk;   // 10 MHz

    temp_sensor_top #(
        .I2C_ADDR    (7'h48),
        .GATE_CYCLES (32'd1000),  // short gate for fast tests
        .NSEC        (`T2F_NSEC),
        .BP_CNT      (`T2F_BP_CNT),
        .BP_T        (`T2F_BP_T),
        .GAIN        (`T2F_GAIN)
    ) dut (
        .clk   (clk),
        .rstn  (rstn),
        .t2f_in(1'b0),
        .scl   (scl),
        .sda   (sda),
        .os_int(os_int)
    );

    i2c_master_model #(
        .SCL_HALF (25)          // 400 kHz @ 10 MHz
    ) master (
        .scl (scl),
        .sda (sda),
        .clk (clk)
    );

    integer errors = 0;
    reg ack;
    reg [7:0] rdata;
    reg [255:0] rd;

    task check;
        input [255:0] got;
        input [255:0] exp;
        input [8*40:0] name;
        begin
            if (got !== exp) begin
                errors = errors + 1;
                $display("FAIL %0s: got %h exp %h", name, got, exp);
            end else begin
                $display("PASS %0s", name);
            end
        end
    endtask


    // ---- protocol monitor (debug) ----
    reg [2:0] prev_state = 3'd7;
    reg [7:0] prev_rxbyte = 8'hff;
    always @(posedge clk) begin
        if (dut.u_i2c.reg_we)
            $display("t=%0t [WRITE] addr=%0h data=%02h", $time, dut.u_i2c.reg_addr, dut.u_i2c.reg_wdata);
        if (dut.u_i2c.got_pointer && dut.u_i2c.rx_byte != prev_rxbyte) begin
            $display("t=%0t [POINTER] = %0h", $time, dut.u_i2c.rx_byte);
            prev_rxbyte = dut.u_i2c.rx_byte;
        end
        if (dut.u_i2c.state !== prev_state) begin
            $display("t=%0t state=%0d->%0d scl=%b sda=%b oe=%b addr=%0h", $time,
                     prev_state, dut.u_i2c.state, scl, sda,
                     dut.u_i2c.sda_oe, dut.u_i2c.reg_addr);
            prev_state = dut.u_i2c.state;
        end
    end
    initial begin
        $dumpfile("tb_i2c.vcd");
        $dumpvars(0, tb_i2c);
        repeat (5) @(posedge clk);
        rstn = 1;
        repeat (10) @(posedge clk);

        // ---- Test 1: write config 0xA4 (shutdown=1, comparator=1, res=00)
        master.i2c_write_reg(7'h48, 8'h02, 8'hA4, ack);
        check({8'd0, ack}, {8'd0, 8'h01}, "write config ACK");
        // read back config
        master.i2c_read_regs(7'h48, 8'h02, 1, rd);
        check(rd[7:0], 8'hA4, "read back config");

        // ---- Test 2: write Thyst = 0x4B, TOS = 0x64, read back
        master.i2c_write_reg(7'h48, 8'h03, 8'h4B, ack);
        master.i2c_write_reg(7'h48, 8'h04, 8'h64, ack);
        master.i2c_read_regs(7'h48, 8'h03, 2, rd);
        check(rd[7:0],  8'h4B, "read Thyst");
        check(rd[15:8], 8'h64, "read TOS (auto-increment)");

        // ---- Test 3: wrong address -> no ACK on address
        master.i2c_start;
        master.i2c_write_byte({7'h50, 1'b0}, ack);
        check({8'd0, ack}, 8'h00, "wrong addr no ACK");
        master.i2c_stop;

        // ---- Test 4: temp register read.  With t2f_in=0 the engine's
        // raw count is 0 -> calibration saturates to -110 C = 0xC9
        // (9-bit two's complement 0b110010010 -> msb 0xC9, lsb bit7 0).
        master.i2c_read_regs(7'h48, 8'h00, 2, rd);
        check(rd[15:0], 16'h00C9, "temp regs saturation at raw=0");

        if (errors == 0)
            $display("== ALL I2C TESTS PASSED ==");
        else
            $display("== %0d I2C TEST(S) FAILED ==", errors);
        $finish;
    end

endmodule
