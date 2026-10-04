// =====================================================================
// frame_bridge.sv -- mpc-frame pad sampler for temp-sensor-chip
//
// The Frame payload is a shared 66-bit bidirectional bus, so the
// design must decide per bit whether it drives or listens.  This
// bridge only samples the pad inputs; all output enables are
// resolved in TempSensorTop so that every payload bit has exactly
// one driver.
//
//   io_in[0] -> t2f_in   (temperature-to-frequency pulse train)
//   io_in[1] -> scl_i    (I2C clock sample)
//   io_in[2] -> sda_i    (I2C data sample, wired-OR bus)
//
// `reset` is active-high, matching the Frame contract.
// =====================================================================

module frame_bridge #(
    parameter int IO_WIDTH = 66
)(
    input  logic                clock,
    input  logic                reset,
    input  logic [IO_WIDTH-1:0] io_in,

    // registered pad samples for the chip internals
    output logic                t2f_i,
    output logic                scl_i,
    output logic                sda_i
);

    always_ff @(posedge clock or posedge reset) begin
        if (reset) begin
            t2f_i <= 1'b0;
            scl_i <= 1'b1;
            sda_i <= 1'b1;
        end else begin
            t2f_i <= io_in[0];
            scl_i <= io_in[1];
            sda_i <= io_in[2];
        end
    end

endmodule
