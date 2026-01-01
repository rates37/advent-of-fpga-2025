module day11_core #(
    parameter N_ADDR_BITS = 16
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
    // consts:
    localparam NODE_BITS = 10;
    localparam EDGE_BITS = 13;
    localparam [23:0] STR_YOU = "you";
    localparam [23:0] STR_OUT = "out";
    localparam [23:0] STR_SVR = "svr";
    localparam [23:0] STR_DAC = "dac";
    localparam [23:0] STR_FFT = "fft";

    // !! signals for submodules:
    // name resolver:
    reg [23:0] nr_query;
    reg nr_valid;
    wire [NODE_BITS-1:0] nr_id;
    wire nr_done;
    wire nr_ready;

    // graph manager / path counter:
    reg gm_we;
    reg[ NODE_BITS-1:0] gm_src;
    reg[ NODE_BITS-1:0] gm_dst;
    wire [EDGE_BITS-1:0] gm_head_start;
    wire [4:0] gm_head_count;
    wire [NODE_BITS-1:0] gm_to;
    wire [NODE_BITS-1:0] pc_addr_node;
    wire [EDGE_BITS-1:0] pc_addr_edge;
    reg pc_start;
    reg [NODE_BITS-1:0] pc_s; // start node ID
    reg [NODE_BITS-1:0] pc_t; // end node ID
    wire [63:0] pc_result;
    wire pc_done;


    // store key IDs:
    reg [NODE_BITS-1:0] ids [0:4]; // in order: "you", "out", "svr", "dac", "fft"

    // parser variables:
    reg [3:0] parser_state;
    reg [7:0] name_buf [0:2];
    reg  [1:0] buf_count;
    reg [NODE_BITS-1:0] curr_src;
    reg has_src; // if 1, we have parsed "<src>: " part of the line and are now parsing nodes that the current src node is connected to
    // parser mini FSM:
    localparam P_INIT = 0;
    localparam P_FETCH = 1;
    localparam P_LOOKUP = 2;
    localparam P_DECIDE = 3;
    localparam P_DONE = 4;

    // FSM:
    localparam S_PARSE = 0;
    localparam S_P1_SETUP = 1;
    localparam S_P1_START = 2;
    localparam S_P1_WAIT = 3;

    localparam S_P2A_1_SETUP = 4;
    localparam S_P2A_1_START = 5;
    localparam S_P2A_1_WAIT = 6;

    localparam S_P2A_2_SETUP = 7;
    localparam S_P2A_2_START = 8;
    localparam S_P2A_2_WAIT = 9;

    localparam S_P2A_3_SETUP = 10;
    localparam S_P2A_3_START = 11;
    localparam S_P2A_3_WAIT = 12;

    localparam S_P2B_1_SETUP = 13;
    localparam S_P2B_1_START = 14;
    localparam S_P2B_1_WAIT = 15;

    localparam S_P2B_2_SETUP = 16;
    localparam S_P2B_2_START = 17;
    localparam S_P2B_2_WAIT = 18;

    localparam S_P2B_3_SETUP = 19;
    localparam S_P2B_3_START = 20;
    localparam S_P2B_3_WAIT = 21;

    localparam S_CALC_RESULTS = 22;
    localparam S_DONE = 23;
    reg [4:0] state;

    reg [63:0] p2_acc [0:1]; // path 1 (svr -> dac -> fft -> out) and path 2 (svr -> fft -> dac -> out)
    integer i;

    // instantiations:
    wire gm_ready;
    name_resolver nr_u0 (
        .clk(clk),
        .rst(rst),

        .name_in(nr_query),
        .valid_in(nr_valid),

        .node_id_out(nr_id),
        .done(nr_done),
        .init_done(nr_ready)
    );
    graph_manager gm_u0(
        .clk(clk),
        .rst(rst),

        .add_edge_en(gm_we),
        .src_node(gm_src),
        .dst_node(gm_dst),

        .read_node_addr(pc_addr_node),
        .head_start_out(gm_head_start),
        .head_count_out(gm_head_count),

        .read_edge_addr(pc_addr_edge),
        .edge_to_out(gm_to),
        .init_done(gm_ready)
    );

    path_counter pc_u0 (
        .clk(clk),
        .rst(rst),
        .start(pc_start),

        .src_node(pc_s),
        .dst_node(pc_t),
        .count_out(pc_result),
        .done(pc_done),

        .gm_read_node_addr(pc_addr_node),
        .gm_head_start(gm_head_start),
        .gm_head_count(gm_head_count),
        .gm_read_edge_addr(pc_addr_edge),
        .gm_edge_to(gm_to)
    );

    always @(posedge clk) begin
        if (rst) begin
            rom_addr <= 0;
            parser_state <= P_INIT;
            state <= S_PARSE;
            buf_count <= 0;
            has_src <= 0;
            gm_we <= 0;
            nr_valid <= 0;
            done <= 0;
            for (i=0; i<5; i=i+1) begin
                ids[i] <= 0;
            end
        end else begin
            // default values:
            gm_we <= 0;
            nr_valid <= 0;
            pc_start <= 0;

            case (state)
                S_PARSE: begin
                    // parser FSM logic:
                    case(parser_state) 
                        P_INIT: begin
                            // wait for the graph manager to clear itself
                            if (gm_ready && nr_ready) begin
                                parser_state <= P_FETCH;
                            end
                        end


                        P_FETCH: begin
                            if (rom_valid) begin
                                if (rom_data == 0) begin
                                    // $display("reached eof at %d", rom_addr);
                                    state <= S_P1_SETUP; // begin solving
                                    parser_state <= P_DONE;
                                end else if (rom_data >= "a" && rom_data <= "z") begin // assume ALWAYS lowercase alpha chars in node names
                                    name_buf[buf_count] <= rom_data;
                                    buf_count <= buf_count + 1;
                                    rom_addr <= rom_addr + 1;
                                    if (buf_count == 2) begin
                                        parser_state <= P_LOOKUP;
                                    end 
                                end else begin
                                    if (rom_data == "\n") begin
                                        has_src <= 0; // reset to parse the next start node
                                    end
                                    rom_addr <= rom_addr + 1;
                                end
                            end else begin
                                if (rom_addr > 0 && !rom_valid) begin
                                    // $display("finished parsing input file at: %d", rom_addr);
                                    state <= S_P1_SETUP;
                                end
                            end
                        end


                        P_LOOKUP: begin
                            nr_query <= {name_buf[0], name_buf[1], name_buf[2]};
                            nr_valid <= 1;
                            buf_count <= 0;
                            parser_state <= P_DECIDE;
                        end



                        P_DECIDE: begin
                            // wait for name lookup module 
                            if (nr_done) begin
                                // store special node IDs for quick access:
                                if (nr_query == STR_YOU) begin
                                    ids[0] <= nr_id;
                                end
                                if (nr_query == STR_OUT) begin
                                    ids[1] <= nr_id;
                                end
                                if (nr_query == STR_SVR) begin
                                    ids[2] <= nr_id;
                                end
                                if (nr_query == STR_DAC) begin
                                    ids[3] <= nr_id;
                                end
                                if (nr_query == STR_FFT) begin
                                    ids[4] <= nr_id;
                                end

                                if (!has_src) begin
                                    curr_src <= nr_id;
                                    has_src <= 1;
                                end else begin
                                    gm_src <= curr_src;
                                    gm_dst <= nr_id;
                                    gm_we <= 1;
                                    // $display("Stored edge: (%d, %d)", curr_src, nr_id);
                                end

                                // fetch next name:
                                parser_state <= P_FETCH;
                            end
                        end


                        P_DONE: begin
                            // do nothing
                            // should neverhappen, but just go to next state as safety:
                            state <= S_P1_SETUP;
                        end
                    endcase
                end

                // PART 1 SOLVER: path_count("you", "out")
                S_P1_SETUP: begin
                    pc_s <= ids[0]; // you
                    pc_t <= ids[1]; // out
                    state <= S_P1_START;
                end

                S_P1_START: begin
                    pc_start <= 1;
                    state <= S_P1_WAIT;
                end


                S_P1_WAIT: begin
                    // wait until path counter finished dfs'ing:
                    if (pc_done) begin
                        part1_result <= pc_result;
                        state <= S_P2A_1_SETUP;
                    end
                end

                // SOLVING PART 2:
                // P2A: solve paths from svr -> dac
                S_P2A_1_SETUP: begin
                    pc_s <= ids[2]; // svr
                    pc_t <= ids[3]; // dac
                    state <= S_P2A_1_START;
                end


                S_P2A_1_START: begin
                    pc_start <= 1;
                    state <= S_P2A_1_WAIT;
                end


                S_P2A_1_WAIT: begin
                    // wait until path counter finished dfs'ing:
                    if (pc_done) begin
                        p2_acc[0] <= pc_result;
                        state <= S_P2A_2_SETUP;
                    end
                end

                // P2A: solve paths from dac -> fft
                S_P2A_2_SETUP: begin
                    pc_s <= ids[3]; // dac
                    pc_t <= ids[4]; // fft
                    state <= S_P2A_2_START;
                end


                S_P2A_2_START: begin
                    pc_start <= 1;
                    state <= S_P2A_2_WAIT;
                end


                S_P2A_2_WAIT: begin
                    if (pc_done) begin
                        p2_acc[0] <= p2_acc[0] * pc_result;
                        state <= S_P2A_3_SETUP;
                    end
                end

                // P2A: solve paths from fft -> out
                S_P2A_3_SETUP: begin
                    pc_s <= ids[4]; // fft
                    pc_t <= ids[1]; // out
                    state <= S_P2A_3_START;
                end


                S_P2A_3_START: begin
                    pc_start <= 1;
                    state <= S_P2A_3_WAIT;
                end


                S_P2A_3_WAIT: begin
                    if (pc_done) begin
                        p2_acc[0] <= p2_acc[0] * pc_result;
                        state <= S_P2B_1_SETUP;
                    end
                end

                // P2B: solve paths from svr -> fft
                S_P2B_1_SETUP: begin
                    pc_s <= ids[2];
                    pc_t <= ids[4];
                    state <= S_P2B_1_START;
                end


                S_P2B_1_START: begin
                    pc_start <= 1;
                    state <= S_P2B_1_WAIT;
                end


                S_P2B_1_WAIT: begin
                    if (pc_done) begin
                        p2_acc[1] <= pc_result;
                        state <= S_P2B_2_SETUP;
                    end
                end

                // P2B: solve paths from fft -> dac
                S_P2B_2_SETUP: begin
                    pc_s <= ids[4];
                    pc_t <= ids[3];
                    state <= S_P2B_2_START;
                end


                S_P2B_2_START: begin
                    pc_start <= 1;
                    state <= S_P2B_2_WAIT;
                end


                S_P2B_2_WAIT: begin
                    if (pc_done) begin
                        p2_acc[1] <= p2_acc[1] * pc_result;
                        state <= S_P2B_3_SETUP;
                    end
                end

                // P2B: solve paths from dac -> out
                S_P2B_3_SETUP: begin
                    pc_s <= ids[3];
                    pc_t <= ids[1];
                    state <= S_P2B_3_START;
                end


                S_P2B_3_START: begin
                    pc_start <= 1;
                    state <= S_P2B_3_WAIT;
                end


                S_P2B_3_WAIT: begin
                    if (pc_done) begin
                        p2_acc[1] <= p2_acc[1] * pc_result;
                        state <= S_CALC_RESULTS;
                    end
                end


                S_CALC_RESULTS: begin
                    part2_result <= p2_acc[0] + p2_acc[1];
                    done <= 1;
                    state <= S_DONE;
                end


                S_DONE: begin
                    done <= 1;
                end


            endcase
        end
    end
