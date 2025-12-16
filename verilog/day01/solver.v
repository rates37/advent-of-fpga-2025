// does the work of solving the puzzle
// takes decoded puzzle input data from decoder_fsm
// is a synthesisable module
module solver #(
    parameter INPUT_DATA_WIDTH  = 16,
    parameter OUTPUT_DATA_WIDTH = 16
) (
    // Synchronous inputs:
    input wire clk,
    input wire rst,

    // Solver input signals:
    input wire input_valid, // whether the input data is currently valid
    input wire dir, // direction to rotate dial in: L -> dir=0, R -> dir=1
    input wire [INPUT_DATA_WIDTH-1:0] rotation, // the amount to rotate by

    // Module outputs (cumulative over time)
    output reg [OUTPUT_DATA_WIDTH-1:0] zero_endings, // number of times dial head is on 0 at END of rotation (part 1 output)
    output reg [OUTPUT_DATA_WIDTH-1:0] zero_crossings // number of times dial head crosses 0 (part 2 output)
);

    // store current position of dial:
    reg [6:0] dial_pos; // only 7 bits needed as just numbers 0-99

    // internal calculation variables/signals:
    reg [INPUT_DATA_WIDTH-6:0] crossings_calc; // intermediately store number of crossings in a single rotation
                                               // max crossings in a rotation is:
                                               // 2^(INPUT_DATA_WIDTH) / 100 <= 2^(INPUT_DATA_WIDTH) / 2^6 
                                               // so INPUT_DATA_WIDTH-6 bits is maximum number of bits
                                               // required to store it
    reg [6:0] new_dial_pos;
    reg passed_landed; // whether passed or landed 0
    integer full_rotations; // used as floor(rotations / 100)
    integer steps_mod_100; // used as rotations % 100
    integer position_signed;
    integer dial_position_unwrapped;

    // next-state logic:
    always @(*) begin
        // provide initial values for all signals to avoid inferring latches
        full_rotations = rotation / 100;
        steps_mod_100 = rotation % 100;
        position_signed = dial_pos; // promote 7-bit unsigned to 32-bit signed (starts positive)
        passed_landed = 0;
        crossings_calc = 0;
        new_dial_pos = dial_pos;
        dial_position_unwrapped = 0;

        if (dir) begin // turn dial right
            dial_position_unwrapped = position_signed + steps_mod_100;

            // check if crossed 0:
            if ((dial_pos != 0) && (dial_position_unwrapped <= 0 || dial_position_unwrapped >= 100)) begin
                passed_landed = 1;
            end
            crossings_calc = full_rotations + passed_landed;
            new_dial_pos = (dial_pos + steps_mod_100) % 100;

        end else begin // turn dial left
            dial_position_unwrapped = position_signed - steps_mod_100;

            // check if crossed 0:
            if ((dial_pos != 0) && (dial_position_unwrapped <= 0 || dial_position_unwrapped >= 100)) begin
                passed_landed = 1;
            end
            crossings_calc = full_rotations + passed_landed;
            new_dial_pos = (dial_pos + 100 - steps_mod_100) % 100;
        end
    end


    // state update:
    always @(posedge clk) begin
        if (rst) begin
            // synchronous reset:
            dial_pos <= 7'd50;
            zero_endings <= 0;
            zero_crossings <= 0;

        end else if (input_valid) begin
            // update state when valid input has been provided
            dial_pos <= new_dial_pos;
            if (new_dial_pos === 0) begin
                zero_endings <= zero_endings + 1;
            end
            zero_crossings <= zero_crossings + crossings_calc;
        end
    end

endmodule
