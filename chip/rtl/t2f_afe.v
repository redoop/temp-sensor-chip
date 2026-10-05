// =====================================================================
// t2f_afe.v -- digital-domain view of the analog front-end macro
//
// Real content: ../analog/t2f_afe.spice (PTAT + current-starved ring
// oscillator).  That SPICE netlist is the schematic; this Verilog view
// exists so the chip netlist can elaborate and so the digital regression
// runs without a SPICE simulator.
//
// Interface (frozen -- the SPICE subcircuit must match these pins):
//   VDDA / VSSA : 1.2 V analog supply
//   en          : 1 = running, 0 = powered down
//   fout        : square wave, ~0.5-0.8 MHz over -40..125 C, 0..VDDA
//
// With CHIP_SIM defined, fout is produced by the behavioural model fitted
// to the ngspice characterization (tb/t2f_model.v).  The model needs a
// timebase, and the real oscillator has no clock pin, so a local 10 MHz
// clock is generated inside this file rather than borrowing the digital
// clock -- that keeps the macro self-contained and its pin list honest.
// Without CHIP_SIM the output is released, so the analog view drives it.
//
// ELECTRICAL NOTES the layout must honour:
//   * fout drive is very weak: the CSRO stage current is ~1 uA, set by
//     the PTAT mirror.  Anything loading this node slows the oscillator
//     and shifts f(T), which the calibration table would then read as a
//     temperature error.
//   * the first stage of t2f_inbuf must therefore be a minimum-size
//     inverter, and its input capacitance belongs in the CSRO output-node
//     load (csro.spice models 100 fF per internal node).
//   * fout must be routed away from switching digital nets; coupling here
//     converts directly into temperature error.
// =====================================================================

module t2f_afe (
    input  wire VDDA,
    input  wire VSSA,
    input  wire en,
    output wire fout
);

`ifdef CHIP_SIM
    // ---- behavioural model of the characterized transfer function ----
    // TEMP_X100 is a testbench hook (0.01 C units).  On silicon this is
    // the real junction temperature.
    reg [31:0] TEMP_X100 = 32'd2500;

    // Local 10 MHz timebase for the model only.  Not a chip pin: the real
    // oscillator free-runs and its frequency is set by PTAT/R*C, not by
    // any clock.
    reg sim_clk = 1'b0;
`ifndef CHIP_SIM_CLK_HALF_NS
`define CHIP_SIM_CLK_HALF_NS 50
`endif
    always #(`CHIP_SIM_CLK_HALF_NS) sim_clk = ~sim_clk;

    t2f_model #(.CLK_HZ(10.0e6)) u_model (
        .clk       (sim_clk),
        .rstn      (en),
        .temp_x100 (TEMP_X100),
        .t2f       (fout)
    );
`else
    // Analog view drives this node (SPICE / extracted netlist).
    assign fout = 1'bz;
`endif

endmodule
