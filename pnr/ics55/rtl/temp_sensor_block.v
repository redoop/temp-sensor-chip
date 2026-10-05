// =====================================================================
// temp_sensor_block.v -- hardenable top for the temp-sensor-chip core
//
// rtl/temp_sensor_top.v expresses both the I2C bus and the alert as
// Verilog tri-state:
//     inout scl, sda;                      // I2C wired-OR bus
//     assign os_int = os_state ? 1'bz : 1'b0;   // open-drain alert
// A standard-cell block has no tri-state cells, so every open-drain pad
// is split into a value + output-enable pair here.  The chip-level pad
// ring recombines them.
//
// Calibration constants are bound from the ngspice characterization
// (tb/t2f_model_params.vh) so the hardened netlist carries the real
// table rather than the module's all-zero default.
// =====================================================================
module temp_sensor_block (
    input  wire clk,
    input  wire rstn,
    input  wire t2f_in,

    // I2C pads: this slave never drives SCL, so it is input only
    input  wire scl_i,
    input  wire sda_i,
    output wire sda_o,      // SDA pull-down value (open drain: always 0)
    output wire sda_oe,     // SDA drive enable, 1 = pull low

    // open-drain over-temperature alert
    output wire os_int_o,   // alert pull-down value (always 0)
    output wire os_int_oe   // alert drive enable, 1 = pull low
);

    localparam [6:0]  I2C_ADDR    = 7'h48;
    localparam [31:0] GATE_CYCLES = 32'd100000;   // 10 ms gate @ 10 MHz

    // calibration table measured from the analog front-end
    localparam integer NSEC = 10;
    localparam [NSEC*16-1:0] BP_CNT = 288'h1ddd1c7b1b571a421910185517e516a5155813ce;
    localparam [NSEC*16-1:0] BP_T   = 160'h00fa00c800a000780050003600280000ffd8ffb0;
    localparam [NSEC*12-1:0] GAIN   = 108'h02402302502102402002001f01a;

    wire [7:0] temp_msb, temp_lsb;
    wire [3:0] reg_addr;
    wire [7:0] reg_wdata, reg_rdata;
    wire       reg_we;
    wire       engine_done;
    wire [7:0] thyst, tos;
    wire       cfg_shutdown, cfg_comparator;

    // Wired-OR resolve: the slave's own pull-down is OR-ed in so it never
    // samples an undriven pad even if the master has released the line.
    wire sda_bus = sda_oe ? 1'b0 : sda_i;

    temp_engine #(
        .GATE_CYCLES (GATE_CYCLES),
        .NSEC        (NSEC),
        .BP_CNT      (BP_CNT),
        .BP_T        (BP_T),
        .GAIN        (GAIN)
    ) u_engine (
        .clk      (clk),
        .rstn     (rstn),
        .t2f_in   (t2f_in),
        .shutdown (cfg_shutdown),
        .temp_msb (temp_msb),
        .temp_lsb (temp_lsb),
        .done     (engine_done)
    );

    temp_regs u_regs (
        .clk           (clk),
        .rstn          (rstn),
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

    i2c_slave #(
        .I2C_ADDR (I2C_ADDR)
    ) u_i2c (
        .clk       (clk),
        .rstn      (rstn),
        .scl       (scl_i),
        .sda       (sda_bus),
        .sda_oe    (sda_oe),
        .reg_addr  (reg_addr),
        .reg_wdata (reg_wdata),
        .reg_we    (reg_we),
        .reg_rdata (reg_rdata)
    );

    // Alert comparator: os low while T >= TOS, released once T < Thyst.
    wire [8:0] temp_val  = {temp_msb, temp_lsb[7]};
    wire [8:0] tos_val   = {tos, 1'b0};
    wire [8:0] thyst_val = {thyst, 1'b0};

    reg os_state;
    always @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            os_state <= 1'b1;                  // inactive, open-drain released
        end else if (engine_done) begin
            if (temp_val >= tos_val)
                os_state <= 1'b0;
            else if (temp_val < thyst_val)
                os_state <= 1'b1;
            // between Thyst and TOS: hold for hysteresis
        end
    end

    // open-drain alert exported as value + enable
    assign os_int_o  = 1'b0;
    assign os_int_oe = ~os_state;

    assign sda_o = 1'b0;

endmodule
