// =====================================================================
// clkgen.v -- 10 MHz chip timebase macro
//
// STATUS: NOT DESIGNED.  This file defines the interface and records the
// requirement; there is no schematic and no layout behind it yet.
//
// ---------------------------------------------------------------------
// Why this block carries a tight specification
// ---------------------------------------------------------------------
// The measurement gate is derived from this clock: temp_engine counts T2F
// rising edges for GATE_CYCLES = 100000 cycles, which is 10 ms only if the
// clock really is 10 MHz.  The calibration table (BP_CNT / BP_T / GAIN,
// from tb/t2f_model_params.vh) was fitted with a 10 ms gate, so a relative
// clock error e scales every count and biases the reported temperature:
//
//     raw_count  ~= f(T) * T_gate          f(25 C) ~= 610 kHz
//                                            raw    ~= 6100 counts
//     sensitivity  ~= 15.6 counts per degree C   (over -40..125 C)
//
//     => temperature error  ~= 6100 * e / 15.6  ~= 390 * e   [deg C]
//
//   e = 1 %     -> ~3.9 degC     (an untrimmed RC oscillator)
//   e = 0.1 %   -> ~0.39 degC
//   e = 0.05 %  -> ~0.20 degC
//
// So a plain on-chip RC oscillator is NOT adequate for the +/-0.5 degC the
// analog front-end can otherwise deliver; the clock needs to be trimmed
// against a reference, or the chip needs a ratiometric scheme in which the
// gate is derived from the same timebase that sets the T2F frequency.
//
// Options, in increasing cost:
//   1. external clock pin (accurate, but adds a pin and a board clock)
//   2. on-chip oscillator + one-point trim against I2C SCL (SCL is not a
//      reliable frequency reference -- a master can stretch it)
//   3. crystal / ceramic resonator
//   4. dual-oscillator ratiometric: count T2F against a reference
//      oscillator of the same type, so supply and temperature drift of the
//      clock largely cancel.  Changes temp_engine, not just this block.
//
// The interface below is what the rest of the chip expects regardless of
// which option is chosen.
// =====================================================================

module clkgen (
    input  wire VDD,
    input  wire VSS,
    input  wire en,     // 1 = running
    output wire clk     // 10 MHz nominal, see accuracy note above
);

`ifdef CHIP_SIM
    // Behavioural 10 MHz for chip-level simulation.  Override the half
    // period with +define+CHIP_SIM_CLK_HALF_NS=<n> to emulate a clock
    // error, e.g. 50 -> 10.0 MHz, 55 -> 9.09 MHz (-9 %).
`ifndef CHIP_SIM_CLK_HALF_NS
`define CHIP_SIM_CLK_HALF_NS 50
`endif
    reg clk_r = 1'b0;
    always #(`CHIP_SIM_CLK_HALF_NS) clk_r = en ? ~clk_r : 1'b0;
    assign clk = clk_r;
`else
    assign clk = 1'b0;   // no implementation yet -- see STATUS above
`endif

endmodule
