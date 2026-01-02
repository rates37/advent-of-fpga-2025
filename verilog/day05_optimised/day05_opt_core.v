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

    // parsing and sorting:
    localparam S_PARSE_RANGE = 1;
    localparam S_INSERT_START = 2;
    localparam S_INSERT_READ = 3;
    localparam S_INSERT_WAIT = 4;
    localparam S_INSERT_CHECK = 5;
    localparam S_INSERT_WRITE_DONE = 6;

    // merging:
    localparam S_MERGE_INIT = 7;
    localparam S_MERGE_READ = 8;
    localparam S_MERGE_CHECK = 9;
    localparam S_MERGE_SAVE = 10;

    // parse values:
    localparam S_PARSE_VALUE = 11;

    // searching for values:
    localparam S_SEARCH_INIT = 12;
    localparam S_SEARCH_LOOP = 13;
    localparam S_SEARCH_WAIT = 14;
    localparam S_SEARCH_EVAL = 15;
    localparam S_SEARCH_NEXT = 16; // return to parse value state after this

    localparam S_DONE = 17;
    reg [4:0] state;

    // !!! RAM:
    reg r_ram_we;
    reg [LOG2_MAX_RANGES-1:0] r_ram_addr;
    reg [127:0] r_ram_w_data;
    wire [127:0] r_ram_r_data;

    ram #(
        .WIDTH(128), // 64-bit Start + 64-bit End
        .DEPTH(MAX_RANGES),
        .ADDR_BITS(LOG2_MAX_RANGES)
    ) u_range_ram_0 (
        .clk(clk),
        .rst(rst),
        .we(r_ram_we),
        .w_addr(r_ram_addr),
        .w_data(r_ram_w_data),
        .r_addr(r_ram_addr),
        .r_data(r_ram_r_data)
    );

    reg m_ram_we;
    reg [LOG2_MAX_RANGES-1:0] m_ram_addr;
    reg [127:0] m_ram_w_data;
    wire [127:0] m_ram_r_data;
    ram #(
        .WIDTH(128),
        .DEPTH(MAX_RANGES),
        .ADDR_BITS(LOG2_MAX_RANGES)
    ) u_merged_ram_0 (
        .clk(clk),
        .rst(rst),
        .we(m_ram_we),
        .w_addr(m_ram_addr),
        .w_data(m_ram_w_data),
        .r_addr(m_ram_addr),
        .r_data(m_ram_r_data)
    );


    // variables/intermediate registers
    reg [63:0] current_num;
    reg [63:0] range_L;
    reg [63:0] range_R;

    // parsing variables:
    reg is_parsing_ranges; // 1 = parsing ranges, 0 = values (for part1 lookup)
    reg is_eof;
    reg has_parsed_digit;

    reg [LOG2_MAX_RANGES:0] num_ranges;
    reg [LOG2_MAX_RANGES:0] num_merged;

    // insertion:
    reg [LOG2_MAX_RANGES:0] scan_idx;

    // merging variables:
    reg [LOG2_MAX_RANGES:0] merge_idx;
    reg [63:0] curr_start;
    reg [63:0] curr_end;

    // search/lookup variables:
    reg [63:0] search_val;
    reg [LOG2_MAX_RANGES:0] low;
    reg [LOG2_MAX_RANGES:0] high; // uses binary search to optimise lookups

    // logic implementation:
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
            r_ram_we <= 0;
            m_ram_we <= 0;
            r_ram_addr <= 0;
            m_ram_addr <= 0;
        end else begin
            // default disable writes
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
                        // check if numeric char:
                        if (rom_data >= "0" && rom_data <= "9") begin
                            current_num <= ((current_num<<3) + (current_num<<1)) + (rom_data - "0");
                            has_parsed_digit <= 1;
                        end else if (rom_data == "-") begin
                            range_L <= current_num;
                            current_num <= 0;
                            has_parsed_digit <= 0;
                        end else if (rom_data == "\n") begin
                            if (has_parsed_digit) begin
                                range_R <= current_num;
                                state <= S_INSERT_START;
                            end else begin
                                // if reach newline without parsing nums, we must've reached the \n\n that separates ranges from IDs
                                is_parsing_ranges <= 0;
                                state <= S_MERGE_INIT;
                            end
                        end

                        // increment for next character (if not moving to insert)
                        if (!(rom_data == "\n" && has_parsed_digit)) begin
                                rom_addr <= rom_addr + 1;
                        end
                    end else begin
                        // reached EOF - shouldn't happen
                        $display("Input file probably malformed!");
                        state <= S_DONE;
                    end
                end

                // Insertion sort:
                S_INSERT_START: begin
                    if (num_ranges == 0) begin
                        r_ram_addr <= 0;
                        r_ram_w_data <= {range_L, range_R};
                        r_ram_we <= 1;
                        num_ranges <= 1;
                        state <= S_INSERT_WRITE_DONE;
                    end else begin
                        scan_idx <= num_ranges-1;
                        state <= S_INSERT_READ;
                    end
                end

                S_INSERT_READ: begin
                    r_ram_addr <= scan_idx;
                    state <= S_INSERT_WAIT;
                end

                S_INSERT_WAIT: begin
                    state <= S_INSERT_CHECK;
                end

                S_INSERT_CHECK: begin
                    if (r_ram_r_data[127:64] > range_L) begin
                        r_ram_addr <= scan_idx + 1;
                        r_ram_w_data <= r_ram_r_data;
                        r_ram_we <= 1;

                        if (scan_idx == 0) begin
                            scan_idx <= {LOG2_MAX_RANGES+1{1'b1}}; // insert -1 here
                            state <= S_INSERT_WRITE_DONE;
                        end else begin
                            scan_idx <= scan_idx - 1;
                            state <= S_INSERT_READ;
                        end
                    end else begin
                        r_ram_addr <= scan_idx + 1;
                        r_ram_w_data <= {range_L, range_R};
                        r_ram_we <= 1;
                        num_ranges <= num_ranges + 1;
                        state <= S_INSERT_WRITE_DONE;
                    end
                end

                S_INSERT_WRITE_DONE: begin
                    if (scan_idx[LOG2_MAX_RANGES] == 1) begin // equivalent to checking scan_idx == -1
                        // if every element from the first position was shifted:
                        r_ram_addr <= 0;
                        r_ram_w_data <= {range_L, range_R};
                        r_ram_we <= 1;
                        num_ranges <= num_ranges + 1;
                    end

                    // continue parsing next range:
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
                    r_ram_addr <= 0;
                    state <= S_MERGE_READ;
                end

                S_MERGE_READ: begin
                    state <= S_MERGE_CHECK;
                end

                S_MERGE_CHECK: begin
                    if (merge_idx == 0) begin
                        curr_start <= r_ram_r_data[127:64];
                        curr_end <= r_ram_r_data[63:0];
                        merge_idx <= 1;
                        r_ram_addr <= 1;
                        state <= S_MERGE_READ;
                    end else begin
                        if (r_ram_r_data[127:64] <= curr_end + 1) begin
                            if (r_ram_r_data[63:0] > curr_end) begin
                                curr_end <= r_ram_r_data[63:0];
                            end
                        end else begin
                            m_ram_addr <= num_merged;
                            m_ram_w_data <= {curr_start, curr_end};
                            m_ram_we <= 1;
                            num_merged <= num_merged + 1;
                            part2_result <= part2_result + (curr_end - curr_start + 1);

                            curr_start <= r_ram_r_data[127:64];
                            curr_end <= r_ram_r_data[63:0];

                        end
                        if (merge_idx + 1 < num_ranges) begin
                            merge_idx <= merge_idx + 1;
                            r_ram_addr <= merge_idx + 1;
                            state <= S_MERGE_READ;
                        end else begin
                            state <= S_MERGE_SAVE;
                        end
                    end
                end

                S_MERGE_SAVE: begin
                    m_ram_addr <= num_merged;
                    m_ram_w_data <= {curr_start, curr_end};
                    m_ram_we <= 1;
                    num_merged <= num_merged + 1;
                    part2_result <= part2_result + (curr_end - curr_start + 1);

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
                        if (rom_data >= "0" && rom_data <= "9") begin
                            current_num <= ((current_num<<3) + (current_num<<1)) + (rom_data - "0");
                            has_parsed_digit <= 1;
                        end else if (rom_data == "\n") begin
                            if (has_parsed_digit) begin
                                search_val <= current_num;
                                state <= S_SEARCH_INIT;
                            end
                            // ignore empty lines / training newlines
                        end
                        // advance rom address
                        if (!(rom_data == 10 && has_parsed_digit)) begin
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
                        m_ram_addr <= low + ((high-low) >> 1);
                        state <= S_SEARCH_WAIT;
                    end
                end

                S_SEARCH_WAIT: begin
                    state <= S_SEARCH_EVAL;
                end

                S_SEARCH_EVAL: begin
                    if (search_val >= m_ram_r_data[127:64] && search_val <= m_ram_r_data[63:0]) begin
                        part1_result <= part1_result + 1;
                        state <= S_SEARCH_NEXT;
                    end else if (search_val < m_ram_r_data[127:64]) begin
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
