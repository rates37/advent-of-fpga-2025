
module day07_core #(
    parameter N_ADDR_BITS = 16,
    parameter MAX_WIDTH = 256,
    parameter ADDR_BITS = 9  // log2(MAX_WIDTH * 2) to double-buffer
) (
    input wire clk,
    input wire rst,
    input wire [7:0] rom_data,
    input wire rom_valid,
    output reg [N_ADDR_BITS:0] rom_addr,
    output reg [63:0] part1_result,
    output reg [63:0] part2_result,
    output reg done
);

    // States
    localparam S_INIT = 0;
    localparam S_FIND_S = 1;
    localparam S_START_ROW = 2;
    localparam S_READY_ROW = 3;
    localparam S_READ_ROW = 4;
    localparam S_CLEAR_NEXT = 5;
    localparam S_PROC_RD1 = 6;
    localparam S_PROC_RD2 = 7;
    localparam S_PROC_RD3 = 8;
    localparam S_PROC_CALC = 9;
    localparam S_SUM_RD = 10;
    localparam S_SUM_WAIT = 11;
    localparam S_SUM_ACC = 12;
    localparam S_DONE = 13;
    reg [3:0] state;

    reg [8:0] col;
    reg [8:0] row_width;
    reg [N_ADDR_BITS:0] next_row_addr;
    reg current_ram_sel; // 0 = read from buf0, 1 = read from buf1
    reg last_row_flag;
    
    // Clear counter for next buffer
    reg [8:0] clear_col;

    // Ram signals
    // Buffer 0: 0 to MAX_WIDTH-1
    // Buffer 1: MAX_WIDTH to 2*MAX_WIDTH-1
    reg ram_we_a, ram_we_b;
    reg [ADDR_BITS-1:0] ram_addr_a, ram_addr_b;
    reg [63:0] ram_w_data_a, ram_w_data_b;
    wire [63:0] ram_r_data_a, ram_r_data_b;
    wire ram_init_done;

    // row storage: (0 = '.', 1 = '^')
    reg [MAX_WIDTH-1:0] row_bits;

    ram_dp_init #(
        .WIDTH(64),
        .DEPTH(MAX_WIDTH * 2),
        .ADDR_BITS(ADDR_BITS),
        .INIT_VALUE(64'd0)
    ) ram_ram (
        .clk(clk),
        .rst(rst),
        .we_a(ram_we_a),
        .addr_a(ram_addr_a),
        .w_data_a(ram_w_data_a),
        .r_data_a(ram_r_data_a),
        .we_b(ram_we_b),
        .addr_b(ram_addr_b),
        .w_data_b(ram_w_data_b),
        .r_data_b(ram_r_data_b),
        .init_done(ram_init_done)
    );

    // Address calculation for double-buffered RAM
    wire [ADDR_BITS-1:0] read_buf_base = current_ram_sel ? MAX_WIDTH : 0;
    wire [ADDR_BITS-1:0] write_buf_base = current_ram_sel ? 0 : MAX_WIDTH;

    // whether each bit is a splitter
    wire is_splitter_prev = (proc_col > 0) ? row_bits[proc_col - 1] : 1'b0;
    wire is_splitter_cur  = row_bits[proc_col];
    wire is_splitter_next = (proc_col < MAX_WIDTH - 1) ? row_bits[proc_col + 1] : 1'b0;

    // storage for values from RAM reads (since only 2 ports on ram module)
    reg [63:0] t_prev_reg, t_cur_reg, t_next_reg;
    reg [8:0] proc_col; // Column currently being processed

    always @(posedge clk) begin
        if (rst) begin
            state <= S_INIT;
            rom_addr <= 0;
            col <= 0;
            part1_result <= 0;
            part2_result <= 0;
            done <= 0;
            current_ram_sel <= 0;
            row_width <= 0;
            last_row_flag <= 0;
            next_row_addr <= 0;
            clear_col <= 0;
            proc_col <= 0;
            row_bits <= 0;
            
            ram_we_a <= 0;
            ram_we_b <= 0;
            ram_addr_a <= 0;
            ram_addr_b <= 0;
            ram_w_data_a <= 0;
            ram_w_data_b <= 0;
            
            t_prev_reg <= 0;
            t_cur_reg <= 0;
            t_next_reg <= 0;
        end else begin
            // disable writes
            ram_we_a <= 0;
            ram_we_b <= 0;

            case (state)
                S_INIT: begin
                    // Wait for RAM init
                    if (ram_init_done) begin
                        state <= S_FIND_S;
                        rom_addr <= 0;
                        col <= 0;
                    end
                end

                S_FIND_S: begin
                    if (rom_data == "S") begin
                        // Write 1 to ram_ram at current column in buffer 0
                        ram_we_a <= 1;
                        ram_addr_a <= col;
                        ram_w_data_a <= 1;
                    end
                    if (rom_data == "\n" || (rom_addr > 0 && rom_data == 0)) begin
                        next_row_addr <= rom_addr + 1;
                        col <= 0;
                        state <= S_START_ROW;
                    end else begin
                        rom_addr <= rom_addr + 1;
                        col <= col + 1;
                    end
                end

                S_START_ROW: begin
                    rom_addr <= next_row_addr;
                    state <= S_READY_ROW;
                end

                S_READY_ROW: begin
                    if (rom_data == "\n") begin
                        next_row_addr <= next_row_addr + 1;
                        state <= S_START_ROW;
                    end else if (rom_data == 0 && rom_addr > 0) begin
                        state <= S_SUM_RD;
                        col <= 0;
                    end else begin
                        state <= S_READ_ROW;
                        col <= 0;
                        row_bits <= 0; // Clear buffer for new row
                    end
                end

                S_READ_ROW: begin
                    if (rom_data == "\n" || rom_data == 0) begin
                        row_width <= col;
                        next_row_addr <= rom_addr + 1;
                        last_row_flag <= (rom_data == 0);
                        state <= S_CLEAR_NEXT;
                        clear_col <= 0;
                    end else begin
                        // 0 = '.', 1 = '^'
                        row_bits[col] <= (rom_data == "^") ? 1 : 0;
                        rom_addr <= rom_addr + 1;
                        col <= col + 1;
                    end
                end

                S_CLEAR_NEXT: begin
                    // Clear write buffer
                    ram_we_a <= 1;
                    ram_addr_a <= write_buf_base + clear_col;
                    ram_w_data_a <= 64'd0;
                    
                    if (clear_col >= row_width) begin
                        state <= S_PROC_RD1;
                        col <= 0;
                    end else begin
                        clear_col <= clear_col + 1;
                    end
                end

                S_PROC_RD1: begin
                    // read t_prev (port A) and t_curr (port B)
                    proc_col <= col;
                    
                    // t_prev address
                    ram_addr_a <= (col > 0) ? (read_buf_base + col - 1) : read_buf_base;
                    // t_curr address
                    ram_addr_b <= read_buf_base + col;
                    state <= S_PROC_RD2;
                end

                S_PROC_RD2: begin
                    // read t_next next cycle
                    ram_addr_a <= read_buf_base + proc_col + 1;
                    state <= S_PROC_RD3;
                end

                S_PROC_RD3: begin
                    // Now t_prev and t_curr are available from RD1 state
                    // store before changing anything
                    t_prev_reg <= (proc_col > 0) ? ram_r_data_a : 64'd0;
                    t_cur_reg <= ram_r_data_b;
                    state <= S_PROC_CALC;
                end

                S_PROC_CALC: begin
                    // t_next finally available from RD2 state
                    t_next_reg <= (proc_col < row_width - 1) ? ram_r_data_a : 0;
                    
                    // Calculate t_new using captured values + fresh t_next
                    begin : calc_block
                        reg [63:0] contrib_curr, contrib_prev, contrib_next, t_new;
                        
                        // Previous cell contributes if it's '^' (bit = 1)
                        contrib_prev = (proc_col > 0 && is_splitter_prev) ? t_prev_reg : 0;
                        
                        // Current cell contributes if it's '.' (bit = 0)
                        contrib_curr = (proc_col < row_width && !is_splitter_cur) ? t_cur_reg : 0;
                        
                        // Next cell contributes if it's '^' (bit = 1)
                        contrib_next = (proc_col < row_width - 1 && is_splitter_next) ? ram_r_data_a : 0;
                        
                        t_new = contrib_prev + contrib_curr + contrib_next;
                        
                        // Write result
                        ram_we_a <= 1;
                        ram_addr_a <= write_buf_base + proc_col;
                        ram_w_data_a <= t_new;
                    end
                    
                    // update part 1 if split:
                    if (proc_col < row_width && is_splitter_cur && t_cur_reg > 0) begin
                        part1_result <= part1_result + 1;
                    end
                    
                    if (proc_col >= row_width) begin
                        current_ram_sel <= !current_ram_sel;
                        col <= 0;
                        if (last_row_flag) begin
                            state <= S_SUM_RD;
                        end else begin
                            state <= S_START_ROW;
                        end
                    end else begin
                        col <= col + 1;
                        state <= S_PROC_RD1;
                    end
                end

                S_SUM_RD: begin
                    ram_addr_a <= read_buf_base + col;
                    state <= S_SUM_WAIT;
                end

                S_SUM_WAIT: begin
                    state <= S_SUM_ACC;
                end

                S_SUM_ACC: begin
                    if (col < row_width) begin
                        part2_result <= part2_result + ram_r_data_a;
                    end
                    
                    if (col >= row_width) begin
                        state <= S_DONE;
                    end else begin
                        col <= col + 1;
                        state <= S_SUM_RD;
                    end
                end

                S_DONE: begin
                    done <= 1;
                end
            endcase
        end
    end

endmodule
