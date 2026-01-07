module gf2_solver #(
    parameter MAX_LIGHTS = 10,
    parameter MAX_BUTTONS = 13
) (
    input wire clk,
    input wire rst,

    // input: coefficient matrix (A) and target bit vector (b)
    input wire start,
    input wire [MAX_LIGHTS-1:0] A [0:MAX_BUTTONS-1], // each button A[i] is a bit vector indicating which lights it affects
    input wire [MAX_LIGHTS-1:0] b, // target state of the lights
    input wire [3:0] m, // number of lights (rows)
    input wire [3:0] n, // number of buttons (cols)

    // output:
    output reg [7:0] min_cost,
    output reg [MAX_BUTTONS-1:0] solution,
    output reg done
);

    // fsm:
    localparam S_IDLE = 0;
    localparam S_INIT = 1;
    localparam S_CHECK = 2;
    localparam S_COMPUTE_RESULT = 3;
    localparam S_UPDATE_BEST = 4;
    localparam S_NEXT_COMB = 5;
    localparam S_DONE = 6;
    reg [2:0] state;

    // current combination being tested:
    reg [MAX_BUTTONS-1:0] current_combo;
    reg [MAX_BUTTONS-1:0] max_combo; // 2^n-1

    // result of Ax for current combo:
    reg [MAX_LIGHTS-1:0] result;
    reg [3:0] button_idx;

    reg [7:0] current_cost;
    integer i;
    reg [MAX_LIGHTS-1:0] mask;
    reg [MAX_LIGHTS-1:0] result_masked;
    reg [MAX_LIGHTS-1:0] b_masked;

    always @(posedge clk) begin
        if (rst) begin
            state <= S_IDLE;
            done <= 0;
            min_cost = 8'hFF;
            solution <= 0;
            current_combo <= 0;
            max_combo <= 0;
        end else begin
            case (state)
                S_IDLE: begin
                    if (start) begin
                        state <= S_INIT;
                        done <= 0;
                        min_cost <= 8'hFF;
                        solution <= 0;
                    end
                end


                S_INIT: begin
                    current_combo <= 0;
                    max_combo <= (1<<n) -1;
                    state <= S_CHECK;
                end


                S_CHECK: begin
                    // check if current combo is a valid sol
                    // compute A * current_combo (mod 2)
                    result <= 0;
                    button_idx <= 0;
                    state <= S_COMPUTE_RESULT;
                end


                S_COMPUTE_RESULT: begin
                    // compute A * current_combo (mod 2) iteratively
                    if (button_idx >= n) begin
                        state <= S_UPDATE_BEST;
                    end else begin
                        if (current_combo[button_idx]) begin
                            result <= result ^ A[button_idx];
                        end
                        button_idx <= button_idx + 1;
                    end
                end


                S_UPDATE_BEST: begin
                    mask = (1<<m) - 1;
                    result_masked = result & mask;
                    b_masked = b&mask;

                    if (result_masked == b_masked) begin
                        // found a valid solution:
                        current_cost = 0;
                        for (i = 0; i<MAX_BUTTONS; i=i+1) begin
                            if (current_combo[i]) begin
                                current_cost = current_cost + 1;
                            end
                        end

                        if (current_cost < min_cost) begin
                            min_cost <= current_cost;
                            solution <= current_combo;
                        end
                    end 
                    state <= S_NEXT_COMB;
                end


                S_NEXT_COMB: begin
                    if (current_combo >= max_combo) begin
                        state <= S_DONE;
                    end else begin
                        current_combo <= current_combo + 1;
                        state <= S_CHECK;
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
