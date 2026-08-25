`timescale 1ns/1ps
// =====================================================================
// temp_regs.v -- register file (LM75-inspired pointer map, simplified
// for a clean read/write of every register):
//
//   addr 0x00 : temperature MSB (read-only, 9-bit temp upper byte)
//   addr 0x01 : temperature LSB (read-only, bit7 = 0.5 C bit)
//   addr 0x02 : Configuration (R/W)
//   addr 0x03 : Thyst hysteresis threshold (R/W)
//   addr 0x04 : TOS overtemperature threshold (R/W)
//
// Combinational read (rdata = f(addr)); write strobe from i2c_slave.
//
// SPDX-License-Identifier: Apache-2.0
// =====================================================================
module temp_regs (
    input  wire       clk,
    input  wire       rstn,
    input  wire [3:0] addr,
    input  wire [7:0] wdata,
    input  wire       we,
    output wire [7:0] rdata,
    // live temperature value from the measurement engine
    input  wire [7:0] temp_msb,
    input  wire [7:0] temp_lsb,
    // configuration outputs
    output reg        cfg_shutdown,
    output reg        cfg_comparator,   // 1 = comparator mode, 0 = interrupt
    output reg [1:0]  cfg_resolution,
    output reg [7:0]  thyst,
    output reg [7:0]  tos
);

    reg [7:0] cfg;   // full configuration byte (read-back value)

    always @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            cfg            <= 8'h00;
            cfg_shutdown   <= 1'b0;
            cfg_comparator <= 1'b0;
            cfg_resolution <= 2'b00;
            thyst          <= 8'h4b;   // +75 C in 0.5 C units (0x4B*2=150)
            tos            <= 8'h64;   // +100 C (0x64*2=200)
        end else if (we) begin
            case (addr)
                4'h2: begin
                    cfg <= wdata;
                    cfg_shutdown   <= wdata[7];
                    cfg_comparator <= wdata[6];
                    cfg_resolution <= wdata[1:0];
                end
                4'h3: thyst <= wdata;
                4'h4: tos   <= wdata;
                default: ;
            endcase
        end
    end

    assign rdata = (addr == 4'h0) ? temp_msb :
                   (addr == 4'h1) ? temp_lsb :
                   (addr == 4'h2) ? cfg :
                   (addr == 4'h3) ? thyst :
                   (addr == 4'h4) ? tos : 8'h00;

endmodule
