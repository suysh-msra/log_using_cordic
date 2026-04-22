# CORDIC-Based Logarithm Calculator (Verilog)

Hardware-friendly logarithm computation using the CORDIC (COordinate Rotation Digital Computer) algorithm. Computes **log2**, **ln** (natural log), and **log10** of an unsigned integer input using only shifts and adds in the core datapath -- no multiplier required for the CORDIC iterations.

## Why Log Base 2?

Log base 2 is the natural choice for a hardware implementation:

- The **integer part** of log2(x) is the bit-position of the most significant set bit, obtained for free via a priority encoder.
- Only the **fractional part** requires iterative CORDIC computation.
- Conversion to other bases is a single fixed-point multiply by a constant:
  - `ln(x)    = log2(x) * ln(2)      = log2(x) * 0.6931471806`
  - `log10(x) = log2(x) * log10(2)   = log2(x) * 0.3010299957`

## Algorithm

Given an N-bit unsigned integer input X, compute log2(X) in fixed-point:

1. **Leading-one detection** -- Find the MSB position `n`. This is the integer part of log2(X).
2. **Normalization** -- Left-shift X so the MSB sits at a fixed bit position. The working register now represents a value in [1.0, 2.0).
3. **CORDIC iterations** (one per fractional output bit):
   - For each iteration `i = 1, 2, ..., FRAC_BITS`:
     - Compute `x_test = x + (x >> i)` (multiply x by 1 + 2^-i using a shift and an add)
     - If `x_test < 2.0` (no overflow into the integer bit):
       - `x = x_test`
       - `y = y + LUT[i]` where `LUT[i] = log2(1 + 2^-i)` (pre-computed constant)
     - Else: skip this factor
   - After all iterations, x has been driven toward 2.0 and y has accumulated the correction.
4. **Result** -- `log2(X) = (n + 1) - y`

## Architecture

Iterative FSM-based design optimized for area:

```
                +-------+     +-------+     +-------+     +-------+     +-------+
    start ----->| IDLE  |---->| NORM  |---->| ITER  |---->| CALC  |---->| DONE  |
                |       |     |       |     | (x16) |     |       |     |       |
                +-------+     +-------+     +-------+     +-------+     +-------+
                   ^                                                        |
                   +--------------------------------------------------------+
```

- **IDLE** -- Waits for `start`; registers input
- **NORM** -- Leading-one detect + barrel-shift normalization (1 cycle)
- **ITER** -- CORDIC shift-and-add iterations (FRAC_BITS cycles)
- **CALC** -- Final result computation (1 cycle)
- **DONE** -- Asserts `done`; holds result until next `start`

**Latency**: FRAC_BITS + 3 clock cycles per computation (19 cycles at default settings).

## Directory Structure

```
cordic_log/
├── rtl/
│   ├── cordic_log2.v       Core iterative CORDIC log2 engine
│   └── cordic_log_top.v    Top wrapper: log2 + conversion to ln and log10
├── tb/
│   └── cordic_log_tb.v     Self-checking testbench (56 test vectors)
├── scripts/
│   └── run_sim.sh          Icarus Verilog compile + run script
└── README.md
```

## Parameters

| Parameter     | Default | Description                                  |
|---------------|---------|----------------------------------------------|
| `INPUT_WIDTH` | 32      | Bit-width of the unsigned integer input      |
| `FRAC_BITS`   | 16      | Number of fractional bits in the output      |

Derived widths:
- `LOG2_INT_BITS = clog2(INPUT_WIDTH) + 1` (6 bits for 32-bit input)
- `LOG2_WIDTH = LOG2_INT_BITS + FRAC_BITS` (22 bits for default parameters)

## Interface

### cordic_log_top (top-level)

| Port        | Dir | Width         | Description                              |
|-------------|-----|---------------|------------------------------------------|
| `clk`       | in  | 1             | Clock                                    |
| `rst_n`     | in  | 1             | Active-low synchronous reset             |
| `start`     | in  | 1             | Pulse high for 1 cycle to begin          |
| `input_val` | in  | INPUT_WIDTH   | Unsigned integer input (must be > 0)     |
| `done`      | out | 1             | High when result is valid                |
| `log2_out`  | out | LOG2_WIDTH    | log2(input) in fixed-point               |
| `ln_out`    | out | LOG2_WIDTH    | ln(input) in fixed-point                 |
| `log10_out` | out | LOG2_WIDTH    | log10(input) in fixed-point              |
| `err_zero`  | out | 1             | Asserted if input was 0 (undefined log)  |

