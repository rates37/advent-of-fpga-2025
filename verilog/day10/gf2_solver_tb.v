// Tests the 3 cases from the puzzle spec
`timescale 1ns/1ps;

module gf_solver_tb;
    reg clk;
    reg rst;
    reg start;
    reg [9:0] A [0:11];
    reg [9:0] b;
    reg [3:0] m;
    reg [3:0] n;
    wire [7:0] min_cost;
    wire [11:0] solution;
    wire done;

    integer test_num;
    integer total_cost;
    integer expected_total;

    gf2_solver #(
        .MAX_BUTTONS(12),
        .MAX_LIGHTS(10)
    ) u_gf2_solver (
        .clk(clk),
        .rst(rst),
        .start(start),
        .A(A),
        .b(b),
        .m(m),
        .n(n),
        .min_cost(min_cost),
        .solution(solution),
        .done(done)
    );

    // clock gen:
    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end

    // function to run a task:
    task run_test;
        input integer expected_cost;
        input [200*8-1:0] description;
        begin
            test_num = test_num + 1;
            $display("==============");
            $display("Test %0d: %0s", test_num, description);
            $display("Expected cost: %0d", expected_cost);
            $display("==============");
            
            // Start
            start = 1;
            repeat (3) @(posedge clk);
            start = 0;
            
            // Wait for done
            wait(done);
            @(posedge clk);
            
            $display("\tResult: min_cost = %0d", min_cost);
            
            if (min_cost == expected_cost) begin
                $display("\tPassed!");
                total_cost = total_cost + min_cost;
            end else begin
                $display("\tFAIL: expected %0d, got %0d", expected_cost, min_cost);
            end
            
            // Reset for next test
            rst = 1;
            repeat (3) @(posedge clk);
            rst = 0;
            repeat (2) @(posedge clk);
        end

    endtask


    // tests:
    initial begin
        rst = 1;
        start = 0;
        test_num = 0;
        total_cost = 0;
        expected_total = 7;

        repeat(5) @(posedge clk);
        rst = 0;
        repeat (2) @(posedge clk);

        // test 1: [.##.] (3) (1,3) (2) (2,3) (0,2) (0,1)
        m = 4;
        n = 6;
        b = 4'b0110;
        A[0] = 10'b0000001000;
        A[1] = 10'b0000001010;
        A[2] = 10'b0000000100;
        A[3] = 10'b0000001100;
        A[4] = 10'b0000000101;
        A[5] = 10'b0000000011;
        run_test(2, "[.##.] with 6 buttons: (3) (1,3) (2) (2,3) (0,2) (0,1)");

        // test 2: [...#.] (0,2,3,4) (2,3) (0,4) (0,1,2) (1,2,3,4)
        m = 5;
        n = 5;
        b = 5'b01000;
        A[0] = 10'b0000011101;
        A[1] = 10'b0000001100;
        A[2] = 10'b0000010001;
        A[3] = 10'b0000000111;
        A[4] = 10'b0000011110;
        run_test(3, "[...#.] with 5 buttons: (0,2,3,4) (2,3) (0,4) (0,1,2) (1,2,3,4)");

        // test 3: [.###.#] (0,1,2,3,4) (0,3,4) (0,1,2,4,5) (1,2)
        m = 6;
        n = 4;
        b = 6'b101110;
        A[0] = 10'b0000011111;
        A[1] = 10'b0000011001;
        A[2] = 10'b0000110111;
        A[3] = 10'b0000000110;
        run_test(2, "[.###.#] with 4 buttons: (0,1,2,3,4) (0,3,4) (0,1,2,4,5) (1,2)");

        $display("total cost: $0d (expected %0d)", total_cost, expected_total);

        if (total_cost == expected_total) begin
            $display("Final total correct");
        end else begin
            $display("Final total incorrect (FAIL)");
        end

        $finish;
    end
endmodule
