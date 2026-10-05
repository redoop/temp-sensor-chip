`timescale 1ns/1ps
module tb_diag;
    localparam time CLK_HALF = 50ns;
    logic clk = 0, rstn = 0;
    logic t2f_in = 0;
    logic scl_i = 1, sda_i = 1;
    wire sda_o, sda_oe, os_int_o, os_int_oe;

    always #(CLK_HALF) clk = ~clk;

    temp_sensor_block dut (
        .clk(clk), .rstn(rstn), .t2f_in(t2f_in),
        .scl_i(scl_i), .sda_i(sda_i),
        .sda_o(sda_o), .sda_oe(sda_oe),
        .os_int_o(os_int_o), .os_int_oe(os_int_oe)
    );

    // count transitions on internal nets that exist at netlist top level
    integer ed_cnt = 0, oe_cnt = 0, tos_cnt = 0;
    reg ed_p = 0, oe_p = 0;

    always @(posedge clk) begin
        if (dut.engine_done_reg_p_QN !== ed_p) begin
            ed_p <= dut.engine_done_reg_p_QN; ed_cnt <= ed_cnt + 1;
        end
        if (sda_oe !== oe_p) begin
            oe_p <= sda_oe; oe_cnt <= oe_cnt + 1;
        end
    end

    // toggle t2f_in so the engine has something to count
    always #(800ns) t2f_in = ~t2f_in;   // ~625 kHz

    initial begin
        repeat (4) @(posedge clk);
        rstn = 1;
        repeat (20) @(posedge clk);
        #1ns;
        $display("after reset: os_int_oe=%b sda_oe=%b", os_int_oe, sda_oe);
        #(25ms);
        $display("engine_done transitions = %0d", ed_cnt);
        $display("sda_oe      transitions = %0d", oe_cnt);
        $display("os_int_oe=%b sda_oe=%b", os_int_oe, sda_oe);
        $finish;
    end
endmodule
