module day08_core #(
    parameter N_ADDR_BITS = 16,
    parameter MAX_NODES = 1024,
    parameter NODE_ADDR_BITS = 10,
    parameter COORD_WIDTH = 32,
    parameter MAX_EDGES = 16384,
    parameter EDGE_ADDR_BITS = 14,
    parameter EDGE_WIDTH = 64,
    parameter PART1_EDGES = 1000
) (
    // Synchronous inputs:
    input wire clk,
    input wire rst,

    // IO to interface with ROM:
    input wire [7:0] rom_data,
    input wire rom_valid,
    output wire [N_ADDR_BITS:0] rom_addr,

    // results:
    output wire [63:0] part1_result,
    output wire [63:0] part2_result,
    output reg done
);
    // fsm states:
    localparam S_IDLE = 0;
    localparam S_PARSE = 1;
    localparam S_EDGE_GENERATION = 2;
    localparam S_SORT_EDGES = 3;
    localparam S_DSU = 4;
    localparam S_DONE = 5;
    reg [2:0] state;


    // start signalling for submodules:
    reg parser_start;
    reg edge_generation_start;
    reg sorter_start;
    reg dsu_start;


    // parser signals:
    wire parser_done;
    wire parser_node_we;
    wire [NODE_ADDR_BITS-1:0] parser_node_w_addr;
    wire [COORD_WIDTH*3-1:0] parser_node_w_data;
    wire [NODE_ADDR_BITS-1:0] num_nodes;


    // node ram signals:
    reg node_we;
    reg [NODE_ADDR_BITS-1:0] node_w_addr;
    wire [NODE_ADDR_BITS-1:0] node_r_addr_a;
    wire [NODE_ADDR_BITS-1:0] node_r_addr_b;
    reg [COORD_WIDTH*3-1:0] node_w_data;
    wire [COORD_WIDTH*3-1:0] node_r_data_a;
    wire [COORD_WIDTH*3-1:0] node_r_data_b;


    // edge generator module signals:
    wire edge_gen_done;
    wire edge_gen_we;
    wire [EDGE_ADDR_BITS-1:0] edge_gen_w_addr;
    wire [EDGE_WIDTH-1:0] edge_gen_w_data;
    wire [EDGE_ADDR_BITS:0] num_edges;


    // edge ram signals:
    reg edge_we_a;
    reg edge_we_b;
    reg [EDGE_ADDR_BITS-1:0] edge_w_addr_a;
    reg [EDGE_ADDR_BITS-1:0] edge_w_addr_b;
    reg [EDGE_WIDTH-1:0] edge_w_data_a;
    reg [EDGE_WIDTH-1:0] edge_w_data_b;
    reg [EDGE_ADDR_BITS-1:0] edge_r_addr_a;
    reg [EDGE_ADDR_BITS-1:0] edge_r_addr_b;
    reg [EDGE_WIDTH-1:0] edge_r_data_a;
    reg [EDGE_WIDTH-1:0] edge_r_data_b;


    // sorter signals:
    wire sorter_done;
    wire [EDGE_ADDR_BITS-1:0] sorter_r_addr_a;
    wire [EDGE_ADDR_BITS-1:0] sorter_r_addr_b;
    wire sorter_we_a;
    wire sorter_we_b;
    wire [EDGE_ADDR_BITS-1:0] sorter_w_addr_a;
    wire [EDGE_ADDR_BITS-1:0] sorter_w_addr_b;
    wire [EDGE_WIDTH-1:0] sorter_w_data_a;
    wire [EDGE_WIDTH-1:0] sorter_w_data_b;


    // dsu signals:
    wire dsu_done;
    wire [EDGE_ADDR_BITS-1:0] dsu_edge_r_addr;
    wire [NODE_ADDR_BITS-1:0] dsu_node_r_addr;
    wire dsu_parent_we;
    wire dsu_size_we;
    wire [NODE_ADDR_BITS-1:0] dsu_parent_r_addr;
    wire [NODE_ADDR_BITS-1:0] dsu_parent_w_addr;
    wire [NODE_ADDR_BITS-1:0] dsu_parent_w_data;
    wire [NODE_ADDR_BITS-1:0] parent_r_data;
    wire [NODE_ADDR_BITS-1:0] dsu_size_w_addr;
    wire [NODE_ADDR_BITS-1:0] dsu_size_r_addr;
    wire [15:0] dsu_size_w_data;
    wire [15:0] size_r_data;


    // instantiate parser module:
    parser #(
        .N_ADDR_BITS(N_ADDR_BITS),
        .MAX_NODES(MAX_NODES),
        .NODE_ADDR_BITS(NODE_ADDR_BITS),
        .COORD_WIDTH(COORD_WIDTH)
    ) u_parser_0 (
        .clk(clk),
        .rst(rst),
        .start(parser_start),
        .rom_data(rom_data),
        .rom_valid(rom_valid),
        .rom_addr(rom_addr),
        .node_we(parser_node_we),
        .node_w_addr(parser_node_w_addr),
        .node_w_data(parser_node_w_data),
        .num_nodes(num_nodes),
        .done(parser_done)
    );


    // multiplex node ram inputs based on state:
    always @(*) begin
        if (state == S_PARSE) begin
            node_we = parser_node_we;
            node_w_addr = parser_node_w_addr;
            node_w_data = parser_node_w_data;
        end else begin
            node_we = 0;
            node_w_addr = 0;
            node_w_data = 0;
        end
    end
    wire [NODE_ADDR_BITS-1:0] node_r_addr_mux_a = (state == S_DSU) ? dsu_node_r_addr : node_r_addr_a;
    wire [NODE_ADDR_BITS-1:0] node_r_addr_mux_b = node_r_addr_b;

    // instantiate node ram:
    ram_dp #(
        .WIDTH(COORD_WIDTH * 3),
        .DEPTH(MAX_NODES),
        .ADDR_BITS(NODE_ADDR_BITS)
    ) u_node_ram_dp_0 (
        .clk(clk),
        .rst(rst),
        
        // port a written to by parser, and read by edge generator and DSU
        .we_a(node_we),
        .addr_a(node_we ? node_w_addr : node_r_addr_mux_a),
        .w_data_a(node_w_data),
        .r_data_a(node_r_data_a),

        // port b only used by edge generator
        .we_b(1'b0), // never need to write to it
        .addr_b(node_r_addr_mux_b),
        .w_data_b({(COORD_WIDTH*3){1'b0}}),
        .r_data_b(node_r_data_b)
    );

    // instantiate edge generator:
    edge_generator #(
        .MAX_NODES(MAX_NODES),
        .NODE_ADDR_BITS(NODE_ADDR_BITS),
        .COORD_WIDTH(COORD_WIDTH),
        .MAX_EDGES(MAX_EDGES),
        .EDGE_ADDR_BITS(EDGE_ADDR_BITS),
        .EDGE_WIDTH(EDGE_WIDTH)
        // left num buckets as 16
    ) u_edge_generator_0 (
        .clk(clk),
        .rst(rst),
        .start(edge_generation_start),
        .num_nodes(num_nodes),
        .node_r_data_a(node_r_data_a),
        .node_r_data_b(node_r_data_b),
        .node_r_addr_a(node_r_addr_a),
        .node_r_addr_b(node_r_addr_b),
        .edge_we(edge_gen_we),
        .edge_w_addr(edge_gen_w_addr),
        .edge_w_data(edge_gen_w_data),
        .num_edges(num_edges),
        .done(edge_gen_done)
    );


    // edge ram multiplexing logic:
    always @(*) begin
        case (state)
            S_EDGE_GENERATION: begin
                edge_we_a = edge_gen_we;
                edge_we_b = 0;
                edge_w_addr_a = edge_gen_w_addr;
                edge_w_addr_b = 0;
                edge_w_data_a = edge_gen_w_data;
                edge_w_data_b = 0;
                edge_r_addr_a = 0;
                edge_r_addr_b = 0;
            end


            S_SORT_EDGES: begin
                edge_we_a = sorter_we_a;
                edge_we_b = sorter_we_b;
                edge_w_addr_a = sorter_w_addr_a;
                edge_w_addr_b = sorter_w_addr_b;
                edge_w_data_a = sorter_w_data_a;
                edge_w_data_b = sorter_w_data_b;
                edge_r_addr_a = sorter_r_addr_a;
                edge_r_addr_b = sorter_r_addr_b;
            end


            S_DSU: begin
                edge_we_a = 0;
                edge_we_b = 0;
                edge_w_addr_a = 0;
                edge_w_addr_b = 0;
                edge_w_data_a = 0;
                edge_w_data_b = 0;
                edge_r_addr_a = dsu_edge_r_addr;
                edge_r_addr_b = 0;
            end


            default: begin
                edge_we_a = 0;
                edge_we_b = 0;
                edge_w_addr_a = 0;
                edge_w_addr_b = 0;
                edge_w_data_a = 0;
                edge_w_data_b = 0;
                edge_r_addr_a = 0;
                edge_r_addr_b = 0;
            end
        endcase
    end


    // instantiate edge ram:
    wire edge_ram_init_done;
    ram_dp_init #(
        .WIDTH(EDGE_WIDTH),
        .DEPTH(MAX_EDGES),
        .ADDR_BITS(EDGE_ADDR_BITS),
        .INIT_VALUE({32'hFFFFFFFF, 32'd0})  // Max weight, indices not strictly relevant
    ) u_edge_ram_0 (
        .clk(clk),
        .rst(rst),
        // port b:
        .we_a(edge_we_a),
        .addr_a(edge_we_a ? edge_w_addr_a :edge_r_addr_a),
        .w_data_a(edge_w_data_a),
        .r_data_a(edge_r_data_a),
        // port b:
        .we_b(edge_we_b),
        .addr_b(edge_we_b ? edge_w_addr_b : edge_r_addr_b),
        .w_data_b(edge_w_data_b),
        .r_data_b(edge_r_data_b),
        .init_done(edge_ram_init_done)
    );


    // instantiate sorter:
    wire [EDGE_ADDR_BITS-1:0] sort_progress;

    bitonic_sorter #(
        .MAX_NUM_VALUES(MAX_EDGES),
        .DATA_ADDR_BITS(EDGE_ADDR_BITS),
        .DATA_WIDTH(EDGE_WIDTH)
    ) u_bitonic_sorter_0 (
        .clk(clk),
        .rst(rst),
        .start(sorter_start),
        .num_values(num_edges),

        .data_we_a(sorter_we_a),
        .data_w_addr_a(sorter_w_addr_a),
        .data_w_data_a(sorter_w_data_a),
        .data_r_addr_a(sorter_r_addr_a),
        .data_r_data_a(edge_r_data_a),

        .data_we_b(sorter_we_b),
        .data_w_addr_b(sorter_w_addr_b),
        .data_w_data_b(sorter_w_data_b),
        .data_r_addr_b(sorter_r_addr_b),
        .data_r_data_b(edge_r_data_b),

        .done(sorter_done),
        .sort_progress(sort_progress)
    );


    // instantiate parent ram:
    ram #(
        .WIDTH(NODE_ADDR_BITS),
        .DEPTH(MAX_NODES),
        .ADDR_BITS(NODE_ADDR_BITS)
    ) u_parent_ram_0 (
        .clk(clk),
        .rst(rst),
        .we(dsu_parent_we),
        .w_addr(dsu_parent_w_addr),
        .w_data(dsu_parent_w_data),
        .r_addr(dsu_parent_r_addr),
        .r_data(parent_r_data)
    );


    // instantiate size ram:
    ram #(
        .WIDTH(16),
        .DEPTH(MAX_NODES),
        .ADDR_BITS(NODE_ADDR_BITS)
    ) u_size_ram_0 (
        .clk(clk),
        .rst(rst),
        .we(dsu_size_we),
        .w_addr(dsu_size_w_addr),
        .w_data(dsu_size_w_data),
        .r_addr(dsu_size_r_addr),
        .r_data(size_r_data)
    );


    // instantiate DSU:
    dsu #(
        .MAX_NODES(MAX_NODES),
        .NODE_ADDR_BITS(NODE_ADDR_BITS),
        .MAX_EDGES(MAX_EDGES),
        .EDGE_ADDR_BITS(EDGE_ADDR_BITS),
        .EDGE_WIDTH(EDGE_WIDTH),
        .COORD_WIDTH(COORD_WIDTH),
        .PART1_EDGES(PART1_EDGES)
    ) u_dsu_0 (
        .clk(clk),
        .rst(rst),
        .start(dsu_start),
        .num_nodes(num_nodes),
        .num_edges(num_edges),
        .edge_r_data(edge_r_data_a),
        .edge_r_addr(dsu_edge_r_addr),
        .node_r_data(node_r_data_a),
        .node_r_addr(dsu_node_r_addr),
        .parent_r_data(parent_r_data),
        .parent_we(dsu_parent_we),
        .parent_r_addr(dsu_parent_r_addr),
        .parent_w_addr(dsu_parent_w_addr),
        .parent_w_data(dsu_parent_w_data),
        .size_r_data(size_r_data),
        .size_we(dsu_size_we),
        .size_r_addr(dsu_size_r_addr),
        .size_w_addr(dsu_size_w_addr),
        .size_w_data(dsu_size_w_data),
        .part1_result(part1_result),
        .part2_result(part2_result),
        .done(dsu_done)
    );

    always @(posedge clk) begin
        if (rst) begin
            state <= S_IDLE;
            parser_start <= 0;
            edge_generation_start <= 0;
            sorter_start <= 0;
            dsu_start <= 0;
            done <= 0;
        end else begin
            parser_start <= 0;
            edge_generation_start <= 0;
            sorter_start <= 0;
            dsu_start <= 0;

            case (state)
                S_IDLE: begin
                    // wait for edge ram initialisation:
                    if (edge_ram_init_done) begin
                        $display("\tIntialisation done, beginning parsing");
                        parser_start <= 1;
                        state <= S_PARSE;
                    end 
                    done <= 0;
                end

                S_PARSE: begin
                    if (parser_done) begin
                        $display("\tParsing done, beginning edge generation");
                        edge_generation_start <= 1;
                        state <= S_EDGE_GENERATION;
                    end
                end

                S_EDGE_GENERATION: begin
                    if (edge_gen_done) begin
                        $display("\tEdge generation done, beginning sorting");
                        sorter_start <= 1;
                        state <= S_SORT_EDGES;
                    end
                end

                S_SORT_EDGES: begin
                    if (sorter_done) begin
                        $display("\tSorting done, beginning DSU");
                        dsu_start <= 1;
                        state <= S_DSU;
                    end
                end

                S_DSU: begin
                    if (dsu_done) begin
                        state <= S_DONE;
                    end
                end

                S_DONE: begin
                    done <= 1;
                end

            endcase
        end
    end

