module day09_core #(
    parameter N_ADDR_BITS = 16
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
    
endmodule




module name_resolver #(
    parameter LOG2_MAX_NODES = 10, // my puzzle input has only 583 nodes so this seems like a reasonable max size
    parameter MAX_NODES = 1024
) (
    input wire clk,
    input wire rst,
    
    input wire [23:0] name_in, // assumption that ALL nodes are exactly 3 chars
    input wire valid_in,

    output reg [LOG2_MAX_NODES-1:0] node_id_out,
    output reg done,
    output reg is_new // whether the node that was just added was in the lookup table already or not
);

    // simple linear store for now
    // TODO: turn into tree-based lookup?
    reg [23:0] name_store [0:MAX_NODES-1];
    reg [LOG2_MAX_NODES-1:0] node_count;

    reg [LOG2_MAX_NODES-1:0] search_idx;
    reg searching;

    always @(posedge clk) begin
        if (rst) begin
            node_count <= 0;
            searching <= 0;
            done <= 0;
        end else begin
            done <= 0;
            is_new <= 0;
            if (valid_in && !searching) begin
                searching <= 1;
                search_idx <= 0;
            end

            if (searching) begin
                if (search_idx < node_count) begin
                    if (name_store[search_idx] == name_in) begin
                        // found node -> end search and return id
                        done <= 1;
                        node_id_out <= search_idx;
                        searching <= 0;
                    end else begin
                        search_idx <= search_idx + 1;
                    end
                end else begin
                    // exhasuted all nodes, must be a new node
                    // add node to store:
                    name_store[node_count] <= name_in;
                    node_id_out <= node_count;
                    node_count <= node_count + 1;
                    is_new <= 1;
                    // end search
                    done <= 1;
                    searching <= 0;
                end
            end
        end
    end

endmodule
