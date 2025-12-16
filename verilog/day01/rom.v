// module to load a file into byte-addressable ROM
// is NOT a synthesisable module
// this is used to show proof of concept for the 
// validity of the solver (not as part of the solution)

module rom #(
    parameter N_ADDR_BITS = 16,
    parameter FILENAME = "input.txt"
) (
    // Synchronous inputs:
    input wire clk,
    // no reset, this is a mock module

    input wire [N_ADDR_BITS:0] addr,
    output reg [7:0] data_out, // memory[addr]
    output reg valid // 
);
    localparam ROM_DEPTH = (1 << (N_ADDR_BITS + 1));

    reg [7:0] rom_array[0:ROM_DEPTH-1];
    // file handling variables:
    integer file_id;
    integer char_val;
    integer mem_idx;
    integer i;
    reg eof_flag;

    initial begin
        // initialise entire memory to zero:
        for (i = 0; i < ROM_DEPTH; i = i+1) begin
            rom_array[i] = 8'd0;
        end

        mem_idx = 0;
        eof_flag = 0;
        // open file:
        file_id = $fopen(FILENAME, "r");
        if (file_id === 0) begin
            $display("ERROR: Could not open input file '%s' for reading.", FILENAME);
            $finish;

        end else begin
            // read characters until EOF or ROM is full:
            while (mem_idx < ROM_DEPTH && !eof_flag) begin
                char_val = $fgetc(file_id);
                if (char_val < 0) begin
                    eof_flag = 1;

                end else begin
                    rom_array[mem_idx] = char_val[7:0];
                    mem_idx = mem_idx + 1;
                end

            end

            // ensure file contents ends in a null character:
            if (mem_idx < ROM_DEPTH-1) begin
                rom_array[mem_idx] = "\n";
                rom_array[mem_idx+1] = 8'b0;
            end

            // close file:
            $fclose(file_id);

        end

    end


    always @(negedge clk) begin // update on negedge to simplify rest of modules
        if (addr < ROM_DEPTH) begin
            data_out <= rom_array[addr];
            valid <= (rom_array[addr] != 8'd0);

        end else begin
            data_out <= 8'b0;
            valid <= 1'b0;
        end

    end

endmodule
