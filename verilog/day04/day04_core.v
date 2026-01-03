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

    // scan pipeline:
    localparam S_SCAN_INIT = 2;
    localparam S_SCAN_REQ1 = 3;
    localparam S_SCAN_GET0 = 4;
    localparam S_SCAN_GET1 = 5;
    localparam S_SCAN_PROCESS = 6;
    localparam S_SCAN_WAIT = 7;
    localparam S_SCAN_FLUSH = 8;

    localparam S_DONE = 9;
    reg [3:0] state;

    // grid storage:
    reg grid_we;
    reg [LOG2_MAX_ROWS-1:0] grid_w_addr;
    reg [LOG2_MAX_ROWS-1:0] grid_r_addr;
    reg [MAX_COLS-1:0] grid_w_data;
    wire [MAX_COLS-1:0] grid_r_data;

    reg [MAX_COLS-1:0] mask_prev; // the mask / update to apply to the previous row 

    ram #(
        .WIDTH(MAX_COLS),
        .DEPTH(MAX_ROWS),
        .ADDR_BITS(LOG2_MAX_ROWS)
    ) u_grid_ram_0 (
        .clk(clk),
        .rst(rst),
        .we(grid_we),
        .w_addr(grid_w_addr),
        .w_data(grid_w_data),
        .r_addr(grid_r_addr),
        .r_data(grid_r_data)
    );
    reg [LOG2_MAX_ROWS-1:0] n_rows;
    reg [LOG2_MAX_ROWS:0] n_cols;

    // memory for loading state:
    reg [LOG2_MAX_ROWS-1:0] load_row;
    reg [LOG2_MAX_ROWS:0] load_col;
    reg [MAX_COLS-1:0] load_buffer;

    // memory for scanning state:
    reg [LOG2_MAX_ROWS-1:0] scan_row;
    reg [63:0] scan_count;
    reg [63:0] total_removed;
    reg first_scan_flag; // use to stop part 1 computation early

    // 3-row window wires:
    reg [MAX_COLS-1:0] row_prev;
    reg [MAX_COLS-1:0] row_curr;
    reg [MAX_COLS-1:0] row_next;

    wire [MAX_COLS-1:0] accessible;
    // instantiate row logic:
    row_logic #(
        .MAX_COLS(MAX_COLS),
        .LOG2_MAX_COLS(LOG2_MAX_COLS)
    ) u_row_logic_0 (
        .row_prev(row_prev),
        .row_curr(row_curr),
        .row_next(row_next),
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

    reg [15:0] ones_count_val;

    always @(posedge clk) begin
        // defaults:
        grid_we <= 0;

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
            grid_w_addr <= 0;
            grid_w_data <= 0;
            grid_r_addr <= 0;
            
            mask_prev <= 0;

            row_prev <= 0;
            row_curr <= 0;
            row_next <= 0;
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
                            grid_we <= 1;
                            grid_w_addr <= load_row;
                            grid_w_data <= load_buffer;
                            n_rows <= load_row + 1;
                        end else begin
                            n_rows <= load_row;
                        end
                        scan_row <= 0;
                        scan_count <= 0;
                        state <= S_SCAN_INIT;
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
                                grid_we <= 1;
                                grid_w_addr <= load_row;
                                grid_w_data <= load_buffer;

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

                S_SCAN_INIT: begin
                    grid_r_addr <= 0;
                    state <= S_SCAN_REQ1;
                end


                S_SCAN_REQ1: begin
                    // row 0 requested in S_SCAN_INIT, will be ready next state
                    // request row 1
                    if (n_rows > 1) begin
                        grid_r_addr <= 1;
                    end else begin
                        grid_r_addr <= 0;
                    end
                    state <= S_SCAN_GET0;
                end


                S_SCAN_GET0: begin
                    // store row 0:
                    row_curr <= grid_r_data;
                    row_prev <= 0;

                    // request row 2:
                    if (n_rows > 2) begin
                        grid_r_addr <= 2;
                    end else begin
                        grid_r_addr <= 0;
                    end
                    state <= S_SCAN_GET1;
                end

                S_SCAN_GET1: begin
                    // store row 1
                    if (n_rows > 1) begin
                        row_next <= grid_r_data;
                    end else begin
                        row_next <= 0;
                    end

                    scan_row <= 0;
                    state <= S_SCAN_PROCESS;
                end

                S_SCAN_PROCESS: begin
                    if (scan_row >= n_rows) begin
                        if (first_scan_flag) begin
                            part1_result <= scan_count;
                            first_scan_flag <= 0;
                        end
                        state <= S_SCAN_FLUSH;
                    end else begin
                        // compute the mask:
                        ones_count_val = ones_count(accessible, n_cols);
                        scan_count <= scan_count + ones_count_val;

                        // buffer the mask:
                        mask_prev <= accessible;

                        // apply update to prev row (if exists);
                        if (scan_row > 0) begin
                            grid_we <= 1;
                            grid_w_addr <= scan_row - 1;
                            grid_w_data <= row_prev & ~mask_prev;
                        end

                        row_prev <= row_curr;
                        row_curr <= row_next;

                        // update next row from pipeline (was already requested in GET0 or prev PROCESS)
                        if (scan_row + 2 < n_rows) begin
                            row_next <= grid_r_data;
                        end else begin
                            row_next <= 0;
                        end 

                        // request next row_next so it is ready when it needs to be used:
                        grid_r_addr <= scan_row + 3;
                        scan_row <= scan_row + 1;
                        state <= S_SCAN_WAIT;
                    end
                end

                S_SCAN_WAIT: begin
                    // wait for ram read:
                    state <= S_SCAN_PROCESS;
                end

                S_SCAN_FLUSH: begin
                    // write the final row update:
                    grid_we <= 1;
                    grid_w_addr <= n_rows - 1;
                    grid_w_data <= row_prev & ~mask_prev;

                    if (scan_count == 0) begin
                        // no updates -> end
                        part2_result <= total_removed;
                        state <= S_DONE;
                    end else begin
                        total_removed <= total_removed + scan_count;
                        scan_count <= 0;
                        scan_row <= 0;
                        state <= S_SCAN_INIT;
                    end
                end


                S_DONE: begin
                    done <= 1;
                end
            endcase
        end
    end
endmodule
