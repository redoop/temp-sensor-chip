// =====================================================================
// TempSensorTopTb.sv -- functional unit test for TempSensorTop
//
// Runs the design WITHOUT the mpc-frame top level, driving the payload
// pads directly, and exercises the complete measurement path:
//
//   t2f_model (analog front-end, ngspice-characterized) -> t2f_in pad
//     -> temp_engine (10 ms gated counter + piecewise-linear table)
//     -> temp_regs -> i2c_slave -> i2c_master_model read-back
//
// Checks:
//   1. reset values on the payload bus
//   2. temperature read-back matches the model input within 1 LSB
//      (0.5 C) at 25, -40, 0, 125 and 85 C
//   3. os_int asserts when the temperature crosses TOS
//   4. TOS / Thyst register read-back and write-through
//   5. correct address is ACKed, a wrong address is NACKed
//
// Timing note: GATE_CYCLES (100000) is calibrated for a 10 MHz clock and
// a 10 ms gate window, so CLK_HALF must stay 50 ns.  Changing the clock
// frequency rescales the raw pulse count and invalidates the calibration
// table derived from the ngspice characterization.
// =====================================================================

`include "t2f_model_params.vh"

module TempSensorTopDut;

    localparam int  IO_WIDTH      = 66;
    localparam time CLK_HALF      = 50ns;   // 10 MHz
    localparam int  I2C_SCL_HALF  = 25;     // 25 clk per half period
    localparam logic [6:0] I2C_ADDR = 7'h48;

    // One 10 ms gate window plus margin, so a fresh conversion has
    // completed before the temperature registers are read.
    localparam time MEASURE_WAIT = 20ms;

    // payload bit assignment (must match TempSensorTop)
    localparam int BIT_T2F       = 0;
    localparam int BIT_SCL       = 1;
    localparam int BIT_SDA       = 2;
    localparam int BIT_OS_INT    = 3;
    localparam int BIT_SHUTDOWN  = 4;
    localparam int BIT_HEARTBEAT = 5;

    logic                clock = 1'b0;
    logic                reset = 1'b1;
    logic [IO_WIDTH-1:0] io_in;
    wire  [IO_WIDTH-1:0] io_out;
    wire  [IO_WIDTH-1:0] io_oe;

    always #(CLK_HALF) clock = ~clock;

    wire reset_n = ~reset;   // chip-internal models are active-low

    // Calibration constants come from the same generated header that
    // drives t2f_model, so the engine's table and the analog model agree
    // by construction.
    TempSensorTop #(
        .IO_WIDTH (IO_WIDTH),
        .I2C_ADDR (I2C_ADDR),
        .NSEC     (`T2F_NSEC),
        .BP_CNT   (`T2F_BP_CNT),
        .BP_T     (`T2F_BP_T),
        .GAIN     (`T2F_GAIN)
    ) dut (
        .clock  (clock),
        .reset  (reset),
        .io_in  (io_in),
        .io_out (io_out),
        .io_oe  (io_oe)
    );

    // -----------------------------------------------------------------
    // I2C bus model: pull-ups, external master, and the design's
    // open-drain SDA pull-down reflected back onto the shared line.
    // -----------------------------------------------------------------
    tri m_scl, m_sda;
    pullup(m_scl);
    pullup(m_sda);

    i2c_master_model #(.SCL_HALF(I2C_SCL_HALF)) master (
        .scl (m_scl),
        .sda (m_sda),
        .clk (clock)
    );

    // io_oe[2] is the design's SDA pull-down indicator.
    assign m_sda = io_oe[BIT_SDA] ? 1'b0 : 1'bz;

    // -----------------------------------------------------------------
    // Analog front-end behavioral model: T2F pulse train for a set
    // temperature, using the parameters fitted from ngspice.
    // -----------------------------------------------------------------
    logic [31:0] temp_x100 = 32'd2500;   // 0.01 C units
    wire         t2f_pulse;

    t2f_model #(.CLK_HZ(10.0e6)) u_t2f (
        .clk       (clock),
        .rstn      (reset_n),
        .temp_x100 (temp_x100),
        .t2f       (t2f_pulse)
    );

    // -----------------------------------------------------------------
    // Pad model: pull-ups resolve released lines high; the payload bits
    // the design does not use are tied off.
    // -----------------------------------------------------------------
    assign io_in[BIT_T2F] = t2f_pulse;
    assign io_in[BIT_SCL] = (m_scl === 1'b0) ? 1'b0 : 1'b1;
    assign io_in[BIT_SDA] = (m_sda === 1'b0) ? 1'b0 : 1'b1;
    assign io_in[IO_WIDTH-1:BIT_OS_INT] = '0;

    // -----------------------------------------------------------------
    // helpers
    // -----------------------------------------------------------------
    integer errors = 0;

    task automatic read_temp(output integer half_steps);
        reg [255:0] rd;
        reg [7:0]   msb, lsb;
        integer     raw;
        begin
            master.i2c_read_regs(I2C_ADDR, 8'h00, 2, rd);
            msb = rd[7:0];
            lsb = rd[15:8];
            raw = {23'b0, msb, lsb[7]};        // 9-bit two's complement
            half_steps = (raw >= 256) ? raw - 512 : raw;
        end
    endtask

    task automatic check_temp(input integer t_x100, input integer expect_half);
        integer got;
        begin
            temp_x100 = t_x100;
            #(MEASURE_WAIT);
            read_temp(got);
            if ((got - expect_half) <= 1 && (expect_half - got) <= 1) begin
                $display("PASS  T=%0d.%02d C  half-steps=%0d (expect %0d)",
                         t_x100/100, t_x100%100, got, expect_half);
            end else begin
                errors = errors + 1;
                $display("FAIL  T=%0d.%02d C  half-steps=%0d (expect %0d)",
                         t_x100/100, t_x100%100, got, expect_half);
            end
        end
    endtask

    task automatic read_reg(input [7:0] ptr, output [7:0] value);
        reg [255:0] rd;
        begin
            master.i2c_read_regs(I2C_ADDR, ptr, 1, rd);
            value = rd[7:0];
        end
    endtask

    task automatic expect_reg(input [7:0] ptr, input [7:0] want,
                              input string name);
        reg [7:0] got;
        begin
            read_reg(ptr, got);
            if (got === want) begin
                $display("PASS  %0s = 0x%02x", name, got);
            end else begin
                errors = errors + 1;
                $display("FAIL  %0s = 0x%02x (expect 0x%02x)", name, got, want);
            end
        end
    endtask

    reg ack;

    initial begin
        // -----------------------------------------------------------------
        // 1) reset state on the payload bus
        // -----------------------------------------------------------------
        repeat (2) @(posedge clock);
        #1ns;

        if (io_out[BIT_HEARTBEAT] !== 1'b0) begin
            errors = errors + 1;  $display("FAIL  reset: heartbeat not 0");
        end
        if (io_oe[BIT_OS_INT] !== 1'b0) begin
            errors = errors + 1;  $display("FAIL  reset: os_int not released");
        end
        if (io_oe[BIT_SDA] !== 1'b0) begin
            errors = errors + 1;  $display("FAIL  reset: SDA not released");
        end
        if (io_oe[BIT_SHUTDOWN] !== 1'b1 || io_oe[BIT_HEARTBEAT] !== 1'b1) begin
            errors = errors + 1;  $display("FAIL  reset: push-pull outputs not enabled");
        end
        if (io_oe[IO_WIDTH-1:BIT_HEARTBEAT+1] !== '0) begin
            errors = errors + 1;  $display("FAIL  reset: stray output enables");
        end

        @(negedge clock);
        reset = 1'b0;
        repeat (4) @(posedge clock);
        #1ns;
        $display("-- reset released (10 MHz clock, 10 ms gate) --");

        // -----------------------------------------------------------------
        // 2) default thresholds must be readable before any conversion
        // -----------------------------------------------------------------
        expect_reg(8'h04, 8'h64, "TOS default (+100 C)");
        expect_reg(8'h03, 8'h4B, "Thyst default (+75 C)");

        // -----------------------------------------------------------------
        // 3) address ACK: our own address is acknowledged, others are not
        // -----------------------------------------------------------------
        master.i2c_start;
        master.i2c_write_byte({I2C_ADDR, 1'b0}, ack);
        master.i2c_stop;
        if (ack === 1'b1) begin
            $display("PASS  address 0x%02x acknowledged", I2C_ADDR);
        end else begin
            errors = errors + 1;
            $display("FAIL  address 0x%02x not acknowledged", I2C_ADDR);
        end
        repeat (4) @(posedge clock);

        master.i2c_start;
        master.i2c_write_byte({7'h50, 1'b0}, ack);
        master.i2c_stop;
        if (ack === 1'b0) begin
            $display("PASS  foreign address 0x50 NACKed");
        end else begin
            errors = errors + 1;
            $display("FAIL  foreign address 0x50 was acknowledged");
        end
        repeat (4) @(posedge clock);

        // -----------------------------------------------------------------
        // 4) temperature read-back at, below and above the breakpoints
        // -----------------------------------------------------------------
        check_temp( 2500,  50);   //  25.00 C, mid-segment
        check_temp(-4000, -80);   // -40.00 C, lowest breakpoint
        check_temp(    0,   0);   //   0.00 C, breakpoint
        check_temp( 8500, 170);   //  85.00 C, mid-segment
        check_temp(12500, 250);   // 125.00 C, highest breakpoint

        // -----------------------------------------------------------------
        // 5) os_int: TOS defaults to +100 C, so 125 C must pull it low
        // -----------------------------------------------------------------
        if (io_oe[BIT_OS_INT] === 1'b1 && io_out[BIT_OS_INT] === 1'b0) begin
            $display("PASS  os_int asserted at 125 C");
        end else begin
            errors = errors + 1;
            $display("FAIL  os_int not asserted at 125 C (oe=%b out=%b)",
                     io_oe[BIT_OS_INT], io_out[BIT_OS_INT]);
        end

        // -----------------------------------------------------------------
        // 6) threshold write-through
        // -----------------------------------------------------------------
        master.i2c_write_reg(I2C_ADDR, 8'h04, 8'h50, ack);   // TOS = +80 C
        master.i2c_write_reg(I2C_ADDR, 8'h03, 8'h3C, ack);   // Thyst = +60 C
        repeat (4) @(posedge clock);
        expect_reg(8'h04, 8'h50, "TOS after write");
        expect_reg(8'h03, 8'h3C, "Thyst after write");

        // -----------------------------------------------------------------
        if (errors == 0)
            $display("USER TEMP SENSOR UNIT TEST PASS");
        else
            $display("USER TEMP SENSOR UNIT TEST FAIL: %0d error(s)", errors);
        $finish;
    end

endmodule
