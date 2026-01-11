
module day02_core # (
    parameter N_ADDR_BITS = 16
) (
    // Synchronous inputs:
    input wire clk,
    input wire rst,

    // IO to interface with ROM:
    input wire [7:0] rom_data,
    input wire rom_valid,
    output reg [N_ADDR_BITS:0] rom_addr,

    // results:
    output reg [63:0] part1_result,
    output reg [63:0] part2_result,
    output reg done
);

    // input parser FSM 
    reg [2:0] state;
    localparam S_WAIT_ROM = 0;
    localparam S_PARSE_LOWER = 1;
    localparam S_PARSE_UPPER = 2;
    localparam S_SETUP_CALC = 3;
    localparam S_CALC_LOOP = 4;
    localparam S_WAIT_SUMMERS = 5;
    localparam S_DONE = 6;

    // helper signals for parser:
    wire [3:0] digit_val;
    assign digit_val = rom_data - "0";
    wire is_digit;
    assign is_digit = (rom_data >= "0" && rom_data <= "9");

    reg [2:0] next_state_after_wait; // getting really creative with reg names

    // parsed data:
    reg [127:0] parsed_lower_bin, parsed_upper_bin;
    reg [79:0] parsed_lower_bcd, parsed_upper_bcd;
    reg [5:0] lower_digits, upper_digits;// number of digits in lower/upper

    // range iteration state:
    reg [63:0] current_range_start, current_range_end;
    reg [5:0] current_D;
    reg calc_start; // signal to summer
    wire done_summer;
    wire [63:0] chunk_sum_part1, chunk_sum_part2;

    // controls/inputs for summer:
    reg [4:0] calc_D;
    reg [63:0] calc_range_start, calc_range_end;
    reg [79:0] calc_lower_bcd, calc_upper_bcd;
    
    range_summer u_range_summer_0 (
        .clk(clk),
        .rst(rst),
        .start(calc_start),

        .D(calc_D),
        .range_start(calc_range_start),
        .range_end(calc_range_end),
        .parsed_lower_bcd(calc_lower_bcd),
        .parsed_upper_bcd(calc_upper_bcd),

        .done(done_summer),
        .part1_sum_out(chunk_sum_part1),
        .sum_out(chunk_sum_part2)
    );

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

    reg done_r;

    always @(posedge clk) begin
        if (rst) begin
            state <= S_WAIT_ROM;
            next_state_after_wait <= S_PARSE_LOWER;
            rom_addr <= 0;
            part1_result <= 0;
            part2_result <= 0;
            parsed_lower_bin <= 0;
            parsed_lower_bcd <= 0;
            parsed_upper_bin <= 0;
            parsed_upper_bcd <= 0;
            lower_digits <= 0;
            upper_digits <= 0;
            done <= 0;
            calc_start <= 0;
            done_r <= 0;
        end else begin
            case (state)
                S_WAIT_ROM: begin
                    state <= next_state_after_wait;
                end

                S_PARSE_LOWER: begin
                    if (is_digit) begin
                        if (parsed_lower_bin == 0 && digit_val == 0 && lower_digits == 0) begin
                        end else begin
                            parsed_lower_bin <= (parsed_lower_bin<<3) + (parsed_lower_bin<<1) + digit_val;
                            parsed_lower_bcd <= {parsed_lower_bcd[75:0], digit_val};
                            lower_digits <= lower_digits + 1;
                        end
                        next_state_after_wait <= S_PARSE_LOWER;
                    end else if (rom_data == "-") begin
                        // reached end of parsing lower bound
                        parsed_upper_bcd <= 0;
                        parsed_upper_bin <= 0;
                        upper_digits <= 0;
                        next_state_after_wait <= S_PARSE_UPPER;
                    end
                    state <= S_WAIT_ROM;
                    rom_addr <= rom_addr + 1;
                end

                S_PARSE_UPPER: begin
                    if (is_digit) begin
                        parsed_upper_bin <= (parsed_upper_bin<<3) + (parsed_upper_bin<<1) + digit_val;
                        parsed_upper_bcd <= {parsed_upper_bcd[75:0], digit_val};
                        upper_digits <= upper_digits + 1;
                        rom_addr <= rom_addr + 1;
                        state <= S_WAIT_ROM;
                        next_state_after_wait <= S_PARSE_UPPER;
                    end else begin
                        state <= S_SETUP_CALC;
                        current_range_start <= parsed_lower_bin;
                        current_range_end <= parsed_upper_bin;
                        current_D <= lower_digits;

                        // check if another range left in input:
                        if (rom_data == ",") begin
                            rom_addr <= rom_addr + 1;
                            next_state_after_wait <= S_PARSE_LOWER;
                        end 
                        // reached end of input file
                        else begin
                            next_state_after_wait <= S_DONE;
                        end
                    end
                end

                S_SETUP_CALC: begin
                    if (current_range_start > current_range_end) begin
                        parsed_lower_bin <= 0; 
                        parsed_lower_bcd <= 0; 
                        parsed_upper_bin <= 0; 
                        parsed_upper_bcd <= 0; 
                        lower_digits <= 0;
                        upper_digits <= 0;

                        if (next_state_after_wait == S_DONE) begin
                            state <= S_DONE;
                        end else begin
                            state <= S_WAIT_ROM;
                        end
                    end else begin
                        calc_D <= current_D;
                        calc_range_start <= current_range_start;

                        if (upper_digits > current_D) begin
                            calc_range_end <= 64'hFFFFFFFFFFFFFFFF;
                        end else begin
                            calc_range_end <= current_range_end;
                        end

                        if (current_D > lower_digits) begin
                            calc_lower_bcd <= 0;
                        end else begin
                            calc_lower_bcd <= parsed_lower_bcd;
                        end

                        calc_upper_bcd <= parsed_upper_bcd;
                        calc_start <= 1;
                        done_r <= 0;
                        state <= S_WAIT_SUMMERS;
                    end
                end

                S_CALC_LOOP: begin
                    current_D <= current_D + 1;
                    state <= S_SETUP_CALC;

                    if (current_D < 19) begin
                        current_range_start <= pow10(current_D);
                    end else begin
                        current_range_start <= 64'hFFFFFFFFFFFFFFFF; // make sure current start is larger than any possible end
                    end
                end

                S_WAIT_SUMMERS: begin
                    calc_start <= 0;

                    if (done_summer) begin
                        part1_result <= part1_result + chunk_sum_part1;
                        part2_result <= part2_result + chunk_sum_part2;
                        state <= S_CALC_LOOP;
                    end
                end

                S_DONE: begin
                    done <= 1;
                end
            endcase
        end
    end

endmodule
