// =====================================================================
// i2c_master_model.v -- bit-banging I2C master (for testbenches)
//
// Provides tasks: i2c_start, i2c_stop, i2c_write_byte (with ACK),
// i2c_read_byte (with master ACK/NACK).  Standard 100/400 kHz timing
// via parameter SCL_HALF (clk cycles per half SCL period).
//
// SPDX-License-Identifier: Apache-2.0
// =====================================================================
module i2c_master_model #(
    parameter integer SCL_HALF = 25   // clk cycles per half-period @ 400kHz/10MHz
)(
    inout wire scl,
    inout wire sda,
    input  wire clk
);

    reg scl_drv = 1'b1;   // open-drain: 1 = release
    reg sda_drv = 1'b1;
    assign scl = scl_drv ? 1'bz : 1'b0;
    assign sda = sda_drv ? 1'bz : 1'b0;

    integer half_cnt = 0;

    task automatic wait_half;
        begin
            repeat (SCL_HALF) @(posedge clk);
        end
    endtask

    task automatic i2c_start;
        begin
            sda_drv = 1'b1;
            scl_drv = 1'b1;
            wait_half;
            wait_half;
            sda_drv = 1'b0;          // SDA low while SCL high = START
            wait_half;
            scl_drv = 1'b0;
            wait_half;
        end
    endtask

    task automatic i2c_stop;
        begin
            sda_drv = 1'b0;
            scl_drv = 1'b0;
            wait_half;
            scl_drv = 1'b1;          // SCL high
            wait_half;
            sda_drv = 1'b1;          // SDA rises while SCL high = STOP
            wait_half;
        end
    endtask

    // Write 8 bits MSB first; returns 1 if slave ACKed
    task automatic i2c_write_byte;
        input [7:0] data;
        output ack;
        integer i;
        begin
            for (i = 7; i >= 0; i = i - 1) begin
                sda_drv = data[i];
                wait_half;              // SCL already low
                scl_drv = 1'b1;
                wait_half;
                scl_drv = 1'b0;
                wait_half;
            end
            // ACK bit
            sda_drv = 1'b1;             // release SDA
            wait_half;
            scl_drv = 1'b1;
            wait_half;
            ack = ~sda;                 // low = ACK
            scl_drv = 1'b0;
            wait_half;
        end
    endtask

    // Read 8 bits MSB first; drive master ACK (0) or NACK (1) after
    task automatic i2c_read_byte;
        output [7:0] data;
        input        master_ack;
        integer i;
        reg [7:0] d;
        begin
            sda_drv = 1'b1;             // release SDA
            d = 8'b0;
            for (i = 7; i >= 0; i = i - 1) begin
                wait_half;
                scl_drv = 1'b1;
                wait_half;
                d[i] = sda;
                scl_drv = 1'b0;
                wait_half;
            end
            data = d;
            sda_drv = master_ack;       // 0 = ACK, 1 = NACK
            wait_half;
            scl_drv = 1'b1;
            wait_half;
            scl_drv = 1'b0;
            wait_half;                  // let SCL settle low before
            sda_drv = 1'b1;             // releasing SDA (no false STOP)
            wait_half;
        end
    endtask

    // Combined helpers
    task automatic i2c_write_reg;
        input [6:0] addr;
        input [7:0] reg_ptr;
        input [7:0] data;
        output ack;
        reg a;
        begin
            i2c_start;
            i2c_write_byte({addr, 1'b0}, a);   // addr + W
            i2c_write_byte(reg_ptr, a);
            i2c_write_byte(data, ack);
            i2c_stop;
        end
    endtask

    task automatic i2c_read_regs;
        input  [6:0] addr;
        input  [7:0] reg_ptr;
        input  integer nbytes;
        output [255:0] data;   // up to 32 bytes
        reg a;
        reg [7:0] d;
        integer i;
        begin
            i2c_start;
            i2c_write_byte({addr, 1'b0}, a);   // addr + W (set pointer)
            i2c_write_byte(reg_ptr, a);
            i2c_start;                          // repeated START
            i2c_write_byte({addr, 1'b1}, a);   // addr + R
            for (i = 0; i < nbytes; i = i + 1) begin
                i2c_read_byte(d, (i == nbytes-1) ? 1'b1 : 1'b0);
                data[i*8 +: 8] = d;
            end
            i2c_stop;
        end
    endtask

endmodule