endmodule




module name_resolver #(
    parameter LOG2_MAX_NODES = 10, // my puzzle input has only 583 nodes so this seems like a reasonable max size
    parameter MAX_NODES = 1024
) (
    input wire clk,
    input wire rst,
    
    input wire [23:0] name_in, // assumption that ALL nodes are exactly 3 chars
    input wire valid_in,

    output reg [LOG2_MAX_NODES-1:0] node_id_out,
    output reg done,
    output reg init_done
);

    localparam HASH_DEPTH = 17576; // 26^3
    localparam HASH_ADDR_BITS = 15;
    // ram to store lookup for each node name:
    reg hash_we;
    reg [HASH_ADDR_BITS-1:0] hash_w_addr;
    reg [9:0] hash_w_data;
    reg [HASH_ADDR_BITS-1:0] hash_r_addr;
    wire [9:0] hash_r_data;

    ram #(
        .WIDTH(10),
        .DEPTH(HASH_DEPTH),
        .ADDR_BITS(HASH_ADDR_BITS)
    ) u_ram_hash_0(
        .clk(clk),
        .rst(rst),
        .we(hash_we),
        .w_addr(hash_w_addr),
        .w_data(hash_w_data),
        .r_addr(hash_r_addr),
        .r_data(hash_r_data)
    );

    // states:
    localparam S_INIT = 0;
    localparam S_IDLE = 1;
    localparam S_COMPUTE = 2;
    localparam S_READ_WAIT = 3;
    localparam S_CHECK = 4;
    reg [2:0] state;

    reg [14:0] init_idx;
    reg [9:0] node_count;
    reg [HASH_ADDR_BITS-1:0] current_hash;

    always @(posedge clk) begin
        if (rst) begin
            state <= S_INIT;
            init_idx <= 0;
            init_done <= 0;
            node_count <= 0;
            done <= 0;
            hash_we <= 0;
        end 
        else begin
            done <= 0;
            hash_we <= 0;

            case (state)
                S_INIT: begin
                    hash_we <= 1;
                    hash_w_addr <= init_idx[HASH_ADDR_BITS-1:0];
                    hash_w_data <= 1023;
                    init_idx <= init_idx + 1;
                    if (init_idx == HASH_DEPTH - 1) begin
                        init_done <= 1;
                        state <= S_IDLE;
                    end
                end

                S_IDLE: begin
                    if (valid_in) begin
                        current_hash <= (name_in[23:16] - 8'd97) * 676 + (name_in[15:8] - 8'd97) * 26 + (name_in[7:0] - 8'd97);
                        state <= S_COMPUTE;
                    end
                end


                S_COMPUTE: begin
                    hash_r_addr <= current_hash;
                    state <= S_READ_WAIT;
                end

                S_READ_WAIT: begin
                    state <= S_CHECK;
                end


                S_CHECK: begin
                    if (hash_r_data == 1023) begin
                        hash_we <= 1;
                        hash_w_addr <= current_hash;
                        hash_w_data <= node_count;

                        node_id_out <= node_count;
                        node_count <= node_count + 1;
                        done <= 1;
                    end else begin
                        node_id_out <= hash_r_data;
                        done <= 1;
                    end
                    state <= S_IDLE;
                end

            endcase
        end
    end

endmodule


module graph_manager #(
    parameter NODE_BITS = 10,
    parameter EDGE_BITS = 13,
    parameter MAX_NODES = 1024, // my puzzle input had ~500 lines (nodes), so this is reasonable(ish) estimate
    parameter MAX_EDGES = 8192 // likely an overshoot
) (
    input wire clk,
    input wire rst,

    input wire add_edge_en,
    input wire [NODE_BITS-1:0] src_node,
    input wire [NODE_BITS-1:0] dst_node,

    input wire [NODE_BITS-1:0] read_node_addr,
    output wire [EDGE_BITS-1:0] head_start_out,
    output wire [4:0] head_count_out, // number of outgoing edges from the node (hardcoded to max 32) // todo maybe fix this

    input wire [EDGE_BITS-1:0] read_edge_addr,
    output wire [NODE_BITS-1:0] edge_to_out,
    output reg init_done
);

    localparam NODE_INFO_WIDTH = EDGE_BITS + 5;

    // node info ram:
    reg node_we;
    reg [NODE_BITS-1:0] node_w_addr;
    reg [NODE_INFO_WIDTH-1:0] node_w_data;
    wire [NODE_INFO_WIDTH-1:0] node_r_data;

    // edge ram signals:
    reg edge_we;
    reg [EDGE_BITS-1:0] edge_w_addr;
    reg [NODE_BITS-1:0] edge_w_data;
    wire [NODE_BITS-1:0] edge_r_data;

    // multiplex read address: 
    reg [NODE_BITS-1:0] node_r_addr_mux;

    ram #(
        .WIDTH(NODE_INFO_WIDTH),
        .DEPTH(MAX_NODES),
        .ADDR_BITS(NODE_BITS)
    ) u_node_ram_0 (
        .clk(clk),
        .rst(rst),
        .we(node_we),
        .w_addr(node_w_addr),
        .w_data(node_w_data),
        .r_addr(node_r_addr_mux),
        .r_data(node_r_data)
    );

    ram #(
        .WIDTH(NODE_BITS),
        .DEPTH(MAX_EDGES),
        .ADDR_BITS(EDGE_BITS)
    ) u_edge_ram_0 (
        .clk(clk),
        .rst(rst),
        .we(edge_we),
        .w_addr(edge_w_addr),
        .w_data(edge_w_data),
        .r_addr(read_edge_addr),
        .r_data(edge_r_data)
    );

    assign head_start_out = node_r_data[NODE_INFO_WIDTH-1:5];
    assign head_count_out = node_r_data[4:0];
    assign edge_to_out = edge_r_data;

    // FSM:
    localparam S_INIT = 0;
    localparam S_IDLE = 1;
    localparam S_READ_NODE = 2;
    localparam S_WRITE_NODE = 3;
    reg [1:0] state;

    reg [NODE_BITS:0] init_idx;
    reg [EDGE_BITS-1:0] edge_count;
    reg [NODE_BITS-1:0] pending_src;
    reg [NODE_BITS-1:0] pending_dst;

    // mux the node ram addr:
    always @(*) begin
        if (state == S_READ_NODE || state == S_WRITE_NODE) begin
            node_r_addr_mux = pending_src;
        end else if (add_edge_en) begin
            node_r_addr_mux = src_node;
        end else begin
            node_r_addr_mux = read_node_addr;
        end
    end

    always @(posedge clk) begin
        if (rst) begin
            state <= S_INIT;
            init_idx <= 0;
            init_done <= 0;
            edge_count <= 0;
            node_we <= 0;
            edge_we <= 0;
        end else begin
            node_we <= 0;
            edge_we <= 0;

            case (state)
                S_INIT: begin
                    node_we <= 1;
                    node_w_addr <= init_idx[NODE_BITS-1:0];
                    node_w_data <= 0;

                    init_idx <= init_idx + 1;
                    if (init_idx == MAX_NODES - 1) begin
                        init_done <= 1;
                        state <= S_IDLE;
                    end
                end


                S_IDLE: begin
                    if (add_edge_en) begin
                        pending_src <= src_node;
                        pending_dst <= dst_node;
                        state <= S_READ_NODE;
                    end
                end


                S_READ_NODE: begin
                    state <= S_WRITE_NODE;
                end


                S_WRITE_NODE: begin
                    if (node_r_data[4:0] == 0) begin
                        node_w_data <= {edge_count, 5'd1};
                    end else begin
                        node_w_data <= {node_r_data[NODE_INFO_WIDTH-1:5], node_r_data[4:0] + 5'd1};
                    end

                    node_we <= 1;
                    node_w_addr <= pending_src;

                    edge_we <= 1;
                    edge_w_addr <= edge_count;
                    edge_w_data <= pending_dst;
                    edge_count <= edge_count + 1;
                    state <= S_IDLE;
                end
            endcase
        end
    end


endmodule


module path_counter #(
    parameter NODE_BITS = 10,
    parameter EDGE_BITS = 13
) (
    input wire clk,
    input wire rst,
    input wire start,

    input wire [NODE_BITS-1:0] src_node,
    input wire [NODE_BITS-1:0] dst_node,
    output reg [63:0] count_out,
    output reg done,

    // connection to graph_manager:
    output reg [NODE_BITS-1:0] gm_read_node_addr,
    input wire [EDGE_BITS-1:0] gm_head_start,
    input wire [4:0] gm_head_count,
    output reg [EDGE_BITS-1:0] gm_read_edge_addr,
    input wire [NODE_BITS-1:0] gm_edge_to
);

    // stack storage: (left as registers for now)
    localparam MAX_STACK_DEPTH = 64;
    reg [NODE_BITS-1:0] stk_node [0:MAX_STACK_DEPTH-1];
    reg [EDGE_BITS-1:0] stk_edge_start [0:MAX_STACK_DEPTH-1];
    reg [4:0] stk_edge_count [0:MAX_STACK_DEPTH-1];
    reg [4:0] stk_edge_idx [0:MAX_STACK_DEPTH-1];
    reg [63:0] stk_sum [0:MAX_STACK_DEPTH-1];
    reg [6:0] sp;

    // memo ram signals:
    reg memo_we;
    reg [NODE_BITS-1:0] memo_w_addr;
    reg [63:0] memo_w_data;
    reg [NODE_BITS-1:0] memo_r_addr;
    wire [63:0] memo_r_data;
    reg [1023:0] memo_v;

    ram #(
        .WIDTH(64),
        .DEPTH(1024),
        .ADDR_BITS(NODE_BITS)
    ) u_memo_ram_0 (
        .clk(clk),
        .rst(rst),
        .we(memo_we),
        .w_addr(memo_w_addr),
        .w_data(memo_w_data),
        .r_addr(memo_r_addr),
        .r_data(memo_r_data)
    );

    localparam S_IDLE = 0;
    localparam S_START_NODE = 1;
    localparam S_MEMO_WAIT = 2;
    localparam S_MEMO_READ = 3;
    localparam S_HEAD_ISSUE = 4;
    localparam S_HEAD_WAIT = 5;
    localparam S_ITERATE = 6;
    localparam S_EDGE_WAIT = 7;
    localparam S_PROCESS_EDGE = 8;
    reg [3:0] state;
    reg [NODE_BITS-1:0] curr_u;

    always @(posedge clk) begin
        if (rst) begin
            state <= S_IDLE;
            done <= 0;
            memo_v <= 0;
            memo_we <= 0;
        end else begin
            memo_we <= 0;

            case (state)
                S_IDLE: begin
                    done <= 0;
                    if (start) begin
                        memo_v <= 0;
                        sp <= 0;
                        stk_node[0] <= src_node;
                        stk_sum[0] <= 0;
                        state <= S_START_NODE;
                    end
                end


                S_START_NODE: begin
                    curr_u = stk_node[sp];
                    if (curr_u == dst_node) begin
                        // found the target:
                        if (sp == 0) begin
                            count_out <= 1;
                            done <= 1;
                            state <= S_IDLE;
                        end else begin
                            stk_sum[sp-1] <= stk_sum[sp-1] + 1;
                            sp <= sp-1;
                            state <= S_ITERATE;
                        end
                    end else if (memo_v[curr_u]) begin
                        // subproblem already solved
                        memo_r_addr <= curr_u;
                        state <= S_MEMO_WAIT;
                    end else begin
                        // need to solve children:
                        gm_read_node_addr <= curr_u;
                        state <= S_HEAD_ISSUE;
                    end 
                end


                S_MEMO_WAIT: begin
                    state <= S_MEMO_READ;
                end


                S_MEMO_READ: begin
                    if (sp == 0) begin
                        count_out <= memo_r_data;
                        done <= 1;
                        state <= S_IDLE;
                    end else begin
                        stk_sum[sp-1] <= stk_sum[sp-1] + memo_r_data;
                        sp <= sp-1;
                        state <= S_ITERATE;
                    end
                end


                S_HEAD_ISSUE: begin
                    state <= S_HEAD_WAIT;
                end


                S_HEAD_WAIT: begin
                    stk_edge_start[sp] <= gm_head_start;
                    stk_edge_count[sp] <= gm_head_count;
                    stk_edge_idx[sp] <= 0;
                    state <= S_ITERATE;
                end


                S_ITERATE: begin
                    if (stk_edge_idx[sp] == stk_edge_count[sp]) begin
                        // all edges processed -> write to memo
                        memo_we <= 1;
                        memo_w_addr <= stk_node[sp];
                        memo_w_data <= stk_sum[sp];
                        memo_v[stk_node[sp]] <= 1;

                        if (sp == 0) begin
                            count_out <= stk_sum[sp];
                            done <= 1;
                            state <= S_IDLE;
                        end else begin
                            stk_sum[sp-1] <= stk_sum[sp-1] + stk_sum[sp];
                            sp <= sp-1;
                            state <= S_ITERATE;
                        end
                    end else begin
                        // process next edge/child:
                        gm_read_edge_addr <= stk_edge_start[sp] + stk_edge_idx[sp];
                        stk_edge_idx[sp] <= stk_edge_idx[sp] + 1;
                        state <= S_EDGE_WAIT;
                    end
                end


                S_EDGE_WAIT: begin
                    state <= S_PROCESS_EDGE;
                end


                S_PROCESS_EDGE: begin
                    // push child onto stack:
                    sp <= sp + 1;
                    stk_node[sp+1] <= gm_edge_to;
                    stk_sum[sp+1] <= 0;
                    state <= S_START_NODE;
                end
            endcase
        end
    end

endmodule
