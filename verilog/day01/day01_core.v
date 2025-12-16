// synthesisable module that reads ASCII data from ROM, solves puzzle, and outputs results
// is a synthesisable module
module day01_core #(
    parameter N_ADDR_BITS = 16, // number of bits required to fully address the ROM module // should ensure is set to 
    parameter INPUT_DATA_WIDTH = 16,
    parameter OUTPUT_DATA_WIDTH = 16
) (
    // Synchronous inputs:
    input wire clk,
    input wire rst,

    // IO to interface with ROM:
    input wire [7:0] rom_data,
    input wire rom_valid,
    output reg [N_ADDR_BITS:0] rom_addr,

    // results:
    output wire [OUTPUT_DATA_WIDTH-1:0] part1_result,
    output wire [OUTPUT_DATA_WIDTH-1:0] part2_result,
    output reg done
);

    // Define FSM states:
    localparam S_STARTUP = 0;
    localparam S_RUNNING = 1;
    localparam S_DONE = 2;

    // internal state and intermediate signals:
    reg [1:0] state;
    wire [INPUT_DATA_WIDTH-1:0] number_decoded;
    wire direction_decoded;
    wire decoder_valid;

    wire decoder_en;

    // enable the decoder to run only when in running state AND input data from ROM is valid
    assign decoder_en = (state == S_RUNNING) && rom_valid;

    // instantiate decoder:
    decoder_fsm u_decoder_0 (
        .clk(clk),
        .rst(rst),

        .char_in(rom_data),
        .char_valid(decoder_en),

        .dir(direction_decoded),
        .number(number_decoded),
        .valid_pulse(decoder_valid)
    );

    // instantiate solver:
    solver u_solver_0 (
        .clk(clk),
        .rst(rst),

        .input_valid(decoder_valid),
        .dir(direction_decoded),
        .rotation(number_decoded),

        .zero_endings(part1_result),
        .zero_crossings(part2_result)
    );

    // Overall module controller fsm:
    always @(posedge clk) begin
        if (rst) begin
            // synchronous reset:
            rom_addr <= 0;
            state <= S_STARTUP;
            done <= 1'b0;

        end else begin
            case (state)
                S_STARTUP: begin
                    // start reading from start of ROM
                    // wait 1 clock cycle for ROM to fetch data before running
                    rom_addr <= 0;
                    state <= S_RUNNING;
                end


                S_RUNNING: begin
                    if (!rom_valid) begin
                        // if rom_valid goes low, we hit end of rom contents
                        // i.e., hit the null terminator of the input file
                        state <= S_DONE;
                    end else begin
                        rom_addr <= rom_addr + 1;
                    end
                end


                S_DONE: begin
                    done <= 1'b1;
                end

            endcase
        end
    end
endmodule
