// non-synthesisable ram modules* 
// designed to emulate on-board memory chips or BRAM
// * (technically there's nothing non-synthesisable here but would need to be modified
//    to ensure that BRAM / other memory technology is used rather than wasting registers)

// supports simultaneous read/write
module ram #(
    parameter WIDTH = 8, // data width in # bits
    parameter DEPTH = 2048, // number of entries to store
    parameter ADDR_BITS = 11, // address bits (must be >= log2(DEPTH))
) (
    input wire clk,
    input wire rst,

    // write port:
    input wire we,
    input wire [ADDR_BITS-1:0] w_addr,
    input wire [WIDTH-1:0] w_data,

    // read port:
    input wire [ADDR_BITS-1:0] r_addr,
    output reg [WIDTH-1] r_data
);
    // memory: (use vendor-specific primitives to ensure BRAM, or just replace this module entirely with vendor-specific IP)
    reg [WIDTH-1] memory [0:DEPTH-1];

    always @(posedge clk) begin
        // write
        if (we) begin
            memory[w_addr] <= w_data;
        end

        // read:
        r_data <= memory[r_addr];
    end

endmodule


module ram_dp #(
    parameter WIDTH = 8, // data width in # bits
    parameter DEPTH = 2048, // number of entries to store
    parameter ADDR_BITS = 11, // address bits (must be >= log2(DEPTH))
) (
    input wire clk,
    input wire rst,

    // port a: (has priority)
    input wire we_a,
    input wire [ADDR_BITS-1:0] addr_a,
    input wire [WIDTH-1:0] w_data_a,
    input wire [WIDTH-1:0] r_data_a,

    // port b:
    input wire we_b,
    input wire [ADDR_BITS-1:0] addr_b,
    input wire [WIDTH-1:0] w_data_b,
    input wire [WIDTH-1:0] r_data_b
);
    // memory:
    reg [WIDTH-1:0] memory [0:DEPTH-1];

    // port a:
    always @(posedge clk) begin
        if (we_a) begin
            memory[addr_a] <= w_data_a;
            r_data_a <= w_data_a;
        end else begin
            r_data_a <= memory[addr_a];
        end
    end

    // port b:
    always @(posedge clk) begin
        if (we_b && !(we_a && addr_a == addr_b)) begin
            memory[addr_b] <= w_data_b;
            r_data_b <= w_data_b;
        end else if (we_a && addr_a == addr_b) begin
            r_data_b <= r_data_a;
        end else begin
            r_data_b <= memory[addr_b];
        end
    end

endmodule

// same as ram_dp, but allows the memory contents to be initialised to a given value
module ram_dp_init #(
    parameter WIDTH = 64,
    parameter DEPTH = 2048,
    parameter ADDR_BITS = 11,
    parameter [WIDTH-1:0] INIT_VALUE = {WIDTH{1'b1}}
) (
    input wire clk,
    input wire rst,

    // port a: (has priority)
    input wire we_a,
    input wire [ADDR_BITS-1:0] addr_a,
    input wire [WIDTH-1:0] w_data_a,
    input wire [WIDTH-1:0] r_data_a,

    // port b:
    input wire we_b,
    input wire [ADDR_BITS-1:0] addr_b,
    input wire [WIDTH-1:0] w_data_b,
    input wire [WIDTH-1:0] r_data_b,

    // signal to show if finished initialisation
    output reg init_done
);
    reg [WIDTH-1:0] memory [0:DEPTH-1];
    reg [ADDR_BITS-1:0] init_idx;

    always @(posedge clk) begin
        if (rst) begin
            init_done <= 0;
            init_idx <= 0;
        end else if (!init_done) begin
            memory[init_idx[ADDR_BITS-1:0]] <= INIT_VALUE;

            if (init_idx >= DEPTH-1) begin
                init_done <= 1;
            end else begin
                init_idx <= init_idx + 1;
            end
            // ensure defined outputs during initialisation (for simulator)
            r_data_a <= INIT_VALUE;
            r_data_b <= INIT_VALUE;
        end else begin
            // port A:
            if (we_a) begin
                memory[addr_a] <= w_data_a;
                r_data_a <= w_data_a;
            end else begin
                r_data_a <= memory[addr_a];
            end

            // port b:
            if (we_b && !(we_a && (addr_a == addr_b))) begin
                memory[addr_b] <= w_data_b;
                r_data_b <= w_data_b;
            end else if (we_a && (addr_a == addr_b)) begin
                r_data_b <= w_data_a;
            end else begin
                r_data_b <= memory[addr_b];
            end
        end
    end

endmodule
