`timescale 1ns/1ps

module tb_bitonic_sorter;

    // Parameters
    localparam MAX_NUM_VALUES = 1024;
    localparam DATA_ADDR_BITS = 10; // 2^10 = 1024
    localparam DATA_WIDTH = 64;

    // control signals:
    reg clk;
    reg rst;
    reg start;
    reg [DATA_ADDR_BITS:0] num_data_values;
    wire done;
    wire [DATA_ADDR_BITS-1:0] sort_progress;

    // sorter ram interface:
    wire [DATA_ADDR_BITS-1:0] s_r_addr_a, s_r_addr_b;
    wire [DATA_WIDTH-1:0] s_r_data_a, s_r_data_b;
    wire s_we_a, s_we_b;
    wire [DATA_ADDR_BITS-1:0] s_w_addr_a, s_w_addr_b;
    wire [DATA_WIDTH-1:0] s_w_data_a, s_w_data_b;

    // tb ram interface (only need one port to initialise values in ram)
    reg tb_mode;
    reg tb_we;
    reg [DATA_ADDR_BITS-1:0] tb_addr;
    reg [DATA_WIDTH-1:0] tb_w_data;
    wire [DATA_WIDTH-1:0] tb_r_data;

    // ram port a signals (muxed between sorter and testbench)
    wire mux_we_a = tb_mode ? tb_we : s_we_a;
    wire [DATA_ADDR_BITS-1:0] mux_addr_a = tb_mode ? tb_addr : (s_we_a ? s_w_addr_a : s_r_addr_a);
    wire [DATA_WIDTH-1:0] mux_w_data_a = tb_mode ? tb_w_data : s_w_data_a;
    // ram port b signals:
    wire mux_we_b = tb_mode ? 1'b0 : s_we_b;
    wire [DATA_ADDR_BITS-1:0] mux_addr_b = tb_mode ? 0 : (s_we_b ? s_w_addr_b : s_r_addr_b);
    wire [DATA_WIDTH-1:0] mux_wdata_b = s_w_data_b;
    assign tb_r_data = s_r_data_a;

    // instantiate sorter:
    bitonic_sorter #(
        .MAX_NUM_VALUES(MAX_NUM_VALUES),
        .DATA_ADDR_BITS(DATA_ADDR_BITS),
        .DATA_WIDTH(DATA_WIDTH)
    ) u_sorter_0 (
        .clk(clk),
        .rst(rst),
        .start(start),
        .num_values(num_data_values),
        .data_we_a(s_we_a),
        .data_w_addr_a(s_w_addr_a),
        .data_w_data_a(s_w_data_a),
        .data_r_addr_a(s_r_addr_a),
        .data_r_data_a(s_r_data_a),
        .data_we_b(s_we_b),
        .data_w_addr_b(s_w_addr_b),
        .data_w_data_b(s_w_data_b),
        .data_r_addr_b(s_r_addr_b),
        .data_r_data_b(s_r_data_b),
        .done(done),
        .sort_progress(sort_progress)
    );

    // instantiate ram:
    ram_dp #(
        .WIDTH(DATA_WIDTH),
        .DEPTH(MAX_NUM_VALUES),
        .ADDR_BITS(DATA_ADDR_BITS)
    ) ram_dp_u0(
        .clk(clk),
        .rst(rst),
        .we_a(mux_we_a),
        .addr_a(mux_addr_a),
        .w_data_a(mux_w_data_a),
        .r_data_a(s_r_data_a),
        .we_b(mux_we_b),
        .addr_b(mux_addr_b),
        .w_data_b(mux_wdata_b),
        .r_data_b(s_r_data_b)
    );

    // generate clock
    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end

    // testbench variables:
    integer i;
    reg [63:0] prev_val;
    reg [63:0] curr_val;
    reg [31:0] w,u,v; // sorter will sort tuples of (w,u,v) form
    integer seed;


    // task to write a value into ram:
    task write_ram(input [DATA_ADDR_BITS-1:0] addr, input [DATA_WIDTH-1:0] data);
        begin
            tb_addr = addr;
            tb_w_data = data;
            tb_we = 1;
            #10;
            tb_we = 0;
            #10;
        end
    endtask

    // task to check output is sorted:
    task verify_sort(input [DATA_ADDR_BITS:0] n);
        integer k;
        reg [63:0] prev;
        reg [63:0] curr;
        begin
            tb_mode = 1;
            prev = 0;

            for (k=0; k<n; k=k+1) begin
                tb_addr = k;
                #10;
                curr = tb_r_data;
                if (k>0) begin
                    if (curr < prev) begin
                        $display("ERROR: Sort failed at index %0d. Prev: %0d, Curr: %d", k, prev, curr);
                        $finish;
                    end
                end
                prev = curr;
            end
            $display("\tSuccess: %d items are sorted.", n);
        end
    endtask


    // actual testbench:
    initial begin
        seed = 69420;
        rst = 1;
        start = 0;
        tb_mode = 1;
        tb_we = 0;
        tb_addr = 0;
        tb_w_data = 0;
        num_data_values = 0;
        #10;
        rst = 0;
        #20;


        // Test 1: 32 random values:
        $display("Test 1: 32 random values");
        num_data_values = 32;
        // initialise ram:
        tb_mode = 1;
        for (i=0; i<num_data_values; i=i+1) begin
            w = $random(seed);
            u = i;
            v = i+num_data_values;
            write_ram(i, {w, u[15:0], v[15:0]});
        end
        // run sorter:
        tb_mode = 0;
        start = 1;
        #10;
        start = 0;
        wait(done);
        #20;
        // check results:
        verify_sort(num_data_values);


        rst = 1;
        #20;
        rst = 0;
        #20;

        // Test 2: 20 random values (to check non-powers of 2)
        $display("Test 2: 20 random values");
        num_data_values = 20;
        // initialise ram:
        tb_mode = 1;
        for (i=0; i<num_data_values; i=i+1) begin
            w = $random(seed);
            u = i;
            v = i+num_data_values;
            write_ram(i, {w, u[15:0], v[15:0]});
        end
        // run sorter:
        tb_mode = 0;
        start = 1;
        #10;
        start = 0;
        wait(done);
        #20;
        // check results:
        verify_sort(num_data_values);


        $display("All tests passed.");
        $finish;
    end

endmodule
