`timescale 1ns / 1ps
//
// cordic_log_top.v - Top-level wrapper providing log2, ln, and log10
//
// Instantiates the CORDIC log2 core and converts the result to
// natural log (ln) and common log (log10) via fixed-point multiplication:
//     ln(x)    = log2(x) * ln(2)
//     log10(x) = log2(x) * log10(2)
//

module cordic_log_top #(
    parameter INPUT_WIDTH = 32,
    parameter FRAC_BITS   = 16
) (
    input  wire                        clk,
    input  wire                        rst_n,
    input  wire                        start,
    input  wire [INPUT_WIDTH-1:0]      input_val,
    output wire                        done,
    output wire [LOG2_WIDTH-1:0]       log2_out,
    output wire [LOG2_WIDTH-1:0]       ln_out,
    output wire [LOG2_WIDTH-1:0]       log10_out,
    output wire                        err_zero
);

    // ----------------------------------------------------------------
    // Portable clog2 (mirrors the one in cordic_log2)
    // ----------------------------------------------------------------
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

    // ----------------------------------------------------------------
    // Derived parameters
    // ----------------------------------------------------------------
    localparam LOG2_INT_BITS = clog2_f(INPUT_WIDTH) + 1;
    localparam LOG2_WIDTH    = LOG2_INT_BITS + FRAC_BITS;

    // ----------------------------------------------------------------
    // Conversion constants at 32-bit precision, rounded to FRAC_BITS
    //   ln(2)    = 0.693147180559945...  -> 0xB17217F8
    //   log10(2) = 0.301029995663981...  -> 0x4D104D42
    // ----------------------------------------------------------------
    localparam [31:0] LN2_32     = 32'hB17217F8;
    localparam [31:0] LOG10_2_32 = 32'h4D104D42;
    localparam [31:0] ROUND_BIT  = 32'd1 << (31 - FRAC_BITS);

    localparam [FRAC_BITS-1:0] LN2_CONST     = (LN2_32     + ROUND_BIT) >> (32 - FRAC_BITS);
    localparam [FRAC_BITS-1:0] LOG10_2_CONST = (LOG10_2_32 + ROUND_BIT) >> (32 - FRAC_BITS);

    // ----------------------------------------------------------------
    // Core CORDIC log2 instance
    // ----------------------------------------------------------------
    wire [LOG2_WIDTH-1:0] log2_internal;

    cordic_log2 #(
        .INPUT_WIDTH (INPUT_WIDTH),
        .FRAC_BITS   (FRAC_BITS)
    ) u_cordic_log2 (
        .clk         (clk),
        .rst_n       (rst_n),
        .start       (start),
        .input_val   (input_val),
        .done        (done),
        .log2_result (log2_internal),
        .err_zero    (err_zero)
    );

    assign log2_out = log2_internal;

    // ----------------------------------------------------------------
    // Fixed-point multiply: ln(x) = log2(x) * ln(2)
    //   product has 2*FRAC_BITS fractional bits; shift right to get FRAC_BITS
    // ----------------------------------------------------------------
    wire [LOG2_WIDTH + FRAC_BITS - 1:0] ln_product;
    assign ln_product = log2_internal * LN2_CONST;
    assign ln_out     = ln_product[LOG2_WIDTH + FRAC_BITS - 1 : FRAC_BITS];

    // ----------------------------------------------------------------
    // Fixed-point multiply: log10(x) = log2(x) * log10(2)
    // ----------------------------------------------------------------
    wire [LOG2_WIDTH + FRAC_BITS - 1:0] log10_product;
    assign log10_product = log2_internal * LOG10_2_CONST;
    assign log10_out     = log10_product[LOG2_WIDTH + FRAC_BITS - 1 : FRAC_BITS];

endmodule
