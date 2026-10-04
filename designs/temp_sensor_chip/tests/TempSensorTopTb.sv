// =====================================================================
// TempSensorTopTb.sv -- unit test for TempSensorTop
//
// Tests the design without the mpc-frame top level.  `reset` is
// active-high, matching the Frame contract.
//
// Checks:
//   1. reset values: heartbeat 0, os_int released, shutdown 0
//   2. after reset: heartbeat toggles, os_int stays released while
//      the temperature is below TOS, shutdown stays 0
//   3. unused payload bits are never driven
// =====================================================================

module TempSensorTopDut;

    localparam int IO_WIDTH = 66;
    localparam time HALF_PERIOD = 5ns;

    logic clock = 1'b0;
    logic reset = 1'b1;
    logic [IO_WIDTH-1:0] io_in = '0;
    wire [IO_WIDTH-1:0] io_out;
    wire [IO_WIDTH-1:0] io_oe;

    always #(HALF_PERIOD) clock = ~clock;

    TempSensorTop #(.IO_WIDTH(IO_WIDTH)) dut (
        .clock(clock), .reset(reset), .io_in(io_in),
        .io_out(io_out), .io_oe(io_oe)
    );

    // os_int is open-drain: oe=1 asserts (drive low), oe=0 releases.
    wire os_int_released = ~io_oe[0];
    // shutdown is push-pull: oe=1 always enabled.
    wire shutdown_driven = io_oe[3];

    initial begin
        // -----------------------------------------------------------------
        // 1) reset state
        // -----------------------------------------------------------------
        repeat (2) @(posedge clock);
        #1ns;

        if (io_out[4] !== 1'b0)
            $fatal(1, "reset: heartbeat not 0");
        if (os_int_released !== 1'b1)
            $fatal(1, "reset: os_int not released");
        if (io_out[3] !== 1'b0)
            $fatal(1, "reset: shutdown not 0");

        // no unused payload bit may be driven
        if (io_oe[1] !== 1'b0 || io_oe[2] !== 1'b0)
            $fatal(1, "reset: i2c output enables unexpectedly driven");
        if (io_oe[IO_WIDTH-1:5] !== '0)
            $fatal(1, "reset: unused outputs unexpectedly enabled");

        // -----------------------------------------------------------------
        // 2) release reset
        // -----------------------------------------------------------------
        @(negedge clock);
        reset = 1'b0;
        repeat (2) @(posedge clock);
        #1ns;

        // heartbeat must be running
        begin
            logic heartbeat_a, heartbeat_b;
            heartbeat_a = io_out[4];
            repeat (1) @(posedge clock);
            #1ns;
            heartbeat_b = io_out[4];
            if (heartbeat_a === heartbeat_b)
                $fatal(1, "heartbeat did not toggle after reset release");
        end

        // shutdown still 0, and still driven
        if (io_out[3] !== 1'b0)
            $fatal(1, "shutdown not 0 after reset release");
        if (shutdown_driven !== 1'b1)
            $fatal(1, "shutdown output enable not asserted");

        // temperature starts at 0C, TOS defaults above it -> no alert
        if (os_int_released !== 1'b1)
            $fatal(1, "os_int asserted without an over-temperature condition");

        // unused bits stay off
        if (io_oe[IO_WIDTH-1:5] !== '0)
            $fatal(1, "unused outputs unexpectedly enabled after reset");

        // -----------------------------------------------------------------
        // 3) t2f_in is a pad input: driving it must not disturb outputs
        // -----------------------------------------------------------------
        io_in[0] = 1'b1;
        repeat (4) @(posedge clock);
        #1ns;
        if (os_int_released !== 1'b1)
            $fatal(1, "os_int asserted while temperature is below TOS");
        if (io_oe[IO_WIDTH-1:5] !== '0)
            $fatal(1, "unused outputs drove during t2f_in activity");

        $display("USER TEMP SENSOR UNIT TEST PASS");
        $finish;
    end

endmodule
