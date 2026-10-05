// =====================================================================
// chip_tb.sv -- chip-level functional test of the merged netlist
//
// Drives the PACKAGE PINS of chip_top and reads temperature back over the
// I2C bus, exactly as a board would.  This proves the merged netlist
// elaborates and that the analog macro view, the level conditioner, the
// POR, the clock and the hardened digital macro are wired together
// correctly.
//
//   analog model (u_afe, CHIP_SIM) -> fout_ana
//     -> u_inbuf -> t2f_dig -> u_dig.t2f_in
//     -> temp_engine -> temp_regs -> i2c_slave
//     -> pad SDA -> i2c_master_model -> read-back
//
// Build with:
//   +define+CHIP_SIM +define+CHIP_SIM_POR_NS=20000
//
// What this test does NOT cover:
//   * the real analog front-end (SPICE).  u_afe is replaced by the
//     behavioural model, so nothing here validates PTAT/CSRO behaviour,
//     start-up, corners or mismatch.
//   * the real pads.  pad_signal.v are abstract stand-ins; ESD, level
//     shifting, drive strength and leakage are untested.
//   * the real clock.  clkgen.v is behavioural; the clock-accuracy
//     requirement documented there is not exercised except by injection.
// =====================================================================

`timescale 1ns/1ps

module chip_tb;

    localparam logic [6:0] I2C_ADDR = 7'h48;
    localparam int  I2C_SCL_HALF   = 25;      // 25 core clocks per half
    localparam time MEASURE_WAIT   = 20ms;    // one 10 ms gate plus margin
    localparam real VDD_CORE       = 1.2;
    localparam real VDD_IO         = 3.3;

    // ---- package pins ------------------------------------------------
    wire VDDD = 1'b1, VSSD = 1'b0;
    wire VDDA = 1'b1, VSSA = 1'b0;
    wire VDDIO = 1'b1, VSSIO = 1'b0;

    tri  SCL;
    tri  SDA;
    wire OS_INT;
    wire T2F_MON;

    // ---- board: I2C pull-ups and an open-drain master -----------------
    // SDA is driven by the chip's open-drain pad and by the master; the
    // pull-up supplies the high level.
    pullup(SCL);
    pullup(SDA);
    pullup(OS_INT);          // OS_INT is open-drain, needs a pull-up

    // The I2C master runs on the chip clock, as in the existing tests.
    wire clk_obs;
    assign clk_obs = dut.clk;

    i2c_master_model #(.SCL_HALF(I2C_SCL_HALF)) master (
        .scl (SCL),
        .sda (SDA),
        .clk (clk_obs)
    );

    // ---- chip under test ---------------------------------------------
    chip_top dut (
        .VDDD (VDDD), .VSSD (VSSD),
        .VDDA (VDDA), .VSSA (VSSA),
        .VDDIO(VDDIO), .VSSIO(VSSIO),
        .SCL  (SCL),
        .SDA  (SDA),
        .OS_INT (OS_INT),
        .T2F_MON (T2F_MON)
    );

    integer errors = 0;

    task automatic read_reg(input [7:0] ptr, output [7:0] value);
        reg [255:0] rd;
        begin
            master.i2c_read_regs(I2C_ADDR, ptr, 1, rd);
            value = rd[7:0];
        end
    endtask

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
            dut.u_afe.TEMP_X100 = t_x100;
            #(MEASURE_WAIT);
            read_temp(got);
            if ((got - expect_half) <= 1 && (expect_half - got) <= 1) begin
                $display("PASS  chip T=%0d.%02d C  half-steps=%0d (expect %0d)",
                         t_x100/100, t_x100%100, got, expect_half);
            end else begin
                errors = errors + 1;
                $display("FAIL  chip T=%0d.%02d C  half-steps=%0d (expect %0d)",
                         t_x100/100, t_x100%100, got, expect_half);
            end
        end
    endtask

    reg [7:0] v;

    initial begin
        // let POR release and the oscillator settle
        #(30_000);
        repeat (20) @(posedge clk_obs);
        #1ns;

        $display("-- chip out of reset, running from the behavioural AFE --");

        // 1) register access through the package pins
        read_reg(8'h04, v);
        if (v === 8'h64) $display("PASS  chip TOS default = 0x%02x", v);
        else begin errors = errors + 1;
                     $display("FAIL  chip TOS default = 0x%02x (expect 0x64)", v); end

        read_reg(8'h03, v);
        if (v === 8'h4B) $display("PASS  chip Thyst default = 0x%02x", v);
        else begin errors = errors + 1;
                     $display("FAIL  chip Thyst default = 0x%02x (expect 0x4b)", v); end

        // 2) closed-loop temperature read-back over the pins
        check_temp( 2500,  50);    //  25.00 C
        check_temp(12500, 250);    // 125.00 C, above the +100 C default TOS

        // 3) the alert must pull its pin low, and the pull-up must read high
        //    when released
        if (OS_INT === 1'b0) $display("PASS  chip OS_INT asserted at 125 C");
        else begin errors = errors + 1;
                     $display("FAIL  chip OS_INT = %b at 125 C (expect 0)", OS_INT); end

        check_temp(    0,   0);    //   0.00 C, below Thyst

        if (OS_INT === 1'b1) $display("PASS  chip OS_INT released at 0 C");
        else begin errors = errors + 1;
                     $display("FAIL  chip OS_INT = %b at 0 C (expect 1)", OS_INT); end

        // 4) the analog monitor pin should be toggling (board loads it)
        begin
            logic a, b;
            // sample 1 us apart: a half period of the slowest T2F edge
            // (0.5 MHz -> 1 us) so the two samples cannot alias
            a = T2F_MON;
            repeat (10) @(posedge clk_obs);
            b = T2F_MON;
            if (a === b) begin
                errors = errors + 1;
                $display("FAIL  T2F_MON not toggling");
            end else $display("PASS  T2F_MON toggling");
        end

        if (errors == 0) $display("CHIP-LEVEL MERGED NETLIST TEST PASS");
        else             $display("CHIP-LEVEL MERGED NETLIST TEST FAIL: %0d error(s)", errors);
        $finish;
    end

    // ---- supply monitors (sanity: the macro views must not float) -----
    initial begin
        #(5_000);
        if (dut.VDDA !== 1'b1 || dut.VSSA !== 1'b0) begin
            $display("FAIL  analog supply not connected in the netlist");
            errors = errors + 1;
        end
    end

endmodule
