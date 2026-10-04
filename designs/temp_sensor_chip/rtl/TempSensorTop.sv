// =====================================================================
// TempSensorTop.sv -- temp-sensor-chip wrapped for mpc-frame
//
// Frame 66-bit payload contract (strict 5-port interface).  Payload bit
// n maps to user_io[n + 7].
//
//   bit  direction  signal
//   ---  ---------  ---------------------------------------------------
//    0   input      t2f_in    temperature-to-frequency pulse train
//    1   input      scl       I2C clock (this slave never stretches it)
//    2   inout      sda       I2C data, wired-OR open-drain
//    3   output     os_int    over-temperature alert, open-drain
//    4   output     shutdown  measurement gate, push-pull
//    5   output     heartbeat activity indicator, push-pull
//   6+   released   unused
//
// Inputs and outputs live on separate payload bits: the external
// analog front-end drives t2f_in push-pull, so it must never share a
// pad with the open-drain os_int alert.
//
// `reset` is active-high (Frame contract); the chip RTL is active-low,
// so rst_n is derived below.
// =====================================================================

/* verilator lint_off PINCONNECTEMPTY */
/* verilator lint_off WIDTHTRUNC   */
/* verilator lint_off WIDTHEXPAND  */
module TempSensorTop #(
    parameter int IO_WIDTH = 66,
    parameter [6:0]  I2C_ADDR = 7'h48,
    parameter [31:0] GATE_CYCLES = 32'd100000,
    parameter integer NSEC = 9,
    parameter [NSEC*16-1:0] BP_CNT = 288'h0,
    parameter [NSEC*16-1:0] BP_T   = 160'h0,
    parameter [NSEC*12-1:0] GAIN   = 108'h0,
    parameter [7:0] SHIFT = 8'd8
)(
    input  logic                clock,
    input  logic                reset,
    input  logic [IO_WIDTH-1:0] io_in,
    output logic [IO_WIDTH-1:0] io_out,
    output logic [IO_WIDTH-1:0] io_oe
);

    // -----------------------------------------------------------------
    // payload bit assignment
    // -----------------------------------------------------------------
    localparam int BIT_T2F       = 0;   // input
    localparam int BIT_SCL       = 1;   // input
    localparam int BIT_SDA       = 2;   // inout, open-drain
    localparam int BIT_OS_INT    = 3;   // output, open-drain
    localparam int BIT_SHUTDOWN  = 4;   // output, push-pull
    localparam int BIT_HEARTBEAT = 5;   // output, push-pull

    // -----------------------------------------------------------------
    // Frame contract: `reset` is active-high.  The chip RTL is
    // active-low, so derive an internal rst_n here.
    // -----------------------------------------------------------------
    wire rst_n = ~reset;

    // -----------------------------------------------------------------
    // internal chip nets
    // -----------------------------------------------------------------
    wire [7:0]  temp_msb, temp_lsb;
    wire [3:0]  reg_addr;
    wire [7:0]  reg_wdata, reg_rdata;
    wire        reg_we;
    wire        engine_done;
    wire [7:0]  thyst, tos;
    wire        cfg_shutdown, cfg_comparator;

    // bridge output: registered pad samples
    wire        t2f_i;
    wire        scl_i;
    wire        sda_i;

    // SDA is a wired-OR bus: the slave only pulls it low.
    wire        sda_oe;
    tri         sda_bus;

    // -----------------------------------------------------------------
    // shutdown: from config register, registered
    // -----------------------------------------------------------------
    reg shutdown_r;
    always_ff @(posedge clock or negedge rst_n) begin
        if (!rst_n)
            shutdown_r <= 1'b0;
        else
            shutdown_r <= cfg_shutdown;
    end

    // -----------------------------------------------------------------
    // frame bridge: pad input sampling only
    // -----------------------------------------------------------------
    frame_bridge #(
        .IO_WIDTH(IO_WIDTH)
    ) u_bridge (
        .clock       (clock),
        .reset       (reset),
        .io_in       (io_in),
        .t2f_i       (t2f_i),
        .scl_i       (scl_i),
        .sda_i       (sda_i)
    );

    // -----------------------------------------------------------------
    // temperature measurement engine
    // -----------------------------------------------------------------
    temp_engine #(
        .GATE_CYCLES (GATE_CYCLES),
        .NSEC        (NSEC),
        .BP_CNT      (BP_CNT),
        .BP_T        (BP_T),
        .GAIN        (GAIN),
        .SHIFT       (SHIFT),
        .USE_SHUTDOWN(1)
    ) u_engine (
        .clk      (clock),
        .rstn     (rst_n),
        .t2f_in   (t2f_i),
        .shutdown (shutdown_r),
        .temp_msb (temp_msb),
        .temp_lsb (temp_lsb),
        .done     (engine_done)
    );

    // -----------------------------------------------------------------
    // register file
    // -----------------------------------------------------------------
    temp_regs u_regs (
        .clk           (clock),
        .rstn          (rst_n),
        .addr          (reg_addr),
        .wdata         (reg_wdata),
        .we            (reg_we),
        .rdata         (reg_rdata),
        .temp_msb      (temp_msb),
        .temp_lsb      (temp_lsb),
        .cfg_shutdown  (cfg_shutdown),
        .cfg_comparator(cfg_comparator),
        .cfg_resolution(),
        .thyst         (thyst),
        .tos           (tos)
    );

    // -----------------------------------------------------------------
    // I2C slave
    //
    // The pad is sampled through the bridge, and the slave's pull-down
    // is OR-ed in so the slave always sees a defined bus value even if
    // the external master has released the line.
    // -----------------------------------------------------------------
    assign sda_bus = sda_oe ? 1'b0 : sda_i;

    i2c_slave #(
        .I2C_ADDR (I2C_ADDR)
    ) u_i2c (
        .clk       (clock),
        .rstn      (rst_n),
        .scl       (scl_i),
        .sda       (sda_bus),
        .sda_oe    (sda_oe),
        .reg_addr  (reg_addr),
        .reg_wdata (reg_wdata),
        .reg_we    (reg_we),
        .reg_rdata (reg_rdata)
    );

    // -----------------------------------------------------------------
    // os_int: open-drain alert comparator (TOS/Thyst hysteresis)
    // -----------------------------------------------------------------
    reg os_state;
    always @(posedge clock or negedge rst_n) begin
        if (!rst_n)
            os_state <= 1'b1;
        else if (engine_done) begin
            if ({temp_msb, temp_lsb[7]} >= {tos, 1'b0})
                os_state <= 1'b0;
            else if ({temp_msb, temp_lsb[7]} < {thyst, 1'b0})
                os_state <= 1'b1;
        end
    end

    // -----------------------------------------------------------------
    // heartbeat
    // -----------------------------------------------------------------
    reg heartbeat;
    always_ff @(posedge clock or negedge rst_n) begin
        if (!rst_n)
            heartbeat <= 1'b0;
        else
            heartbeat <= ~heartbeat;
    end

    // -----------------------------------------------------------------
    // Single driver for the whole payload bus.  Every bit is either
    // actively driven or explicitly released to high-Z.
    // -----------------------------------------------------------------
    always_comb begin
        io_out = '0;
        io_oe  = '0;

        // SDA: open-drain, mirror the slave's pull-down onto the pad.
        io_out[BIT_SDA] = 1'b0;
        io_oe [BIT_SDA] = sda_oe;

        // os_int: open-drain, pull low only while alerting.
        io_out[BIT_OS_INT] = 1'b0;
        io_oe [BIT_OS_INT] = ~os_state;

        // shutdown: push-pull, reflects the software configuration.
        io_out[BIT_SHUTDOWN] = shutdown_r;
        io_oe [BIT_SHUTDOWN] = 1'b1;

        // heartbeat: push-pull activity indicator.
        io_out[BIT_HEARTBEAT] = heartbeat;
        io_oe [BIT_HEARTBEAT] = 1'b1;
    end

endmodule
/* verilator lint_on PINCONNECTEMPTY */
/* verilator lint_on WIDTHTRUNC   */
/* verilator lint_on WIDTHEXPAND  */
