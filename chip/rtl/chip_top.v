// =====================================================================
// chip_top.v -- temp-sensor-chip full-chip structural netlist
//
// Merges the chip's three domains into one elaborated netlist:
//
//   analog         u_afe     PTAT current source + current-starved ring
//                            oscillator (temperature -> frequency)
//   analog/digital u_inbuf   T2F level conditioner: the CSRO output is a
//                            weak (~1 uA), slow, 0..1.2 V square wave and
//                            must be shaped into a clean standard-cell
//                            input for the digital core
//   digital        u_dig     hardened temp_sensor_block macro (ICS55,
//                            produced by pnr/ics55)
//
// plus the always-on support blocks (clock, POR) and the pad ring.
//
// ---------------------------------------------------------------------
// What "merged netlist" means here -- read this before using the file
// ---------------------------------------------------------------------
// A transistor-level SPICE netlist and a gate-level Verilog netlist are
// different abstract domains and cannot be concatenated into one file.
// The analog blocks therefore appear as macros with a defined pin
// interface:
//
//   * their behavioural Verilog view (t2f_afe.v, clkgen.v, por.v, and
//     pad_signal.v) lets this netlist elaborate and simulate in the
//     digital domain;
//   * their real content is the SPICE netlist under ../analog/, plus the
//     layout that does not exist yet for most of them.
//
// Chip-level LVS must compare the layout against BOTH views.  There is no
// single "one true netlist" for a mixed-signal chip; there are two views
// of every macro plus the structural top that binds them.
//
// ---------------------------------------------------------------------
// Status of each instance -- do not mistake placeholders for silicon
// ---------------------------------------------------------------------
//   u_dig     REAL   hardened macro: netlist + DEF + GDS/LEF/LIB exist
//   u_afe     PARTIAL SPICE schematic exists; CSRO has no layout, the
//                     PTAT cell layout has DRC violations
//   u_inbuf   REAL   standard-cell inverter chain (1.2 V domain)
//   u_clkgen  MISSING only a specification exists; needs a trimmed
//                     oscillator (see ../README.md on clock accuracy)
//   u_por     MISSING only a specification exists
//   pads      MISSING the installed ICS55 IO library ships pad-ring
//                     structure (corner/cut/filler/power) but NO signal
//                     IO cells, so these are abstract placeholders
// =====================================================================

