module day03_core #(
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

    // constants/localparams:
    localparam MAX_LINE_LEN = 128; // Max characters per line supported by solver (real problem input was 100 chars)
    localparam LOG_MAX_LINE_LEN = 7; // Bits needed to address MAX_LINE_LEN = ceil(log2(MAX_LINE_LEN))


    // FSM / state:
    /* 
     * We will load in data and process simultaneously -> two 'contexts' to consider
     * Context 0: Loading line (reading from ROM) into bitmap of positions
     * Context 1: Processing line (computing p1 and p2 answers)
     * When a newline is found(i.e., finished reading in current line), they swap 
     * (will stall until both contexts are finished current task)
     * So idea is that while line[i] is being read in, line[i-1] will be being processed
    */
    reg [MAX_LINE_LEN-1:0] digits_valid_bitmap [0:1][0:9]; // two 10x x128-bit buffers
    reg [LOG_MAX_LINE_LEN:0] line_length [0:1];
    reg [LOG_MAX_LINE_LEN:0] load_idx;
    reg load_buf_idx;
    reg proc_buf_idx;
    reg proc_active;

    // result accumulators:
    reg [63:0] p1_acc;
    reg [63:0] p2_acc;

    // processing fsm states:
    localparam S_IDLE = 0;
    localparam S_CALC_P1 = 1;
    localparam S_CALC_P2 = 2;
    localparam S_DONE = 3;
    reg [2:0] state;
    reg [3:0] remaining_len; // only need to store up to 2(part 1) or 12 (part 2)
    reg [LOG_MAX_LINE_LEN:0] current_scan_idx; // where we are currently in the line
    reg [63:0] current_val_accum; // accumulate the value for the current line / query (since will be queries for 2 and 12)


    // ! Decoding / loading FSM:
    wire [7:0] char_in = rom_data;
    wire digit_valid = (char_in >= "0" && char_in <= "9");
    wire [3:0] digit_val = digit_valid ? (char_in - "0") : 4'd0; // default value of 0
    wire char_is_newline = (char_in == "\n" || char_in == 0); // file might accidentally not have trailing newline
    integer j;
    wire next_buf_idx = ~load_buf_idx;
    wire proc_busy_on_next = (state != S_IDLE && proc_buf_idx == next_buf_idx); // need to check if proc busy working on buffer that we want to switch to
    wire stall = char_is_newline && proc_busy_on_next;

    always @(posedge clk) begin
        if (rst) begin
            rom_addr <= 0;
            load_idx <= 0;
            load_buf_idx <= 0;
            // clear bitmaps:
            for (j=0; j<10; j=j+1) begin
                digits_valid_bitmap[0][j] <= 0;
                digits_valid_bitmap[1][j] <= 0;
            end
            proc_active <= 0;
        end else if (!done) begin
            // read addr logic:
            if ((rom_valid || rom_addr == 0) && !stall) begin
                rom_addr <= rom_addr + 1;
            end

            // write to buffer:
            if (rom_valid && !stall) begin
                if (digit_valid && load_idx < MAX_LINE_LEN) begin
                    // set bit in relevant bitmap:
                    digits_valid_bitmap[load_buf_idx][digit_val][load_idx] <= 1'b1;
                    load_idx <= load_idx + 1;
                end else if (char_is_newline) begin
                    line_length[load_buf_idx] <= load_idx;
                    // swap buffers:
                    load_buf_idx <= ~load_buf_idx;
                    // clear the next buffer:
                    for (j=0; j<10; j=j+1) begin
                        digits_valid_bitmap[~load_buf_idx][j] <= 0;
                        load_idx <= 0;
                    end
                end
            end
        end
    end

    // ! End of Decoding FSM logic


    //! Processing / compute logic:
    reg prev_load_buf_idx;

    // helper to find first set bit in a range of a bitmap:
    function [LOG_MAX_LINE_LEN:0] find_first_set;
        input [MAX_LINE_LEN-1:0] bitmap;
        input [LOG_MAX_LINE_LEN:0] start_range;
        input [LOG_MAX_LINE_LEN:0] end_range;
        integer i;
        reg found;
    begin
        find_first_set = MAX_LINE_LEN; // default to not found
        found = 0;
        // in simulation the loop bounds can be start_range and end_range 
        //  but some synthesisers won't handle this so left the larger loop 
        //  bounds for now
        for (i=0; i<MAX_LINE_LEN; i=i+1) begin 
            if (i >= start_range && i <= end_range && !found) begin
                if (bitmap[i]) begin
                    find_first_set = i;
                    found = 1;
                end
            end
        end
    end
    endfunction

    // helper to pick next digit:
    reg [3:0] best_digit;
    reg [LOG_MAX_LINE_LEN:0] best_digit_pos;
    reg found_digit;
    integer d;
    reg [LOG_MAX_LINE_LEN:0] search_limit;
    reg [LOG_MAX_LINE_LEN:0] found_pos_temp;

    always @(*) begin
        found_digit = 0;
        best_digit = 0;
        best_digit_pos = 0;
        search_limit = line_length[proc_buf_idx] - remaining_len;

        // scan 9 down to 0
        for (d=9; d>=0; d = d-1) begin
            if (!found_digit) begin
                found_pos_temp = find_first_set(digits_valid_bitmap[proc_buf_idx][d], current_scan_idx, search_limit);
                if (found_pos_temp != MAX_LINE_LEN) begin
                    found_digit = 1;
                    best_digit = d[3:0];
                    best_digit_pos = found_pos_temp;
                end
            end
        end
    end

    // proc fsm logic:
    always @(posedge clk) begin
        if (rst) begin
            state <= S_IDLE;
            prev_load_buf_idx <= 0;
            proc_buf_idx <= 0;
            p1_acc <= 0;
            part1_result <= 0;
            p2_acc <= 0;
            part2_result <= 0;
            done <= 0;
        end else begin
            case (state)
                S_IDLE: begin
                    if (load_buf_idx != prev_load_buf_idx) begin // this if statement effectively blocks the computing FSM until the decoding FSM has a newly decoded line ready to process
                        proc_buf_idx <= prev_load_buf_idx;
                        prev_load_buf_idx <= load_buf_idx;

                        // start calculating part 1 result:
                        state <= S_CALC_P1;
                        remaining_len <= 2;
                        current_scan_idx <= 0;
                        current_val_accum <= 0;
                    end else if (!rom_valid && rom_addr > 0) begin
                        // finished
                        done <= 1;
                        part1_result <= p1_acc;
                        part2_result <= p2_acc;
                        state <= S_DONE;
                    end
                end

                S_CALC_P1: begin
                    if (remaining_len > 0) begin
                        current_val_accum <= (current_val_accum * 10) + {60'd0, best_digit};// make sure widths align (also stops from being treated as negative)
                        current_scan_idx <= best_digit_pos + 1;
                        remaining_len <= remaining_len - 1;
                    end else begin
                        // accumulate part 1 result:
                        p1_acc <= p1_acc + current_val_accum;

                        // move to compute part 2 result:
                        state <= S_CALC_P2;
                        remaining_len <= 12;
                        current_scan_idx <= 0;
                        current_val_accum <= 0;
                    end
                end


                S_CALC_P2: begin
                    if (remaining_len > 0) begin
                        current_val_accum <= (current_val_accum * 10) + {60'd0, best_digit};// make sure widths align (also stops from being treated as negative)
                        current_scan_idx <= best_digit_pos + 1;
                        remaining_len <= remaining_len - 1;
                    end else begin
                        // accumulate part 2 result:
                        p2_acc <= p2_acc + current_val_accum;

                        // go to idle to process next line:
                        state <= S_IDLE;
                    end
                end

                S_DONE: begin
                    done <= 1;
                end
            endcase
        end
    end
endmodule
