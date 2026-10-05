// =====================================================================
// pad_signal.v -- abstract signal-pad placeholders
//
// WHY THESE ARE PLACEHOLDERS
// ---------------------------------------------------------------------
// The installed ICS55 IO library
//   IP/IO/ICsprout_55LLULP1233_IO_251013
// ships only pad-ring structure: corner, cut, filler, power/ground ring,
// PAR, PBMUX and PWE cells.  It contains NO signal IO cells -- no input
// buffer, no output driver, no bidirectional pad.  Verified by filtering
// the 23 MACROs in its LEF:
//
//   P65_1233_{CORNER,CUT,FILLER*,PAR,PAR_5,PBMUX,PWE,VDD*,VSS*}
//
// So a real pad ring cannot be built from the installed PDK.  Rather than
// block the rest of the chip design on it, the pad interfaces are frozen
// here.  When the signal IO library arrives, replace these modules with
// wrappers around the real cells -- the rest of chip_top does not change.
//
// The pin convention below is deliberately the usual one:
//   CORE_I   pad -> core
//   CORE_O   core -> pad (drive value)
//   CORE_OE  core -> pad (drive enable; 0 = release)
//
// Electrical requirements the real pads must satisfy:
//   SCL     3.3 V input, must tolerate the I2C bus levels and a master
//           that stretches the clock.
//   SDA     3.3 V open-drain bidirectional.  The core only ever pulls
//           low, so no output-value driver is needed beyond a pull-down
//           device; an in-pad or external pull-up supplies the high.
//   OS_INT  3.3 V open-drain output, same pull-down-only requirement.
//
// Note for SDA/OS_INT: because these are open-drain, CORE_O is always 0
// and only CORE_OE matters.  The pads must NOT drive a high level, or a
// bus conflict results.
//
// All pad models are simulation-only stand-ins and must never be
// synthesised.
// =====================================================================

// ---------------------------------------------------------------------
// Input pad
// ---------------------------------------------------------------------
module pad_in (
    input  wire PAD,
    input  wire VDDIO,
    input  wire VSSIO,
    output wire CORE_I
);
    // A real pad adds ESD, level shifting and a Schmitt input.  The
    // stand-in just forwards the level.
    assign CORE_I = PAD;
endmodule

// ---------------------------------------------------------------------
// Open-drain output pad
// ---------------------------------------------------------------------
module pad_out_od (
    input  wire VDDIO,
    input  wire VSSIO,
    inout  wire PAD,
    input  wire CORE_O,
    input  wire CORE_OE
);
    // Pull-down only: never drive a high level onto an open-drain net.
    // CORE_O must be 0 for this pad type; it is accepted so that a future
    // push-pull variant has the same interface.
    assign PAD = CORE_OE ? CORE_O : 1'bz;
endmodule

// ---------------------------------------------------------------------
// Open-drain bidirectional pad
// ---------------------------------------------------------------------
module pad_bidir_od (
    input  wire VDDIO,
    input  wire VSSIO,
    inout  wire PAD,
    output wire CORE_I,
    input  wire CORE_O,
    input  wire CORE_OE
);
    assign PAD    = CORE_OE ? CORE_O : 1'bz;
    assign CORE_I = PAD;
endmodule

// ---------------------------------------------------------------------
// Analogue observation pad (no digital driver)
// ---------------------------------------------------------------------
module pad_analog (
    input  wire VSSIO,
    inout  wire PAD,
    input  wire AIN
);
    // A real implementation routes the analogue node out through an
    // ESD-protected, high-impedance path with minimal added capacitance:
    // probing this node loads the CSRO, which shifts f(T).  Keep the pad
    // small and treat the loading as part of the calibration.
    assign PAD = AIN;
endmodule

// ---------------------------------------------------------------------
// Pad-ring power structure
// ---------------------------------------------------------------------
// The installed library does provide the real ring cells (P65_1233_VDD1,
// VSS1, VDDIO3, ...).  They are modelled here as a single stand-in so the
// supply intent is explicit in the netlist: analog, digital and IO
// supplies are separate nets, star-routed, and are NOT tied together on
// chip.  Replace with the real cells at floorplan time.
module pad_ring_power (
    input  wire VDD,
    input  wire VSS
);
endmodule
