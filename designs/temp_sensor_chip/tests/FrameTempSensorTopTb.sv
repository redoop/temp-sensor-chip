// =====================================================================
// FrameTempSensorTopTb.sv -- Frame integration test for temp_sensor_chip
//
// Signals travel through external user_io, FrameTop, and the design.
// This test checks:
//   1. design ID is selected through FrameTop during reset
//   2. t2f_in (io_in[0]) reaches the pad from the Frame payload
//   3. heartbeat (io_out[4]) toggles out to user_io[11]
//   4. shutdown (io_out[3]) drives user_io[10] low
//
// Keep the selection sequence; edit the functional checks.
// =====================================================================

module FrameTempSensorTopTb;

    // usually keep / 通常保留:
    localparam int IO_WIDTH = 73;
    localparam int DESIGN_ID_WIDTH = 7;
    `ifndef FRAME_TEST_DESIGN_ID
      initial $error("FRAME_TEST_DESIGN_ID must be provided by the build tool");
    `endif
    localparam logic [DESIGN_ID_WIDTH-1:0] DESIGN_ID = `FRAME_TEST_DESIGN_ID;
    localparam time HALF_PERIOD = 5ns;

    logic clock = 1'b0;
    logic reset = 1'b1;
    logic [IO_WIDTH-1:0] test_io_out = '0;
    logic [IO_WIDTH-1:0] test_io_oe = '0;
    tri  [IO_WIDTH-1:0] user_io;

    always #(HALF_PERIOD) clock = ~clock;

    // usually keep / 通常保留:
    for (genvar io_index = 0; io_index < IO_WIDTH; io_index++) begin : gen_test_io
        assign user_io[io_index] = test_io_oe[io_index]
            ? test_io_out[io_index]
            : 1'bz;
    end

    FrameTop dut (
        .clock(clock), .reset(reset), .user_io(user_io)
    );

    initial begin
        // -----------------------------------------------------------------
        // usually keep / 通常保留:
        // During reset=1, drive DESIGN_ID on user_io[6:0].
        // FrameTop reads ID only during reset; changes after reset
        // release do not switch designs.
        // -----------------------------------------------------------------
        test_io_oe[DESIGN_ID_WIDTH-1:0] = '1;
        test_io_out[DESIGN_ID_WIDTH-1:0] = DESIGN_ID;
        repeat (20) @(posedge clock);
        @(negedge clock);
        reset = 1'b0;
        repeat (20) @(posedge clock);
        #1ns;

        if (!dut.selection_valid || !dut.design_selected[DESIGN_ID])
            $fatal(1, "design was not selected through FrameTop");

        // -----------------------------------------------------------------
        // functional checks / 功能检查:
        //
        // Payload mapping: design io_*[n] <-> user_io[n + DESIGN_ID_WIDTH].
        //   t2f_in    -> io_in [0]  -> user_io[7]
        //   os_int    -> io_out[0]  -> user_io[7]  (same pin, bidirectional)
        //   heartbeat -> io_out[4]  -> user_io[11]
        // -----------------------------------------------------------------

        // 1) t2f_in path: drive user_io[7] (t2f_in), check it appears
        //    as io_in[0] on the design side.
        test_io_oe[DESIGN_ID_WIDTH + 0] = 1'b1;
        test_io_out[DESIGN_ID_WIDTH + 0] = 1'b1;
        #1ns;
        if (user_io[DESIGN_ID_WIDTH + 0] !== 1'b1)
            $fatal(1, "t2f_in did not reach FrameTop");

        // 2) t2f_in release: stop driving the pad so the design owns it.
        //    os_int is open-drain and only pulls low, so no contention.
        test_io_oe[DESIGN_ID_WIDTH + 0] = 1'b0;

        // 3) heartbeat: io_out[4] drives user_io[11] and must toggle.
        //    Sample it twice a half period apart to prove it is running.
        #(HALF_PERIOD);
        begin
            logic heartbeat_first;
            heartbeat_first = user_io[DESIGN_ID_WIDTH + 4];
            if (heartbeat_first === 1'bz)
                $fatal(1, "heartbeat path is inactive (high-Z)");
            #(HALF_PERIOD * 2);
            if (user_io[DESIGN_ID_WIDTH + 4] === 1'bz)
                $fatal(1, "heartbeat path went high-Z");
            if (user_io[DESIGN_ID_WIDTH + 4] === heartbeat_first)
                $fatal(1, "heartbeat did not toggle on user_io");
        end

        // 4) shutdown (io_out[3]) is push-pull low after reset.
        if (user_io[DESIGN_ID_WIDTH + 3] !== 1'b0)
            $fatal(1, "shutdown output did not drive low");

        $display("USER TEMP SENSOR FRAME TEST PASS");
        $finish;
    end

endmodule
