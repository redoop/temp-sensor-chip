// =====================================================================
// por.v -- power-on reset macro
//
// STATUS: NOT DESIGNED.  Interface plus requirement only.
//
// Requirement:
//   * rstn must be held low until BOTH supplies are valid and stable,
//     and must stay low long enough for the digital core's asynchronous
//     reset to take effect (no minimum is needed in the core -- the flops
//     use RN -- but the PTAT/CSRO need time to start and settle).
//   * release must be monotonic.  A slow supply ramp must not produce a
//     reset that releases and re-asserts: that would re-arm the gate
//     counter mid-measurement.
//   * the oscillator start-up is the slow part.  analog/spice/tb_t2f.spice
//     ramps VDD in 10 us and allows 0.5 ms before measuring, so the reset
//     should not release before roughly 1 ms after VDDA is valid.
//
// Typical implementation: a supply-detector (analogue) driving an RC, into
// a Schmitt input, then a short digital counter so the release edge is
// clean.  The detector and Schmitt belong to the analogue side; the
// counter can be standard cells.
//
// Testbench override: define CHIP_SIM_POR_NS to change the simulated reset
// width.
// =====================================================================

module por (
    input  wire VDDD,
    input  wire VSSD,
    input  wire VDDA,
    input  wire VSSA,
    output wire rstn
);

`ifdef CHIP_SIM
`ifndef CHIP_SIM_POR_NS
`define CHIP_SIM_POR_NS 20000      // 20 us is plenty for simulation
`endif
    reg rstn_r = 1'b0;
    initial begin
        rstn_r = 1'b0;
        #(`CHIP_SIM_POR_NS);
        rstn_r = 1'b1;
    end
    assign rstn = rstn_r;
`else
    assign rstn = 1'b0;   // no implementation yet -- see STATUS above
`endif

endmodule
