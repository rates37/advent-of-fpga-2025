// ports are same as gf2_solver, just accepting integers rather than bit lists since now solving over integers
module ilp_solver #(
    parameter MAX_LIGHTS = 10,
    parameter MAX_BUTTONS = 14,
    parameter MAX_JOLTAGE_BITS = 9,
    parameter MAX_PRESS_BITS = 8
) (
    input wire clk,
    input wire rst,
    
    // inputs:
    input wire start,
    input wire [MAX_LIGHTS-1:0] A [0:MAX_BUTTONS-1],
    input wire [MAX_JOLTAGE_BITS-1:0] b [0:MAX_LIGHTS-1],
    input wire [3:0] m,
    input wire [3:0] n,
    
    // outputs
    output reg [15:0] min_cost,
    output reg [MAX_PRESS_BITS-1:0] solution [0:MAX_BUTTONS-1],
    output reg done
);
    //fsm:

    localparam S_IDLE = 0;
    localparam S_INIT = 1;
    localparam S_FIND_PIVOT = 2;
    localparam S_SWAP_WAIT = 3;
    localparam S_ELIMINATE = 4;
    localparam S_ENUM_INIT = 5;
    localparam S_SET_FREE = 6;
    localparam S_BACKSUB_INIT = 7;
    localparam S_BACKSUB_SUM = 8;
    localparam S_BACKSUB_DIV = 9;
    localparam S_CHECK_VALID = 10;
    localparam S_UPDATE_BEST = 11;
    localparam S_ENUM_NEXT = 12;
    localparam S_DONE = 13;
    reg [3:0] state;

    reg signed [15:0] aug_coef [0:MAX_LIGHTS-1][0:MAX_BUTTONS-1];
    reg signed [20:0] aug_rhs [0:MAX_LIGHTS-1];

    // pivot tracking:
    reg signed [4:0] pivot_col [0:MAX_LIGHTS-1];
    reg [MAX_BUTTONS-1:0] is_pivot;

    // free variables
    reg [MAX_PRESS_BITS-1:0] free_val [0:MAX_BUTTONS-1];
    reg [MAX_PRESS_BITS-1:0] max_free [0:MAX_BUTTONS-1];

    // Current solution
    reg signed [20:0] x [0:MAX_BUTTONS-1];
    reg [15:0] current_cost;

    // best solution:
    reg [15:0] best_cost;
    reg [MAX_PRESS_BITS-1:0] best_solution [0:MAX_BUTTONS-1];
    reg found_solution;

    // Processing indices:
    reg [3:0] curr_col;
    reg [3:0] curr_row;
    reg [3:0] elim_row;
    reg [3:0] comp_row;
    reg [3:0] comp_col;
    reg [3:0] pivot_row;
    reg all_valid;

    // Temp for elimination:
    reg signed [15:0] pivot_val;
    reg signed [15:0] factor;
    reg signed [20:0] bsum;
    reg signed [15:0] pivot_coef;
    // Iteration counter (otherwise simulation takes way too long)
    reg [19:0] iter_count;
    localparam MAX_ITERATIONS = 1000000; // 1M iterations
    reg [3:0] found_row;
    integer i;
    integer j;

    always @(posedge clk) begin
        if (rst) begin
            state <= S_IDLE;
            done <= 0;
            min_cost <= 0;
            curr_col <= 0;
            curr_row <= 0;
            is_pivot <= 0;
            found_solution <= 0;
            best_cost <= 16'hFFFF;
            iter_count <= 0;

            for (i=0; i<MAX_BUTTONS; i=i+1) begin
                solution[i] <= 0;
                x[i] <= 0;
                free_val[i] <= 0;
                max_free[i] <= 0;
                best_solution[i] <= 0;
            end

            for (i=0; i<MAX_LIGHTS; i=i+1) begin
                for (j=0; j<MAX_LIGHTS; j=j+1) begin
                    aug_coef[i][j] <= 0;
                end
                aug_rhs[i] <= 0;
                pivot_col[i] <= -1;
            end
        
        end else begin
            case (state)
                S_IDLE: begin
                    if (start) begin
                        state <= S_INIT;
                        done <= 0;
                        found_solution <= 0;
                        best_cost <= 16'hFFFF;
                    end
                end


                S_INIT: begin
                    is_pivot <= 0;

                    for (i=0; i<MAX_LIGHTS; i=i+1) begin
                        pivot_col[i] <= -1;
                        aug_rhs[i] <= 0;
                        for (j=0; j<MAX_BUTTONS; j=j+1) begin
                            aug_coef[i][j] <= 0;
                        end
                        if (i < m) begin
                            for (j=0; j<MAX_BUTTONS; j=j+1) begin
                                if (j < n && A[j][i]) begin
                                    aug_coef[i][j] <= 1;
                                end
                            end
                            aug_rhs[i] <= b[i];
                        end
                    end

                    for (i=0; i<MAX_BUTTONS; i=i+1) begin
                        x[i] <= 0;
                        free_val[i] <= 0;
                    end

                    curr_col <= 0;
                    curr_row <= 0;
                    state <= S_FIND_PIVOT;
                end


                S_FIND_PIVOT: begin
                    if (curr_col >= n || curr_row >= m) begin
                        state <= S_ENUM_INIT;
                    end else begin
                        found_row = m;
                        for (i=0; i<MAX_LIGHTS; i=i+1) begin
                            if (i>=curr_row && i<m && found_row==m) begin
                                if (aug_coef[i][curr_col] == 1) begin
                                    found_row = i;
                                end else if (aug_coef[i][curr_col] != 0) begin
                                    found_row = i;
                                end
                            end
                        end
                        pivot_row <= found_row;
                        state <= S_SWAP_WAIT;
                    end
                end


                S_SWAP_WAIT: begin
                    if (pivot_row >= m) begin
                        curr_col <= curr_col + 1;
                        state <= S_FIND_PIVOT;
                    end else begin
                        // Swap rows
                        if (pivot_row != curr_row) begin
                            for (j=0; j<MAX_BUTTONS; j=j+1) begin
                                aug_coef[curr_row][j] <= aug_coef[pivot_row][j];
                                aug_coef[pivot_row][j] <= aug_coef[curr_row][j];
                            end
                            aug_rhs[curr_row] <= aug_rhs[pivot_row];
                            aug_rhs[pivot_row] <= aug_rhs[curr_row];
                        end

                        pivot_col[curr_row] <= curr_col;
                        is_pivot[curr_col] <= 1;
                        elim_row <= curr_row + 1;
                        state <= S_ELIMINATE;
                    end
                end


                S_ELIMINATE: begin
                    if (elim_row >= m) begin
                        curr_col <= curr_col + 1;
                        curr_row <= curr_row + 1;
                        state <= S_FIND_PIVOT;
                    end else begin
                        if (aug_coef[elim_row][curr_col] != 0) begin
                            pivot_val = aug_coef[curr_row][curr_col];
                            factor = aug_coef[elim_row][curr_col];
                            
                            for (j = 0; j < MAX_BUTTONS; j = j + 1) begin
                                aug_coef[elim_row][j] <= aug_coef[elim_row][j] * pivot_val - aug_coef[curr_row][j] * factor;
                            end
                            aug_rhs[elim_row] <= aug_rhs[elim_row] * pivot_val - aug_rhs[curr_row] * factor;
                        end
                        elim_row <= elim_row + 1;
                    end
                end


                S_ENUM_INIT: begin
                    for (i=0; i<MAX_BUTTONS; i=i+1) begin
                        free_val[i] <= 0;
                        max_free[i] <= 0;
                        if (i<n && !is_pivot[i]) begin
                            for (j=0; j<MAX_LIGHTS; j=j+1) begin
                                if (j < m && A[i][j] && b[j] > max_free[i]) begin
                                    max_free[i] <= b[j][MAX_PRESS_BITS-1:0];
                                end
                            end
                        end
                    end 
                    iter_count <= 0;
                    state <= S_SET_FREE;
                end


                S_SET_FREE: begin
                    for (i=0; i<MAX_BUTTONS; i=i+1) begin
                        if (i<n && !is_pivot[i]) begin
                            x[i] <= free_val[i];
                        end else begin
                            x[i] <= 0;
                        end
                    end
                    comp_row <= m-1;
                    state <= S_BACKSUB_INIT;
                end


                S_BACKSUB_INIT: begin
                    if (comp_row >= m) begin
                        state <= S_CHECK_VALID;
                    end else if (pivot_col[comp_row] < 0) begin
                        if (aug_rhs[comp_row] != 0) begin
                            comp_row <= 0;
                            state <= S_ENUM_NEXT;
                        end else begin
                            comp_row <= comp_row - 1;
                        end
                    end else begin
                        bsum <= aug_rhs[comp_row];
                        pivot_coef <= aug_coef[comp_row][pivot_col[comp_row]];
                        comp_col <= pivot_col[comp_row] + 1;
                        state <= S_BACKSUB_SUM;
                    end
                end


                S_BACKSUB_SUM: begin
                    if (comp_col >= n) begin
                        state <= S_BACKSUB_DIV;
                    end else begin
                        bsum <= bsum - aug_coef[comp_row][comp_col] * x[comp_col];
                        comp_col <= comp_col + 1;
                    end
                end


                S_BACKSUB_DIV: begin
                    if (pivot_coef != 0 && (bsum % pivot_coef) == 0) begin
                        x[pivot_col[comp_row]] <= bsum / pivot_coef;
                        comp_row <= comp_row - 1;
                        state <= S_BACKSUB_INIT;
                    end else begin
                        comp_row <= 0;
                        state <= S_ENUM_NEXT;
                    end
                end


                S_CHECK_VALID: begin
                    all_valid = 1;
                    current_cost = 0;

                    for (i=0; i<MAX_BUTTONS; i=i+1) begin
                        if (i<n) begin
                            if (x[i] < 0) begin
                                all_valid <= 0;
                            end else begin
                                current_cost = current_cost + x[i];
                            end
                        end
                    end

                    if (all_valid && current_cost < best_cost) begin
                        state <= S_UPDATE_BEST;
                    end else begin
                        comp_row <= 0;
                        state <= S_ENUM_NEXT;
                    end
                end


                S_UPDATE_BEST: begin
                    best_cost <= current_cost;
                    found_solution <= 1;
                    for (i=0; i<MAX_BUTTONS; i=i+1) begin
                        best_solution[i] <= x[i][MAX_PRESS_BITS-1:0];
                    end
                    comp_row <= 0;
                    state <= S_ENUM_NEXT;
                end


                S_ENUM_NEXT: begin
                    iter_count <= iter_count + 1;
                    // this is gross and horrible but simulation takes too long otherwise
                    if (comp_row >= n || iter_count >= MAX_ITERATIONS) begin
                        state <= S_DONE;
                    end else begin
                        if (!is_pivot[comp_row]) begin
                            if (free_val[comp_row] < max_free[comp_row]) begin
                                free_val[comp_row] <= free_val[comp_row] + 1;
                                state <= S_SET_FREE;
                            end else begin
                                free_val[comp_row] <= 0;
                                comp_row <= comp_row + 1;
                            end
                        end else begin
                            comp_row <= comp_row + 1;
                        end
                    end
                end


                S_DONE: begin
                    if (found_solution) begin
                        min_cost <= best_cost;
                        for (i=0; i<MAX_BUTTONS; i=i+1) begin
                            solution[i] <= best_solution[i];
                        end
                    end else begin
                        min_cost <= 16'hFFFF;
                    end
                    done <= 1;
                end

                default: begin
                    state <= S_IDLE;
                end
            endcase
        end
    end

endmodule
