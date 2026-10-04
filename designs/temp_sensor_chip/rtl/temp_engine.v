/* verilator lint_off WIDTHEXPAND */
/* verilator lint_off SELRANGE */
// =====================================================================
// temp_engine.v -- temperature measurement engine (T2F counting)
//
// Counts T2F oscillator pulses during a gate window derived from `clk`,
// then converts the raw count to a 9-bit temperature in 0.5 C units
// (two's complement, LM75-style) using PIECEWISE-LINEAR calibration:
//
//     find segment i : BP_CNT[i] <= raw < BP_CNT[i+1]
//     temp_half = BP_T[i] + ((raw - BP_CNT[i]) * GAIN[i]) >> SHIFT
//
// The breakpoints come from the ngspice characterization
// (scripts/gen_t2f_model.py -> tb/t2f_model_params.vh).  Piecewise
// linearity keeps the readout error < ~1 C across the full range even
// though f(T) is not perfectly linear.
//
// SPDX-License-Identifier: Apache-2.0
// =====================================================================
module temp_engine #(
    parameter [31:0] GATE_CYCLES = 32'd100000,   // 10 ms @ 10 MHz
    parameter integer NSEC = 10,                  // breakpoints
    // packed breakpoints: count[i] (16-bit), temp[i] (9-bit signed half-steps)
    parameter [NSEC*16-1:0] BP_CNT = 320'h000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000,
    parameter [NSEC*16-1:0] BP_T   = 160'h000000000000000000000000000000000000000000,
    // per-segment gains (Q8): GAIN[i] = (T[i+1]-T[i])*256/(C[i+1]-C[i])
    parameter [NSEC*12-1:0] GAIN   = 120'h00000000000000000000000000000000,
    parameter [7:0]         SHIFT  = 8'd8,
    parameter               USE_SHUTDOWN = 1
)(
    input  wire       clk,
    input  wire       rstn,
    input  wire       t2f_in,     // temperature-to-frequency pulse train
    input  wire       shutdown,   // 1 = halt measurement
    output reg  [7:0] temp_msb,   // 9-bit temp, upper 8 bits
    output reg  [7:0] temp_lsb,   // bit7 = 0.5 C bit, lower bits 0
    output reg        done        // measurement complete pulse
);

    // -----------------------------------------------------------------
    // Gate generation
    // -----------------------------------------------------------------
    reg [31:0] gate_cnt;
    reg        gate;
    wire       gate_done = (gate_cnt == GATE_CYCLES - 1);

    always @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            gate_cnt <= 32'd0;
            gate     <= 1'b0;
        end else if (shutdown && USE_SHUTDOWN) begin
            gate_cnt <= 32'd0;
            gate     <= 1'b0;
        end else begin
            if (gate_done)
                gate_cnt <= 32'd0;          // re-arm the gate window
            else
                gate_cnt <= gate_cnt + 32'd1;
            gate     <= ~gate_done;
        end
    end

    // -----------------------------------------------------------------
    // T2F pulse counting (rising edges)
    // -----------------------------------------------------------------
    reg        t2f_d;
    reg [15:0] raw_cnt;
    always @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            t2f_d   <= 1'b0;
            raw_cnt <= 16'd0;
        end else begin
            t2f_d <= t2f_in;
            if (!gate)
                raw_cnt <= 16'd0;
            else if (t2f_in & ~t2f_d)
                raw_cnt <= raw_cnt + 16'd1;
        end
    end

    // -----------------------------------------------------------------
    // Latch count at end of gate
    // -----------------------------------------------------------------
    reg [15:0] latched_cnt;
    reg        latch_done;
    always @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            latched_cnt <= 16'd0;
            latch_done  <= 1'b0;
        end else if (gate_done) begin
            latched_cnt <= raw_cnt;
            latch_done  <= 1'b1;
        end else begin
            latch_done  <= 1'b0;
        end
    end

    // -----------------------------------------------------------------
    // Piecewise-linear conversion (packed-parameter part-selects so the
    // logic is fully synthesizable and iverilog-safe)
    // -----------------------------------------------------------------
    // case-based lookup functions (iverilog-safe, synthesizable)
    function [15:0] get_cnt;
        input [3:0] i;
        begin
            case (i)
                4'd0: get_cnt = BP_CNT[15:0];
                4'd1: get_cnt = BP_CNT[31:16];
                4'd2: get_cnt = BP_CNT[47:32];
                4'd3: get_cnt = BP_CNT[63:48];
                4'd4: get_cnt = BP_CNT[79:64];
                4'd5: get_cnt = BP_CNT[95:80];
                4'd6: get_cnt = BP_CNT[111:96];
                4'd7: get_cnt = BP_CNT[127:112];
                4'd8: get_cnt = BP_CNT[143:128];
                4'd9: get_cnt = BP_CNT[159:144];
                default: get_cnt = 16'd0;
            endcase
        end
    endfunction
    function signed [8:0] get_temp;
        input [3:0] i;
        begin
            case (i)
                4'd0: get_temp = $signed(BP_T[8:0]);
                4'd1: get_temp = $signed(BP_T[24:16]);
                4'd2: get_temp = $signed(BP_T[40:32]);
                4'd3: get_temp = $signed(BP_T[56:48]);
                4'd4: get_temp = $signed(BP_T[72:64]);
                4'd5: get_temp = $signed(BP_T[88:80]);
                4'd6: get_temp = $signed(BP_T[104:96]);
                4'd7: get_temp = $signed(BP_T[120:112]);
                4'd8: get_temp = $signed(BP_T[136:128]);
                4'd9: get_temp = $signed(BP_T[152:144]);
                default: get_temp = 9'sd0;
            endcase
        end
    endfunction
    function [11:0] get_gain;
        input [3:0] i;
        begin
            case (i)
                4'd0: get_gain = GAIN[11:0];
                4'd1: get_gain = GAIN[23:12];
                4'd2: get_gain = GAIN[35:24];
                4'd3: get_gain = GAIN[47:36];
                4'd4: get_gain = GAIN[59:48];
                4'd5: get_gain = GAIN[71:60];
                4'd6: get_gain = GAIN[83:72];
                4'd7: get_gain = GAIN[95:84];
                4'd8: get_gain = GAIN[107:96];
                default: get_gain = 12'd0;
            endcase
        end
    endfunction

    // find segment: index of the last breakpoint <= raw
    reg [3:0] seg;
    integer s;
    always @* begin
        seg = 4'd0;
        for (s = NSEC-1; s >= 0; s = s - 1) begin
            if (latched_cnt >= get_cnt(s[3:0])) begin
                seg = s[3:0];
                s = -1;   // stop at the highest matching breakpoint
            end
        end
    end

    // breakpoint values for the selected segment
    wire [15:0] c_seg   = get_cnt(seg);
    wire signed [8:0] t_seg = get_temp(seg);
    wire [11:0] g_seg   = (seg == NSEC-1) ? 12'd0 : get_gain(seg[3:0]);

    // interpolate; clamp the delta for counts below the first breakpoint
    wire below_range = (latched_cnt < get_cnt(4'd0));
    wire [15:0] dcount = (latched_cnt >= c_seg) ? latched_cnt - c_seg : 16'd0;
    wire [23:0] prod   = dcount * g_seg;
    /* verilator lint_off WIDTHTRUNC */
    wire signed [31:0] t_half = $signed(t_seg)
                               + $signed({23'b0, prod[23:8]});
    /* verilator lint_on WIDTHTRUNC */

    // saturate to [-110, 250] half-steps (-55..125 C); below the
    // calibrated range reads -55 C (0xC9)
    wire signed [32:0] t_sat = below_range ? -32'sd110 :
                                (t_half > 32'sd250) ? 32'sd250 :
                                (t_half < -32'sd110) ? -32'sd110 : t_half;

    always @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            temp_msb <= 8'd0;
            temp_lsb <= 8'd0;
        end else if (latch_done) begin
            temp_msb <= t_sat[8:1];
            temp_lsb <= {t_sat[0], 7'd0};
        end
    end

    assign done = latch_done;

endmodule
/* verilator lint_on WIDTHEXPAND */
/* verilator lint_on SELRANGE */
