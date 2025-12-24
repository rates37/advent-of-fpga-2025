module day09_core #(
    parameter N_ADDR_BITS = 16,
    parameter LOG_MAX_POINTS = 9, // my puzzle input had 496 lines(points), adjust ass necessary
    // NOTE: if using small inputs - PLEASE LOWER THIS NUMBER, the iverilog simulator does not 
    // optimise it and simulating a pipeline of 512 units will take a while
    parameter LOG_MAX_POINT_VAL = 17 // all my points are under 100k < 2^17
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
    // num points:
    localparam MAX_POINTS = (1<<LOG_MAX_POINTS);

    // FSM states:
    localparam S_IDLE = 0;
    localparam S_READ = 1;
    localparam S_BUILD_SEGMENTS = 2;
    localparam S_PART1 = 3;
    localparam S_PART_2_STREAM = 4;
    localparam S_PART_2_DRAIN = 5;
    localparam S_DONE = 6;
    reg [2:0] state;

    // point memory:
    reg [LOG_MAX_POINTS:0] point_count;
    reg [LOG_MAX_POINT_VAL:0] point_x [0:MAX_POINTS-1];
    reg [LOG_MAX_POINT_VAL:0] point_y [0:MAX_POINTS-1];

    // parsing variables:
    reg [LOG_MAX_POINT_VAL:0] parse_x, parse_y;
    reg parsing_first; // if 1, means parsing X coordinate
    reg [LOG_MAX_POINTS:0] parse_idx;

    // part 1 variables:
    reg [LOG_MAX_POINTS:0] p1_i, p1_j; // iter variables
    reg [LOG_MAX_POINT_VAL:0] p1_x1, p1_y1, p1_x2, p1_y2;
    reg [LOG_MAX_POINT_VAL:0] p1_dx, p1_dy;
    reg [63:0] p1_area;

    // part 2 variables:
    reg [LOG_MAX_POINTS:0] pipe_i, pipe_j;
    reg [LOG_MAX_POINTS:0] drain_count;

    // pipeline stage registers:
    reg [LOG_MAX_POINT_VAL:0] stage_seg_x1      [0:MAX_POINTS-1];
    reg [LOG_MAX_POINT_VAL:0] stage_seg_y1      [0:MAX_POINTS-1];
    reg [LOG_MAX_POINT_VAL:0] stage_seg_x2      [0:MAX_POINTS-1];
    reg [LOG_MAX_POINT_VAL:0] stage_seg_y2      [0:MAX_POINTS-1];
    reg                       stage_active      [0:MAX_POINTS-1];

    // pipeline data registers:
    reg [LOG_MAX_POINT_VAL:0] pipe_rect_x1      [0:MAX_POINTS-1];
    reg [LOG_MAX_POINT_VAL:0] pipe_rect_y1      [0:MAX_POINTS-1];
    reg [LOG_MAX_POINT_VAL:0] pipe_rect_x2      [0:MAX_POINTS-1];
    reg [LOG_MAX_POINT_VAL:0] pipe_rect_y2      [0:MAX_POINTS-1];
    reg [LOG_MAX_POINT_VAL:0] pipe_minX         [0:MAX_POINTS-1];
    reg [LOG_MAX_POINT_VAL:0] pipe_minY         [0:MAX_POINTS-1];
    reg [LOG_MAX_POINT_VAL:0] pipe_maxX         [0:MAX_POINTS-1];
    reg [LOG_MAX_POINT_VAL:0] pipe_maxY         [0:MAX_POINTS-1];
    reg [63:0]                pipe_area         [0:MAX_POINTS-1];
    reg                       pipe_cut_detected [0:MAX_POINTS-1];
    reg [LOG_MAX_POINTS:0]    pipe_hit_count    [0:MAX_POINTS-1];
    reg                       pipe_valid        [0:MAX_POINTS-1];

    // first pipeline stage input:
    wire [LOG_MAX_POINT_VAL:0] feed_x1, feed_x2, feed_y1, feed_y2;
    wire [LOG_MAX_POINT_VAL:0] feed_minX, feed_minY, feed_maxX, feed_maxY;
    wire [63:0]                feed_area;
    wire [LOG_MAX_POINT_VAL:0] feed_w, feed_h;
    
    assign feed_x1 = point_x[pipe_i];
    assign feed_x2 = point_x[pipe_j];
    assign feed_y1 = point_y[pipe_i];
    assign feed_y2 = point_y[pipe_j];
    assign feed_minX = (feed_x1 < feed_x2) ? feed_x1 : feed_x2;
    assign feed_maxX = (feed_x1 > feed_x2) ? feed_x1 : feed_x2;
    assign feed_minY = (feed_y1 < feed_y2) ? feed_y1 : feed_y2;
    assign feed_maxY = (feed_y1 > feed_y2) ? feed_y1 : feed_y2;
    assign feed_w = feed_maxX - feed_minX + 1;
    assign feed_h = feed_maxY - feed_minY + 1;
    assign feed_area = feed_h * feed_w;

    integer k;

    // pipeline stages:
    wire [MAX_POINTS-1:0] stage_cut;
    wire [MAX_POINTS-1:0] stage_ray_hit;

    genvar g;
    generate
        for (g=0; g<MAX_POINTS; g=g+1) begin : pipe_line_stages
            // logic to detect cuts:
            wire seg_is_vertical;
            wire cut_vertical;
            wire seg_is_horizontal;
            wire cut_horizontal;

            wire [LOG_MAX_POINT_VAL:0] in_minX, in_minY, in_maxX, in_maxY;
            wire [LOG_MAX_POINT_VAL:0] seg_minX, seg_minY, seg_maxX, seg_maxY;
            
            // feed inputs from registers or previous stage:
            if (g == 0) begin
                assign in_minX = feed_minX;
                assign in_minY = feed_minY;
                assign in_maxX = feed_maxX;
                assign in_maxY = feed_maxY;
            end else begin
                assign in_minX = pipe_minX[g-1];
                assign in_minY = pipe_minY[g-1];
                assign in_maxX = pipe_maxX[g-1];
                assign in_maxY = pipe_maxY[g-1];
            end

            assign seg_is_vertical = (stage_seg_x1[g] == stage_seg_x2[g]);
            assign seg_is_horizontal = (stage_seg_y1[g] == stage_seg_y2[g]);

            assign seg_minX = (stage_seg_x1[g] < stage_seg_x2[g]) ? stage_seg_x1[g] : stage_seg_x2[g];
            assign seg_minY = (stage_seg_y1[g] < stage_seg_y2[g]) ? stage_seg_y1[g] : stage_seg_y2[g];
            assign seg_maxX = (stage_seg_x1[g] > stage_seg_x2[g]) ? stage_seg_x1[g] : stage_seg_x2[g];
            assign seg_maxY = (stage_seg_y1[g] > stage_seg_y2[g]) ? stage_seg_y1[g] : stage_seg_y2[g];

            assign cut_vertical = seg_is_vertical && (stage_seg_x1[g] > in_minX) && (stage_seg_x1[g] < in_maxX) && (in_minY < seg_maxY) && (seg_minY < in_maxY);
            assign cut_horizontal = seg_is_horizontal && (stage_seg_y1[g] > in_minY) && (stage_seg_y1[g] < in_maxY) && (in_minX < seg_maxX) && (seg_minX < in_maxX);
            assign stage_cut[g] = stage_active[g] && (cut_vertical || cut_horizontal);

            // ray casting logic: can check any direction, I check vertical here
            wire [LOG_MAX_POINT_VAL:0] centerX_doubled, centerY_doubled;
            assign centerX_doubled = in_minX + in_maxX;
            assign centerY_doubled = in_minY + in_maxY;
            wire ray_right_of_seg;
            wire ray_between_y;
            assign ray_right_of_seg = ((stage_seg_x1[g]*2) > centerX_doubled);
            assign ray_between_y = (centerY_doubled > (seg_minY*2)) && (centerY_doubled < (seg_maxY*2));
            assign stage_ray_hit[g] = stage_active[g] && seg_is_vertical && ray_right_of_seg && ray_between_y;

        end
    endgenerate

    // FSM:
    always @(posedge clk) begin
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
            p1_i <= 0;
            p1_j <= 0;
            pipe_i <= 0;
            pipe_j <= 0;
            drain_count <= 0;

            for (k=0; k<MAX_POINTS; k=k+1) begin
                stage_active[k] <= 0;
                pipe_valid[k] <=0 ;
                pipe_cut_detected[k] <= 0;
                pipe_hit_count[k] <= 0;
            end
        end else begin
            case(state)
                S_IDLE: begin
                    state <= S_READ;
                    rom_addr <= 0;
                end

                S_READ: begin
                    if (rom_data == "\n" || (rom_addr > 0 && rom_data == 0)) begin
                        if (rom_data == "\n" || rom_data == 0) begin
                            // save the parsed point:
                            point_x[parse_idx] <= parse_x;
                            point_y[parse_idx] <= parse_y;
                            // increment variables:
                            parse_idx <= parse_idx + 1;
                            parsing_first <= 1;
                            parse_x <= 0;
                            parse_y <= 0;

                            // if at EOF, move to next state
                            if (rom_data == 0 && parsing_first) begin 
                                state <= S_BUILD_SEGMENTS;
                                point_count <= parse_idx; // need to +1 here since increment only happens at end of block
                            end
                        end
                        rom_addr <= rom_addr + 1;
                    end else if (rom_data == ",") begin
                        // if hit comma, then we must have finished parsing the X coordinate
                        parsing_first <= 0;
                        rom_addr <= rom_addr + 1;
                    end else if (rom_data >= "0" && rom_data <= "9") begin
                        // $display("Parsing character: '%c'", rom_data);
                        if (parsing_first) begin
                            parse_x <= parse_x*10 + (rom_data - "0");
                        end else begin
                            parse_y <= parse_y*10 + (rom_data - "0");
                        end
                        rom_addr <= rom_addr + 1;
                    end else begin
                        // ignore any other character that isnt in ,\n0-9
                        rom_addr <= rom_addr + 1;
                    end
                end


                S_BUILD_SEGMENTS: begin
                    // build all the segments and load them into pipeline stages
                    // use parallel assignment 
                    for (k=0; k<MAX_POINTS; k=k+1) begin
                        if (k<point_count) begin
                            stage_seg_x1[k] <= point_x[k];
                            stage_seg_y1[k] <= point_y[k];
                            stage_seg_x2[k] <= point_x[(k==point_count-1) ? 0 : (k+1)];
                            stage_seg_y2[k] <= point_y[(k==point_count-1) ? 0 : (k+1)];
                            stage_active[k] <= 1;
                        end else begin
                            stage_active[k] <= 0;
                        end
                    end
                    
                    // start computation:
                    state <= S_PART1;
                    p1_i <= 0;
                    p1_j <= 0;
                end


                S_PART1: begin
                    // loop ove all unique pairs of points:
                    if (p1_i < point_count) begin
                        // combinational logic:
                        p1_x1 = point_x[p1_i];
                        p1_y1 = point_y[p1_i];
                        p1_x2 = point_x[p1_j];
                        p1_y2 = point_y[p1_j];

                        p1_dx = (p1_x1 > p1_x2) ? (p1_x1 - p1_x2) : (p1_x2 - p1_x1);
                        p1_dy = (p1_y1 > p1_y2) ? (p1_y1 - p1_y2) : (p1_y2 - p1_y1);
                        p1_area = (p1_dx + 1) * (p1_dy + 1);
                        // end combinational logic

                        // track largest area:
                        if (p1_area > part1_result) begin
                            part1_result <= p1_area;
                        end

                        // increment loop counters:
                        if (p1_j + 1 < p1_i) begin
                            p1_j <= p1_j + 1;
                        end else begin
                            p1_i <= p1_i + 1;
                            p1_j <= 0;
                        end
                    end else begin
                        // finished iterating over pairs of points:
                        state <= S_PART_2_STREAM;
                        pipe_i <= 1;
                        pipe_j <= 0;

                        // initialise pipeline:
                        for (k=0; k<MAX_POINTS; k=k+1) begin
                            pipe_valid[k] <= 0;
                            pipe_cut_detected[k] <= 0;
                            pipe_hit_count[k] <= 0;
                        end
                    end
                end

                // todo: VITAL: integrate p2 with p1 stage above, it will HALVE simulation time
                S_PART_2_STREAM: begin
                    if (pipe_i < point_count) begin
                        // if ((pipe_i-1) % 50 == 0) begin
                        //     $display("Done %d/%d", pipe_i, point_count);
                        // end
                        // feed data into the first pipeline stage:
                        pipe_rect_x1[0] <= feed_x1;
                        pipe_rect_y1[0] <= feed_y1;
                        pipe_rect_x2[0] <= feed_x2;
                        pipe_rect_y2[0] <= feed_y2;
                        pipe_minX[0]    <= feed_minX;
                        pipe_minY[0]    <= feed_minY;
                        pipe_maxX[0]    <= feed_maxX;
                        pipe_maxY[0]    <= feed_maxY;
                        pipe_area[0]    <= feed_area;
                        pipe_cut_detected[0] <= stage_cut[0];
                        pipe_hit_count[0] <= stage_ray_hit[0] ? 1 : 0;
                        pipe_valid[0] <= 1;

                        // progress non-starting pipeline stages:
                        for (k=1; k<MAX_POINTS; k=k+1) begin
                            pipe_rect_x1[k] <= pipe_rect_x1[k-1];
                            pipe_rect_y1[k] <= pipe_rect_y1[k-1];
                            pipe_rect_x2[k] <= pipe_rect_x2[k-1];
                            pipe_rect_y2[k] <= pipe_rect_y2[k-1];
                            pipe_minX[k] <= pipe_minX[k-1];
                            pipe_minY[k] <= pipe_minY[k-1];
                            pipe_maxX[k] <= pipe_maxX[k-1];
                            pipe_maxY[k] <= pipe_maxY[k-1];
                            pipe_area[k] <= pipe_area[k-1];
                            pipe_cut_detected[k] <= pipe_cut_detected[k-1] || stage_cut[k];
                            pipe_hit_count[k] <= pipe_hit_count[k-1] + (stage_ray_hit[k] ? 1 : 0);
                            pipe_valid[k] <= pipe_valid[k-1];
                        end

                        // check final pipe line stage output:
                        if (pipe_valid[MAX_POINTS-1]) begin
                            if (!pipe_cut_detected[MAX_POINTS-1] && (pipe_hit_count[MAX_POINTS-1][0] == 1)) begin
                                if (pipe_area[MAX_POINTS-1] > part2_result) begin
                                    part2_result <= pipe_area[MAX_POINTS-1];
                                end
                            end
                        end

                        // increment loop counters:
                        if (pipe_j + 1 < pipe_i) begin
                            pipe_j <= pipe_j + 1;
                        end else begin
                            pipe_j <= 0;
                            pipe_i <= pipe_i + 1;
                        end 
                    end else begin
                        // finished -> flush pipeline then done
                        state <= S_PART_2_DRAIN;
                        drain_count <= 0;
                    end
                end

                S_PART_2_DRAIN: begin
                    if (drain_count < MAX_POINTS) begin
                        // feed invalid signal to pipeline beginning (not necessary but I guess good practice)
                        pipe_valid[0] <= 0;

                        // progress pipeline stages:
                        // progress non-starting pipeline stages:
                        for (k=1; k<MAX_POINTS; k=k+1) begin
                            pipe_rect_x1[k] <= pipe_rect_x1[k-1];
                            pipe_rect_y1[k] <= pipe_rect_y1[k-1];
                            pipe_rect_x2[k] <= pipe_rect_x2[k-1];
                            pipe_rect_y2[k] <= pipe_rect_y2[k-1];
                            pipe_minX[k] <= pipe_minX[k-1];
                            pipe_minY[k] <= pipe_minY[k-1];
                            pipe_maxX[k] <= pipe_maxX[k-1];
                            pipe_maxY[k] <= pipe_maxY[k-1];
                            pipe_area[k] <= pipe_area[k-1];
                            pipe_cut_detected[k] <= pipe_cut_detected[k-1] || stage_cut[k];
                            pipe_hit_count[k] <= pipe_hit_count[k-1] + (stage_ray_hit[k] ? 1 : 0);
                            pipe_valid[k] <= pipe_valid[k-1];
                        end

                        // check output of final stage:
                        if (pipe_valid[MAX_POINTS-1]) begin
                            if(!pipe_cut_detected[MAX_POINTS-1] && (pipe_hit_count[MAX_POINTS-1][0] == 1)) begin
                                if (pipe_area[MAX_POINTS-1] > part2_result) begin
                                    part2_result <= pipe_area[MAX_POINTS-1];
                                end
                            end
                        end

                        // increment counter:
                        drain_count <= drain_count + 1;
                    end else begin
                        state <= S_DONE;
                        done <= 1;
                    end
                end


                S_DONE: begin
                     done <= 1;
                end

                default: state <= S_IDLE; // not necessary here 
            endcase
        end
    end
endmodule