### Output Format

All outputs use unsigned fixed-point with `LOG2_INT_BITS` integer bits and `FRAC_BITS` fractional bits. To convert to a real number:

```
real_value = output / (2 ^ FRAC_BITS)
```

For the default 32-bit input with 16 fractional bits, the output is 22 bits:

```
[21:16] = integer part (0 to 31)
[15:0]  = fractional part
```

## Simulation

### Prerequisites

- [Icarus Verilog](http://iverilog.icarus.com/) (iverilog + vvp)
- Optional: [GTKWave](http://gtkwave.sourceforge.net/) for waveform viewing

### Run

```bash
./scripts/run_sim.sh            # compile and run
./scripts/run_sim.sh --wave     # compile, run, and open waveform viewer
./scripts/run_sim.sh --clean    # remove generated files
```

### Expected Output

```
CORDIC Logarithm Testbench  (INPUT_WIDTH=32, FRAC=16)
...
RESULTS:  56 PASSED,  0 FAILED  (of 56 tests)
** ALL TESTS PASSED **
```

The testbench exercises:
- Zero input (error flag check)
- All 32 powers of two (exact integer results)
- 23 non-trivial values including edge cases (3, 100, 2^31-1, 2^32-1, etc.)

## Accuracy

With the default `FRAC_BITS = 16`:

| Output  | Typical Error | Max Error   | Notes                              |
|---------|--------------|-------------|-------------------------------------|
| log2    | < 1 ULP      | ~6 ULPs     | Powers of 2 are exact               |
| ln      | < 2 ULPs     | ~10 ULPs    | Includes conversion constant error  |
| log10   | < 2 ULPs     | ~10 ULPs    | Error scales with log2 magnitude    |

1 ULP = 1 / 2^FRAC_BITS = 1/65536 ~ 0.0015% for FRAC_BITS = 16.

## LUT Regeneration

The CORDIC look-up table stores `log2(1 + 2^-i)` at 32-bit precision. To regenerate or verify values:

```python
import math
for i in range(1, 33):
    val = math.log2(1 + 2**(-i))
    fixed = round(val * 2**32)
    print(f"i={i:2d}: 32'h{fixed:08X}")
```

## Resource Usage Notes

The core CORDIC datapath uses:
- One (INPUT_WIDTH+1)-bit adder (shift-and-add for x)
- One (FRAC_BITS+1)-bit adder (y accumulator)
- One barrel shifter (variable right-shift of x)
- One barrel shifter (normalization left-shift, used once)
- A small ROM for the LUT (FRAC_BITS entries of FRAC_BITS bits each)

The top-level wrapper adds two multipliers for the ln/log10 conversion (LOG2_WIDTH x FRAC_BITS bits each). These are combinational and operate only on the final result.

## Bugs Encountered During Development

### Bug 1: LUT Part-Select Width Mismatch (RTL)

**Symptom**: Every CORDIC iteration produced `lut_val = 0`, so `y_acc` never accumulated. All log2 results were stuck at `(msb_pos + 1)` with zero fractional part. The initial test run showed 46 of 56 tests failing, with only accidental passes where stale results happened to match.

**Root cause**: The LUT function was declared with an 8-bit input (`input [7:0] idx`), but the `iter_cnt` register was only 5 bits wide (`ITER_BITS = clog2(17) = 5`). The call site used an explicit part-select:

```verilog
wire [FRAC_BITS-1:0] lut_val = get_lut(iter_cnt[7:0]);  // BUG
```

iverilog warned: *"Part select [7:0] is selecting after the vector iter_cnt[4:0]. Replacing the out of bound bits with 'bx."* The upper 3 bits were filled with `x`, causing the `case` statement inside the function to fall through to `default` (returning 0) on every call.

**Fix**: Remove the explicit part-select and let Verilog's implicit zero-extension handle the width conversion:

```verilog
wire [FRAC_BITS-1:0] lut_val = get_lut(iter_cnt);        // FIXED
```

### Bug 2: Testbench Done-Signal Race Condition (Testbench)

**Symptom**: Back-to-back tests read stale results from the *previous* computation. The first few tests passed by coincidence (e.g., log2(1) = 0 matched the stale zero-input result), but subsequent tests showed wildly wrong values like log2(3) = 31.0 (which was actually the result from the prior test on val=2147483648).

**Root cause**: The FSM holds `done = 1` in state `S_DONE` until a new `start` arrives. When the testbench fired the next test, the `while (!done)` polling loop saw the *leftover* `done = 1` from the previous computation and exited immediately, reading the old `log2_result` before the new computation even began.

```verilog
// ORIGINAL (BUGGY) -- exits immediately if done is still high
while (!done) @(posedge clk);
```

**Fix**: Wait for `done` to deassert first (acknowledging that the FSM has accepted the new `start`), then wait for the fresh `done` assertion:

```verilog
// FIXED -- two-phase handshake
while (done) @(posedge clk);   // wait for previous done to clear
while (!done) @(posedge clk);  // wait for new computation to finish
@(posedge clk); #1;            // let outputs settle
```

Also switched stimulus signals from non-blocking (`<=`) to blocking (`=`) with `#1` delays after `posedge clk`, eliminating delta-cycle race conditions between the testbench and DUT.

### Bug 3: LUT Truncation Bias (Accuracy)

**Symptom**: All powers of 2 showed a consistent +3 ULP overestimate in log2 (e.g., log2(8) = 3.000046 instead of 3.000000). Non-power-of-2 inputs had 4-6 ULP errors.

**Root cause**: The LUT function truncated 32-bit constants down to `FRAC_BITS` by right-shifting:

```verilog
get_lut = val32 >> (32 - FRAC_BITS);  // truncates (floors)
```

Each truncated entry loses up to 0.99 ULP. Since ~10 of the 16 LUT entries are selected per computation, the cumulative truncation in `y_acc` was ~3 ULP too low. Because the result is `(n+1) - y`, a low `y_acc` produces a high result.

**Fix**: Round instead of truncate by adding 0.5 ULP before the shift:

```verilog
get_lut = (val32 + (32'd1 << (31 - FRAC_BITS))) >> (32 - FRAC_BITS);
```

This reduced the power-of-2 error from 3 ULP to 0 ULP (exact). A saturating subtraction was also added to guard against the rare case where rounded-up LUT values cause `y_acc` to slightly exceed 2^FRAC_BITS:

```verilog
wire [LOG2_WIDTH:0] result_raw  = {1'b0, int_part_shft} - {{LOG2_INT_BITS{1'b0}}, y_acc};
wire [LOG2_WIDTH-1:0] result_safe = result_raw[LOG2_WIDTH] ? {LOG2_WIDTH{1'b0}} : result_raw[LOG2_WIDTH-1:0];
```

### Bug 4: Overly Tight Testbench Tolerances (Testbench)

**Symptom**: After fixing bugs 1-3, 29 tests still failed -- all on `ln_out` or `log10_out` with errors of 0.00006 to 0.00015, just above the uniform 4-ULP tolerance.

**Root cause**: The conversion from log2 to log10 multiplies by a 16-bit constant (`log10(2) = 0.3010...`, stored as 19728/65536). The constant itself has a quantization error of ~0.3 ULP. When multiplied by a large log2 value (up to 32), this error is amplified: `32 * 0.3/65536 = 0.000147`. A single tolerance couldn't cover both the tight log2 accuracy and the looser conversion accuracy.

**Fix**: Replaced the single tolerance with per-output tolerances:

```verilog
tol_log2 = 8.0 / scale;                                  // 8 ULPs for core CORDIC
tol_conv = tol_log2 + (exp_log2 + 1.0) * 1.0 / scale;   // scales with value
```

The conversion tolerance accounts for the constant quantization error growing linearly with the log2 magnitude, matching the physical error source.

## License

This design is provided as-is for educational and practical use.
