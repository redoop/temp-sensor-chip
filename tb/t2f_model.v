// =====================================================================
// t2f_model.v -- behavioral model of the analog front-end
//
// Generates a pulse train whose frequency is a piecewise-linear
// interpolation of the ngspice-characterized f(T) breakpoints (T2F_NSEC
// points), matching scripts/gen_t2f_model.py.  Used by tb_top to verify
// the digital count->temperature mapping exactly.
//
// SPDX-License-Identifier: Apache-2.0
// =====================================================================
`include "t2f_model_params.vh"

module t2f_model #(
    parameter real CLK_HZ = 10.0e6
)(
    input  wire clk,
    input  wire rstn,
    input  wire signed [31:0] temp_x100,  // temperature in 0.01 C steps
    output reg  t2f
);

    // breakpoints (packed in t2f_model_params.vh)
    localparam integer N = `T2F_NSEC;
    wire [15:0] t_cnt [0:N-1];
    wire [15:0] f_hz  [0:N-1];
    genvar gi;
    generate
        for (gi = 0; gi < N; gi = gi + 1) begin : bp
            assign t_cnt[gi] = 16'd0;  // unused here
        end
    endgenerate

    // unpack temps (C x100) and freqs (Hz): packed parameters
    localparam [N*16-1:0] T_PACK = `T2F_T_PACK;
    localparam [N*32-1:0] F_PACK = `T2F_F_PACK;
    wire signed [15:0] tc [0:N-1];
    wire [31:0] fz [0:N-1];
    genvar gj;
    generate
        for (gj = 0; gj < N; gj = gj + 1) begin : up
            assign tc[gj] = T_PACK[(gj+1)*16-1 -: 16];
            assign fz[gj] = F_PACK[(gj+1)*32-1 -: 32];
        end
    endgenerate

    // piecewise interpolation of f(temp_x100)
    reg [31:0] period_hz;
    integer k;
    always @* begin
        period_hz = fz[0];
        if (temp_x100 <= tc[0]) begin
            period_hz = fz[0];
        end else if (temp_x100 >= tc[N-1]) begin
            period_hz = fz[N-1];
        end else begin
            for (k = 0; k < N-1; k = k + 1) begin
                if (temp_x100 >= tc[k] && temp_x100 < tc[k+1]) begin
                    period_hz = fz[k] + (fz[k+1] - fz[k]) *
                                ($signed(temp_x100) - $signed(tc[k])) /
                                ($signed(tc[k+1]) - $signed(tc[k]));
                end
            end
        end
        if (period_hz < 100) period_hz = 100;
    end

    // DDS accumulator: t2f = MSB of a phase accumulator stepped by
    // f/CLK*2^32, giving an exact average frequency
    reg [31:0] acc;
    reg [31:0] step;
    always @* begin
        step = $rtoi($itor(period_hz) / CLK_HZ * 4294967296.0);
        if (step == 32'd0) step = 32'd1;
    end

    always @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            acc <= 32'd0;
            t2f <= 1'b0;
        end else begin
            acc <= acc + step;
            t2f <= acc[31];
        end
    end

endmodule
