`timescale 1ns / 1ps
//
// cordic_log_tb.v - Self-checking testbench for cordic_log_top
//

module cordic_log_tb;

    // ----------------------------------------------------------------
    // Parameters  (must match DUT)
    // ----------------------------------------------------------------
    parameter INPUT_WIDTH = 32;
    parameter FRAC_BITS   = 16;

    function integer clog2_f;
        input integer n;
        integer m;
        begin
            m = n - 1;
            clog2_f = 0;
            while (m > 0) begin
                m = m >> 1;
                clog2_f = clog2_f + 1;
            end
        end
    endfunction

    localparam LOG2_INT_BITS = clog2_f(INPUT_WIDTH) + 1;
    localparam LOG2_WIDTH    = LOG2_INT_BITS + FRAC_BITS;

    // ----------------------------------------------------------------
    // DUT signals
    // ----------------------------------------------------------------
    reg                        clk;
    reg                        rst_n;
    reg                        start;
    reg  [INPUT_WIDTH-1:0]     input_val;
    wire                       done;
    wire [LOG2_WIDTH-1:0]      log2_out;
    wire [LOG2_WIDTH-1:0]      ln_out;
    wire [LOG2_WIDTH-1:0]      log10_out;
    wire                       err_zero;

    // ----------------------------------------------------------------
    // DUT instantiation
    // ----------------------------------------------------------------
    cordic_log_top #(
        .INPUT_WIDTH (INPUT_WIDTH),
        .FRAC_BITS   (FRAC_BITS)
    ) dut (
        .clk       (clk),
        .rst_n     (rst_n),
        .start     (start),
        .input_val (input_val),
        .done      (done),
        .log2_out  (log2_out),
        .ln_out    (ln_out),
        .log10_out (log10_out),
        .err_zero  (err_zero)
    );

    // ----------------------------------------------------------------
    // Clock: 10 ns period
    // ----------------------------------------------------------------
    initial clk = 1'b0;
    always #5 clk = ~clk;

    // ----------------------------------------------------------------
    // Scoreboard counters
    // ----------------------------------------------------------------
    integer pass_cnt;
    integer fail_cnt;
    integer test_num;

    // ----------------------------------------------------------------
    // Fixed-point scaling factor as a real
    // ----------------------------------------------------------------
    real scale;
    initial begin
        scale = 1.0;
        begin : calc_scale
            integer i;
            for (i = 0; i < FRAC_BITS; i = i + 1)
                scale = scale * 2.0;
        end
    end

    // ----------------------------------------------------------------
    // Task: apply one stimulus and check all three outputs
    // ----------------------------------------------------------------
    task automatic run_and_check;
        input [INPUT_WIDTH-1:0] val;
        real exp_log2, exp_ln, exp_log10;
        real act_log2, act_ln, act_log10;
        real err_log2, err_ln, err_log10;
        real tol_log2, tol_conv;
        begin
            test_num = test_num + 1;

            // log2 tolerance: 8 ULPs from CORDIC + LUT quantization
            tol_log2 = 8.0 / scale;

            // Drive DUT: set signals after posedge with #1 to avoid races
            @(posedge clk); #1;
            input_val = val;
            start     = 1;
            @(posedge clk); #1;
            start     = 0;

            // Wait for done from any previous computation to clear
            while (done) @(posedge clk);
            // Wait for this computation to complete
            while (!done) @(posedge clk);
            @(posedge clk); #1;  // one more cycle to let outputs settle

            if (val == 0) begin
                if (err_zero) begin
                    $display("[%0d] PASS  input=0  err_zero asserted correctly", test_num);
                    pass_cnt = pass_cnt + 1;
                end else begin
                    $display("[%0d] FAIL  input=0  err_zero NOT asserted", test_num);
                    fail_cnt = fail_cnt + 1;
                end
            end else begin
                // Compute expected values using IEEE real math
                exp_log2  = $ln(1.0 * val) / $ln(2.0);
                exp_ln    = $ln(1.0 * val);
                exp_log10 = $log10(1.0 * val);

                // ln/log10 tolerance: log2 error * const + value-dependent
                // constant quantization error (scales with log2 magnitude)
                tol_conv = tol_log2 + (exp_log2 + 1.0) * 1.0 / scale;

                // Convert DUT fixed-point outputs to real
                act_log2  = (1.0 * log2_out)  / scale;
                act_ln    = (1.0 * ln_out)     / scale;
                act_log10 = (1.0 * log10_out)  / scale;

                err_log2  = act_log2  - exp_log2;
                err_ln    = act_ln    - exp_ln;
                err_log10 = act_log10 - exp_log10;
                if (err_log2  < 0.0) err_log2  = -err_log2;
                if (err_ln    < 0.0) err_ln    = -err_ln;
                if (err_log10 < 0.0) err_log10 = -err_log10;

                if (err_log2 > tol_log2) begin
                    $display("[%0d] FAIL  val=%0d  log2: exp=%f  got=%f  err=%f (tol=%f)",
                             test_num, val, exp_log2, act_log2, err_log2, tol_log2);
                    fail_cnt = fail_cnt + 1;
                end else if (err_ln > tol_conv) begin
                    $display("[%0d] FAIL  val=%0d  ln:   exp=%f  got=%f  err=%f (tol=%f)",
                             test_num, val, exp_ln, act_ln, err_ln, tol_conv);
                    fail_cnt = fail_cnt + 1;
                end else if (err_log10 > tol_conv) begin
                    $display("[%0d] FAIL  val=%0d  log10:exp=%f  got=%f  err=%f (tol=%f)",
                             test_num, val, exp_log10, act_log10, err_log10, tol_conv);
                    fail_cnt = fail_cnt + 1;
                end else begin
                    $display("[%0d] PASS  val=%0d  log2=%f (exp %f)  ln=%f  log10=%f",
                             test_num, val, act_log2, exp_log2, act_ln, act_log10);
                    pass_cnt = pass_cnt + 1;
                end
            end
        end
    endtask

    // ----------------------------------------------------------------
    // Main test sequence
    // ----------------------------------------------------------------
    integer idx;

    initial begin
        $dumpfile("cordic_log.vcd");
        $dumpvars(0, cordic_log_tb);

        pass_cnt  = 0;
        fail_cnt  = 0;
        test_num  = 0;
        rst_n     = 1'b0;
        start     = 1'b0;
        input_val = {INPUT_WIDTH{1'b0}};

        // Reset
        repeat (4) @(posedge clk);
        rst_n = 1'b1;
        repeat (2) @(posedge clk);

        $display("========================================================");
        $display(" CORDIC Logarithm Testbench  (INPUT_WIDTH=%0d, FRAC=%0d)",
                 INPUT_WIDTH, FRAC_BITS);
        $display("========================================================");

        // --- Edge case: zero input ---
        $display("\n--- Zero input (expect err_zero) ---");
        run_and_check(0);

        // --- Exact powers of two (log2 should be integer) ---
        $display("\n--- Powers of 2 ---");
        for (idx = 0; idx < INPUT_WIDTH; idx = idx + 1) begin
            run_and_check(1 << idx);
        end

        // --- Specific known values ---
        $display("\n--- Known values ---");
        run_and_check(32'd3);
        run_and_check(32'd5);
        run_and_check(32'd7);
        run_and_check(32'd10);
        run_and_check(32'd12);
        run_and_check(32'd15);
        run_and_check(32'd100);
        run_and_check(32'd255);
        run_and_check(32'd256);
        run_and_check(32'd1000);
        run_and_check(32'd1023);
        run_and_check(32'd1024);
        run_and_check(32'd4096);
        run_and_check(32'd12345);
        run_and_check(32'd65535);
        run_and_check(32'd65536);
        run_and_check(32'd100000);
        run_and_check(32'd1000000);
        run_and_check(32'd16777216);    // 2^24
        run_and_check(32'd123456789);
        run_and_check(32'd1073741824);  // 2^30
        run_and_check(32'd2147483647);  // 2^31 - 1
        run_and_check(32'hFFFFFFFF);    // 2^32 - 1

        // --- Summary ---
        $display("\n========================================================");
        $display(" RESULTS:  %0d PASSED,  %0d FAILED  (of %0d tests)",
                 pass_cnt, fail_cnt, pass_cnt + fail_cnt);
        $display("========================================================");

        if (fail_cnt == 0)
            $display(" ** ALL TESTS PASSED **\n");
        else
            $display(" ** SOME TESTS FAILED **\n");

        $finish;
    end

    // ----------------------------------------------------------------
    // Timeout watchdog
    // ----------------------------------------------------------------
    initial begin
        #1000000;
        $display("ERROR: simulation timed out");
        $finish;
    end

endmodule
