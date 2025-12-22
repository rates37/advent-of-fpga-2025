module day07_core #(
    parameter N_ADDR_BITS = 16,
    parameter MAX_WIDTH = 256, // maximum width of a single 
    parameter LOG2_MAX_WIDTH = 8
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

    // FSM states:
    localparam S_INIT = 0;
    localparam S_FIND_S = 1;
    localparam S_START_ROW = 2;
    localparam S_READY_ROW = 3;
    localparam S_READ_ROW = 4;
    localparam S_CLEAR_NEXT = 5;
    localparam S_PROCESS = 6;
    localparam S_SUM_RESULT = 7;
    localparam S_DONE = 8;

    reg [3:0] state;
    reg [LOG2_MAX_WIDTH:0] col;
    reg [LOG2_MAX_WIDTH:0] row_width; // assuming approx square
    reg [N_ADDR_BITS:0] next_row_addr;
    reg current_ram_sel;
    reg last_row_flag;

    // arrays to store rows:
    reg [63:0] ram_0 [0:MAX_WIDTH-1];  // array for current row
    reg [63:0] ram_1 [0:MAX_WIDTH-1];  // array for next row
    reg [7:0] row_buf [0:MAX_WIDTH-1]; // store characters in the row currently being processed

    // logic to compute next state row of tachyons
    wire [63:0] t_cur = (current_ram_sel == 0) ? ram_0[col] : ram_1[col];
    wire [63:0] t_prev = (col > 0) ? ((current_ram_sel == 0) ? ram_0[col-1] : ram_1[col-1]) : 0;
    wire [63:0] t_next = (col < MAX_WIDTH-1) ? ((current_ram_sel == 0) ? ram_0[col+1] : ram_1[col+1]): 0;
    wire [63:0] t_new = 
        ((col < row_width && row_buf[col] == ".") ? t_cur : 0) +
        ((col > 0 && row_buf[col-1] == "^") ? t_prev : 0) +
        ((col < row_width-1 && row_buf[col+1] == "^") ? t_next : 0);
    
    integer i;
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
        end else begin
            case (state)
                S_INIT: begin
                    // clear all register buffers:
                    for (i=0; i<MAX_WIDTH; i=i+1) begin
                        ram_0[i] <= 0;
                        ram_1[i] <= 0;
                        row_buf[i] <= 0;
                    end
                    col <= 0;
                    state <= S_FIND_S;
                    rom_addr <= 0;
                end


                S_FIND_S: begin
                    if (rom_data == "S") begin
                        if (current_ram_sel) begin
                            ram_1[col] <= 1;
                        end else begin
                            ram_0[col] <= 1;
                        end
                    end

                    // check if hit newline
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
                        // reaches EOF
                        state <= S_SUM_RESULT;
                        col <= 0;
                    end else begin
                        col <= 0;
                        state <= S_READ_ROW;
                    end
                end


                S_READ_ROW: begin
                    if (rom_data == "\n") begin
                        row_width <= col;
                        next_row_addr <= rom_addr + 1;
                        last_row_flag <= (rom_data == 0);
                        state <= S_CLEAR_NEXT;
                        col <= 0;
                    end else begin
                        row_buf[col] <= rom_data;
                        rom_addr <= rom_addr + 1;
                        col <= col + 1;
                    end
                end


                S_CLEAR_NEXT: begin
                    for (i=0; i<MAX_WIDTH; i=i+1) begin
                        if (current_ram_sel == 0) begin
                            ram_1[i] <= 0;
                        end else begin
                            ram_0[i] <= 0;
                        end
                    end
                    col <= 0;
                    state <= S_PROCESS;
                end


                S_PROCESS: begin
                    if (current_ram_sel) begin
                        ram_0[col] <= t_new;
                    end else begin
                        ram_1[col] <= t_new;
                    end

                    // if splitting, increment p1 output
                    if (col < row_width && row_buf[col] == "^" && t_cur > 0) begin
                        part1_result <= part1_result + 1;
                    end

                    if (col == MAX_WIDTH-1 || col >= row_width) begin
                        current_ram_sel <= !current_ram_sel;
                        col <= 0;
                        if (last_row_flag) begin
                            state <= S_SUM_RESULT;
                        end else begin
                            state <= S_START_ROW;
                        end
                    end else begin
                        col <= col + 1;
                    end
                end


                S_SUM_RESULT: begin
                    if (col == MAX_WIDTH || col >= row_width+1) begin
                        state <= S_DONE;
                    end else begin
                        part2_result <= part2_result + (current_ram_sel == 0 ? ram_0[col] : ram_1[col]);
                        col <= col + 1;
                    end
                end


                S_DONE: begin
                    done <= 1;
                end
            endcase
        end
    end

endmodule
