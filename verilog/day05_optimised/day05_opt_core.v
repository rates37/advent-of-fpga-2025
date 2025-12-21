module day05_opt_core #(
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

    // FSM States and State logic
    localparam S_IDLE = 0;

    // parsing and merge/sorting:
    localparam S_PARSE_RANGE = 1;
    localparam S_INSERT_SHIFT = 2;
    localparam S_MERGE_INIT = 3;
    localparam S_MERGE_CHECK = 4;
    localparam S_MERGE_SAVE = 5;
    localparam S_MERGE_FINALISE = 6;

    // parse values:
    localparam S_PARSE_VALUE = 7;

    // searching for values:
    localparam S_SEARCH_INIT = 8;
    localparam S_SEARCH_LOOP = 9;
    localparam S_SEARCH_EVAL = 10;
    localparam S_SEARCH_NEXT = 11; // return to parse value state after this

    localparam S_DONE = 12;
    reg [3:0] state;

    // !!! RAM:
    // Range Storage (RAM but implemented within module for simplicity)
    reg [127:0] range_ram [0:MAX_RANGES-1];
    reg [127:0] merged_ram [0:MAX_RANGES-1]; // stored as two 64-bit vals (low, high) 
    
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

    // insertion logic signals:
    wire [MAX_RANGES-1:0] cmp_mask; // cmp_mask[i] is 1 if current range's lower bound is 
                                    //  less than the range at position i in the range_ram 
                                    //  (i.e., it will need to be shifted in order to insert 
                                    //  the newly parsed range)
    genvar i;
    generate
        for (i=0; i<MAX_RANGES; i=i+1) begin : gen_cmp
            assign cmp_mask[i] = (i < num_ranges) && (range_ram[i][127:64] > range_L);
        end
    endgenerate

    // 16:4 priority encoder
    function [4:0] prio16(input [15:0] mask);
        begin
            if (mask[0]) prio16 = 5'd0;
            else if (mask[1]) prio16 = 5'd1;
            else if (mask[2]) prio16 = 5'd2;
            else if (mask[3]) prio16 = 5'd3;
            else if (mask[4]) prio16 = 5'd4;
            else if (mask[5]) prio16 = 5'd5;
            else if (mask[6]) prio16 = 5'd6;
            else if (mask[7]) prio16 = 5'd7;
            else if (mask[8]) prio16 = 5'd8;
            else if (mask[9]) prio16 = 5'd9;
            else if (mask[10]) prio16 = 5'd10;
            else if (mask[11]) prio16 = 5'd11;
            else if (mask[12]) prio16 = 5'd12;
            else if (mask[13]) prio16 = 5'd13;
            else if (mask[14]) prio16 = 5'd14;
            else if (mask[15]) prio16 = 5'd15;
            else prio16 = 5'd16; // code for not found
        end
    endfunction

    wire [4:0] block_prio [15:0];
    wire [15:0] block_valid;
    generate
        for (i=0; i<16; i=i+1) begin : gen_prio
            assign block_prio[i] = prio16(cmp_mask[i*16 +: 16]);
            assign block_valid[i] = (block_prio[i] != 5'd16);
        end
    endgenerate

    wire [4:0] master_prio = prio16(block_valid);
    wire [LOG2_MAX_RANGES-1:0] target_idx = (master_prio == 5'd16) ? num_ranges : {master_prio[3:0], block_prio[master_prio[3:0]][3:0]};

    // merging variables:
    reg [LOG2_MAX_RANGES-1:0] merge_idx;
    reg [63:0] curr_start;
    reg [63:0] curr_end;

    // search/lookup variables:
    reg [63:0] search_val;
    reg [LOG2_MAX_RANGES-1:0] low;
    reg [LOG2_MAX_RANGES-1:0] mid;
    reg [LOG2_MAX_RANGES-1:0] high; // uses binary search to optimise lookups

    integer k;

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
            m_ram_addr <= 0;
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
                        char_in = rom_data;  // todo: this is useless just use rom_data directly

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
                                state <= S_INSERT_SHIFT;
                            end else begin
                                // if reach newline without parsing nums, we must've reached the \n\n that separates ranges from IDs
                                is_parsing_ranges <= 0;
                                state <= S_MERGE_INIT;
                            end
                        end

                        // increment for next character (if not moving to different state)
                        if (char_in != "\n" || (char_in == "\n" && !has_parsed_digit)) begin // todo: review this logic something tickles me wrong about it
                                rom_addr <= rom_addr + 1;
                        end
                    end else begin
                        // reached EOF - shouldn't happen
                        $display("Input file probably malformed!");
                        state <= S_DONE;
                    end
                end


                S_INSERT_SHIFT: begin
                    // single-cycle parallel shift
                    for (k=0; k<MAX_RANGES; k=k+1) begin
                        if (k==target_idx) begin
                            range_ram[k] <= {range_L, range_R};
                        end else if (k>target_idx && k <= num_ranges) begin
                            range_ram[k] <= range_ram[k-1];
                        end
                    end
                    num_ranges <= num_ranges + 1;

                    current_num <= 0;
                    has_parsed_digit <= 0;
                    rom_addr <= rom_addr + 1;
                    state <= S_PARSE_RANGE;
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
                    end else if (merge_idx < num_ranges) begin
                        if (range_ram[merge_idx][127:64] <= curr_end + 1) begin
                            if (range_ram[merge_idx][63:0] > curr_end) begin
                                curr_end <= range_ram[merge_idx][63:0];
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
                    curr_start <= range_ram[merge_idx][127:64]; 
                    curr_end <= range_ram[merge_idx][63:0];
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
                        char_in = rom_data; // todo: like previous parsing state, this is useless just use rom_data directly

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
                        if (state == S_PARSE_VALUE && !(rom_data == 10 && has_parsed_digit)) begin
                            rom_addr <= rom_addr + 1;
                        end
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
                        m_ram_addr <= low + (high-low) / 2;
                        state <= S_SEARCH_EVAL;
                    end

                end

                S_SEARCH_EVAL: begin
                    mid <= m_ram_addr;
                    if (search_val >= m_ram_rdata[127:64] && search_val <= m_ram_rdata[63:0]) begin
                        part1_result <= part1_result + 1;
                        state <= S_SEARCH_NEXT;
                    end else if (search_val < m_ram_rdata[127:64]) begin
                        if (m_ram_addr == 0) begin
                            state <= S_SEARCH_NEXT;
                        end else begin
                            high <= m_ram_addr - 1;
                            state <= S_SEARCH_LOOP;
                        end
                    end else begin
                            low <= m_ram_addr + 1;
                            state <= S_SEARCH_LOOP;
                    end
                end

                S_SEARCH_NEXT: begin
                    current_num <= 0;
                    has_parsed_digit <= 0;

                    if (is_eof) begin
                        state <= S_DONE;
                    end else begin
                        state <= S_PARSE_VALUE;
                        rom_addr <= rom_addr + 1;
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
