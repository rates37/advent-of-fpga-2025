// impelments a bitonic sorting algorithm
// assuming data is stored in an external 2-port RAM
// note: if num values is not a power of 2, then it will be padded
// using the value in PAD_VALUE parameter

module bitonic_sorter #(
    parameter MAX_NUM_VALUES = 8192,
    parameter DATA_ADDR_BITS = 13,
    parameter DATA_WIDTH = 64,
    parameter PAD_VALUE = {32'hFFFFFFFF, 32'd0}
) (
    input wire clk,
    input wire rst,
    input wire start,
    input wire [DATA_ADDR_BITS:0] num_values,

    // 2 port RAM interface:
    output reg data_we_a,
    output reg [DATA_ADDR_BITS-1:0] data_w_addr_a,
    output reg [DATA_WIDTH-1:0] data_w_data_a,
    output reg [DATA_ADDR_BITS-1:0] data_r_addr_a,
    input wire [DATA_WIDTH-1:0] data_r_data_a,
    
    output reg data_we_b,
    output reg [DATA_ADDR_BITS-1:0] data_w_addr_b,
    output reg [DATA_WIDTH-1:0] data_w_data_b,
    output reg [DATA_ADDR_BITS-1:0] data_r_addr_b,
    input wire [DATA_WIDTH-1:0] data_r_data_b,

    // output signals:
    output reg done,
    output reg [DATA_ADDR_BITS-1:0] sort_progress // used as a debug to show the progress of sorting
                                                  // can be left un-used 
);

    // define states:
    localparam S_IDLE = 0;
    localparam S_PAD = 1;
    localparam S_CALC_INDICES = 2;
    localparam S_READ = 3;
    localparam S_WAIT = 4;
    localparam S_COMPARE = 5;
    localparam S_DONE = 6;
    reg [2:0] state;

    // loop indices:
    reg [DATA_ADDR_BITS:0] i_loop;
    reg [DATA_ADDR_BITS:0] j_loop;
    reg [DATA_ADDR_BITS:0] k_loop;
    reg [DATA_ADDR_BITS:0] n_padded;
    reg [DATA_ADDR_BITS:0] idx_i;
    reg [DATA_ADDR_BITS:0] idx_l;
    reg [DATA_ADDR_BITS:0] pad_idx;
    wire [63:0] val_i = data_r_data_a;
    wire [63:0] val_l = data_r_data_b;

    wire ascending = ((idx_i & k_loop) == 0);
    wire should_swap = ascending ? (val_i > val_l) : (val_i < val_l);

    function [DATA_ADDR_BITS:0] next_power_of_2;
        input [DATA_ADDR_BITS:0] val;
        begin
            next_power_of_2 = 1;
            while (next_power_of_2 < val) begin
                next_power_of_2 = next_power_of_2 << 1;
            end
        end
    endfunction

    always @(posedge clk) begin
        if (rst) begin
            state <= S_IDLE;
            done <= 0;
            data_we_a <= 0;
            data_we_b <= 0;
            sort_progress <= 0;
        end else begin
            // disable writing by default:
            data_we_a <= 0;
            data_we_b <= 0;

            case (state)
                S_IDLE: begin
                    if (start) begin
                        n_padded <= next_power_of_2(num_values);
                        pad_idx <= num_values;
                        state <= S_PAD;
                        done <= 0;
                    end
                end


                S_PAD: begin
                    if (pad_idx < n_padded && pad_idx < MAX_NUM_VALUES) begin
                        data_we_a <= 1;
                        data_w_addr_a <= pad_idx[DATA_ADDR_BITS-1:0];
                        data_w_data_a <= PAD_VALUE; // this should be larger than all other values in the memory
                        pad_idx <= pad_idx + 1;
                    end else begin
                        // finished padding:
                        i_loop <= 0;
                        j_loop <= 1;
                        k_loop <= 2;
                        state <= S_CALC_INDICES;
                    end
                end


                S_CALC_INDICES: begin
                    idx_i <= i_loop;
                    idx_l <= i_loop ^ j_loop;

                    if ((i_loop ^ j_loop) > i_loop) begin
                        state <= S_READ;
                    end else begin
                        state <= S_COMPARE;
                    end
                end


                S_READ: begin
                    // read both values to compare from RAM:
                    data_r_addr_a <= idx_i[DATA_ADDR_BITS-1:0];
                    data_r_addr_b <= idx_l[DATA_ADDR_BITS-1:0];
                    state <= S_WAIT;
                end


                S_WAIT: begin
                    // single cycle to wait for ram values to be loaded
                    state <= S_COMPARE;
                end


                S_COMPARE: begin
                    if ((idx_l > idx_i) && should_swap) begin
                        data_we_a <= 1;
                        data_w_addr_a <= idx_i[DATA_ADDR_BITS-1:0];
                        data_w_data_a <= data_r_data_b;

                        data_we_b <= 1;
                        data_w_addr_b <= idx_l[DATA_ADDR_BITS-1:0];
                        data_w_data_b <= data_r_data_a;
                    end

                    // increment loop:
                    i_loop <= i_loop + 1;
                    sort_progress <= i_loop[DATA_ADDR_BITS-1:0];

                    if (i_loop >= n_padded - 1) begin
                        // done inner loop -> update j:
                        if (j_loop == 1) begin
                            if (k_loop == n_padded) begin
                                state <= S_DONE;
                            end else begin
                                i_loop <= 0;
                                j_loop <= k_loop;
                                k_loop <= k_loop << 1;
                                state <= S_CALC_INDICES;
                            end
                        end else begin
                            i_loop <= 0;
                            j_loop <= j_loop >> 1;
                            state <= S_CALC_INDICES;
                        end
                    end else begin
                        state <= S_CALC_INDICES;
                    end
                end


                S_DONE: begin
                    done <= 1;
                end
            endcase
        end
    end


endmodule
