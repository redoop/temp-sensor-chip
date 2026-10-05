// =====================================================================
// t2f_inbuf.v -- T2F level conditioner (analog -> digital boundary)
//
// The CSRO output is a weak, slow 0..1.2 V square wave (stage current
// ~1 uA, so edge rates are far slower than a standard-cell input likes).
// This block turns it into a clean 1.2 V-domain logic signal for the
// digital core.
//
// Sizing rationale -- the whole point of the block:
//
//   stage 1   minimum size, and the ONLY load the oscillator sees.  Its
//             input capacitance must be budgeted into the CSRO output
//             node: extra capacitance slows the oscillator and shifts
//             f(T), which after the piecewise table is indistinguishable
//             from a temperature error.
//   stage 2-5 progressively larger, so the switching threshold sits near
//             VDDA/2 and the edge presented to the core is fast.
//
// An odd number of inverting stages preserves polarity.
//
// Hysteresis: this chain has none.  On a slow, high-impedance input a
// plain chain can produce multiple edges per transition.  Two options,
// neither of which can be expressed with these cells alone:
//   (a) add a weak feedback path -- needs a resistor or a deliberately
//       weak (long-channel) device, i.e. an analogue structure, not a
//       standard cell;
//   (b) use a pad/input cell with a Schmitt characteristic.
// Until one of those is chosen the digital side relies on the 3-tap SCL
// style filtering and the fact that T2F is ~0.5-0.8 MHz against a 10 MHz
// sampling clock, which tolerates slow edges but NOT multiple threshold
// crossings.  Treat this as an open design item.
//
// Cell domain: 1.2 V thin-oxide devices.  Do not implement with 3.3 V IO
// devices: their higher threshold narrows the duty cycle seen by the core
// and can swallow narrow pulses.
//
// Pins used below are the real ICS55 ports: INVX* is (Y, A).
// =====================================================================

module t2f_inbuf (
    input  wire VDD,
    input  wire VSS,
    input  wire ain,
    output wire dout
);

    wire n1, n2, n3, n4;

    INVX0P5H7L u_s1 (.A(ain), .Y(n1));   // minimum size: lightest load
    INVX0P7H7L u_s2 (.A(n1),  .Y(n2));
    INVX1H7L   u_s3 (.A(n2),  .Y(n3));
    INVX1H7L   u_s4 (.A(n3),  .Y(n4));
    INVX2H7L   u_s5 (.A(n4),  .Y(dout));

endmodule
