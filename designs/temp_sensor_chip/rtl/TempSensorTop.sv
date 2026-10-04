// =====================================================================
// TempSensorTop.sv -- temp-sensor-chip wrapped for mpc-frame
//
// Frame 66-bit payload contract (strict 5-port interface):
//   clock, reset : system clock / active-high reset
//   io_in [0]    : t2f_in  (temperature-to-frequency)
//   io_in [1]    : scl     (I2C clock sample)
//   io_in [2]    : sda     (I2C data sample)
//   io_out[0]    : os_int  (open-drain alert; oe=0 drive low)
//   io_out[1]    : scl_oe  (I2C SCL output-enable, unused)
//   io_out[2]    : sda_oe  (I2C SDA output-enable, unused)
//   io_out[3]    : shutdown (measurement gate)
//   io_out[4]    : heartbeat
//
// I2C: wired-OR bus.  i2c_slave drives SDA low during ACK/data-0;
// external master drives otherwise.  Bridge samples SCL/SDA and
// forwards to i2c_slave.
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

    // tri-state SDA net: wired-OR between i2c_slave output and
    // external master (via io_in[2]).
    tri sda_bus;

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
    // -----------------------------------------------------------------
    assign sda_bus = io_in[2];

    // I2C slave (SDA visibility is provided by the wired-OR net below)
    i2c_slave #(
        .I2C_ADDR (I2C_ADDR)
    ) u_i2c (
        .clk       (clock),
        .rstn      (rst_n),
        .scl       (scl_i),
        .sda       (sda_bus),
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

        // os_int is open-drain: pull low only while alerting,
        // otherwise release the pad.
        io_out[0] = 1'b0;
        io_oe[0]  = ~os_state;

        // shutdown: push-pull, reflects the software configuration.
        io_out[3] = shutdown_r;
        io_oe[3]  = 1'b1;

        // heartbeat: push-pull activity indicator.
        io_out[4] = heartbeat;
        io_oe[4]  = 1'b1;
    end

endmodule
/* verilator lint_on PINCONNECTEMPTY */
/* verilator lint_on WIDTHTRUNC   */
/* verilator lint_on WIDTHEXPAND  */
