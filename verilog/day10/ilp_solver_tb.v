`timescale 1ns/1ps

module tb_ilp_solver;
    reg clk;
    reg rst;
    reg start;
    reg [9:0] A [0:13];
    reg [8:0] b [0:9];
    reg [3:0] m, n;
    wire [15:0] min_cost;
    wire [7:0] solution [0:13];
    wire done;
    
    integer i;
    integer test_num;
    integer total_cost;
    integer expected_total;
    
    ilp_solver #(
        .MAX_LIGHTS(10),
        .MAX_BUTTONS(14),
        .MAX_JOLTAGE_BITS(9),
        .MAX_PRESS_BITS(8)
    ) u_ilp_solver_0 (
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
            fork
                begin
                    wait(done);
                end
                begin
                    repeat (100000) @(posedge clk);
                    $display("Timed out :(");
                end
            join_any
            
            @(posedge clk);
            

            $display("Result: min_cost = %0d", min_cost);
            $display("Solution:");
            for (i = 0; i < n; i = i + 1) begin
                if (solution[i] > 0)
                    $display("\tx[%0d] = %0d", i, solution[i]);
            end
            
            if (min_cost == expected_cost) begin
                $display("PASS");
                total_cost = total_cost + min_cost;
            end else begin
                $display("FAIL - Expected %0d, got %0d", expected_cost, min_cost);
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
        expected_total = 33;
        
        // Clear arrays
        for (i = 0; i < 14; i = i + 1) A[i] = 0;
        for (i = 0; i < 10; i = i + 1) b[i] = 0;
        
        repeat (5) @(posedge clk);
        rst = 0;
        repeat (2) @(posedge clk);
        
        // Test 1: [.##.] (3) (1,3) (2) (2,3) (0,2) (0,1) {3,5,4,7}
        m = 4;
        n = 6;
        A[0] = 10'b0000001000;
        A[1] = 10'b0000001010;
        A[2] = 10'b0000000100;
        A[3] = 10'b0000001100;
        A[4] = 10'b0000000101;
        A[5] = 10'b0000000011;
        b[0] = 3;
        b[1] = 5;
        b[2] = 4;
        b[3] = 7;
        
        run_test(10, "Sample line 1: [.##.] (3) (1,3) (2) (2,3) (0,2) (0,1) {3,5,4,7}");
        
        // Test 2: [...#.] (0,2,3,4) (2,3) (0,4) (0,1,2) (1,2,3,4) {7,5,12,7,2}
        m = 5;
        n = 5;
        A[0] = 10'b0000011101;
        A[1] = 10'b0000001100;
        A[2] = 10'b0000010001;
        A[3] = 10'b0000000111;
        A[4] = 10'b0000011110;
        b[0] = 7;
        b[1] = 5;
        b[2] = 12;
        b[3] = 7;
        b[4] = 2;
        
        run_test(12, "Sample line 2: [...#.] (0,2,3,4) (2,3) (0,4) (0,1,2) (1,2,3,4) {7,5,12,7,2}");
        
        // Test 3: [.###.#] (0,1,2,3,4) (0,3,4) (0,1,2,4,5) (1,2) {10,11,11,5,10,5}
        m = 6;
        n = 4;
        A[0] = 10'b0000011111;
        A[1] = 10'b0000011001;
        A[2] = 10'b0000110111;
        A[3] = 10'b0000000110;
        b[0] = 10;
        b[1] = 11;
        b[2] = 11;
        b[3] = 5;
        b[4] = 10;
        b[5] = 5;
        
        run_test(11, "Sample line 3: [.###.#] (0,1,2,3,4) (0,3,4) (0,1,2,4,5) (1,2) {10,11,11,5,10,5}");
        
        $display("FINAL RESULTS:");
        $display("Total cost: %0d", total_cost);
        
        if (total_cost == expected_total) begin
            $display("Final total correct");
        end else begin
            $display("Final total incorrect (FAIL)");
        end
        
        $finish;
    end
    
    // Timeout incase infinite loop:
    initial begin
        #50000000;
        $display("\nOVERALL timeout :(");
        $finish;
    end

endmodule