endmodule



// module to parse the input file and write 3D coordinates to a RAM block
module parser #(
    parameter N_ADDR_BITS = 16,
    parameter MAX_NODES = 8192,
    parameter NODE_ADDR_BITS = 13,
    parameter COORD_WIDTH = 32
) (
    input wire clk,
    input wire rst,
    input wire start,

    // rom interfacing signals:
    input wire [7:0] rom_data,
    input wire rom_valid,
    output reg [N_ADDR_BITS:0] rom_addr,

    // node RAM write interface
    output reg node_we,
    output reg [NODE_ADDR_BITS-1:0] node_w_addr,
    output reg [COORD_WIDTH*3-1:0] node_w_data, // node data = (x,y,z) tuple

    // output signals:
    output reg [NODE_ADDR_BITS-1:0] num_nodes, // total number of nodes parsed
    output reg done
);
    // define parser FSM states:
    localparam S_IDLE = 0;
    localparam S_READ_CHAR = 1;
    localparam S_PARSE_X = 2;
    localparam S_PARSE_Y = 3;
    localparam S_PARSE_Z = 4;
    localparam S_STORE = 5;
    localparam S_DONE = 6;
    reg [2:0] state;
    reg [2:0] next_state;

    // store current coordinate:
    reg [COORD_WIDTH-1:0] acc;
    reg [COORD_WIDTH-1:0] coord_x;
    reg [COORD_WIDTH-1:0] coord_y;
    reg [COORD_WIDTH-1:0] coord_z;

    wire is_digit = (rom_data >= "0") && (rom_data <= "9");
    wire is_comma = (rom_data == ",");
    wire is_newline = (rom_data == "\n");
    wire is_eof = !rom_valid;
    wire [3:0] digit_value = rom_data - "0"; 
    // wire [3:0] digit_value = rom_data[3:0]; // since "0" is 0x30, can get digit value just by taking bottom 4 bits!

    // mac storage:
    wire [COORD_WIDTH-1:0] acc_x_10 = (acc << 3) + (acc << 1);
    wire [COORD_WIDTH-1:0] acc_next = acc_x_10 + {28'd0, digit_value};

    always @(posedge clk) begin
        if (rst) begin
            state <= S_IDLE;
            rom_addr <= 0;
            acc <= 0;
            coord_x <= 0;
            coord_y <= 0;
            coord_z <= 0;
            node_w_addr <= 0;
            node_we <= 0;
            num_nodes <= 0;
            done <= 0;
        end else begin
            // default disable we:
            node_we <= 0;

            case (state)
                S_IDLE: begin
                    if (start) begin
                        state <= S_READ_CHAR;
                        rom_addr <= 0;
                        acc <= 0;
                        node_w_addr <= 0;
                        num_nodes <= 0;
                        done <= 0;
                    end
                end

                // wait for rom data available (not strictly necessary for this simulation context but included anyways)
                S_READ_CHAR: begin
                    if (is_eof) begin
                        state <= S_DONE;
                    end else if (rom_valid) begin
                        state <= S_PARSE_X;
                    end
                end


                S_PARSE_X: begin
                    if (is_digit) begin
                        acc <= acc_next;
                        rom_addr <= rom_addr + 1;
                    end else if (is_comma) begin
                        coord_x <= acc;
                        acc <= 0;
                        rom_addr <= rom_addr + 1;
                        state <= S_PARSE_Y;
                    end else if (is_eof) begin
                        state <= S_DONE; // don't save current partially parsed point
                    end else begin
                        rom_addr <= rom_addr + 1;
                    end
                end


                S_PARSE_Y: begin
                    if (is_digit) begin
                        acc <= acc_next;
                        rom_addr <= rom_addr + 1;
                    end else if (is_comma) begin
                        coord_y <= acc;
                        acc <= 0;
                        rom_addr <= rom_addr + 1;
                        state <= S_PARSE_Z;
                    end else if (is_eof) begin
                        state <= S_DONE; // don't save current partially parsed point
                    end else begin
                        rom_addr <= rom_addr + 1;
                    end
                end


                S_PARSE_Z: begin
                    if (is_digit) begin
                        acc <= acc_next;
                        rom_addr <= rom_addr + 1;
                    end else if (is_newline || is_eof) begin
                        coord_z <= acc;
                        state <= S_STORE;
                    end else begin
                        rom_addr <= rom_addr + 1;
                    end
                end


                S_STORE: begin
                    // write current coordinate to RAM:
                    node_we <= 1;
                    node_w_data <= {coord_x, coord_y, coord_z};
                    node_w_addr <= num_nodes;
                    num_nodes <= num_nodes + 1;
                    acc <= 0;

                    if (is_eof || num_nodes >= MAX_NODES - 1) begin
                        state <= S_DONE;
                    end else begin
                        rom_addr <= rom_addr + 1;
                        state <= S_READ_CHAR;
                    end
                end


                S_DONE: begin
                    done <= 1;
                end
            endcase
        end
    end

endmodule


/*
Generates edges between all node pairs and filters them to keep
    only the smallest edges that will fit in the RAM buffer

Reads from Node RAM (each entry is (x,y,z) tuples) and writes 
    into Edge RAM, where each entry is (dist, u, v) tuples

Uses a "histogram"-like pass to estimate distance distribution and
    set a threshold, ensuring only the smallest MAX_EDGES edges
    are put into edge RAM.
*/
module edge_generator #(
    parameter MAX_NODES = 1024,
    parameter NODE_ADDR_BITS = 10,
    parameter COORD_WIDTH = 32,
    parameter MAX_EDGES = 8192,
    parameter EDGE_ADDR_BITS = 13,
    parameter EDGE_WIDTH = 64,
    parameter NUM_BUCKETS = 16
) (
    input wire clk,
    input wire rst,
    input wire start,
    input wire [NODE_ADDR_BITS-1:0] num_nodes,

    // node RAM read interface (2 port):
    input wire [COORD_WIDTH*3-1:0] node_r_data_a, // packed coordinate tuples (x,y,z), read from ram
    input wire [COORD_WIDTH*3-1:0] node_r_data_b,
    output reg [NODE_ADDR_BITS-1:0] node_r_addr_a, // indices to req data from ram
    output reg [NODE_ADDR_BITS-1:0] node_r_addr_b,

    // edge ran write interface:
    output reg edge_we,
    output reg [EDGE_ADDR_BITS-1:0] edge_w_addr,
    output reg [EDGE_WIDTH-1:0] edge_w_data,

    // output signals:
    output reg [EDGE_ADDR_BITS:0] num_edges,
    output reg done
);
    // FSM states:
    localparam S_IDLE = 0;
    localparam S_HISTOGRAM = 1;
    localparam S_THRESHOLD = 2;
    localparam S_COLLECT = 3;
    localparam S_DONE = 4;
    reg [2:0] state;

    // pairwise iter indices:
    reg [NODE_ADDR_BITS-1:0] idx_i;
    reg [NODE_ADDR_BITS-1:0] idx_j;
    // iter helpers:
    wire last_j = (idx_j >= num_nodes - 1);
    wire last_pair = (idx_i >= num_nodes - 2) && last_j;

    // pipeline registers: 5 stages to minimise logic depth
    reg [NODE_ADDR_BITS-1:0] pipe_i [0:4];
    reg [NODE_ADDR_BITS-1:0] pipe_j [0:4];
    reg pipe_valid [0:4];

    // extract coordinates from node data (stage 1)
    wire [COORD_WIDTH-1:0] x_a = node_r_data_a[COORD_WIDTH*3-1:COORD_WIDTH*2];
    wire [COORD_WIDTH-1:0] y_a = node_r_data_a[COORD_WIDTH*2-1:COORD_WIDTH];
    wire [COORD_WIDTH-1:0] z_a = node_r_data_a[COORD_WIDTH-1:0];
    wire [COORD_WIDTH-1:0] x_b = node_r_data_b[COORD_WIDTH*3-1:COORD_WIDTH*2];
    wire [COORD_WIDTH-1:0] y_b = node_r_data_b[COORD_WIDTH*2-1:COORD_WIDTH];
    wire [COORD_WIDTH-1:0] z_b = node_r_data_b[COORD_WIDTH-1:0];

    // compute delltas per coordinate dimension (stage 2)
    reg signed [COORD_WIDTH:0] dx;
    reg signed [COORD_WIDTH:0] dy;
    reg signed [COORD_WIDTH:0] dz;

    // squares delta values (stage 3)
    reg [COORD_WIDTH*2-1:0] dx2;
    reg [COORD_WIDTH*2-1:0] dy2;
    reg [COORD_WIDTH*2-1:0] dz2;

    // sum squares (stage 4):
    reg [COORD_WIDTH*2+1:0] dist_sq;

    // histogram buckets
    // bucket[k] == count of number of edges that are less than (BUCKET_BASE << k)
    localparam [COORD_WIDTH*2+1:0] BUCKET_BASE = 64'd250000; // this limit is chosen based on data distribution of the input coords. for this puzzle 250k works well
    reg [19:0] bucket_counts [0:NUM_BUCKETS-1];
    reg [3:0] bucket_idx;
    reg [COORD_WIDTH*2+1:0] threshold;

    integer k;

    always @(posedge clk) begin
        if (rst) begin
            state <= S_IDLE;
            idx_i <= 0;
            idx_j <= 0;
            num_edges <= 0;
            edge_we <= 0;
            done <= 0;
            threshold <= {(COORD_WIDTH*2+2){1'b1}};
            for (k=0; k<NUM_BUCKETS; k=k+1) begin
                bucket_counts[k] <= 0;
            end
            for (k=0; k<5; k=k+1) begin
                pipe_valid[k] <= 0;
            end
        end else begin
            edge_we <= 0;

            case (state)
                S_IDLE: begin
                    if (start) begin
                        state <= S_HISTOGRAM;
                        idx_i <= 0;
                        idx_j <= 1;
                        num_edges <= 0;
                        done <= 0;
                        for (k=0; k<NUM_BUCKETS; k=k+1) begin
                            bucket_counts[k] <= 0;
                        end
                        for (k=0; k<5; k=k+1) begin
                            pipe_valid[k] <= 0;
                        end
                    end
                end


                S_HISTOGRAM: begin
                    // stage 1: read from node ram:
                    node_r_addr_a <= idx_i;
                    node_r_addr_b <= idx_j;
                    pipe_valid[0] <= 1;
                    pipe_i[0] <= idx_i;
                    pipe_j[0] <= idx_j;

                    // shift pipeline:
                    for (k=0; k<4; k=k+1) begin
                        pipe_valid[k+1] <= pipe_valid[k];
                        pipe_i[k+1] <= pipe_i[k];
                        pipe_j[k+1] <= pipe_j[k];
                    end


                    // stage 2: compute deltas:
                    if (pipe_valid[1]) begin
                        dx <= $signed({1'b0, x_a}) - $signed({1'b0, x_b});
                        dy <= $signed({1'b0, y_a}) - $signed({1'b0, y_b});
                        dz <= $signed({1'b0, z_a}) - $signed({1'b0, z_b});
                    end

                    // stage 3: square:
                    if (pipe_valid[2]) begin
                        dx2 <= $unsigned($signed({{31{dx[COORD_WIDTH]}}, dx}) * $signed({{31{dx[COORD_WIDTH]}}, dx}));
                        dy2 <= $unsigned($signed({{31{dy[COORD_WIDTH]}}, dy}) * $signed({{31{dy[COORD_WIDTH]}}, dy}));
                        dz2 <= $unsigned($signed({{31{dz[COORD_WIDTH]}}, dz}) * $signed({{31{dz[COORD_WIDTH]}}, dz}));
                    end

                    // stage 4: sum squares:
                    if (pipe_valid[3]) begin
                        dist_sq <= dx2 + dy2 + dz2;
                    end

                    // stage 5: update bucket counts:
                    if (pipe_valid[4]) begin
                        for (k=0; k<NUM_BUCKETS; k=k+1) begin
                            if (dist_sq < (BUCKET_BASE << k)) begin
                                bucket_counts[k] <= bucket_counts[k] + 1;
                            end
                        end
                    end

                    // if final pair, move to next state:
                    if (last_pair) begin
                        pipe_valid[0] <= 0;
                        // flush pipeline -> do nothing until entire pipeline is invalid
                        if (!pipe_valid[0] && !pipe_valid[1] && !pipe_valid[2] && !pipe_valid[3] && !pipe_valid[4]) begin
                            state <= S_THRESHOLD;
                            bucket_idx <= 0;
                        end
                    end else if (last_j) begin
                        idx_i <= idx_i + 1;
                        idx_j <= idx_i + 2;
                    end else begin
                        idx_j <= idx_j + 1;
                    end
                end


                S_THRESHOLD: begin
                    // find the smallest bucket that fills at least half of the buffer:
                    if (bucket_counts[bucket_idx] >= (MAX_EDGES>>1) || bucket_idx == NUM_BUCKETS-1) begin
                        $display("Info: bucket %0d chosen!", bucket_idx);
                        threshold <= BUCKET_BASE << bucket_idx;
                        state <= S_COLLECT;
                        idx_i <= 0;
                        idx_j <= 1;
                        for (k=0; k<5; k=k+1) begin
                            pipe_valid[k] <= 0;
                        end
                    end else begin
                        bucket_idx <= bucket_idx + 1;
                    end
                end


                S_COLLECT: begin
                    // stage 0: read nodes:
                    node_r_addr_a <= idx_i;
                    node_r_addr_b <= idx_j;
                    pipe_valid[0] <= 1;
                    pipe_i[0] <= idx_i;
                    pipe_j[0] <= idx_j;

                    // shift pipeline:
                    for (k=0; k<4; k=k+1) begin
                        pipe_valid[k+1] <= pipe_valid[k];
                        pipe_i[k+1] <= pipe_i[k];
                        pipe_j[k+1] <= pipe_j[k];
                    end


                    // stage 2: compute deltas:
                    if (pipe_valid[1]) begin
                        dx <= $signed({1'b0, x_a}) - $signed({1'b0, x_b});
                        dy <= $signed({1'b0, y_a}) - $signed({1'b0, y_b});
                        dz <= $signed({1'b0, z_a}) - $signed({1'b0, z_b});
                    end

                    // stage 3: square:
                    if (pipe_valid[2]) begin
                        dx2 <= $unsigned($signed({{31{dx[COORD_WIDTH]}}, dx}) * $signed({{31{dx[COORD_WIDTH]}}, dx}));
                        dy2 <= $unsigned($signed({{31{dy[COORD_WIDTH]}}, dy}) * $signed({{31{dy[COORD_WIDTH]}}, dy}));
                        dz2 <= $unsigned($signed({{31{dz[COORD_WIDTH]}}, dz}) * $signed({{31{dz[COORD_WIDTH]}}, dz}));
                    end

                    // stage 4: sum squares:
                    if (pipe_valid[3]) begin
                        dist_sq <= dx2 + dy2 + dz2;
                    end

                    // stage 5: filter if below threshold and store: **** this is the only difference between S_HISTORGAM and S_COLLECT 
                    if (pipe_valid[4]) begin
                        if (dist_sq < threshold && num_edges < MAX_EDGES) begin
                            edge_we <= 1;
                            edge_w_addr <= num_edges[EDGE_ADDR_BITS-1:0];
                            edge_w_data <= {(dist_sq > 32'hFFFFFFFF ? 32'hFFFFFFFF : dist_sq[31:0]), 
                                            {(16-NODE_ADDR_BITS){1'b0}}, pipe_i[4],
                                            {(16-NODE_ADDR_BITS){1'b0}}, pipe_j[4]};
                            num_edges <= num_edges + 1;
                        end else if (num_edges >= MAX_EDGES) begin
                            $display("WARNING: Not all edges below threshold were selected!");
                        end
                    end

                    // advance indices:
                    if (last_pair) begin
                        // flush pipeline:
                        pipe_valid[0] <= 0;
                        if (!pipe_valid[0] &&!pipe_valid[1] && !pipe_valid[2] && !pipe_valid[3] && !pipe_valid[4]) begin
                            state <= S_DONE;
                        end
                    end else if (last_j) begin
                        idx_i <= idx_i + 1;
                        idx_j <= idx_i + 2;
                    end else begin
                        idx_j <= idx_j + 1;
                    end
                end


                S_DONE: begin
                    done <= 1;
                end
            endcase
        end
    end

endmodule

// at some point I started calling them nodes rather than coords and it kind of stuck, I'm too deep in now to be bothered switching
module dsu #(
    parameter MAX_NODES = 1024,
    parameter NODE_ADDR_BITS = 10,
    parameter MAX_EDGES = 8192,
    parameter EDGE_ADDR_BITS = 13,
    parameter EDGE_WIDTH = 64,
    parameter COORD_WIDTH = 32,
    parameter PART1_EDGES = 1000 // number of edges to process for part 1
) (
    input wire clk,
    input wire rst,
    input wire start,

    // info about inputs:
    input wire [NODE_ADDR_BITS-1:0] num_nodes,
    input wire [EDGE_ADDR_BITS:0] num_edges,

    // edge ram read interface
    input wire [EDGE_WIDTH-1:0] edge_r_data,
    output reg [EDGE_ADDR_BITS-1:0] edge_r_addr,

    // node ram read interface:
    input wire [COORD_WIDTH*3-1:0] node_r_data,
    output reg [NODE_ADDR_BITS-1:0] node_r_addr,

    // parent ram rw interface (for the dsu algorithm)
    input wire [NODE_ADDR_BITS-1:0] parent_r_data,
    output reg parent_we,
    output reg [NODE_ADDR_BITS-1:0] parent_r_addr,
    output reg [NODE_ADDR_BITS-1:0] parent_w_addr,
    output reg [NODE_ADDR_BITS-1:0] parent_w_data,

    // size ram interface (for dsu algorithm)
    input wire [15:0] size_r_data, // assuming always 16 bit for size ram width
    output reg size_we,
    output reg [NODE_ADDR_BITS-1:0] size_r_addr,
    output reg [NODE_ADDR_BITS-1:0] size_w_addr,
    output reg [15:0] size_w_data,

    // output values and signals
    output reg [63:0] part1_result,
    output reg [63:0] part2_result,
    output reg done
);
    // define states:
    localparam S_IDLE = 0;
    localparam S_INIT = 1;
    // get next edge e = (U,V) from edge ram:
    localparam S_READ_EDGE = 2;
    localparam S_WAIT_EDGE = 3;
    localparam S_FIND_U_ISSUE = 4; // extract results from reading edge ram

    // perform find(u) operation to find root node of tree with u in it
    localparam S_FIND_U_WAIT = 5;
    localparam S_FIND_U_CHECK = 6;

    // perform find(v) operation to find root node of tree with v in it
    localparam S_FIND_V_WAIT = 7;
    localparam S_FIND_V_CHECK = 8;

    // get sizes of each tree
    localparam S_READ_SIZES = 9;
    localparam S_WAIT_SIZES = 10; // get size of U tree
    localparam S_WAIT_SIZES_V = 11; // get size of V tree

    // perform union(u,v), provided not in the same tree. use union by size heuristic
    localparam S_UNION = 12;

    // find top 3 components by iterating over sizes ram after PART1_EDGES edges have been processed
    localparam S_SCAN_ISSUE = 13;
    localparam S_SCAN_WAIT = 14;
    localparam S_SCAN_CHECK = 15;
    localparam S_COMPUTE_P1 = 16;

    // get x coords (part 2)
    localparam S_FETCH_X1 = 17;
    localparam S_WAIT_X1 = 18;
    localparam S_FETCH_X2 = 19;
    localparam S_WAIT_X2 = 20;
    localparam S_COMPUTE_P2 = 21;
    localparam S_DONE = 22;
    reg [4:0] state;

    // variables for edge processing:
    reg [EDGE_ADDR_BITS:0] edge_idx;
    reg [NODE_ADDR_BITS-1:0] edge_u;
    reg [NODE_ADDR_BITS-1:0] edge_v;

    // find operation:
    reg [NODE_ADDR_BITS-1:0] find_node;
    reg [NODE_ADDR_BITS-1:0] root_u;
    reg [NODE_ADDR_BITS-1:0] root_v;
    reg [15:0] size_u;
    reg [15:0] size_v;

    // component tracking:
    reg [NODE_ADDR_BITS-1:0] num_components;
    reg part1_done;
    reg [NODE_ADDR_BITS-1:0] last_u; // final edge nodes (part 2)
    reg [NODE_ADDR_BITS-1:0] last_v; // final edge nodes (part 2)

    // top 3 component sizes (part 1):
    reg [15:0] top1;
    reg [15:0] top2;
    reg [15:0] top3;
    reg [NODE_ADDR_BITS-1:0] scan_idx;
    reg [NODE_ADDR_BITS-1:0] scan_prev_idx; // for comparison

    // x coord fetching
    reg [COORD_WIDTH-1:0] x_u;
    reg [COORD_WIDTH-1:0] x_v;

    // initialisation counter index:
    reg [NODE_ADDR_BITS-1:0] init_idx;

    // extract edge fields: 32-bits for weight, followed by 2x 16-bits for index of U and V within node ram:
    wire [NODE_ADDR_BITS-1:0] edge_u_in = edge_r_data[16+NODE_ADDR_BITS-1:16];
    wire [NODE_ADDR_BITS-1:0] edge_v_in = edge_r_data[NODE_ADDR_BITS-1:0];

    // extract x coordinate from node data:
    wire [COORD_WIDTH-1:0] node_x = node_r_data[COORD_WIDTH*3-1:COORD_WIDTH*2];

    // pray for me:
    always @(posedge clk) begin
        if (rst) begin
            state <= S_IDLE;
            parent_we <= 0;
            size_we <= 0;
            done <= 0;
            part1_done <= 0;
            part1_result <= 0;
            part2_result <= 0;
            edge_idx <= 0;
            init_idx <= 0;
            num_components <= 0;
        end else begin
            parent_we <= 0;
            size_we <= 0;
            case (state) 
                S_IDLE: begin
                    if (start) begin
                        state <= S_INIT;
                        init_idx <= 0;
                        num_components <= num_nodes;
                        done <= 0;
                        part1_done <= 0;
                        part1_result <= 0;
                        part2_result <= 0;
                        edge_idx <= 0;
                        top1 <= 0;
                        top2 <= 0;
                        top3 <= 0;
                    end
                end


                S_INIT: begin
                    // set parent array so that every node is its own parent (initially the forest in kruskals is completely disconnected)
                    parent_we <= 1;
                    parent_w_addr <= init_idx;
                    parent_w_data <= init_idx;

                    size_we <= 1;
                    size_w_addr <= init_idx;
                    size_w_data <= 1;

                    if (init_idx >= num_nodes - 1) begin
                        state <= S_READ_EDGE;
                    end else begin
                        init_idx <= init_idx + 1;
                    end
                end


                S_READ_EDGE: begin
                    if (edge_idx >= num_edges) begin
                        // finished processing all edges:
                        if (!part1_done) begin
                            state <= S_SCAN_ISSUE;
                            scan_idx <= 0;
                        end else begin
                            state <= S_DONE;
                        end
                    end else if (part1_done && num_components <= 1) begin
                        state <= S_DONE;
                    end else begin
                        edge_r_addr <= edge_idx;
                        state <= S_WAIT_EDGE;
                    end
                end


                S_WAIT_EDGE: begin
                    // wait for data to be read from edge ram:
                    state <= S_FIND_U_ISSUE;
                end


                S_FIND_U_ISSUE: begin
                    edge_u <= edge_r_data[31:16];
                    edge_v <= edge_r_data[15:0];
                    find_node <= edge_r_data[31:16];
                    parent_r_addr <= edge_r_data[31:16];
                    state <= S_FIND_U_WAIT;
                end


                S_FIND_U_WAIT: begin
                    // wait for parent ram reading:
                    state <= S_FIND_U_CHECK;
                end


                S_FIND_U_CHECK: begin
                    if (parent_r_data == find_node) begin
                        // found the root of the tree with U in it:
                        root_u <= find_node;

                        // begin next find operation:
                        find_node <= edge_v; 
                        parent_r_addr <= edge_v;
                        state <= S_FIND_V_WAIT;
                    end else begin
                        // continue traversing up the tree:
                        find_node <= parent_r_data;
                        parent_r_addr <= parent_r_data;
                        state <= S_FIND_U_WAIT;
                    end
                end


                S_FIND_V_WAIT: begin
                    // 1 cycle waiting for parent ram read:
                    state <= S_FIND_V_CHECK;
                end


                S_FIND_V_CHECK: begin
                    if (parent_r_data == find_node) begin
                        // found the root of the tree with V in it:
                        root_v <= find_node;

                        // find sizes of both root/trees:
                        size_r_addr <= root_u;
                        state <= S_READ_SIZES;
                    end else begin
                        // continue traversing up the tree:
                        find_node <= parent_r_data;
                        parent_r_addr <= parent_r_data;
                        state <= S_FIND_V_WAIT;
                    end
                end


                S_READ_SIZES: begin
                    // cycle to allow read from ram:
                    state <= S_WAIT_SIZES;
                end


                S_WAIT_SIZES: begin
                    // store size of root(u) then find size of root(v)
                    size_u <= size_r_data;
                    size_r_addr <= root_v;
                    state <= S_WAIT_SIZES_V;
                end


                S_WAIT_SIZES_V: begin
                    // cycle to allow read from sizes ram
                    state <= S_UNION;
                end


                S_UNION: begin
                    size_v <= size_r_data;

                    if (root_u != root_v) begin
                        // union by size -> smaller tree becomes child of larger tree
                        if (size_u >= size_r_data) begin // have to use size_r_data since size(V) not latched yet at this state
                            parent_we <= 1;
                            parent_w_addr <= root_v;
                            parent_w_data <= root_u;

                            size_we <= 1;
                            size_w_addr <= root_u;
                            size_w_data <= size_u + size_r_data;
                        end else begin 
                            parent_we <= 1;
                            parent_w_addr <= root_u;
                            parent_w_data <= root_v;

                            size_we <= 1;
                            size_w_addr <= root_v;
                            size_w_data <= size_u + size_r_data;
                        end

                        num_components <= num_components - 1;
                        last_u <= edge_u;
                        last_v <= edge_v;
                    end

                    // move to next edge:
                    edge_idx <= edge_idx + 1;

                    // check part 1 threshold or part 2 completion
                    if (edge_idx + 1 >= PART1_EDGES && !part1_done) begin
                        state <= S_SCAN_ISSUE;
                        scan_idx <= 0;
                    end else if (part1_done && (root_u != root_v) && (num_components <= 2)) begin
                        // this union makes a single component -> get the X coords:
                        state <= S_FETCH_X1;
                        node_r_addr <= edge_u;
                    end else begin
                        state <= S_READ_EDGE;
                    end
                end


                S_SCAN_ISSUE: begin
                    parent_r_addr <= scan_idx;
                    size_r_addr <= scan_idx;
                    scan_prev_idx <= scan_idx;
                    state <= S_SCAN_WAIT;
                end


                S_SCAN_WAIT: begin
                    // wait for parent/size ram read
                    state <= S_SCAN_CHECK;
                end


                S_SCAN_CHECK: begin
                    // parent_r_data is for scan_prev_idx
                    if (parent_r_data == scan_prev_idx) begin
                        // track top 3 components:
                        if (size_r_data > top1) begin
                            top3 <= top2;
                            top2 <= top1;
                            top1 <= size_r_data;
                        end else if (size_r_data > top2) begin
                            top3 <= top2;
                            top2 <= size_r_data;
                        end else if (size_r_data > top3) begin
                            top3 <= size_r_data;
                        end
                    end

                    scan_idx <= scan_idx+1;

                    if (scan_idx >= num_nodes) begin
                        state <= S_COMPUTE_P1;
                    end else begin
                        state <= S_SCAN_ISSUE;
                    end
                end


                S_COMPUTE_P1: begin
                    part1_result <= top1 * top2 * top3;
                    part1_done <= 1;

                    if (num_components > 1) begin
                        // continue performing unions:
                        state <= S_READ_EDGE;
                    end else begin
                        // if already connected, then just compute P2 result:
                        state <= S_FETCH_X1;
                        node_r_addr <= last_u;
                    end
                end


                S_FETCH_X1: begin
                    state <= S_WAIT_X1;
                end


                S_WAIT_X1: begin
                    x_u <= node_x;
                    node_r_addr <= last_v;
                    state <= S_FETCH_X2;
                end


                S_FETCH_X2: begin
                    state <= S_WAIT_X2;
                end


                S_WAIT_X2: begin
                    x_v <= node_x;
                    state <= S_COMPUTE_P2;
                end


                S_COMPUTE_P2: begin
                    part2_result <= x_u * x_v;
                    state <= S_DONE;
                end


                S_DONE: begin
                    done <= 1;
                end
            endcase
        end
    end
endmodule

