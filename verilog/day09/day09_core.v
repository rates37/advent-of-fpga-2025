module day09_core #(
    parameter N_ADDR_BITS = 16,
    parameter LOG_MAX_POINTS = 9,
    parameter LOG_MAX_POINT_VAL = 17,
    parameter SEGS_PER_STAGE = 32,
    parameter LOG_SEGS = 5
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

    localparam MAX_POINTS = (1<<LOG_MAX_POINTS);
    localparam NUM_STAGES = MAX_POINTS / SEGS_PER_STAGE;
    localparam LOG_STAGES = LOG_MAX_POINTS - LOG_SEGS;

    // fsm:
    localparam S_IDLE = 0;
    localparam S_READ = 1;
    localparam S_BUILD_SEGMENTS = 2;
    localparam S_LOAD_SEGMENTS = 3;
    localparam S_LOAD_WAIT = 4;
    localparam S_LOAD_READ = 5;
    localparam S_LOAD_COMMIT = 6;
    localparam S_PART1 = 7;
    localparam S_PART1_READ = 8;
    localparam S_PART1_COMPUTE = 9;
    localparam S_PART2_WAIT = 10;
    localparam S_DONE = 11;
    reg [3:0] state;

    // point storage:
    reg [LOG_MAX_POINTS:0] point_count;
    reg ram_we_a;
    reg [LOG_MAX_POINTS:0] ram_addr_a;
    reg [LOG_MAX_POINTS:0] ram_addr_b;
    reg [LOG_MAX_POINT_VAL:0] ram_w_data_x;
    reg [LOG_MAX_POINT_VAL:0] ram_w_data_y;
    wire [LOG_MAX_POINT_VAL:0] ram_r_data_x_a;
    wire [LOG_MAX_POINT_VAL:0] ram_r_data_y_a;
    wire [LOG_MAX_POINT_VAL:0] ram_r_data_x_b;
    wire [LOG_MAX_POINT_VAL:0] ram_r_data_y_b;

    ram_dp #(
        .WIDTH(LOG_MAX_POINT_VAL+1),
        .DEPTH(MAX_POINTS),
        .ADDR_BITS(LOG_MAX_POINTS+1)
    ) point_x_ram (
        .clk(clk),
        .rst(rst),
        .we_a(ram_we_a), 
        .addr_a(ram_addr_a), 
        .w_data_a(ram_w_data_x), 
        .r_data_a(ram_r_data_x_a),
        .we_b(1'b0), 
        .addr_b(ram_addr_b), 
        .w_data_b({(LOG_MAX_POINT_VAL+1){1'b0}}), 
        .r_data_b(ram_r_data_x_b)
    );

    ram_dp #(
        .WIDTH(LOG_MAX_POINT_VAL+1),
        .DEPTH(MAX_POINTS),
        .ADDR_BITS(LOG_MAX_POINTS+1)
    ) point_y_ram (
        .clk(clk),
        .rst(rst),
        .we_a(ram_we_a), 
        .addr_a(ram_addr_a), 
        .w_data_a(ram_w_data_y), 
        .r_data_a(ram_r_data_y_a),
        .we_b(1'b0), 
        .addr_b({ram_addr_b}), 
        .w_data_b({(LOG_MAX_POINT_VAL+1){1'b0}}), 
        .r_data_b(ram_r_data_y_b)
    );
    
    // parsing:
    reg [LOG_MAX_POINT_VAL:0] parse_x;
    reg [LOG_MAX_POINT_VAL:0] parse_y;
    reg parsing_first;
    reg [LOG_MAX_POINTS:0] parse_idx;

    // part 1 calc variables:
    reg [LOG_MAX_POINT_VAL:0] p1_x1;
    reg [LOG_MAX_POINT_VAL:0] p1_y1;
    reg [LOG_MAX_POINT_VAL:0] p1_x2;
    reg [LOG_MAX_POINT_VAL:0] p1_y2;
    reg [LOG_MAX_POINT_VAL:0] p1_dx;
    reg [LOG_MAX_POINT_VAL:0] p1_dy;
    reg [63:0] p1_area;

    // loop counters
    reg [LOG_MAX_POINTS:0] pipe_i;
    reg [LOG_MAX_POINTS:0] pipe_j;
    reg [LOG_MAX_POINTS:0] load_idx;
    reg [LOG_STAGES:0] load_stage_idx;

    // segment loading:
    reg stage_load_en [0:NUM_STAGES-1];
    reg [LOG_MAX_POINT_VAL:0] seg_load_x1;
    reg [LOG_MAX_POINT_VAL:0] seg_load_y1;
    reg [LOG_MAX_POINT_VAL:0] seg_load_x2;
    reg [LOG_MAX_POINT_VAL:0] seg_load_y2;
    reg seg_load_active;

    // pipeline inter-stage signals:
    wire [LOG_SEGS:0] stage_seg_count [0:NUM_STAGES-1];
    wire stage_in_ready [0:NUM_STAGES-1];
    wire stage_out_valid [0:NUM_STAGES-1];
    reg first_in_valid;
    wire [LOG_MAX_POINT_VAL:0] stage_minX [0:NUM_STAGES];
    wire [LOG_MAX_POINT_VAL:0] stage_minY [0:NUM_STAGES];
    wire [LOG_MAX_POINT_VAL:0] stage_maxX [0:NUM_STAGES];
    wire [LOG_MAX_POINT_VAL:0] stage_maxY [0:NUM_STAGES];
    wire [63:0] stage_area [0:NUM_STAGES];
    wire stage_cut [0:NUM_STAGES];
    wire [LOG_MAX_POINTS:0] stage_hits [0:NUM_STAGES];
    wire stage_data_valid [0:NUM_STAGES];

    // feed computation for first (input) stage
    wire [LOG_MAX_POINT_VAL:0] feed_x1 = ram_r_data_x_a;
    wire [LOG_MAX_POINT_VAL:0] feed_x2 = ram_r_data_x_b;
    wire [LOG_MAX_POINT_VAL:0] feed_y1 = ram_r_data_y_a;
    wire [LOG_MAX_POINT_VAL:0] feed_y2 = ram_r_data_y_b;
    wire [LOG_MAX_POINT_VAL:0] feed_minX = (feed_x1 < feed_x2) ? feed_x1 : feed_x2;
    wire [LOG_MAX_POINT_VAL:0] feed_maxX = (feed_x1 > feed_x2) ? feed_x1 : feed_x2;
    wire [LOG_MAX_POINT_VAL:0] feed_minY = (feed_y1 < feed_y2) ? feed_y1 : feed_y2;
    wire [LOG_MAX_POINT_VAL:0] feed_maxY = (feed_y1 > feed_y2) ? feed_y1 : feed_y2;
    wire [LOG_MAX_POINT_VAL:0] feed_w = feed_maxX - feed_minX + 1;
    wire [LOG_MAX_POINT_VAL:0] feed_h = feed_maxY - feed_minY + 1;
    wire [63:0] feed_area = feed_w * feed_h;

    // first stage input:
    reg pipe_in_valid;
    assign stage_minX[0] = feed_minX;
    assign stage_minY[0] = feed_minY;
    assign stage_maxX[0] = feed_maxX;
    assign stage_maxY[0] = feed_maxY;
    assign stage_area[0] = feed_area;
    assign stage_cut[0] = 0;
    assign stage_hits[0] = 0;
    assign stage_data_valid[0] = (state == S_PART1_COMPUTE && pipe_i < point_count);

    // tracking number of rectangles sent
    reg [31:0] rectangles_sent;
    reg [31:0] rectangles_received;

    // create pipeline stages:
    genvar g;
    generate
        for (g=0; g<NUM_STAGES; g=g+1) begin : pipe_stages
            wire next_out_ready;
            if (g == NUM_STAGES - 1) begin
                assign next_out_ready = 1'b1;
            end else begin
                assign next_out_ready = stage_in_ready[g + 1];
            end

            wire this_in_valid;
            if (g == 0) begin
                assign this_in_valid = first_in_valid;
            end else begin
                assign this_in_valid = stage_out_valid[g - 1];
            end

            pipeline_stage #(
                .LOG_MAX_POINT_VAL(LOG_MAX_POINT_VAL),
                .LOG_MAX_POINTS(LOG_MAX_POINTS),
                .SEGS_PER_STAGE(SEGS_PER_STAGE),
                .LOG_SEGS(LOG_SEGS)
            ) stage_inst (
                .clk(clk),
                .rst(rst),
                
                // Segment loading
                .load_en(stage_load_en[g]),
                .seg_load_x1(seg_load_x1),
                .seg_load_y1(seg_load_y1),
                .seg_load_x2(seg_load_x2),
                .seg_load_y2(seg_load_y2),
                .seg_load_active(seg_load_active),
                .seg_count(stage_seg_count[g]),
                
                // Input comms signals:
                .in_ready(stage_in_ready[g]),
                .in_valid(this_in_valid),
                .in_minX(stage_minX[g]),
                .in_minY(stage_minY[g]),
                .in_maxX(stage_maxX[g]),
                .in_maxY(stage_maxY[g]),
                .in_area(stage_area[g]),
                .in_cut_detected(stage_cut[g]),
                .in_hit_count(stage_hits[g]),
                .in_data_valid(stage_data_valid[g]),
                
                // Output comms signals:
                .out_ready(next_out_ready),
                .out_valid(stage_out_valid[g]),
                .out_minX(stage_minX[g+1]),
                .out_minY(stage_minY[g+1]),
                .out_maxX(stage_maxX[g+1]),
                .out_maxY(stage_maxY[g+1]),
                .out_area(stage_area[g+1]),
                .out_cut_detected(stage_cut[g+1]),
                .out_hit_count(stage_hits[g+1]),
                .out_data_valid(stage_data_valid[g+1])
            );
        end
    endgenerate

    integer k;
    always @(posedge clk) begin
        // defaults:
        ram_we_a <= 0;
        ram_w_data_x <= 0;
        ram_w_data_y <= 0;
        if (rst) begin
            state <= S_IDLE;
            rom_addr <= 0;
            done <= 0;
            part1_result <= 0;
            part2_result <= 0;
            point_count <= 0;
            parse_idx <= 0;
            parsing_first <= 1;
            parse_x <= 0;
            parse_y <= 0;
            pipe_i <= 0;
            pipe_j <= 0;
            load_idx <= 0;
            load_stage_idx <= 0;
            pipe_in_valid <= 0;
            rectangles_sent <= 0;
            rectangles_received <= 0;
            seg_load_x1 <= 0;
            seg_load_x2 <= 0;
            seg_load_y1 <= 0;
            seg_load_y2 <= 0;
            seg_load_active <= 0;
            for (k=0; k<NUM_STAGES; k=k+1) begin
                stage_load_en[k] <= 0;
            end
            first_in_valid <= 0;
            ram_addr_a <= 0;
            ram_addr_b <= 0;
        end else begin
            // clear load enables:
            for (k=0; k<NUM_STAGES; k=k+1) begin
                stage_load_en[k] <= 0;
            end

            // check final stage output for part 2 result accumulation:
            if (stage_out_valid[NUM_STAGES-1] && stage_data_valid[NUM_STAGES]) begin
                rectangles_received <= rectangles_received + 1; // track to know when pipeline is finished
                if (!stage_cut[NUM_STAGES] && (stage_hits[NUM_STAGES][0] == 1)) begin
                    if (stage_area[NUM_STAGES] > part2_result) begin
                        part2_result <= stage_area[NUM_STAGES];
                        $display("DEBUG: Part2 Update Area=%0d | Corners: (%0d,%0d) - (%0d,%0d)", stage_area[NUM_STAGES], stage_minX[NUM_STAGES], stage_minY[NUM_STAGES], stage_maxX[NUM_STAGES], stage_maxY[NUM_STAGES]);
                    end
                end
            end

            // input handshake
            if (first_in_valid && stage_in_ready[0]) begin
                first_in_valid <= 0;
            end

            case (state)
                S_IDLE: begin
                    state <= S_READ;
                    rom_addr <= 0;
                end


                S_READ: begin
                    if (rom_data == "\n" || (rom_addr > 0 && rom_data == 0)) begin
                        if (rom_data == "\n" || rom_data == 0) begin
                            if (!parsing_first) begin
                                // Write to RAM
                                ram_we_a <= 1;
                                ram_addr_a <= parse_idx;
                                ram_w_data_x <= parse_x;
                                ram_w_data_y <= parse_y;
                                
                                parse_idx <= parse_idx + 1;
                                parsing_first <= 1;
                                parse_x <= 0;
                                parse_y <= 0;
                            end

                            if (rom_data == 0) begin
                                state <= S_BUILD_SEGMENTS;
                                point_count <= parse_idx;
                            end
                        end
                        rom_addr <= rom_addr + 1;
                    end else if (rom_data == ",") begin
                        parsing_first <= 0;
                        rom_addr <= rom_addr + 1;
                    end else if (rom_data >= "0" && rom_data <= "9") begin
                        if (parsing_first) begin
                            parse_x <= (parse_x<<3) + (parse_x<<1) + (rom_data[3:0]);
                        end else begin
                            parse_y <= (parse_y<<3) + (parse_y<<1) + (rom_data[3:0]);
                        end
                        rom_addr <= rom_addr + 1;
                    end else begin
                        rom_addr <= rom_addr + 1;
                    end
                end


                S_BUILD_SEGMENTS: begin
                    load_idx <= 0;
                    load_stage_idx <= 0;
                    state <= S_LOAD_SEGMENTS;
                end


                S_LOAD_SEGMENTS: begin
                    if (load_idx < point_count) begin
                        ram_addr_a <= load_idx;
                        ram_addr_b <= (load_idx == point_count-1) ? 0 : (load_idx+1);
                        state <= S_LOAD_WAIT;
                    end else begin
                        // finished loading pipeline, begin iterating over rectangles
                        state <= S_PART1;
                        pipe_i <= 1;
                        pipe_j <= 0;
                        rectangles_sent <= 0;
                        rectangles_received <= 0;
                        first_in_valid <= 0;
                    end
                end


                S_LOAD_WAIT: begin
                    state <= S_LOAD_READ;
                end


                S_LOAD_READ: begin
                    seg_load_x1 <= ram_r_data_x_a;
                    seg_load_y1 <= ram_r_data_y_a;
                    seg_load_x2 <= ram_r_data_x_b;
                    seg_load_y2 <= ram_r_data_y_b;
                    seg_load_active <= 1;
                    state <= S_LOAD_COMMIT;
                end


                S_LOAD_COMMIT: begin
                    // now that seg_load values are valid/latched, assert load enable
                    stage_load_en[load_stage_idx] <= 1;
                    load_idx <= load_idx + 1;

                    if (load_stage_idx+1 < NUM_STAGES) begin
                        load_stage_idx <= load_stage_idx + 1;
                    end else begin
                        load_stage_idx <= 0;
                    end
                    state <= S_LOAD_SEGMENTS;
                end


                S_PART1: begin
                    if (pipe_i < point_count) begin
                        ram_addr_a <= pipe_i;
                        ram_addr_b <= pipe_j;
                        state <= S_PART1_READ;
                    end else begin
                        // sent all rectangles through pipeline -> wait to flush pipeline
                        first_in_valid <= 0;
                        state <= S_PART2_WAIT;
                    end
                end


                S_PART1_READ: begin
                    state <= S_PART1_COMPUTE;
                end


                S_PART1_COMPUTE: begin
                    // calculate part 1 area:
                    p1_dx = (ram_r_data_x_a > ram_r_data_x_b) ? (ram_r_data_x_a - ram_r_data_x_b) : (ram_r_data_x_b - ram_r_data_x_a);
                    p1_dy = (ram_r_data_y_a > ram_r_data_y_b) ? (ram_r_data_y_a - ram_r_data_y_b) : (ram_r_data_y_b - ram_r_data_y_a);
                    p1_area = (p1_dx + 1) * (p1_dy + 1);
                    if (p1_area > part1_result) begin
                        part1_result <= p1_area;
                    end

                    // sent rectangle to pipeline:
                    if (first_in_valid) begin
                        if (stage_in_ready[0]) begin
                            rectangles_sent <= rectangles_sent + 1;

                            if (pipe_j + 1 < pipe_i) begin
                                pipe_j <= pipe_j + 1;
                            end else begin
                                pipe_j <= 0;
                                pipe_i <= pipe_i + 1;
                            end
                            state <= S_PART1;
                        end
                        ram_addr_a <= pipe_i;
                        ram_addr_b <= pipe_j;
                    end else begin
                        // only send rectangle if it's bigger than the currently largest seen areas
                        if (p1_area > part2_result) begin
                            first_in_valid <= 1;
                            ram_addr_a <= pipe_i;
                            ram_addr_b <= pipe_j;
                        end else begin
                            // area too small, move to next rectangle:
                            if (pipe_j + 1 < pipe_i) begin
                                pipe_j <= pipe_j + 1;
                            end else begin
                                pipe_i <= pipe_i + 1;
                                pipe_j <= 0;
                            end
                            state <= S_PART1;
                        end
                    end
                end


                S_PART2_WAIT: begin
                    if (rectangles_received >= rectangles_sent) begin
                        state <= S_DONE;
                        done <= 1;
                    end
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
