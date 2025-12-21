module day06_core #(
    parameter N_ADDR_BITS = 16,
    parameter WIDTH_BITS = 14, // maximum number of colums defined as 2^WIDTH_BITS = 16k, my puzzle has 3709 cols
    parameter HEIGHT_BITS = 3 // max rows defined as 2^HEIGHT_BITS = 8, my puzzle has 5 rows

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

    // 2D memory grid to store input:
    localparam MAX_WIDTH = (1 << WIDTH_BITS);
    localparam MAX_HEIGHT = (1 << HEIGHT_BITS);
    reg [7:0] grid_mem [0:MAX_HEIGHT-1][0:MAX_WIDTH-1]; // todo dont' need a whole byte per entry here, can just be 4 bits
    reg [WIDTH_BITS-1:0] row_len [0:MAX_HEIGHT-1]; // track char count of each row to ensure no junk data is considered

    // temp variables used in calculation blocks:
    reg col_empty;
    reg [63:0] col_val;
    reg col_has_digit;
    reg [7:0] char_tmp;

    // FSM states:
    localparam S_LOAD_INPUT = 0;
    localparam S_SCAN_COL = 1;
    localparam S_PROCESS_COL = 2;
    localparam S_MULT = 3; // try to be efficient with multiplication, so have a 'multiply task' state that other states can use like a function call
    localparam S_END_BLOCK = 4;
    localparam S_BLOCK_REDUCE = 5; // sequentialy reduce row totals
    localparam S_DONE = 6;
    reg [2:0] state;
    reg [2:0] next_state;

    // pointers:
    reg [WIDTH_BITS-1:0] curr_x, max_x;
    reg [HEIGHT_BITS-1:0] curr_y, max_y;
    reg [7:0] operator; // todo: use single bit for this rather than using ascii value
    reg in_block; // true if scanner is currently inside a problem block

    // accumulation registers:
    reg [63:0] p1_nums [0:MAX_HEIGHT-1];
    reg [63:0] p1_acc;
    reg [63:0] p2_acc;
    reg is_first_p2;
    reg [63:0] mult_a, mult_b, mult_result; // assume results will not overflow

    // multiply number by 10 using shifts:
    function [63:0] mult10;
        input [63:0] val;
        begin
            mult10 = (val << 3) + (val << 1);
        end
    endfunction


    integer i;
    always @(posedge clk) begin
        if (rst) begin
            state <= S_LOAD_INPUT;
            rom_addr <= 0;
            curr_x <= 0;
            curr_y <= 0;
            max_x <= 0;
            max_y <= 0;
            part1_result <= 0;
            part2_result <= 0;
            done <= 0;
            in_block <= 0;
            for (i=0; i<MAX_HEIGHT; i=i+1) begin
                row_len[i] <= 0;
            end
        end else begin
            case(state)
                S_LOAD_INPUT: begin
                    if (rom_valid) begin
                        if (rom_data == "\n") begin
                            if (curr_x > 0) begin // only move to next row if current row has content in it
                                row_len[curr_y] <= curr_x;
                                if (curr_x > max_x) begin
                                    max_x <= curr_x; // track longest row (should all be the same but just incase)
                                end
                                // move pointers to start of next row
                                curr_y <= curr_y + 1;
                                curr_x <= 0;
                            end
                        end else begin
                            grid_mem[curr_y][curr_x] <= rom_data; // todo convert straight to int here?
                            curr_x <= curr_x + 1;
                        end
                        rom_addr <= rom_addr + 1;
                    end else if (rom_addr > 0) begin
                        // assume not rom_valid == reached EOF
                        // store current line (in case input doesn't have trailing newline)
                        if (curr_x > 0) begin
                            row_len[curr_y] <= curr_x;
                            max_y <= curr_y + 1;
                            if (curr_x > max_x) begin
                                max_x <= curr_x; 
                            end
                        end else begin
                            max_y <= curr_y;
                        end
                        state <= S_SCAN_COL;
                        curr_x <= 0;
                    end
                end


                S_SCAN_COL: begin
                    if (curr_x >= max_x) begin  // shouldn't ever happen but just incase
                        if (in_block) begin
                            state <= S_END_BLOCK;
                        end else begin
                            state <= S_DONE; 
                        end
                    end else begin
                        col_empty = 1;
                        for (i=0; i<MAX_HEIGHT; i=i+1) begin 
                            if (i < max_y) begin
                                if (curr_x < row_len[i[HEIGHT_BITS-1:0]]) begin
                                    if (grid_mem[i[HEIGHT_BITS-1:0]][curr_x] > 32) begin
                                        col_empty = 0; // if the column has at least a single number in it
                                    end
                                end
                            end
                        end

                        if (col_empty) begin
                            if (in_block) begin
                                state <= S_END_BLOCK;
                            end else begin
                                curr_x <= curr_x + 1;
                            end
                        end else begin
                            if (!in_block) begin
                                in_block <= 1;
                                is_first_p2 <= 1;
                                p2_acc <= 0;
                                for (i=0; i<MAX_HEIGHT; i=i+1) begin
                                    p1_nums[i] <= 0;
                                end
                                operator <= "+";
                            end
                            state <= S_PROCESS_COL;
                        end
                    end
                end


                S_PROCESS_COL: begin
                    // process rows/cols (part 1/2) in parallel
                    col_val = 0;
                    col_has_digit = 0;

                    // identify operator in bottom row:
                    if (curr_x < row_len[max_y-1]) begin
                        char_tmp = grid_mem[max_y-1][curr_x];
                        if (char_tmp == "+" || char_tmp == "*") begin
                            operator <= char_tmp;
                        end
                    end

                    // parallel numeric accumulate:
                    for (i=0; i<MAX_HEIGHT; i=i+1) begin
                        if (i < max_y - 1) begin
                            if (curr_x < row_len[i[HEIGHT_BITS-1:0]]) begin
                                char_tmp = grid_mem[i[HEIGHT_BITS-1:0]][curr_x];
                                if (char_tmp >= "0" && char_tmp <= "9") begin
                                    // accumulate horizontal (part 1):
                                    p1_nums[i[HEIGHT_BITS-1:0]] <= mult10(p1_nums[i[HEIGHT_BITS-1:0]]) + (char_tmp - "0");

                                    // accumulate vertical (part 2):
                                    col_val = mult10(col_val) + (char_tmp - "0");
                                    col_has_digit = 1;
                                end
                            end
                        end
                    end

                    // update part 2 block accumulator:
                    if (col_has_digit) begin
                        if (is_first_p2) begin
                            // if first number, then no need to apply operator
                            p2_acc <= col_val;
                            is_first_p2 <= 0;
                            curr_x <= curr_x + 1;
                            state <= S_SCAN_COL;
                        end else if (operator == "*") begin
                            // use multiply 'subroutine':
                            mult_a <= p2_acc;
                            mult_b <= col_val;
                            next_state <= S_SCAN_COL;
                            state <= S_MULT;
                            curr_x <= curr_x + 1;
                        end else begin
                            // add directly
                            p2_acc <= p2_acc + col_val;
                            curr_x <= curr_x + 1;
                            state <= S_SCAN_COL;
                        end
                    end else begin
                        curr_x <= curr_x + 1;
                        state <= S_SCAN_COL;
                    end
                end


                S_MULT: begin
                    mult_result = mult_a * mult_b;
                    if (next_state == S_SCAN_COL) begin
                        // part 2 - vertical accumulation
                        p2_acc <= mult_result;
                    end else if (next_state == S_BLOCK_REDUCE) begin
                        // part 1 - row-based accumulation
                        p1_acc <= mult_result;
                    end
                    state <= next_state;
                end


                S_END_BLOCK: begin
                    // part 1 reduction begins with first row's total, then go on to sequentially accumulate it
                    p1_acc <= p1_nums[0];
                    curr_y <= 1;
                    state <= S_BLOCK_REDUCE;
                end


                S_BLOCK_REDUCE: begin
                    if (curr_y >= max_y - 1) begin
                        // finished current 'block' -> update output accumulators and begin next block:
                        part1_result <= part1_result + p1_acc;
                        part2_result <= part2_result + p2_acc;
                        in_block <= 0;
                        state <= S_SCAN_COL;
                    end else begin
                        if (operator == "*") begin
                            mult_a <= p1_acc;
                            mult_b <= p1_nums[curr_y];
                            next_state <= S_BLOCK_REDUCE;
                            state <= S_MULT;
                        end else begin
                            p1_acc <= p1_acc + p1_nums[curr_y];
                        end
                        curr_y <= curr_y + 1;
                    end
                end


                S_DONE: begin
                    done <= 1;
                end



            endcase
        end
    end
endmodule