module chip_top (
    // ---- supplies -------------------------------------------------
    input  wire VDDD,       // 1.2 V  digital core
    input  wire VSSD,       // 0 V    digital core
    input  wire VDDA,       // 1.2 V  analog  (separate: see README)
    input  wire VSSA,       // 0 V    analog
    input  wire VDDIO,      // 3.3 V  pad ring
    input  wire VSSIO,      // 0 V    pad ring

    // ---- package pins --------------------------------------------
    input  wire SCL,        // I2C clock (3.3 V, pad ring)
    inout  wire SDA,        // I2C data  (3.3 V, open drain)
    output wire OS_INT,     // over-temperature alert (open drain)
    output wire T2F_MON     // analog: CSRO monitor for in-situ trim
);

    // =================================================================
    // 1. Timebase and reset
    // =================================================================
    // The 10 ms measurement gate is derived from CLK, so the clock is
    // part of the temperature reference, not just a digital housekeeping
    // signal.  See ../README.md: the calibration table assumes 10 MHz and
    // a clock error e biases the reading by roughly 385 * e degrees C.
    wire clk;               // 10 MHz nominal

    clkgen u_clkgen (
        .VDD  (VDDA),
        .VSS  (VSSA),
        .en   (1'b1),
        .clk  (clk)
    );

    wire rstn;              // active-low, asynchronous

    por u_por (
        .VDDD (VDDD),
        .VSSD (VSSD),
        .VDDA (VDDA),
        .VSSA (VSSA),
        .rstn (rstn)
    );

    // =================================================================
    // 2. Analog front-end: PTAT + current-starved ring oscillator
    // =================================================================
    wire fout_ana;          // weak, slow 0..1.2 V square wave, ~0.5-0.8 MHz

    t2f_afe u_afe (
        .VDDA (VDDA),
        .VSSA (VSSA),
        .en   (1'b1),
        .fout (fout_ana)
    );

    // =================================================================
    // 3. T2F level conditioner (analog -> digital boundary)
    // =================================================================
    // Must present minimal input capacitance to the CSRO: any extra load
    // slows the oscillator and shifts f(T), which the calibration table
    // would then mis-interpret as a temperature error.
    wire t2f_dig;

    t2f_inbuf u_inbuf (
        .VDD  (VDDD),
        .VSS  (VSSD),
        .ain  (fout_ana),
        .dout (t2f_dig)
    );

    // =================================================================
    // 4. Hardened digital macro (pnr/ics55)
    // =================================================================
    wire scl_i;             // SCL as seen by the core
    wire sda_i;             // SDA as seen by the core (wired-OR resolved)
    wire sda_o;             // SDA pull-down value (open drain: always 0)
    wire sda_oe;            // SDA drive enable, 1 = pull low
    wire os_int_o;          // alert pull-down value (always 0)
    wire os_int_oe;         // alert drive enable, 1 = pull low

    temp_sensor_block u_dig (
        .clk       (clk),
        .rstn      (rstn),
        .t2f_in    (t2f_dig),
        .scl_i     (scl_i),
        .sda_i     (sda_i),
        .sda_o     (sda_o),
        .sda_oe    (sda_oe),
        .os_int_o  (os_int_o),
        .os_int_oe (os_int_oe)
    );

    // =================================================================
    // 5. Pad ring
    // =================================================================
    // Power ring structure is instantiated from the real library that the
    // PDK does ship (corner / cut / filler / power cells).  The signal
    // pads are abstract placeholders: the installed ICS55 IO library has
    // no signal IO cells, so a real pad ring cannot be built until the
    // signal IO library is added.  Their interface is frozen here so the
    // rest of the chip does not change when they arrive.

    // ---- SCL: 3.3 V input ------------------------------------------
    pad_in u_pad_scl (
        .PAD    (SCL),
        .VDDIO  (VDDIO),
        .VSSIO  (VSSIO),
        .CORE_I (scl_i)
    );

    // ---- SDA: 3.3 V open-drain bidirectional -----------------------
    // The core only ever pulls SDA low; the pad's pull-up (external or
    // in-pad) supplies the high level.
    pad_bidir_od u_pad_sda (
        .PAD     (SDA),
        .VDDIO   (VDDIO),
        .VSSIO   (VSSIO),
        .CORE_I  (sda_i),
        .CORE_O  (sda_o),
        .CORE_OE (sda_oe)
    );

    // ---- OS_INT: 3.3 V open-drain output ---------------------------
    pad_out_od u_pad_os_int (
        .PAD     (OS_INT),
        .VDDIO   (VDDIO),
        .VSSIO   (VSSIO),
        .CORE_O  (os_int_o),
        .CORE_OE (os_int_oe)
    );

    // ---- T2F_MON: analog observation pad ---------------------------
    // Bring-up aid: watching the raw oscillator lets the T2F frequency be
    // measured on silicon and the calibration table re-derived, which is
    // the only way to correct for process spread (the SPICE corners span
    // roughly +/-7 % at a given temperature).
    pad_analog u_pad_t2f_mon (
        .PAD   (T2F_MON),
        .VSSIO (VSSIO),
        .AIN   (fout_ana)
    );

    // =================================================================
    // 6. Supply interconnect (star routing on the analog side)
    // =================================================================
    // Kept explicit so the layout step has a netlist to follow: the
    // analog supply is NOT tied to the digital supply in this netlist.
    // The pad ring structure cells below are the real library cells.
    pad_ring_power u_ring_vddd (.VDD (VDDD), .VSS (VSSD));
    pad_ring_power u_ring_vdda (.VDD (VDDA), .VSS (VSSA));
    pad_ring_power u_ring_vddio(.VDD (VDDIO), .VSS (VSSIO));

endmodule
