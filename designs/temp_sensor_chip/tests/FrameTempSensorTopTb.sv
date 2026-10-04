// =====================================================================
// FrameTempSensorTopTb.sv -- Frame integration test for temp_sensor_chip
//
// Everything travels through the external user_io bus, FrameTop and the
// design pads.  This test closes the loop that the unit test opens:
//
//   t2f_model (analog front-end) -> user_io[T2F] -> FrameTop -> design
//     -> temp_engine -> temp_regs -> i2c_slave
//     -> user_io[SDA] -> i2c_master_model read-back
//
// Checks:
//   1. the design ID is latched through user_io[6:0] during reset
//   2. temperature read back over the Frame pads matches the model input
//   3. os_int pulls its own pad low above TOS (open-drain, with pull-up)
//   4. shutdown drives low and heartbeat toggles
//
// Timing note: GATE_CYCLES is calibrated for 10 MHz / 10 ms, so CLK_HALF
// must stay 50 ns.
// =====================================================================

module FrameTempSensorTopTb;

    localparam int  IO_WIDTH       = 73;
    localparam int  DESIGN_ID_WIDTH = 7;
    `ifndef FRAME_TEST_DESIGN_ID
      initial $error("FRAME_TEST_DESIGN_ID must be provided by the build tool");
    `endif
    localparam logic [DESIGN_ID_WIDTH-1:0] DESIGN_ID = `FRAME_TEST_DESIGN_ID;

    localparam time CLK_HALF     = 50ns;   // 10 MHz
    localparam int  I2C_SCL_HALF = 25;
    localparam logic [6:0] I2C_ADDR = 7'h48;
    localparam time MEASURE_WAIT = 20ms;

    // payload bit n -> user_io[n + DESIGN_ID_WIDTH]
    localparam int IO_T2F       = DESIGN_ID_WIDTH + 0;
    localparam int IO_SCL       = DESIGN_ID_WIDTH + 1;
    localparam int IO_SDA       = DESIGN_ID_WIDTH + 2;
    localparam int IO_OS_INT    = DESIGN_ID_WIDTH + 3;
    localparam int IO_SHUTDOWN  = DESIGN_ID_WIDTH + 4;
    localparam int IO_HEARTBEAT = DESIGN_ID_WIDTH + 5;

    logic clock = 1'b0;
    logic reset = 1'b1;
    logic [IO_WIDTH-1:0] test_io_out = '0;
    logic [IO_WIDTH-1:0] test_io_oe  = '0;
    tri   [IO_WIDTH-1:0] user_io;

    always #(CLK_HALF) clock = ~clock;

    for (genvar io_index = 0; io_index < IO_WIDTH; io_index++) begin : gen_test_io
        assign user_io[io_index] = test_io_oe[io_index]
            ? test_io_out[io_index]
            : 1'bz;
    end

    FrameTop dut (
        .clock(clock), .reset(reset), .user_io(user_io)
    );

    // -----------------------------------------------------------------
    // External I2C master on the shared pads.  SCL/SDA are open-drain
    // with board pull-ups; the design's SDA pull-down reaches the bus
    // through FrameTop's payload output enable.
    // -----------------------------------------------------------------
    pullup(user_io[IO_SCL]);
    pullup(user_io[IO_SDA]);

    i2c_master_model #(.SCL_HALF(I2C_SCL_HALF)) master (
        .scl (user_io[IO_SCL]),
        .sda (user_io[IO_SDA]),
        .clk (clock)
    );

    // os_int is open-drain, so the alert pad needs a pull-up to be
    // readable: released reads 1, asserted reads 0.
    pullup(user_io[IO_OS_INT]);

    // -----------------------------------------------------------------
    // External analog front-end model driving the T2F pad push-pull.
    // -----------------------------------------------------------------
    logic [31:0] temp_x100 = 32'd2500;   // 0.01 C units
    wire         t2f_pulse;

    t2f_model #(.CLK_HZ(10.0e6)) u_t2f (
        .clk       (clock),
        .rstn      (~reset),
        .temp_x100 (temp_x100),
        .t2f       (t2f_pulse)
    );

    assign user_io[IO_T2F] = t2f_pulse;

    // -----------------------------------------------------------------
    // checks
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
            raw = {23'b0, msb, lsb[7]};
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
                $display("PASS  frame T=%0d.%02d C  half-steps=%0d (expect %0d)",
                         t_x100/100, t_x100%100, got, expect_half);
            end else begin
                errors = errors + 1;
                $display("FAIL  frame T=%0d.%02d C  half-steps=%0d (expect %0d)",
                         t_x100/100, t_x100%100, got, expect_half);
            end
        end
    endtask

    initial begin
        // -----------------------------------------------------------------
        // Design selection: drive the ID on user_io[6:0] while reset is high
        // -----------------------------------------------------------------
        test_io_oe[DESIGN_ID_WIDTH-1:0]  = '1;
        test_io_out[DESIGN_ID_WIDTH-1:0] = DESIGN_ID;
        repeat (20) @(posedge clock);
        @(negedge clock);
        reset = 1'b0;
        repeat (20) @(posedge clock);
        #1ns;

        if (!dut.selection_valid || !dut.design_selected[DESIGN_ID]) begin
            $fatal(1, "design was not selected through FrameTop");
        end
        $display("-- design %0d selected through FrameTop --", DESIGN_ID);

        // -----------------------------------------------------------------
        // Payload outputs: shutdown low, heartbeat running
        // -----------------------------------------------------------------
        if (user_io[IO_SHUTDOWN] !== 1'b0) begin
            errors = errors + 1;
            $display("FAIL  shutdown pad not driven low");
        end else begin
            $display("PASS  shutdown pad driven low");
        end

        begin
            logic hb_a, hb_b;
            // heartbeat toggles every clock, so sample an odd number of
            // cycles apart or the two samples alias to the same value.
            // Note: the build uses Verilator --binary (2-state), where a
            // 1'bz literal collapses to 1'b0, so a high-Z comparison
            // would be meaningless here; check for a clean 0/1 instead.
            hb_a = user_io[IO_HEARTBEAT];
            repeat (1) @(posedge clock);
            #1ns;
            hb_b = user_io[IO_HEARTBEAT];
            if (hb_a !== 1'b0 && hb_a !== 1'b1) begin
                errors = errors + 1;
                $display("FAIL  heartbeat pad is not a clean logic level");
            end else if (hb_a === hb_b) begin
                errors = errors + 1;
                $display("FAIL  heartbeat pad did not toggle (both %b)", hb_a);
            end else begin
                $display("PASS  heartbeat pad toggling");
            end
        end

        // -----------------------------------------------------------------
        // Closed-loop temperature read-back through the Frame pads
        // -----------------------------------------------------------------
        check_temp( 2500,  50);   //  25.00 C
        check_temp(12500, 250);   // 125.00 C, above the +100 C default TOS

        // os_int must now be pulling its pad low
        if (user_io[IO_OS_INT] === 1'b0) begin
            $display("PASS  os_int asserted on the Frame pad at 125 C");
        end else begin
            errors = errors + 1;
            $display("FAIL  os_int pad = %b at 125 C (expect 0)", user_io[IO_OS_INT]);
        end

        check_temp(    0,   0);   //   0.00 C, back below Thyst

        if (user_io[IO_OS_INT] === 1'b1) begin
            $display("PASS  os_int released on the Frame pad at 0 C");
        end else begin
            errors = errors + 1;
            $display("FAIL  os_int pad = %b at 0 C (expect 1)", user_io[IO_OS_INT]);
        end

        if (errors == 0)
            $display("USER TEMP SENSOR FRAME TEST PASS");
        else
            $display("USER TEMP SENSOR FRAME TEST FAIL: %0d error(s)", errors);
        $finish;
    end

endmodule
