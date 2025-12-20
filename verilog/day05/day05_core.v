module day05_core #(
    parameter N_ADDR_BITS = 16,
    parameter MAX_RANGES = 180 // my puzzle input has 177 input ranges
    parameter LOG2_MAX_RANGES = 8
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

    // FSM States and State logic (good god this is a big FSM):
    localparam S_IDLE = 0;

    // parsing pipeline:
    localparam S_PARSE_PIPE = 1; // main pipelined parsing state
    localparam S_STORE_RANGE = 2; // write to RAM

    // sorting ranges:
    localparam S_SORT_PREP = 3;
    localparam S_SORT_OUTER = 4;
    localparam S_SORT_INNER = 5;
    localparam S_SORT_READ_A = 6;
    localparam S_SORT_READ_B = 7;
    localparam S_SORT_COMPARE = 8;
    localparam S_SORT_SWAP_1 = 9;
    localparam S_SORT_SWAP_2 = 10;

    // merging ranges:
    localparam S_MERGE_INIT = 11;
    localparam S_MERGE_READ = 12;
    localparam S_MERGE_CHECK = 13;
    localparam S_MERGE_SAVE = 14;
    localparam S_MERGE_FINALISE = 15;

    // parse values:
    localparam S_PARSE_VALUE_PIPE = 16;

    // searching for values:
    localparam S_SEARCH_INIT = 17;
    localparam S_SEARCH_CHECK = 18;
    localparam S_SEARCH_READ = 19;
    localparam S_SEARCH_EVAL = 20;
    localparam S_SEARCH_NEXT = 21; // return to parse value state after this

    localparam S_DONE = 22;
    reg [4:0] state;

    // !!! RAM:
    // Range Storage (RAM but implemented within module for simplicity)
    reg [127:0] range_ram [0:MAX_RANGES-1];
    reg [127:0] merged_ram [0:MAX_RANGES-1]; // stored as two 64-bit vals (low, high) 
    
    // range ram controls:
    reg [LOG2_MAX_RANGES-1:0] r_ram_addr;
    reg r_ram_we;
    reg [127:0] r_ram_wdata;
    reg [127:0] r_ram_rdata;

    // merged ram controls:
    reg [LOG2_MAX_RANGES-1:0] m_ram_addr;
    reg m_ram_we;
    reg [127:0] m_ram_wdata;
    reg [127:0] m_ram_rdata;

    // ram logic:
    always @(posedge clk) begin
        if (r_ram_we) begin
            range_ram[r_ram_addr] <= r_ram_wdata;
        end
        r_ram_rdata <= range_ram[r_ram_addr];
    end

    always @(posedge clk) begin
        if (m_ram_we) begin
            merged_ram[m_ram_addr] <= m_ram_wdata;
        end
        m_ram_rdata <= merged_ram[m_ram_addr];
    end



endmodule
