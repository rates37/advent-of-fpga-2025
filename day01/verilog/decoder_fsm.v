// reads ASCII data from ROM, and decodes it into meaningful puzzle inputs
// is a synthesisable module
module decoder_fsm # (
    parameter DATA_WIDTH = 16 // width of data that will be passed to the solver module (this must match solver#INPUT_DATA_WIDTH)
) (
    // Synchronous inputs:
    input wire clk,
    input wire rst,

    // ASCII input data:
    input wire [7:0] char_in, // the value of the 7-bit ascii character currently read from ROM
    input wire char_valid,

    // outputs:
    output reg dir, // L -> dir=0, R -> dir=1
    output reg [DATA_WIDTH-1:0] number, // about to rotate dial by
    output reg valid_pulse // will be pulsed high for 1 clk cycle once the full line has been read in
);
    // states of decoder FSM:
    localparam S_IDLE = 1'b0;
    localparam S_READING = 1'b1;

    // internal signals and state:
    reg state;
    reg [DATA_WIDTH-1:0] number_acc; // accumulator for reading in numeric value since will be char by char
    reg dir_internal;

    // next state decoding logic
    always @(posedge clk) begin
        if (rst) begin
            // synchronous reset:
            state <= S_IDLE;
            number_acc <= 0;
            dir_internal <= 1'b0; // arbitrary initial value but not important as will be overwritten when FSM leaves IDLE state
            dir <= 1'b0;
            number <= 0;
            valid_pulse <= 1'b0;

        end else begin
            valid_pulse <= 1'b0; // default to low, can set high if finished current line later
            if (char_valid) begin
                case (state)
                    S_IDLE: begin
                        number_acc <= 0; // starting to decode a new line, so reset acc
                        if (char_in === "L") begin
                            dir_internal <= 1'b0;
                            state <= S_READING; // prepare to read numeric characters into number_acc

                        end else if (char_in === "R") begin
                            dir_internal <= 1'b1;
                            state <= S_READING;

                        end // otherwise simply consume character and ignore (if input data is correctly formatted, this will not happen)
                    end

                    S_READING: begin
                        // if input character is a number:
                        if (char_in >= "0" && char_in <= "9") begin
                            number_acc <= (number_acc * 10) + (char_in - "0");

                        end 
                        // if read in a newline character (this signals end of current reading)
                        else if (char_in == 8'h0A) begin // 0x0A is newline in ASCII
                            dir <= dir_internal;
                            number <= number_acc;
                            valid_pulse <= 1'b1;
                            state <= S_IDLE;

                        end else begin
                            // error occurred: malformed input file
                            state <= S_IDLE; // revert to idle state to recover as quickly as possible
                        end
                    end
                endcase
            end
        end
    end
endmodule
