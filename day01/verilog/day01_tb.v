`timescale 1ns/1ps

module day01_tb;

    // parameters:
    parameter N_ADDR_BITS = 16;
    parameter CLK_PERIOD = 10; // 10ns period
    parameter OUTPUT_DATA_WIDTH = 16;
    parameter INPUT_DATA_FILENAME = "input.txt"; // the filename of the text file that contains puzzle input
                                                 // relative to the directory that the iverilog output is RUN from

    //control signals:
    reg clk;
    reg rst;

    // rom connection wires:
    wire [N_ADDR_BITS:0] rom_addr;
    wire [7:0] rom_data;
    wire rom_valid;

    // results:
    wire [OUTPUT_DATA_WIDTH-1:0] part1_result;
    wire [OUTPUT_DATA_WIDTH-1:0] part2_result;
    wire done;


    // Generate periodic clock:
    initial begin
        clk = 0;
        forever #(CLK_PERIOD/2) clk = !clk;
    end

    // instantiate rom with input file:
    rom #(
        .N_ADDR_BITS(16),
        .FILENAME(INPUT_DATA_FILENAME)
    ) u_rom_0 (
        .clk(clk),
        .addr(rom_addr),
        .data_out(rom_data),
        .valid(rom_valid)
    );

    // instantiate synthesisable 'day01_core' module:
    day01_core #(
        .N_ADDR_BITS(N_ADDR_BITS),
        .INPUT_DATA_WIDTH(16), // todo: come up with more descriptive parameter name as currently conflicts
        .OUTPUT_DATA_WIDTH(OUTPUT_DATA_WIDTH)
    ) u_core_0 (
        .clk(clk),
        .rst(rst),

        .rom_addr(rom_addr),
        .rom_data(rom_data),
        .rom_valid(rom_valid),

        .part1_result(part1_result),
        .part2_result(part2_result),
        .done(done)
    );

    // run the day01_core module until done:
    initial begin
        // reset all modules:
        rst = 1;
        repeat (5) @(posedge clk); // be really sure everything is reset
        rst = 0;
        $display("INFO: Day01 solver started.");

        // wait until done = 1:
        wait (done === 1);

        // wait a couple of clock cycles to ensure final calculations are complete:
        repeat (5) @(posedge clk);

        // display results:
        $display("Day 1 Complete");
        $display("Part 1 Result: %0d", part1_result);
        $display("Part 2 Result: %0d", part2_result);
        $finish;
    end

    // optional: timer to prevent infinite loops (mainly used during debugging)
    // initial begin
    //     #100000000; // for longer input files, this might need to be larger
    //     $display("Timeout reached.");
    //     $finish;
    // end

    // optional: dump waveforms to vcd file for use in waveform viewer
    // initial begin
    //     $dumpfile("day01_wave.vcd");
    //     $dumpvars(0, day01_tb);
    // end

endmodule
