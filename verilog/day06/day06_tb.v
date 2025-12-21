`timescale 1ns/1ps

module day06_tb;

    // parameters:
    parameter N_ADDR_BITS = 16;
    parameter CLK_PERIOD = 10; // 10ns period
    parameter OUTPUT_DATA_WIDTH = 64;
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

    integer clock_cycle_count;
    initial begin
        clock_cycle_count = 0;
    end
    always @(clk) begin
        if (rst) begin
            clock_cycle_count = 0;
        end else if (clk && !done) begin
            clock_cycle_count = clock_cycle_count + 1;
        end
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

    // instantiate synthesisable 'day06_core' module:
    day06_core #(
        .N_ADDR_BITS(N_ADDR_BITS)
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

    // run day06_core module until done:
    initial begin
        // reset all modules:
        rst = 1;
        repeat (5) @(posedge clk); // be really sure everything is reset
        rst = 0;
        $display("INFO: Day06 solver started.");

        // wait until done = 1:
        wait (done === 1);

        // wait a couple of clock cycles to ensure final calculations are complete:
        repeat (5) @(posedge clk);

        // display results:
        $display("Day 6 Complete");
        $display("Part 1 Result: %0d", part1_result);
        $display("Part 2 Result: %0d", part2_result);
        $display("Took %0d clock cycles", clock_cycle_count);
        $finish;
    end

endmodule
