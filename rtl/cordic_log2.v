`timescale 1ns / 1ps
//
// cordic_log2.v - Iterative CORDIC-based log base 2 calculator
//
// Algorithm:
//   1. Find MSB position (n) of input  -> integer part of log2
//   2. Normalize input to [1.0, 2.0) fixed-point
//   3. Multiply x by factors (1 + 2^-i) that keep x < 2.0,
//      accumulating y = sum of log2(1 + 2^-i) for selected factors
//   4. Result: log2(input) = (n + 1) - y   (since x was driven toward 2.0)
//
// Only shifts and adds are used in the core datapath (no multiplier).
//

module cordic_log2 #(
    parameter INPUT_WIDTH = 32,
    parameter FRAC_BITS   = 16
) (
    input  wire                        clk,
    input  wire                        rst_n,
    input  wire                        start,
    input  wire [INPUT_WIDTH-1:0]      input_val,
    output reg                         done,
    output reg  [LOG2_WIDTH-1:0]       log2_result,
    output reg                         err_zero
);

    // ----------------------------------------------------------------
    // Derived parameters
    // ----------------------------------------------------------------
    localparam LOG2_INT_BITS = clog2_f(INPUT_WIDTH) + 1;
    localparam LOG2_WIDTH    = LOG2_INT_BITS + FRAC_BITS;
    localparam X_WIDTH       = INPUT_WIDTH + 1;
    localparam MSB_BITS      = clog2_f(INPUT_WIDTH);
    localparam ITER_BITS     = clog2_f(FRAC_BITS + 1);

    // ----------------------------------------------------------------
    // Portable clog2 function (avoids $clog2 portability issues)
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
    // LUT: log2(1 + 2^-i) at 32-bit fractional precision
    // Returned value is truncated to FRAC_BITS for the accumulator.
    // ----------------------------------------------------------------
    function [FRAC_BITS-1:0] get_lut;
        input [7:0] idx;
        reg [31:0] val32;
        begin
            case (idx)
                8'd1:  val32 = 32'h95C01A3A;
                8'd2:  val32 = 32'h5269E12F;
                8'd3:  val32 = 32'h2B803474;
                8'd4:  val32 = 32'h1663F6FB;
                8'd5:  val32 = 32'h0B5D69BB;
                8'd6:  val32 = 32'h05B9E5A1;
                8'd7:  val32 = 32'h02DFCA17;
                8'd8:  val32 = 32'h01709C47;
                8'd9:  val32 = 32'h00B87C20;
                8'd10: val32 = 32'h005C4995;
                8'd11: val32 = 32'h002E27AC;
                8'd12: val32 = 32'h0017148F;
                8'd13: val32 = 32'h000B8A76;
                8'd14: val32 = 32'h0005C546;
                8'd15: val32 = 32'h0002E2A6;
                8'd16: val32 = 32'h00017154;
                8'd17: val32 = 32'h0000B8AA;
                8'd18: val32 = 32'h00005C55;
                8'd19: val32 = 32'h00002E2B;
                8'd20: val32 = 32'h00001715;
                8'd21: val32 = 32'h00000B8B;
                8'd22: val32 = 32'h000005C5;
                8'd23: val32 = 32'h000002E3;
                8'd24: val32 = 32'h00000171;
                8'd25: val32 = 32'h000000B9;
                8'd26: val32 = 32'h0000005C;
                8'd27: val32 = 32'h0000002E;
                8'd28: val32 = 32'h00000017;
                8'd29: val32 = 32'h0000000C;
                8'd30: val32 = 32'h00000006;
                8'd31: val32 = 32'h00000003;
                8'd32: val32 = 32'h00000001;
                default: val32 = 32'h00000000;
            endcase
            get_lut = (val32 + (32'd1 << (31 - FRAC_BITS))) >> (32 - FRAC_BITS);
        end
    endfunction

    // ----------------------------------------------------------------
    // FSM encoding
    // ----------------------------------------------------------------
    localparam [2:0] S_IDLE = 3'd0,
                     S_NORM = 3'd1,
                     S_ITER = 3'd2,
                     S_CALC = 3'd3,
                     S_DONE = 3'd4;

    // ----------------------------------------------------------------
    // Registers
    // ----------------------------------------------------------------
    reg [2:0]               state;
    reg [X_WIDTH-1:0]       x_reg;
    reg [FRAC_BITS:0]       y_acc;          // can reach 1.0 = 2^FRAC_BITS
    reg [ITER_BITS-1:0]     iter_cnt;
    reg [MSB_BITS-1:0]      msb_pos_reg;
    reg [INPUT_WIDTH-1:0]   input_reg;
    reg                     zero_flag;

    // ----------------------------------------------------------------
    // Leading-one detector  (combinational, operates on input_reg)
    // Scans from LSB to MSB; last match wins → gives highest set bit.
    // ----------------------------------------------------------------
    reg [MSB_BITS-1:0] msb_pos_comb;
    reg                zero_comb;
    integer k;

    always @(*) begin
        msb_pos_comb = {MSB_BITS{1'b0}};
        zero_comb    = 1'b1;
        for (k = 0; k < INPUT_WIDTH; k = k + 1) begin
            if (input_reg[k]) begin
                msb_pos_comb = k[MSB_BITS-1:0];
                zero_comb    = 1'b0;
            end
        end
    end

    // ----------------------------------------------------------------
    // Normalization: shift input so MSB lands at bit [INPUT_WIDTH-1]
    // ----------------------------------------------------------------
    wire [MSB_BITS-1:0] shift_amt     = (INPUT_WIDTH - 1) - msb_pos_comb;
    wire [X_WIDTH-1:0]  x_normalized  = {1'b0, input_reg} << shift_amt;

    // ----------------------------------------------------------------
    // CORDIC datapath (combinational, used during S_ITER)
    // ----------------------------------------------------------------
    wire [X_WIDTH-1:0]   x_shifted  = x_reg >> iter_cnt;
    wire [X_WIDTH-1:0]   x_test     = x_reg + x_shifted;
    wire                 x_overflow = x_test[INPUT_WIDTH];
    wire [FRAC_BITS-1:0] lut_val    = get_lut(iter_cnt);

    // ----------------------------------------------------------------
    // Result computation wires (used in S_CALC)
    // msb_pos extended to LOG2_WIDTH, then: result = (msb+1)<<F - y_acc
    // Saturating subtraction guards against LUT rounding edge cases.
    // ----------------------------------------------------------------
    wire [LOG2_WIDTH-1:0] msb_plus_one  = {{(LOG2_WIDTH - MSB_BITS){1'b0}}, msb_pos_reg} + 1'b1;
    wire [LOG2_WIDTH-1:0] int_part_shft = msb_plus_one << FRAC_BITS;
    wire [LOG2_WIDTH:0]   result_raw    = {1'b0, int_part_shft} - {{(LOG2_INT_BITS){1'b0}}, y_acc};
    wire [LOG2_WIDTH-1:0] result_safe   = result_raw[LOG2_WIDTH] ? {LOG2_WIDTH{1'b0}} : result_raw[LOG2_WIDTH-1:0];

    // ----------------------------------------------------------------
    // FSM
    // ----------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state       <= S_IDLE;
            done        <= 1'b0;
            err_zero    <= 1'b0;
            log2_result <= {LOG2_WIDTH{1'b0}};
            x_reg       <= {X_WIDTH{1'b0}};
            y_acc       <= {(FRAC_BITS+1){1'b0}};
            iter_cnt    <= {ITER_BITS{1'b0}};
            msb_pos_reg <= {MSB_BITS{1'b0}};
            input_reg   <= {INPUT_WIDTH{1'b0}};
            zero_flag   <= 1'b0;
        end else begin
            case (state)
                // -------------------------------------------------
                S_IDLE: begin
                    done     <= 1'b0;
                    err_zero <= 1'b0;
                    if (start) begin
                        input_reg <= input_val;
                        state     <= S_NORM;
                    end
                end

                // -------------------------------------------------
                S_NORM: begin
                    if (zero_comb) begin
                        zero_flag <= 1'b1;
                        state     <= S_CALC;
                    end else begin
                        x_reg       <= x_normalized;
                        msb_pos_reg <= msb_pos_comb;
                        y_acc       <= {(FRAC_BITS+1){1'b0}};
                        iter_cnt    <= {{(ITER_BITS-1){1'b0}}, 1'b1};
                        zero_flag   <= 1'b0;
                        state       <= S_ITER;
                    end
                end

                // -------------------------------------------------
                S_ITER: begin
                    if (!x_overflow) begin
                        x_reg <= x_test;
                        y_acc <= y_acc + {1'b0, lut_val};
                    end

                    if (iter_cnt == FRAC_BITS[ITER_BITS-1:0]) begin
                        state <= S_CALC;
                    end else begin
                        iter_cnt <= iter_cnt + 1'b1;
                    end
                end

                // -------------------------------------------------
                S_CALC: begin
                    if (zero_flag) begin
                        log2_result <= {LOG2_WIDTH{1'b0}};
                        err_zero    <= 1'b1;
                    end else begin
                        log2_result <= result_safe;
                    end
                    done  <= 1'b1;
                    state <= S_DONE;
                end

                // -------------------------------------------------
                S_DONE: begin
                    if (start) begin
                        done      <= 1'b0;
                        err_zero  <= 1'b0;
                        zero_flag <= 1'b0;
                        input_reg <= input_val;
                        state     <= S_NORM;
                    end
                end

                default: state <= S_IDLE;
            endcase
        end
    end

endmodule
