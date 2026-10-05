// =====================================================================
// tb_gl.sv -- gate-level simulation of the ICS55 post-route netlist
//
// Independently verifies the hardened netlist (not the RTL) by closing
// the same loop the RTL tests close:
//   t2f_model -> t2f_in -> [gate netlist] -> I2C read-back
//
// The netlist was hardened from temp_sensor_block, whose open-drain pads
// are value+enable pairs:
//   sda_o/sda_oe      I2C SDA pull-down
//   os_int_o/os_int_oe  over-temperature alert pull-down
// =====================================================================
`timescale 1ns/1ps

module tb_gl;

    localparam time CLK_HALF      = 50ns;   // 10 MHz, required by GATE_CYCLES
    localparam int  I2C_SCL_HALF  = 25;
    localparam logic [6:0] I2C_ADDR = 7'h48;
    localparam time MEASURE_WAIT  = 20ms;   // one 10 ms gate plus margin

    logic clk  = 1'b0;
    logic rstn = 1'b0;
    wire  t2f_in;
    wire  scl_i, sda_i;
    wire  sda_o, sda_oe, os_int_o, os_int_oe;

    always #(CLK_HALF) clk = ~clk;

    // ---- board: I2C bus with pull-ups and an open-drain master ----
    tri m_scl, m_sda;
    pullup(m_scl);
    pullup(m_sda);

    i2c_master_model #(.SCL_HALF(I2C_SCL_HALF)) master (
        .scl (m_scl),
        .sda (m_sda),
        .clk (clk)
    );

    // The netlist's open-drain SDA pull-down must be visible to the
    // master (so it samples the ACK), but it must NOT be fed back into
    // the block: the block already resolves its own pull-down with
    // sda_bus = sda_oe ? 0 : sda_i.  Feeding it back would close a
    // zero-delay loop (sda_oe -> pad -> sda_i -> block -> sda_oe).
    // The pad input therefore follows the master's own driver only,
    // read through the BFM's open-drain control signals.
    assign m_sda = sda_oe ? 1'b0 : 1'bz;

    wire master_scl_low = (master.scl_drv === 1'b0);
    wire master_sda_low = (master.sda_drv === 1'b0);

    assign scl_i = master_scl_low ? 1'b0 : 1'b1;
    assign sda_i = master_sda_low ? 1'b0 : 1'b1;

    // ---- analog front-end behavioral model (ngspice characterization) ----
    logic [31:0] temp_x100 = 32'd2500;
    t2f_model #(.CLK_HZ(10.0e6)) u_t2f (
        .clk       (clk),
        .rstn      (rstn),
        .temp_x100 (temp_x100),
        .t2f       (t2f_in)
    );

    // ---- post-route gate-level netlist under test ----
    temp_sensor_block dut (
        .clk       (clk),
        .rstn      (rstn),
        .t2f_in    (t2f_in),
        .scl_i     (scl_i),
        .sda_i     (sda_i),
        .sda_o     (sda_o),
        .sda_oe    (sda_oe),
        .os_int_o  (os_int_o),
        .os_int_oe (os_int_oe)
    );

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
                $display("PASS  GL T=%0d.%02d C  half-steps=%0d (expect %0d)",
                         t_x100/100, t_x100%100, got, expect_half);
            end else begin
                errors = errors + 1;
                $display("FAIL  GL T=%0d.%02d C  half-steps=%0d (expect %0d)",
                         t_x100/100, t_x100%100, got, expect_half);
            end
        end
    endtask

    initial begin
        repeat (4) @(posedge clk);
        rstn = 1'b1;
        repeat (4) @(posedge clk);
        #1ns;

        // decisive probe: does the slave acknowledge its own address?
        begin
            reg ack_probe;
            master.i2c_start;
            master.i2c_write_byte({I2C_ADDR, 1'b0}, ack_probe);
            master.i2c_stop;
            $display("DEBUG GL address 0x%02x ack=%b", I2C_ADDR, ack_probe);
            $display("DEBUG GL scl_i=%b sda_i=%b rstn=%b", scl_i, sda_i, rstn);
        end
        repeat (4) @(posedge clk);

        // debug: read the default thresholds first.  If these come back
        // correctly the I2C read path works and any temperature mismatch
        // is in the measurement path instead.
        begin
            reg [255:0] rd;
            master.i2c_read_regs(I2C_ADDR, 8'h04, 1, rd);
            $display("DEBUG GL TOS(0x04) = 0x%02x (expect 0x64)", rd[7:0]);
            master.i2c_read_regs(I2C_ADDR, 8'h03, 1, rd);
            $display("DEBUG GL Thyst(0x03) = 0x%02x (expect 0x4b)", rd[7:0]);
            master.i2c_read_regs(I2C_ADDR, 8'h00, 2, rd);
            $display("DEBUG GL temp regs = 0x%02x 0x%02x", rd[7:0], rd[15:8]);
        end

        // baseline: temperature 0-ish reads low, alert released
        check_temp( 2500,  50);   //  25.00 C
        check_temp(12500, 250);   // 125.00 C, above the +100 C default TOS

        if (os_int_oe === 1'b1 && os_int_o === 1'b0) begin
            $display("PASS  GL os_int asserted at 125 C");
        end else begin
            errors = errors + 1;
            $display("FAIL  GL os_int not asserted at 125 C (oe=%b o=%b)",
                     os_int_oe, os_int_o);
        end

        check_temp(    0,   0);   //   0.00 C, back below Thyst

        if (os_int_oe === 1'b0) begin
            $display("PASS  GL os_int released at 0 C");
        end else begin
            errors = errors + 1;
            $display("FAIL  GL os_int still asserted at 0 C (oe=%b)", os_int_oe);
        end

        // the open-drain value outputs must stay low
        if (sda_o !== 1'b0 || os_int_o !== 1'b0) begin
            errors = errors + 1;
            $display("FAIL  GL open-drain value outputs not low (sda_o=%b os_int_o=%b)",
                     sda_o, os_int_o);
        end

        if (errors == 0)
            $display("GATE-LEVEL NETLIST TEST PASS");
        else
            $display("GATE-LEVEL NETLIST TEST FAIL: %0d error(s)", errors);
        $finish;
    end

endmodule
