module pipeline_stage #(
    parameter LOG_MAX_POINT_VAL = 17,
    parameter LOG_MAX_POINTS = 9,
    parameter SEGS_PER_STAGE = 32,
    parameter LOG_SEGS = 5
) (
    input clk,
    input rst,

    // segment loading:
    input wire load_en,
    input wire [LOG_MAX_POINT_VAL:0] seg_load_x1,
    input wire [LOG_MAX_POINT_VAL:0] seg_load_x2,
    input wire [LOG_MAX_POINT_VAL:0] seg_load_y1,
    input wire [LOG_MAX_POINT_VAL:0] seg_load_y2,
    input wire seg_load_active,
    output reg [LOG_SEGS:0] seg_count,

    // ready/valid input:
    output wire in_ready, // whether this stage can accept input
    input wire in_valid, // input data is valid
    input wire [LOG_MAX_POINT_VAL:0] in_minX,
    input wire [LOG_MAX_POINT_VAL:0] in_minY,
    input wire [LOG_MAX_POINT_VAL:0] in_maxX,
    input wire [LOG_MAX_POINT_VAL:0] in_maxY,
    input wire [63:0] in_area,
    input wire in_cut_detected,
    input wire [LOG_MAX_POINTS:0] in_hit_count,
    input wire in_data_valid,

    // ready/valid output:
    input wire out_ready, // whether the next stage can accept input
    output reg out_valid, // this stage's output data is valid
    output reg [LOG_MAX_POINT_VAL:0] out_minX,
    output reg [LOG_MAX_POINT_VAL:0] out_minY,
    output reg [LOG_MAX_POINT_VAL:0] out_maxX,
    output reg [LOG_MAX_POINT_VAL:0] out_maxY,
    output reg [63:0] out_area,
    output reg out_cut_detected,
    output reg [LOG_MAX_POINTS:0] out_hit_count,
    output reg out_data_valid
);

    // ram to store segments:
    localparam SEG_WIDTH = 1 + 4 * (LOG_MAX_POINT_VAL + 1);// segment stored as {valid, x1, y1, x2, y2}
    reg seg_we;
    reg [LOG_SEGS-1:0] seg_w_addr;
    reg [LOG_SEGS-1:0] seg_r_addr;
    reg [SEG_WIDTH-1:0] seg_w_data;
    wire [SEG_WIDTH-1:0] seg_r_data;

    ram #(
        .WIDTH(SEG_WIDTH),
        .DEPTH(SEGS_PER_STAGE),
        .ADDR_BITS(LOG_SEGS)
    ) u_seg_ram (
        .clk(clk),
        .rst(rst),
        .we(seg_we),
        .w_addr(seg_w_addr),
        .w_data(seg_w_data),
        .r_addr(seg_r_addr),
        .r_data(seg_r_data)
    );

    // unpack segment:
    wire seg_active = seg_r_data[SEG_WIDTH-1];
    wire [LOG_MAX_POINT_VAL:0] seg_x1 = seg_r_data[4*(LOG_MAX_POINT_VAL+1)-1 : 3*(LOG_MAX_POINT_VAL+1)];
    wire [LOG_MAX_POINT_VAL:0] seg_y1 = seg_r_data[3*(LOG_MAX_POINT_VAL+1)-1 : 2*(LOG_MAX_POINT_VAL+1)];
    wire [LOG_MAX_POINT_VAL:0] seg_x2 = seg_r_data[2*(LOG_MAX_POINT_VAL+1)-1 : 1*(LOG_MAX_POINT_VAL+1)];
    wire [LOG_MAX_POINT_VAL:0] seg_y2 = seg_r_data[1*(LOG_MAX_POINT_VAL+1)-1 : 0];

    // FSM:
    localparam S_IDLE = 0;
    localparam S_READ = 1;
    localparam S_CHECK = 2;
    localparam S_OUTPUT = 3;
    reg [1:0] state;

    assign in_ready = (state == S_IDLE) && (!out_valid || out_ready); // ready when idle OR if there is no valid output waiting
    reg [LOG_SEGS:0] seg_idx;
    // store the input rectangle (since only valid on clock cycle when leaving S_IDLE)
    reg [LOG_MAX_POINT_VAL:0] lat_minX;
    reg [LOG_MAX_POINT_VAL:0] lat_minY;
    reg [LOG_MAX_POINT_VAL:0] lat_maxX;
    reg [LOG_MAX_POINT_VAL:0] lat_maxY;
    reg [63:0] lat_area;
    reg lat_data_valid;
    reg acc_cut;
    reg [LOG_MAX_POINTS:0] acc_hits;

    // segment geometry calcs:
    wire seg_is_vertical = (seg_x1 == seg_x2);
    wire seg_is_horizontal = (seg_y1 == seg_y2);
    wire [LOG_MAX_POINT_VAL:0] seg_minX = (seg_x1 < seg_x2) ? seg_x1 : seg_x2;
    wire [LOG_MAX_POINT_VAL:0] seg_minY = (seg_y1 < seg_y2) ? seg_y1 : seg_y2;
    wire [LOG_MAX_POINT_VAL:0] seg_maxX = (seg_x1 > seg_x2) ? seg_x1 : seg_x2;
    wire [LOG_MAX_POINT_VAL:0] seg_maxY = (seg_y1 > seg_y2) ? seg_y1 : seg_y2;

    // cut/ray detection:
    wire cut_v = seg_is_vertical && (seg_x1 > lat_minX) && (seg_x1 < lat_maxX) && (lat_minY < seg_maxY) && (seg_minY < lat_maxY);
    wire cut_h = seg_is_horizontal && (seg_y1 > lat_minY) && (seg_y1 < lat_maxY) && (lat_minX < seg_maxX) && (seg_minX < lat_maxX);
    wire local_cut = seg_active && (cut_v || cut_h);
    wire [LOG_MAX_POINT_VAL+1:0] cx2 = lat_minX + lat_maxX;
    wire [LOG_MAX_POINT_VAL+1:0] cy2 = lat_minY + lat_maxY;
    wire local_hit = seg_active && seg_is_vertical && ((seg_x1*2) > cx2) && (cy2 > (seg_minY*2)) && (cy2 < (seg_maxY * 2));

    always @(posedge clk) begin
        if (rst) begin
            state <= S_IDLE;
            seg_count <= 0;
            seg_we <= 0;
            seg_r_addr <= 0;
            seg_idx <= 0;
            out_valid <= 0;
            out_data_valid <= 0;
            out_cut_detected <= 0;
            out_hit_count <= 0;
            out_minX <= 0;
            out_minY <= 0;
            out_maxX <= 0;
            out_maxY <= 0;
            out_area <= 0;
            lat_data_valid <= 0;
            acc_cut <= 0;
            acc_hits <= 0;
        end else begin
            seg_we <= 0;

            if (out_valid && out_ready) begin
                // clear output valid signal. when next stage accepts
                out_valid <= 0; 
            end

            // segment loading:
            if (load_en && state == S_IDLE && !out_valid) begin
                seg_we <= 1;
                seg_w_addr <= seg_count[LOG_SEGS-1:0];
                seg_w_data <= {seg_load_active, seg_load_x1, seg_load_y1, seg_load_x2, seg_load_y2};
                seg_count <= seg_count + 1;
            end


            case (state)
                S_IDLE: begin
                    // accept input when ready:
                    if (in_valid && in_ready) begin
                        if (in_data_valid && seg_count > 0 && !in_cut_detected) begin
                            lat_minX <= in_minX;
                            lat_minY <= in_minY;
                            lat_maxX <= in_maxX;
                            lat_maxY <= in_maxY;
                            lat_area <= in_area;
                            lat_data_valid <= 1;
                            acc_cut <= in_cut_detected;
                            acc_hits <= in_hit_count;

                            // initialise read:
                            seg_idx <= 0;
                            seg_r_addr <= 0;
                            state <= S_READ; // process
                        end else begin
                            // pass through immediately
                            out_minX <= in_minX;
                            out_minY <= in_minY;
                            out_maxX <= in_maxX;
                            out_maxY <= in_maxY;
                            out_area <= in_area;
                            out_cut_detected <= in_cut_detected;
                            out_hit_count <= in_hit_count;
                            out_data_valid <= in_data_valid;
                            out_valid <= 1;
                        end
                    end
                end

                S_READ: begin
                    if (seg_count > 1) begin
                        seg_r_addr <= 1;
                    end 
                    state <= S_CHECK;
                end

                S_CHECK: begin
                    acc_cut <= acc_cut | local_cut;
                    acc_hits <= acc_hits + (local_hit ? 1 : 0);

                    // short circuit -> if we detect a cut, we can stop immediately
                    if (acc_cut | local_cut) begin
                        out_minX <= lat_minX;
                        out_minY <= lat_minY;
                        out_maxX <= lat_maxX;
                        out_maxY <= lat_maxY;
                        out_area <= lat_area;
                        out_cut_detected <= 1;
                        out_hit_count <= acc_hits;
                        out_data_valid <= lat_data_valid;
                        out_valid <= 1;
                        state <= S_OUTPUT;
                    end else if (seg_idx + 1 < seg_count) begin
                        // move to check next segment
                        seg_idx <= seg_idx + 1;
                        seg_r_addr <= seg_idx + 2;
                        // stay in S_CHECK
                    end else begin
                        // finished processing all segments
                        out_minX <= lat_minX;
                        out_minY <= lat_minY;
                        out_maxX <= lat_maxX;
                        out_maxY <= lat_maxY;
                        out_area <= lat_area;
                        out_cut_detected <= acc_cut | local_cut;
                        out_hit_count <= acc_hits + (local_hit ? 1 : 0);
                        out_data_valid <= lat_data_valid;
                        out_valid <= 1;
                        state <= S_OUTPUT;
                        
                    end
                end

                S_OUTPUT: begin
                    // halt until next stage ready to accept
                    if (out_ready) begin
                        state <= S_IDLE;
                    end
                end

                default: begin
                    state <= S_IDLE;
                end
            endcase
        end
    end 
endmodule
