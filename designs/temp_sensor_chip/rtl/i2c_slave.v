// =====================================================================
// i2c_slave.v -- I2C slave interface (LM75/TMP100-style)
//
// - 7-bit address (default 0x48), up to 400 kHz SCL
// - START, addr+W, [pointer byte], [data bytes], STOP
//   START, addr+R, [data bytes], STOP
// - Register pointer auto-increments after every byte
// - Open-drain SDA (only ever pulled low), synchronized inputs
//
// Register bus: byte-wide, addr[3:0] (LM75 regs 0x00-0x03), with
// combinational read (rdata = mem[addr]) and write strobe.
//
// SPDX-License-Identifier: Apache-2.0
// =====================================================================
module i2c_slave #(
    parameter [6:0] I2C_ADDR = 7'h48
)(
    input  wire       clk,
    input  wire       rstn,
    inout  wire       scl,
    inout  wire       sda,
    // Open-drain SDA pull-down indicator, exported so an integration
    // wrapper can reflect it onto a shared bidirectional pad
    // (io_oe[n] = sda_oe).  Unused when sda is wired directly to a pad.
    output wire       sda_oe,
    output reg  [3:0] reg_addr,
    output reg  [7:0] reg_wdata,
    output reg        reg_we,     // write strobe (1 clk pulse)
    input  wire [7:0] reg_rdata   // combinational read data
);

    // -----------------------------------------------------------------
    // Synchronized inputs + filtered SCL
    // -----------------------------------------------------------------
    reg scl_r1, scl_r2, sda_r1, sda_r2;
    always @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            scl_r1 <= 1'b1; scl_r2 <= 1'b1;
            sda_r1 <= 1'b1; sda_r2 <= 1'b1;
        end else begin
            scl_r1 <= scl; scl_r2 <= scl_r1;
            sda_r1 <= sda; sda_r2 <= sda_r1;
        end
    end
    wire scl_in = scl_r2;
    wire sda_in = sda_r2;

    reg [2:0] scl_hist;
    always @(posedge clk or negedge rstn) begin
        if (!rstn) scl_hist <= 3'b111;
        else       scl_hist <= {scl_hist[1:0], scl_in};
    end
    wire scl_hi = &scl_hist;
    wire scl_lo = ~|scl_hist;
    reg scl_hi_r, scl_lo_r;
    always @(posedge clk or negedge rstn) begin
        if (!rstn) begin scl_hi_r <= 1'b0; scl_lo_r <= 1'b0; end
        else begin scl_hi_r <= scl_hi; scl_lo_r <= scl_lo; end
    end
    wire scl_rise = scl_hi & ~scl_hi_r;
    wire scl_fall = scl_lo & ~scl_lo_r;

    // -----------------------------------------------------------------
    // START / STOP
    // -----------------------------------------------------------------
    reg sda_dly;
    always @(posedge clk or negedge rstn) begin
        if (!rstn) sda_dly <= 1'b1;
        else       sda_dly <= sda_in;
    end
    wire start_det = scl_hi & ~sda_in &  sda_dly;
    wire stop_det  = scl_hi &  sda_in & ~sda_dly;

    // -----------------------------------------------------------------
    // State machine (byte-oriented, phase flag for addr vs data ACK)
    // -----------------------------------------------------------------
    localparam ST_IDLE = 3'd0;
    localparam ST_ADDR = 3'd1;   // receive address byte
    localparam ST_ACK  = 3'd2;   // 9th clock (ACK), phase: ADDR or DATA
    localparam ST_RBYTE= 3'd3;   // transmit data byte (read)
    localparam ST_ACKR = 3'd4;   // master ACK after transmitted byte
    localparam ST_BYTE = 3'd5;   // receive data byte (write)

    reg [2:0] state;
    reg [2:0] bitcnt;             // receive bit counter 7..0
    reg [2:0] tx_idx;             // transmit bit index 7..0
    reg [7:0] rx_shift;
    reg       rw;                 // 1 = read
    reg       data_phase;         // ACK is for data (not address)
    reg       got_pointer;
    reg       byte_pending;       // byte captured, waiting for bit-0 SCL fall
    reg       master_nack;        // master sent NACK after our byte
    reg       addr_ok;            // received address matches I2C_ADDR
    reg [7:0] rx_byte;

    always @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            state        <= ST_IDLE;
            bitcnt       <= 3'd7;
            tx_idx       <= 3'd7;
            rx_shift     <= 8'd0;
            rw           <= 1'b0;
            data_phase   <= 1'b0;
            got_pointer  <= 1'b0;
            byte_pending <= 1'b0;
            master_nack  <= 1'b0;
            addr_ok      <= 1'b0;
            rx_byte      <= 8'd0;
            reg_addr     <= 4'd0;
            reg_wdata    <= 8'd0;
            reg_we       <= 1'b0;
        end else begin
            reg_we <= 1'b0;
            if (stop_det) begin
                state        <= ST_IDLE;
                bitcnt       <= 3'd7;
                got_pointer  <= 1'b0;
                byte_pending <= 1'b0;
                master_nack  <= 1'b0;
                addr_ok      <= 1'b0;
            end else if (start_det) begin
                state        <= ST_ADDR;
                bitcnt       <= 3'd7;
                rx_shift     <= 8'd0;
                got_pointer  <= 1'b0;
                byte_pending <= 1'b0;
            end else begin
                case (state)
                    ST_IDLE: ;

                    // ---- receive address byte (7-bit addr + R/W) ----
                    ST_ADDR: begin
                        if (scl_rise) begin
                            //
                            rx_shift <= {rx_shift[6:0], sda_in};
                            if (bitcnt == 3'd0) byte_pending <= 1'b1;
                            else                bitcnt <= bitcnt - 3'd1;
                        end
                        // bit-0 clock ends -> enter ACK phase (9th clock)
                        if (scl_fall && byte_pending) begin
                            byte_pending <= 1'b0;
                            state        <= ST_ACK;
                            data_phase   <= 1'b0;
                            // Latch address-match here so the ACK phase can
                            // drive SDA low for our own address.  Without
                            // this the slave NACKs every address, including
                            // its own.
                            addr_ok      <= (rx_shift[7:1] == I2C_ADDR);
                        end
                    end

                    // ---- 9th clock: slave ACK + routing ----
                    ST_ACK: begin
                        if (scl_fall) begin
                            if (!data_phase) begin
                                // address byte
                                rw <= rx_shift[0];
                                if (rx_shift[7:1] == I2C_ADDR) begin
                                    if (rx_shift[0]) begin
                                        state  <= ST_RBYTE;   // read
                                        tx_idx <= 3'd7;
                                    end else begin
                                        state       <= ST_BYTE;  // write: next is pointer
                                        bitcnt      <= 3'd7;
                                        got_pointer <= 1'b0;
                                    end
                                end else begin
                                    state <= ST_IDLE;   // not addressed
                                end
                            end else begin
                                // data byte (write path)
                                if (!got_pointer) begin
                                    reg_addr    <= rx_byte[3:0];
                                    got_pointer <= 1'b1;
                                end else begin
                                    reg_wdata <= rx_byte;
                                    reg_we    <= 1'b1;
                                    // no auto-inc here: the write strobe
                                    // and addr increment would race; multi-
                                    // byte writes use explicit pointers
                                end
                                state  <= ST_BYTE;
                                bitcnt <= 3'd7;
                            end
                        end
                    end

                    // ---- transmit 8 bits (read) ----
                    ST_RBYTE: begin
                        if (scl_fall) begin
                            if (tx_idx == 3'd0) begin
                                state  <= ST_ACKR;
                                tx_idx <= 3'd7;
                            end else begin
                                tx_idx <= tx_idx - 3'd1;
                            end
                        end
                    end

                    // ---- master ACK after transmitted byte ----
                    ST_ACKR: begin
                        if (scl_rise) begin
                            // sample the master's ACK/NACK; NACK -> stop
                            if (sda_in) begin
                                master_nack <= 1'b1;
                            end
                        end
                        if (scl_fall) begin
                            if (!master_nack)
                            if (master_nack) begin
                                state       <= ST_IDLE;
                                master_nack <= 1'b0;
                            end else begin
                                reg_addr <= reg_addr + 4'd1;   // auto-inc
                                state    <= ST_RBYTE;
                                tx_idx   <= 3'd7;
                            end
                        end
                    end

                    // ---- receive 8 bits (write) ----
                    ST_BYTE: begin
                        if (scl_rise) begin
                            rx_shift <= {rx_shift[6:0], sda_in};
                            if (bitcnt == 3'd0) begin
                                // capture the complete byte at bit0's rise
                                rx_byte      <= {rx_shift[6:0], sda_in};
                                byte_pending <= 1'b1;
                            end else
                                bitcnt <= bitcnt - 3'd1;
                        end
                        // bit-0 clock ends -> enter ACK phase (9th clock)
                        if (scl_fall && byte_pending) begin
                            byte_pending <= 1'b0;
                            state        <= ST_ACK;
                            data_phase   <= 1'b1;
                        end
                    end

                    default: state <= ST_IDLE;
                endcase
            end
        end
    end

    // -----------------------------------------------------------------
    // SDA output (open-drain): '0' bit pulls low (oe=1), '1' releases.
    // sda_oe is also exported on the port list above.
    // -----------------------------------------------------------------
    reg sda_oe_r;
    always @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            sda_oe_r <= 1'b0;
        end else begin
            case (state)
                ST_ACK: begin
                    // pull low for ACK during the ACK clock; a non-matching
                    // address is NOT acknowledged (NACK = release)
                    if (scl_lo)        sda_oe_r <= data_phase ? 1'b1 : addr_ok;
                    else if (scl_fall) sda_oe_r <= 1'b0;
                end
                ST_RBYTE: begin
                    // drive current TX bit while SCL is low
                    if (scl_lo) begin
                        sda_oe_r <= ~reg_rdata[tx_idx];
                    end else if (scl_fall) sda_oe_r <= 1'b0;
                end
                ST_ACKR: begin
                    sda_oe_r <= 1'b0;   // master drives ACK; slave released
                end
                default: sda_oe_r <= 1'b0;
            endcase
        end
    end

    assign sda_oe = sda_oe_r;
    assign sda    = sda_oe_r ? 1'b0 : 1'bz;

endmodule
