module day05_core #(
    parameter N_ADDR_BITS = 16,
    parameter MAX_RANGES = 180, // my puzzle input has 177 input ranges
    parameter LOG2_MAX_RANGES = 8
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

    // FSM States and State logic (good god this is a big FSM):
    localparam S_IDLE = 0;

    // parsing pipeline:
    localparam S_PARSE_RANGE = 1;
    localparam S_STORE_RANGE = 2;

    // sorting ranges: // todo: convert range RAM to a shift register that can shift ranges in order to implement optimised insertion sort for online range parsing (rather than parse -> sort as separate stages)
    localparam S_SORT_PREP = 3;
    localparam S_SORT_INNER = 4;
    localparam S_SORT_COMPARE = 5;
    localparam S_SORT_SWAP = 6;

    // merging ranges:
    localparam S_MERGE_INIT = 7;
    localparam S_MERGE_CHECK = 8;
    localparam S_MERGE_SAVE = 9;
    localparam S_MERGE_FINALISE = 10;

    // parse values:
    localparam S_PARSE_VALUE = 11;

    // searching for values:
    localparam S_SEARCH_INIT = 12;
    localparam S_SEARCH_LOOP = 13;
    localparam S_SEARCH_NEXT = 14; // return to parse value state after this

    localparam S_DONE = 15;
    reg [4:0] state;

    // !!! RAM:
    // Range Storage (RAM but implemented within module for simplicity)
    reg [127:0] range_ram [0:MAX_RANGES-1];
    reg [127:0] merged_ram [0:MAX_RANGES-1]; // stored as two 64-bit vals (low, high) 
    
    // range ram controls:
    reg [LOG2_MAX_RANGES-1:0] r_ram_addr;
    wire [127:0] r_ram_rdata;
    assign r_ram_rdata = range_ram[r_ram_addr];

    // merged ram controls:
    reg [LOG2_MAX_RANGES-1:0] m_ram_addr;
    wire [127:0] m_ram_rdata;
    assign m_ram_rdata = merged_ram[m_ram_addr];

    // variables/intermediate registers
    reg [63:0] current_num;
    reg [63:0] range_L;
    reg [63:0] range_R;

    // parsing variables:
    reg [7:0] char_in;
    reg is_parsing_ranges; // 1 = parsing ranges, 0 = values (for part1 lookup)
    reg is_eof;
    reg has_parsed_digit;

    reg [LOG2_MAX_RANGES-1:0] num_ranges;
    reg [LOG2_MAX_RANGES-1:0] num_merged;

    // sorting variables:
    reg [LOG2_MAX_RANGES-1:0] sort_i;
    reg [LOG2_MAX_RANGES-1:0] sort_j;
    reg [127:0] val_A;
    reg [127:0] val_B;

    // merging variables:
    reg [LOG2_MAX_RANGES-1:0] merge_idx;
    reg [63:0] curr_start;
    reg [63:0] curr_end;
    reg [63:0] next_start;
    reg [63:0] next_end;

    // search/lookup variables:
    reg [63:0] search_val;
    reg [LOG2_MAX_RANGES-1:0] low;
    reg [LOG2_MAX_RANGES-1:0] mid;
    reg [LOG2_MAX_RANGES-1:0] high; // uses binary search to optimise lookups

    // logic implementation:
    // this gonna take a long time
    always @(posedge clk) begin
        if (rst) begin
            state <= S_IDLE;
            rom_addr <= 0;
            part1_result <= 0;
            part2_result <= 0;
            done <= 0;
            num_ranges <= 0;
            num_merged <= 0;
            is_parsing_ranges <= 1;
            is_eof <= 0;
            current_num <= 0;
            has_parsed_digit <= 0;
        end else begin
            case (state)
                S_IDLE: begin
                    state <= S_PARSE_RANGE;
                    rom_addr <= 0;
                    current_num <= 0;
                    has_parsed_digit <= 0;
                end

                //! ----------------------
                //! Parsing Ranges States:
                //! ----------------------

                S_PARSE_RANGE: begin
                    if (rom_valid) begin
                        char_in = rom_data; 

                        // check if numeric char:
                        if (char_in >= "0" && char_in <= "9") begin
                            current_num <= (current_num*10) + (char_in - "0");
                            has_parsed_digit <= 1;
                        end else if (char_in == "-") begin
                            range_L <= current_num;
                            current_num <= 0;
                            has_parsed_digit <= 0;
                        end else if (char_in == "\n") begin
                            if (has_parsed_digit) begin
                                range_R <= current_num;
                                state <= S_STORE_RANGE;
                            end else begin
                                // if reach newline without parsing nums, we must've reached the \n\n that separates ranges from IDs
                                is_parsing_ranges <= 0;
                                state <= S_SORT_PREP;
                            end
                        end

                        // increment for next character (if not moving to different state)
                        if (char_in != "\n" || (char_in == "\n" && !has_parsed_digit)) begin // todo: review this logic something tickles me wrong about it
                                rom_addr <= rom_addr + 1;
                        end
                    end else begin
                        // reached EOF - shouldn't happen
                        // $display("Input file probably malformed!")
                        state <= S_DONE;
                    end
                end


                S_STORE_RANGE: begin
                    // write the range to RAM:
                    range_ram[num_ranges] <= {range_L, range_R};
                    num_ranges <= num_ranges + 1;

                    // reset parsing variables:
                    current_num <= 0;
                    has_parsed_digit <= 0;

                    // continue parsing:
                    rom_addr <= rom_addr + 1;
                    state <= S_PARSE_RANGE;
                end

                //! ----------------------
                //! Sorting Ranges Stages:
                //! ----------------------
                S_SORT_PREP: begin
                    if (num_ranges < 2) begin
                        state <= S_MERGE_INIT;
                    end else begin
                        sort_i <= 0;
                        sort_j <= 0;
                        state <= S_SORT_INNER;
                        // $display("Starting sort: %d ranges", num_ranges);
                    end
                end

                S_SORT_INNER: begin
                    if (sort_i >= num_ranges - 1) begin
                        state <= S_MERGE_INIT;
                    end else if (sort_j >= num_ranges - 1 - sort_i) begin
                        sort_i <= sort_i + 1;
                        sort_j <= 0;
                        state <= S_SORT_INNER;
                    end else begin
                        r_ram_addr <= sort_j;
                        state <= S_SORT_COMPARE;
                    end
                end

                S_SORT_COMPARE: begin
                    val_A = r_ram_rdata;
                    r_ram_addr = sort_j + 1;
                    val_B = r_ram_rdata; // this is icky, likely won't synthesise well, should probably add a buffer clock cycle to store valA and val_B separately

                    if (val_A[127:64] > val_B[127:64]) begin
                        val_B = range_ram[sort_j + 1];
                        state <= S_SORT_SWAP;
                    end else begin
                        sort_j <= sort_j + 1;
                        state <= S_SORT_INNER;
                    end
                end

                S_SORT_SWAP: begin
                    range_ram[sort_j] <= val_B;
                    range_ram[sort_j + 1] <= val_A;
                    sort_j <= sort_j + 1;
                    state <= S_SORT_INNER;
                end

                //! ----------------------
                //! Merging Ranges Stages:
                //! ----------------------
                S_MERGE_INIT: begin
                    merge_idx <= 0;
                    num_merged <= 0;
                    part2_result <= 0;
                    state <= S_MERGE_CHECK;
                end

                S_MERGE_CHECK: begin
                    if (merge_idx == 0) begin
                        curr_start <= range_ram[0][127:64];
                        curr_end <= range_ram[0][63:0];
                        merge_idx <= 1;
                        state <= S_MERGE_CHECK;
                    end else if (merge_idx < num_ranges) begin
                        next_start = range_ram[merge_idx][127:64];
                        next_end = range_ram[merge_idx][63:0];
                        if (next_start <= curr_end + 1) begin
                            if (next_end > curr_end) begin
                                curr_end <= next_end;
                            end 
                            merge_idx <= merge_idx + 1;
                        end else begin
                            state <= S_MERGE_SAVE;
                        end
                    end else begin
                        state <= S_MERGE_FINALISE;
                    end
                end

                S_MERGE_SAVE: begin
                    merged_ram[num_merged] <= {curr_start, curr_end};
                    num_merged <= num_merged + 1;
                    part2_result <= part2_result + (curr_end - curr_start + 1);
                    curr_start <= next_start;
                    curr_end <= next_end;
                    merge_idx <= merge_idx + 1;
                    state <= S_MERGE_CHECK;
                end

                S_MERGE_FINALISE: begin
                    // save the final range:
                    merged_ram[num_merged] <= {curr_start, curr_end};
                    num_merged <= num_merged + 1;
                    part2_result <= part2_result + (curr_end - curr_start + 1);

                    // transition to parsing values stage:
                    current_num <= 0;
                    has_parsed_digit <= 0;
                    rom_addr <= rom_addr + 1;
                    state <= S_PARSE_VALUE;
                end


                //! ------------------------------------
                //! Parsing Values and Searching Stages:
                //! ------------------------------------
                S_PARSE_VALUE: begin
                    if (rom_valid) begin
                        char_in = rom_data;

                        if (char_in >= "0" && char_in <= "9") begin
                            current_num <= (current_num * 10) + (char_in - "0");
                            has_parsed_digit <= 1;
                        end else if (char_in == "\n") begin
                            if (has_parsed_digit) begin
                                search_val <= current_num;
                                state <= S_SEARCH_INIT;
                            end
                            // ignore empty lines / training newlines
                        end

                        // advance rom address
                        rom_addr <= rom_addr + 1;
                    end else begin
                        // reached EOF, check final ID:
                        if (has_parsed_digit) begin
                            search_val <= current_num;
                            state <= S_SEARCH_INIT;
                            is_eof <= 1;
                        end else begin
                            state <= S_DONE;
                        end
                    end
                end

                S_SEARCH_INIT: begin
                    // $display("Searching for %d", search_val);
                    low <= 0;
                    high <= num_merged - 1;
                    state <= S_SEARCH_LOOP;
                end

                S_SEARCH_LOOP: begin
                    if (low > high) begin
                        state <= S_SEARCH_NEXT;
                    end else begin
                        mid = low + (high-low) / 2;
                        m_ram_addr = mid;
                        if (search_val >= m_ram_rdata[127:64] && search_val <= m_ram_rdata[63:0]) begin
                            // found enclosing interval:
                            part1_result <= part1_result + 1;
                            state <= S_SEARCH_NEXT;
                        end else if (search_val < m_ram_rdata[127:64]) begin
                            if (mid == 0) begin
                                state <= S_SEARCH_NEXT;
                            end else begin
                                high <= mid-1;
                                state <= S_SEARCH_LOOP;
                            end
                        end else begin
                            low <= mid + 1;
                            state <= S_SEARCH_LOOP;
                        end
                    end

                end

                S_SEARCH_NEXT: begin
                    current_num <= 0;
                    has_parsed_digit <= 0;

                    if (is_eof) begin
                        state <= S_DONE;
                    end else begin
                        state <= S_PARSE_VALUE;
                    end
                end

                S_DONE: begin
                    // holy YOOOOOOOOOOOOOOOOOOOOOOO IT WORKED
                    done <= 1;
                end
            endcase
        end
    end
endmodule
