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
        .is_new()  // todo: actually not necessary I think?
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
                            if (gm_ready) begin
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
                    // pass
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
    output reg is_new // whether the node that was just added was in the lookup table already or not
);

    // simple linear store for now
    // TODO: turn into tree-based lookup?
    reg [23:0] name_store [0:MAX_NODES-1];
    reg [LOG2_MAX_NODES-1:0] node_count;

    reg [LOG2_MAX_NODES-1:0] search_idx;
    reg searching;

    always @(posedge clk) begin
        if (rst) begin
            node_count <= 0;
            searching <= 0;
            done <= 0;
        end else begin
            done <= 0;
            is_new <= 0;
            if (valid_in && !searching) begin
                searching <= 1;
                search_idx <= 0;
            end

            if (searching) begin
                if (search_idx < node_count) begin
                    if (name_store[search_idx] == name_in) begin
                        // found node -> end search and return id
                        done <= 1;
                        node_id_out <= search_idx;
                        searching <= 0;
                    end else begin
                        search_idx <= search_idx + 1;
                    end
                end else begin
                    // exhasuted all nodes, must be a new node
                    // add node to store:
                    name_store[node_count] <= name_in;
                    node_id_out <= node_count;
                    node_count <= node_count + 1;
                    is_new <= 1;
                    // end search
                    done <= 1;
                    searching <= 0;
                end
            end
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
    output reg [EDGE_BITS-1:0] head_start_out,
    output reg [4:0] head_count_out, // number of outgoing edges from the node (hardcoded to max 32) // todo maybe fix this

    input wire [EDGE_BITS-1:0] read_edge_addr,
    output reg [NODE_BITS-1:0] edge_to_out,
    output reg init_done
);

    // using a CSR-like approach to store nodes (uses less memory overhead than linked list approach)
    reg [EDGE_BITS-1:0] heads [0:MAX_NODES-1];
    reg [4:0] counts [0:MAX_NODES-1];
    reg [NODE_BITS-1:0] edge_store [0:MAX_EDGES-1];

    reg [EDGE_BITS-1:0] edge_count;
    reg [NODE_BITS:0] init_idx;

    always @(posedge clk) begin
        head_start_out <= heads[read_node_addr];
        head_count_out <= counts[read_node_addr];
        edge_to_out <= edge_store[read_edge_addr];

        if (rst) begin
            edge_count <= 0;
            init_idx <= 0;
            init_done <= 0;
        end else if (!init_done) begin
            // iteratively clear this here, because the rest of the solver takes so **** long to run, that 1024 cycles is comparatively negligible and it's better to save on logic resources / registers
            heads[init_idx] <= 0;
            counts[init_idx] <= 0;
            init_idx <= init_idx + 1;
            if (init_idx == MAX_NODES-1) begin
                init_done <= 1;
            end
        end else if (add_edge_en) begin
            if (counts[src_node] == 0) begin
                heads[src_node] <= edge_count;
            end
            edge_store[edge_count] <= dst_node;
            counts[src_node] <= counts[src_node] + 1;
            edge_count <= edge_count + 1;
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

    // stack storage:
    localparam MAX_STACK_DEPTH = 64;
    reg [NODE_BITS-1:0] stk_node [0:MAX_STACK_DEPTH-1];
    reg [EDGE_BITS-1:0] stk_edge_start [0:MAX_STACK_DEPTH-1];
    reg [4:0] stk_edge_count [0:MAX_STACK_DEPTH-1];
    reg [4:0] stk_edge_idx [0:MAX_STACK_DEPTH-1];
    reg [63:0] stk_sum [0:MAX_STACK_DEPTH-1];
    reg [6:0] sp;

    // memoization: // todo: move this to an external ram module
    reg [63:0] memo [0:1023];
    reg [1023:0] memo_v; // valid bit tags to avoid clearing memo array between 'calls' to this 'function'

    // FSM:
    localparam S_IDLE = 0; // reuse S_IDLE as done state since start input required to trigger new computation from idle
    localparam S_START_NODE = 1;
    localparam S_FETCH_HEAD = 2;
    localparam S_FETCH_HEAD_2 = 3;
    localparam S_ITERATE = 4;
    localparam S_FETCH_EDGE = 5;
    localparam S_PROCESS_EDGE = 6;
    reg [2:0] state;
    reg [NODE_BITS-1:0] curr_u;

    always @(posedge clk) begin
        if (rst) begin
            state <= S_IDLE;
            done <= 0;
            memo_v <= 0;
        end else begin
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
                        // reached end:
                        if (sp == 0) begin
                            count_out <= 1;
                            done <= 1;
                            state <= S_IDLE;
                        end else begin
                            stk_sum[sp-1] <= stk_sum[sp-1] + 1;
                            sp <= sp-1;
                            // go back to caller (parent node)
                            state <= S_ITERATE;
                        end
                    end else if (memo_v[curr_u]) begin
                        if (sp == 0) begin
                            count_out <= memo[curr_u];
                            done <= 1;
                            state <= S_IDLE;
                        end else begin
                            stk_sum[sp-1] <= stk_sum[sp-1] + memo[curr_u];
                            sp <= sp-1;
                            // go back to caller (parent node)
                            state <= S_ITERATE;
                        end
                    end else begin
                        state <= S_FETCH_HEAD;
                        gm_read_node_addr <= curr_u;
                    end
                end

                S_FETCH_HEAD: begin
                    state <= S_FETCH_HEAD_2; // wait for a cycle to let graph manager respond
                end

                S_FETCH_HEAD_2: begin
                    stk_edge_count[sp] <= gm_head_count;
                    stk_edge_start[sp] <= gm_head_start;
                    stk_edge_idx[sp] <= 0;

                    // loop over adjacent nodes:
                    state <= S_ITERATE;
                end


                S_ITERATE: begin
                    // check if done:
                    if (stk_edge_idx[sp] == stk_edge_count[sp]) begin
                        // iterated over all outgoing edges
                        // store result:
                        memo[stk_node[sp]] <= stk_sum[sp];
                        memo_v[stk_node[sp]] <= 1;
                        if (sp == 0) begin
                            count_out <= stk_sum[sp];
                            done <= 1;
                            state <= S_IDLE;
                        end else begin
                            stk_sum[sp-1] <= stk_sum[sp-1] + stk_sum[sp];
                            sp <= sp - 1;
                            state <= S_ITERATE;
                        end
                    end else begin
                        // continue iterating over edges:
                        gm_read_edge_addr <= stk_edge_start[sp] + stk_edge_idx[sp];
                        stk_edge_idx[sp] <= stk_edge_idx[sp] + 1;
                        state <= S_FETCH_EDGE;
                    end
                end


                S_FETCH_EDGE: begin
                    state <= S_PROCESS_EDGE;
                end


                S_PROCESS_EDGE: begin
                    sp <= sp + 1;
                    stk_node[sp+1] <= gm_edge_to;
                    stk_sum[sp+1] <= 0;
                    state <= S_START_NODE;
                end
            endcase
        end
    end


endmodule
