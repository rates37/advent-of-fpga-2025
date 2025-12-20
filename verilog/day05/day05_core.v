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
    localparam S_SORT_OUTER = 4;
    localparam S_SORT_INNER = 5;
    localparam S_SORT_READ_A = 6;
    localparam S_SORT_READ_B = 7;
    localparam S_SORT_COMPARE = 8;
    localparam S_SORT_SWAP_1 = 9;
    localparam S_SORT_SWAP_2 = 10;

    // merging ranges:
    localparam S_MERGE_INIT = 11;
    localparam S_MERGE_READ = 12;
    localparam S_MERGE_CHECK = 13;
    localparam S_MERGE_SAVE = 14;
    localparam S_MERGE_FINALISE = 15;

    // parse values:
    localparam S_PARSE_VALUE = 16;

    // searching for values:
    localparam S_SEARCH_INIT = 17;
    localparam S_SEARCH_CHECK = 18;
    localparam S_SEARCH_READ = 19;
    localparam S_SEARCH_EVAL = 20;
    localparam S_SEARCH_NEXT = 21; // return to parse value state after this

    localparam S_DONE = 22;
    reg [4:0] state;

    // !!! RAM:
    // Range Storage (RAM but implemented within module for simplicity)
    reg [127:0] range_ram [0:MAX_RANGES-1];
    reg [127:0] merged_ram [0:MAX_RANGES-1]; // stored as two 64-bit vals (low, high) 
    
    // range ram controls:
    reg [LOG2_MAX_RANGES-1:0] r_ram_addr;
    reg r_ram_we;
    reg [127:0] r_ram_wdata;
    reg [127:0] r_ram_rdata;

    // merged ram controls:
    reg [LOG2_MAX_RANGES-1:0] m_ram_addr;
    reg m_ram_we;
    reg [127:0] m_ram_wdata;
    reg [127:0] m_ram_rdata;

    // ram logic:
    always @(posedge clk) begin
        if (r_ram_we) begin
            range_ram[r_ram_addr] <= r_ram_wdata;
        end
        r_ram_rdata <= range_ram[r_ram_addr];
    end

    always @(posedge clk) begin
        if (m_ram_we) begin
            merged_ram[m_ram_addr] <= m_ram_wdata;
        end
        m_ram_rdata <= merged_ram[m_ram_addr];
    end

    // variables/intermediate registers
    reg [63:0] current_num;
    reg [63:0] range_L;
    reg [63:0] range_R;

    // parsing variables:
    reg [7:0] char_in;
    reg char_valid;

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
            r_ram_we <= 0;
            m_ram_we <= 0;
            current_num <= 0;
            has_parsed_digit <= 0;
        end else begin
            // default prevent writing to ram:
            r_ram_we <= 0;
            m_ram_we <= 0;

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
                        // reached EOF
                        state <= S_DONE;
                    end
                end


                S_STORE_RANGE: begin
                    // write the range to RAM:
                    r_ram_addr <= num_ranges;
                    r_ram_wdata <= {range_L, range_R};
                    r_ram_we <= 1;
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
                        state <= S_SORT_OUTER;
                        // $display("Starting sort: %d ranges", num_ranges);
                    end
                end

                S_SORT_OUTER: begin
                    if (sort_i >= num_ranges - 1) begin
                        state <= S_MERGE_INIT;
                    end else begin
                        sort_j <= 0;
                        state <= S_SORT_INNER;
                    end
                end

                S_SORT_INNER: begin
                    if (sort_j >= num_ranges - 1 - sort_i) begin
                        sort_i <= sort_i + 1;
                        state <= S_SORT_OUTER;
                    end else begin
                        r_ram_addr <= sort_j;
                        state <= S_SORT_READ_A;
                    end
                end

                S_SORT_READ_A: begin
                    // r_ram_adr was set to sort_j in S_SORT_INNER
                    r_ram_addr <= sort_j + 1;
                    state <= S_SORT_READ_B;
                end

                S_SORT_READ_B: begin
                    val_A <= r_ram_rdata;
                    // r_ram_rdata is sort_j + 1 (set in S_SORT_READ_A)
                    state <= S_SORT_COMPARE;
                end

                S_SORT_COMPARE: begin
                    val_B <= r_ram_rdata;
                    state <= S_SORT_SWAP_1;
                end

                S_SORT_SWAP_1: begin
                    if (val_A[127:64] > val_B[127:64]) begin
                        // need to swap since out of order:
                        // $display("Swapping indices %d and %d because: %d > %d", sort_j, sort_j+1, val_A[127:64], val_B[127:64]);
                        r_ram_addr <= sort_j;
                        r_ram_wdata <= val_B;
                        r_ram_we <= 1;
                        state <= S_SORT_SWAP_2; // need to write val A into the old position of valB to complete the swap
                    end else begin
                        // already in order -> move to next pair
                        sort_j <= sort_j + 1; // todo: can make this more efficient since range[sort_j+1] is already loaded -> can save a clock cycle on each inner loop?
                                              // currently leaving as a todo because more important to get mvp working and already implementing a lot of optimisations
                        state <= S_SORT_INNER;
                    end
                end

                S_SORT_SWAP_2: begin
                    r_ram_addr <= sort_j + 1;
                    r_ram_wdata <= val_A;
                    r_ram_we <= 1;
                    sort_j <= sort_j + 1;
                    state <= S_SORT_INNER;
                end


                //! ----------------------
                //! Merging Ranges Stages:
                //! ----------------------
                S_MERGE_INIT: begin
                    // if (num_ranges == 0) begin
                    //     $display("Something has gone very wrong: no ranges parsed");
                    // end
                    merge_idx <= 0;
                    r_ram_addr <= 0;
                    num_merged <= 0;
                    state <= S_MERGE_READ;
                end

                S_MERGE_READ: begin
                    state <= S_MERGE_CHECK;
                end

                S_MERGE_CHECK: begin
                    if (merge_idx == 0) begin
                        curr_start <= r_ram_rdata[127:64];
                        curr_end <= r_ram_rdata[63:0];
                        merge_idx <= 1;
                        r_ram_addr <= 1;
                        state <= S_MERGE_READ;
                    end else if (merge_idx <= num_ranges) begin
                        if (merge_idx == num_ranges) begin
                            state <= S_MERGE_FINALISE;
                        end else begin
                            next_start = r_ram_rdata[127:64];
                            next_end = r_ram_rdata[63:0];

                            if (next_start <= curr_end+1) begin
                                if (next_end > curr_end) begin
                                    curr_end <= next_end;
                                end
                                // keep reading ranges to merge as many sequential ranges as possible 
                                merge_idx <= merge_idx + 1;
                                r_ram_addr <= merge_idx + 1;
                                state <= S_MERGE_READ;
                            end else begin
                                // once we reach a discontinuity, save the currently accumulated range into the merged range RAM
                                state <= S_MERGE_SAVE;
                            end
                        end
                    end
                end

                S_MERGE_SAVE: begin
                    m_ram_addr <= num_merged;
                    m_ram_wdata <= {curr_start, curr_end};
                    m_ram_we <= 1;
                    num_merged <= num_merged + 1;
                    part2_result <= part2_result + (curr_end - curr_start + 1); // calculate p2 result as merging ranges 
                    curr_start <= next_start;
                    curr_end <= next_end;
                    merge_idx <= merge_idx + 1;
                    r_ram_addr <= merge_idx + 1;
                    state <= S_MERGE_READ;
                end

                S_MERGE_FINALISE: begin
                    // save the final range:
                    m_ram_addr <= num_merged;
                    m_ram_wdata <= {curr_start, curr_end};
                    m_ram_we <= 1;
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
                    state <= S_SEARCH_CHECK;
                end

                S_SEARCH_CHECK: begin
                    if (low > high) begin
                        // failed to find an interval that contains search_val
                        state <= S_SEARCH_NEXT;
                    end else begin
                        mid <= low + (high - low) / 2;
                        m_ram_addr <= low + (high - low) / 2;
                        state <= S_SEARCH_READ;
                    end
                end

                S_SEARCH_READ: begin
                    // state to wait for data from RAM to be read
                    state <= S_SEARCH_EVAL;

                end

                S_SEARCH_EVAL: begin
                    if (search_val >= m_ram_rdata[127:64] && search_val <= m_ram_rdata[63:0]) begin
                        // found an enclosing interval
                        part1_result <= part1_result  + 1;
                        state <= S_SEARCH_NEXT;
                    end else if (search_val < m_ram_rdata[127:64]) begin 
                        if (mid == 0) begin
                            state <= S_SEARCH_NEXT;
                        end else begin
                            high <= mid-1;
                            state <= S_SEARCH_CHECK;
                        end
                    end else begin
                            low <= mid + 1;
                            state <= S_SEARCH_CHECK;
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
