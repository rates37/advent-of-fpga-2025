module day04_core #(
    parameter N_ADDR_BITS = 16,
    parameter MAX_ROWS = 150, // my puzzle input was 137x137
    parameter MAX_COLS = 150,
    parameter LOG2_MAX_COLS = 8,
    parameter LOG2_MAX_ROWS = 8
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

    // define states:
    localparam S_IDLE = 0;
    localparam S_LOAD = 1; // load grid into memory
    localparam S_SCAN = 2; // scan over the grid and count/mark accessible cells
    localparam S_APPLY = 3; // remove accessible cells
    localparam S_DONE = 4;
    reg [2:0] state;

    // grid storage:
    reg [MAX_COLS-1:0] grid_row [0:MAX_ROWS-1];
    reg [LOG2_MAX_ROWS-1:0] n_rows;
    reg [LOG2_MAX_COLS:0] n_cols;

    // memory for loading state:
    reg [LOG2_MAX_ROWS-1:0] load_row;
    reg [LOG2_MAX_ROWS:0] load_col;
    reg [MAX_COLS-1:0] load_buffer;

    // memory for scanning state:
    reg [LOG2_MAX_ROWS-1:0] scan_row;
    reg [63:0] scan_count;
    reg [63:0] total_removed;
    reg first_scan_flag; // use to stop part 1 computation early

    reg [MAX_COLS-1:0] removal_mask [0:MAX_ROWS-1];

    // 3-row window wires:
    wire [MAX_COLS-1:0] row_prev_wire;
    wire [MAX_COLS-1:0] row_curr_wire;
    wire [MAX_COLS-1:0] row_next_wire;
    assign row_prev_wire = (scan_row > 0) ? grid_row[scan_row-1] : {MAX_COLS{1'b0}};
    assign row_curr_wire = (scan_row < n_rows) ? grid_row[scan_row] : {MAX_COLS{1'b0}};
    assign row_next_wire = (scan_row < n_rows-1) ? grid_row[scan_row+1] : {MAX_COLS{1'b0}};

    wire [MAX_COLS-1:0] accessible;
    // instantiate row logic:
    row_logic #(
        .MAX_COLS(MAX_COLS),
        .LOG2_MAX_COLS(LOG2_MAX_COLS)
    ) u_row_logic_0 (
        .row_prev(row_prev_wire),
        .row_curr(row_curr_wire),
        .row_next(row_next_wire),
        .n_cols(n_cols),
        .accessible(accessible)
    );

    // ones counter function:
    function [15:0] ones_count;
        input [MAX_COLS-1:0] bits;
        input [LOG2_MAX_COLS:0] width;
        integer i;
        begin
            ones_count = 0;
            for (i = 0; i < MAX_COLS; i = i + 1) begin
                if (i<width) begin
                    ones_count = ones_count + bits[i];
                end
            end
        end
    endfunction

    integer i;
    reg [15:0] ones_count_val;
    always @(posedge clk) begin
        if (rst) begin
            state <= S_IDLE;
            rom_addr <= 0;
            done <= 0;
            part1_result <= 0;
            part2_result <= 0;
            n_rows <= 0;
            n_cols <= 0;
            load_row <= 0;
            load_col <= 0;
            load_buffer <= 0;
            scan_row <= 0;
            scan_count <= 0;
            total_removed <= 0;
            first_scan_flag <= 1;

            // clear the masks/grid storage:
            for (i=0; i<MAX_ROWS; i=i+1) begin
                grid_row[i] <= 0;
                removal_mask[i] <= 0;
            end
        end else begin
            case (state)
                S_IDLE: begin
                    rom_addr <= 0;
                    state <= S_LOAD;
                end


                S_LOAD: begin
                    if (!rom_valid) begin
                        // reached EOF
                        if (load_col > 0) begin
                            grid_row[load_row] <= load_buffer;
                            n_rows <= load_row + 1;
                        end else begin
                            n_rows <= load_row;
                        end
                        scan_row <= 0;
                        scan_count <= 0;
                        first_scan_flag <= 1;
                        state <= S_SCAN;
                    end else begin
                        case (rom_data)
                            "@": begin
                                load_buffer[load_col] <= 1;
                                load_col <= load_col + 1;
                            end

                            ".": begin
                                load_buffer[load_col] <= 0;
                                load_col <= load_col + 1;
                            end

                            "\n": begin
                                // end of current row:
                                grid_row[load_row] <= load_buffer;
                                if (n_cols == 0) begin
                                    n_cols <= load_col;
                                end
                                load_buffer <= 0;
                                load_row <= load_row + 1;
                                load_col <= 0;
                            end

                            default: begin
                                // do nothing -> ignore
                            end
                        endcase
                        rom_addr <= rom_addr + 1;
                    end
                end


                S_SCAN: begin
                    // process one row per cycle
                    if (scan_row >= n_rows) begin
                        // finished scan:
                        if (first_scan_flag) begin
                            part1_result <= scan_count;
                            first_scan_flag <= 0;
                        end
                        state <= S_APPLY;
                    end else begin
                        ones_count_val = ones_count(accessible, n_cols);
                        scan_count <= scan_count + ones_count_val;
                        removal_mask[scan_row] <= accessible;
                        scan_row <= scan_row + 1;
                    end
                end


                S_APPLY: begin
                    if (scan_count == 0) begin
                        // none removed in this scan -> finished!
                        part2_result <= total_removed;
                        state <= S_DONE;
                    end else begin
                        // apply removals:
                        for (i=0; i<MAX_ROWS; i=i+1) begin
                            grid_row[i] <= grid_row[i] & ~removal_mask[i];
                            removal_mask[i] <= 0;
                        end
                        // accumulate total and scan grid again:
                        total_removed <= total_removed + scan_count;
                        scan_count <= 0;
                        scan_row <= 0;
                        state <= S_SCAN;
                    end
                end


                S_DONE: begin
                    done <= 1;
                end
            endcase
        end
    end
endmodule
