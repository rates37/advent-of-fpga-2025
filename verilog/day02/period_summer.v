
/**
 * Calculates the sum of all D-digit numbers in the range [limit_lower, limit_upper]
 * that are formed by repeating an L-digit number.
 *
 * Inputs:
 *  clk / rst: Regular synchronous inputs
 *  start: signal to begin summing
 *  D: Total number of digits (e.g., 6)
 *  L: Length of the repeating pattern
 *  limit_lower, limit_upper: The range to sum within.
 *  parsed_lower_bcd, parsed_upper_bcd: BCD representations for easy number extraction
 *
 * Outputs:
 *  sum: The sum of all invalid D digit numbers in the range formed by repeating an L digit number
 *  done: indicator that sum computation has finished
 */
module period_summer (
    input wire clk,
    input wire rst,
    input wire start,

    input wire [63:0] limit_lower,
    input wire [63:0] limit_upper,
    input wire [79:0] parsed_lower_bcd,
    input wire [79:0] parsed_upper_bcd,

    input wire [4:0] D,
    input wire [4:0] L,

    output reg done,
    output reg [63:0] sum
);
    // states:
    parameter S_IDLE = 0;
    parameter S_CALC_M = 1;
    parameter S_CALC_MIN = 2;
    parameter S_CALC_MAX = 3;
    parameter S_CALC_SUM = 4;

    reg [2:0] state;
    reg [63:0] M;
    reg [63:0] s_min;
    reg [63:0] s_max;
    reg [63:0] count;
    reg [63:0] sum_ab;
    reg [63:0] temp_M;
    reg [63:0] seed;
    integer k;

    function [63:0] extract_seed; // extract first L digits from D digit BCD number
        input [79:0] bcd;
        input [4:0] D_in;
        input [4:0] L_in;
        reg [79:0] temp;
        integer i;
        begin
            extract_seed = 0;
            for (i = 0; i < L_in; i = i+1) begin
                extract_seed = extract_seed * 10 + bcd[(D_in - 1 - i)*4 +: 4];
            end
        end
    endfunction

    function [63:0] pow10; /// look up for powers of 10
        input [5:0] p;
        begin
            case (p)
                0: pow10 = 1;
                1: pow10 = 10;
                2: pow10 = 100;
                3: pow10 = 1000;
                4: pow10 = 10000;
                5: pow10 = 100000;
                6: pow10 = 1000000;
                7: pow10 = 10000000;
                8: pow10 = 100000000;
                9: pow10 = 1000000000;
                10: pow10 = 10000000000;
                11: pow10 = 100000000000;
                12: pow10 = 1000000000000;
                13: pow10 = 10000000000000;
                14: pow10 = 100000000000000;
                15: pow10 = 1000000000000000;
                16: pow10 = 10000000000000000;
                17: pow10 = 100000000000000000;
                18: pow10 = 1000000000000000000;
                default: pow10 = 0;
            endcase
        end
    endfunction

    always @(posedge clk) begin
        if (rst) begin
            state <= S_IDLE;
            done <= 0;
        end 
        else begin
            case (state)
                S_IDLE: begin
                    done <= 0;
                    if (start) begin
                        M <= 0;
                        state <= S_CALC_M;
                    end
                end

                S_CALC_M: begin
                    temp_M = 0;
                    for (k = 0; k < 20; k = k + 1) begin
                        if ((k+1)*L <= D) begin
                            temp_M = temp_M + pow10(k*L);
                        end
                    end
                    M <= temp_M;
                    state <= S_CALC_MIN;
                end

                S_CALC_MIN: begin
                    if (limit_lower == 0) begin
                        s_min <= pow10(L-1);
                    end else begin
                        seed = extract_seed(parsed_lower_bcd, D, L);
                        if (seed < pow10(L-1)) begin
                            seed = pow10(L-1);
                        end
                        if (seed * M < limit_lower) begin
                            s_min <= seed+1;
                        end else begin
                            s_min <= seed;
                        end
                    end
                    state <= S_CALC_MAX;
                end

                S_CALC_MAX: begin
                    if (limit_upper > 64'hF000000000000000) begin
                        s_max <= pow10(L)-1;
                    end else begin
                        seed = extract_seed(parsed_upper_bcd, D, L);
                        if (seed * M > limit_upper) begin
                            s_max <= seed-1;
                        end else begin
                            s_max <= seed;
                        end
                    end
                    state <= S_CALC_SUM;
                end

                S_CALC_SUM: begin
                    if (s_max < s_min) begin
                        sum <= 0;
                    end else begin
                        count = s_max - s_min + 1;
                        sum_ab = s_max + s_min;
                        if (count[0] == 0) begin
                            count = count >> 1;
                        end else begin
                            sum_ab = sum_ab >> 1;
                        end
                        sum <= M * sum_ab * count;
                    end
                    state <= S_IDLE;
                    done <= 1;
                end
            endcase
        end
    end
endmodule
