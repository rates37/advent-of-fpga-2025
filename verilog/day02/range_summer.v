/* 
 * Sums invalid numbers in the range [A,B] with D digits
 * Calculated part 2 result, but part 1 result is an intermediate
 * value, so it outputs that as well
 */
module range_summer (
    // sequential module inputs
    input wire clk,
    input wire rst,
    input wire start,

    // task inputs:
    input wire [4:0] D,
    input wire [63:0] range_start,
    input wire [63:0] range_end,
    input wire [79:0] parsed_lower_bcd,
    input wire [79:0] parsed_upper_bcd,

    // outputs:
    output reg [63:0] sum_out,
    output reg [63:0] part1_sum_out,
    output reg done,

);

    // state definition:
    reg [3:0] state;
    localparam S_IDLE = 0;
    localparam S_PROCESS_PERIODS = 1;
    localparam S_WAIT_SUMMER_START = 2;
    localparam S_WAIT_RESULT = 3;

    // period definition:
    reg [4:0] period_L;
    reg [1:0] period_idx;

    reg [4:0] p1, p2, p3;
    reg [1:0] op1, op2, op3; // 0 = add, 1 = sub, 2 = None

    reg [63:0] term_sum;
    wire [63:0] period_result;
    reg [4:0] next_L;
    reg [1:0] next_op;
    reg [1:0] cur_op;
    reg period_go;
    wire period_done;

    period_summer u_summer_0 (
        .clk(clk),
        .rst(rst),
        .start(period_go),

        .limit_lower(range_start),
        .limit_upper(range_end),
        .parsed_lower_bcd(parsed_lower_bcd),
        .parsed_upper_bcd(parsed_upper_bcd),

        .D(D),
        .L(period_L),

        .done(period_done),
        .sum(period_result)
    );

    always @(posedge clk) begin
        if (rst) begin
            state <= S_IDLE;
            done <= 0;
            period_go <= 0;
            part1_sum_out <= 0;
            sum_out <= 0;
        end else begin
            case (state)
                S_IDLE: begin
                    done <= 0;
                    if (start) begin
                        part1_sum_out <= 0;
                        sum_out <= 0;

                        // provide default values:
                        p1 = 0;
                        p2 = 0;
                        p3 = 0;
                        op1 = 2;
                        op2 = 2;
                        op3 = 2;

                        // Maximal prime divisor add/sub table
                        // this is the same as the hard coded list in 
                        // my optimised day 2 part 2 python solution
                        // will write up formal explanation soon
                        // currently my notes on it are beyond deranged
                        case (D)
                            4: begin
                                p1 = 2;
                                p2 = 1;
                                op1 = 0;
                                op2 = 2;
                            end

                            6: begin
                                p1 = 3;
                                p2 = 2;
                                p3 = 1;
                                op1 = 0;
                                op2 = 0;
                                op3 = 1;
                            end

                            8: begin
                                p1 = 4;
                                p2 = 0;
                                op1 = 0;
                                op2 = 2;
                            end

                            9: begin
                                p1 = 3;
                                p2 = 0;
                                op1 = 0;
                                op2 = 2;
                            end

                            10: begin
                                p1 = 5;
                                p2 = 2;
                                p3 = 1;
                                op1 = 0;
                                op2 = 0;
                                op3 = 1;
                            end

                            12: begin
                                p1 = 6;
                                p2 = 4;
                                p3 = 2;
                                op1 = 0;
                                op2 = 0;
                                op3 = 1;
                            end

                            14: begin
                                p1 = 7;
                                p2 = 2;
                                p3 = 1;
                                op1 = 0;
                                op2 = 0;
                                op3 = 1;
                            end

                            15: begin
                                p1 = 5;
                                p2 = 3;
                                p3 = 1;
                                op1 = 0;
                                op2 = 0;
                                op3 = 1;
                            end

                            16: begin
                                p1 = 8;
                                p2 = 0;
                                op1 = 0;
                                op2 = 2;
                            end

                            18: begin
                                p1 = 9;
                                p2 = 6;
                                p3 = 3;
                                op1 = 0;
                                op2 = 0;
                                op3 = 1;
                            end

                            20: begin
                                p1 = 10;
                                p2 = 4;
                                p3 = 2;
                                op1 = 0;
                                op2 = 0;
                                op3 = 1;
                            end

                            default: begin
                                if (D > 1) begin
                                    p1 = 1;
                                    p2 = 0;
                                    op1 = 0;
                                    op2 = 2;
                                end else begin
                                    p1 = 0;
                                    op1 = 2;
                                end
                            end
                        endcase

                        period_idx <= 0;
                        state <= S_PROCESS_PERIODS;
                    end
                end

                S_PROCESS_PERIODS: begin
                    // set next values of L and op
                    if (period_idx == 0) begin
                        next_L = p1;
                        next_op = op1;
                    end else if (period_idx == 1) begin
                        next_L = p2;
                        next_op = op2;
                    end else if (period_idx == 2) begin
                        next_L = p3;
                        next_op = op3;
                    end else begin
                        next_L = 0;
                        next_op = 2;
                    end

                    // check if finished processing all periods:
                    if (next_op == 2 || next_L == 0) begin
                        done <= 1;
                        state <= S_IDLE;
                    end 
                    // otherwise process next period:
                    else begin
                        period_L <= next_L;
                        period_go <= 1;
                        state <= S_WAIT_SUMMER_START;
                    end
                end

                S_WAIT_SUMMER_START: begin
                    period_go <= 0;
                    if (!period_done) begin
                        state <= S_WAIT_RESULT;
                    end
                end

                S_WAIT_RESULT: begin
                    if (period_done) begin
                        if (period_idx == 0) begin
                            cur_op = op1;
                        end else if (period_idx == 1) begin
                            cur_op = op2;
                        end else begin
                            cur_op = op3;
                        end

                        // store p1 result if using D/2 period:
                        if (period_idx == 0 && D[0] == 0) begin
                            // first period will always be half the length
                            // just need to ensure length is EVEN (D[0] == 0)
                            part1_sum_out <= period_result;
                        end

                        // accumulate total (for part 2):
                        if (cur_op == 0) begin
                            sum_out <= sum_out + period_result;
                        end else begin
                            sum_out <= sum_out - period_result;
                        end

                        // move to next state:
                        period_idx <= period_idx + 1;
                        state <= S_PROCESS_PERIODS;
                    end
                end
            endcase
        end
    end
endmodule
