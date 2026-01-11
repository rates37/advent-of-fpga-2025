module heap_sorter #(
    parameter MAX_NUM_VALUES = 8192,
    parameter DATA_ADDR_BITS = 13,
    parameter DATA_WIDTH = 64
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

    // fsm:
    localparam S_IDLE = 0;
    localparam S_BUILD_START = 1;
    localparam S_HEAPIFY_RD1 = 2;
    localparam S_HEAPIFY_RD1_WAIT = 3;
    localparam S_HEAPIFY_RD2 = 4;
    localparam S_HEAPIFY_RD2_WAIT = 5;
    localparam S_HEAPIFY_CMP = 6;
    localparam S_HEAPIFY_WR1 = 7;
    localparam S_HEAPIFY_WR2 = 8;
    localparam S_BUILD_NEXT = 9;
    localparam S_EXTR_START = 10;
    localparam S_EXTR_SWAP1 = 11;
    localparam S_EXTR_SWAP2 = 12;
    localparam S_EXTR_SWAP3 = 13;
    localparam S_DONE = 14;

    reg [3:0] state;
    reg signed [DATA_ADDR_BITS+1:0] build_idx;
    reg [DATA_ADDR_BITS:0] heap_size;
    reg [DATA_ADDR_BITS:0] heapify_node;
    reg building;

    reg [DATA_WIDTH-1:0] node_val;
    reg [DATA_WIDTH-1:0] left_val;
    reg [DATA_WIDTH-1:0] right_val;
    reg [DATA_ADDR_BITS:0] left_child;
    reg [DATA_ADDR_BITS:0] right_child;
    reg has_left;
    reg has_right;
    reg needs_swap;
    reg swap_with_left;

    always @(posedge clk) begin
        if (rst) begin
            state <= S_IDLE;
            done <= 0;
            data_we_a <= 0;
            data_we_b <= 0;
        end else begin
            data_we_a <= 0;
            data_we_b <= 0;

            case (state)
                S_IDLE: begin
                    if (start) begin
                        if (num_values <= 1) begin
                            state <= S_DONE;
                        end else begin
                            heap_size <= num_values;
                            build_idx <= (num_values >> 1) - 1;
                            state <= S_BUILD_START;
                        end
                        done <= 0;
                        sort_progress <= 0;
                    end
                end

                S_BUILD_START: begin
                    heapify_node <= build_idx;
                    state <= S_HEAPIFY_RD1;
                    building <= 1;
                end

                S_HEAPIFY_RD1: begin
                    // read current node, and get child addresses
                    data_r_addr_a <= heapify_node;
                    left_child <= (heapify_node<<1) + 1;
                    right_child <= (heapify_node<<1) + 2;
                    state <= S_HEAPIFY_RD1_WAIT;
                end

                S_HEAPIFY_RD1_WAIT: begin
                    state <= S_HEAPIFY_RD2;
                end

                S_HEAPIFY_RD2: begin
                    node_val <= data_r_data_a;
                    has_left <= left_child < heap_size;
                    has_right <= right_child < heap_size;

                    if (left_child < heap_size) begin
                        data_r_addr_a <= left_child;
                        if (right_child < heap_size) begin
                            data_r_addr_b <= right_child;
                        end
                        state <= S_HEAPIFY_RD2_WAIT;
                    end else begin
                        needs_swap <= 0;
                        state <= S_HEAPIFY_WR1;
                    end
                end

                S_HEAPIFY_RD2_WAIT: begin
                    state <= S_HEAPIFY_CMP;
                end

                S_HEAPIFY_CMP: begin
                    left_val <= data_r_data_a;
                    right_val <= data_r_data_b;

                    needs_swap <= 0;
                    swap_with_left <= 0;

                    if (has_left && (data_r_data_a > node_val)) begin
                        if (has_right && (data_r_data_b > data_r_data_a)) begin
                            needs_swap <= 1;
                            swap_with_left <= 0;
                        end else begin
                            needs_swap <= 1;
                            swap_with_left <= 1;
                        end
                    end else if (has_right && (data_r_data_b > node_val)) begin
                        needs_swap <= 1;
                        swap_with_left <= 0;
                    end

                    state <= S_HEAPIFY_WR1;
                end

                S_HEAPIFY_WR1: begin
                    if (needs_swap) begin
                        data_we_a <= 1;
                        data_w_addr_a <= heapify_node;
                        data_w_data_a <= swap_with_left ? left_val : right_val;
                        state <= S_HEAPIFY_WR2;
                    end else begin
                        state <= building ? S_BUILD_NEXT : S_EXTR_START;
                    end
                end

                S_HEAPIFY_WR2: begin
                    data_we_a <= 1;
                    data_w_addr_a <= swap_with_left ? left_child : right_child;
                    data_w_data_a <= node_val;

                    // continue sinking down
                    heapify_node <= swap_with_left ? left_child : right_child;
                    state <= S_HEAPIFY_RD1;
                end

                S_BUILD_NEXT: begin
                    if (build_idx == 0) begin
                        // finished heapifying, begin extracting
                        state <= S_EXTR_START;
                    end else begin
                        build_idx <= build_idx - 1;
                        state <= S_BUILD_START;
                    end
                end

                S_EXTR_START: begin
                    if (heap_size <= 1) begin
                        state <= S_DONE;
                    end else begin
                        data_r_addr_a <= 0;
                        data_r_addr_b <= (heap_size - 1);
                        state <= S_EXTR_SWAP1;
                    end
                end

                S_EXTR_SWAP1: begin
                    state <= S_EXTR_SWAP2;
                end

                S_EXTR_SWAP2: begin
                    node_val <= data_r_data_a;
                    left_val <= data_r_data_b;

                    data_we_a <= 1;
                    data_w_addr_a <= 0;
                    data_w_data_a <= data_r_addr_b;
                    state <= S_EXTR_SWAP3;
                end

                S_EXTR_SWAP3: begin
                    data_we_a <= 1;
                    data_w_addr_a <= (heap_size - 1);
                    data_w_data_a <= node_val;

                    heap_size <= heap_size - 1;
                    sort_progress <= heap_size - 1;
                    heapify_node <= 0;
                    building <= 0;
                    state <= S_HEAPIFY_RD1;
                end

                S_DONE: begin
                    done <= 1;
                end

                default: begin
                    state <= S_IDLE;
                end

            endcase

        end
    end
endmodule
