// uses Row Reduction to get to RREF then iterates over free variables to find min cost
// O(m^2 * n + 2^k) where k = number of free vars
module gf2_solver #(
    parameter MAX_LIGHTS = 10,
    parameter MAX_BUTTONS = 13
) (
    input wire clk,
    input wire rst,

    // input: coefficient matrix (A) and target bit vector (b)
    input wire start,
    input wire [MAX_LIGHTS-1:0] A [0:MAX_BUTTONS-1], // each button A[i] is a bit vector indicating which lights it affects
    input wire [MAX_LIGHTS-1:0] b, // target state of the lights
    input wire [3:0] m, // number of lights (rows)
    input wire [3:0] n, // number of buttons (cols)

    // output:
    output reg [7:0] min_cost,
    output reg [MAX_BUTTONS-1:0] solution,
    output reg done
);

    // fsm:
    localparam S_IDLE = 0;
    localparam S_INIT = 1;
    localparam S_FIND_PIVOT = 2;
    localparam S_SWAP = 3;
    localparam S_SWAP_WAIT = 4;
    localparam S_ELIMINATE = 5;
    localparam S_NEXT_COL = 6;
    localparam S_COMPUTE_X0 = 7;
    localparam S_COMPUTE_BASIS = 8;
    localparam S_ENUM_INIT = 9;
    localparam S_ENUM_CHECK = 10;
    localparam S_ENUM_NEXT = 11;
    localparam S_DONE = 12;
    reg [3:0] state;

    // augmented matrix [A^T | b]:
    reg [MAX_BUTTONS-1:0] aug_coef [0:MAX_LIGHTS-1];
    reg [MAX_LIGHTS-1:0] aug_rhs;

    // pviot tracking:
    reg [3:0] curr_col;
    reg [3:0] curr_row;
    reg [3:0] pivot_row;
    reg [3:0] elim_row;
    // track which column has pivot in which row:
    reg signed [4:0] pivot_col [0:MAX_LIGHTS-1]; // pivot_col[row] = column with pivot (or -1)
    reg [MAX_BUTTONS-1:0] is_pivot; // is_pivot[j] is 1 if col j is a pivot col

    // track free variables:
    reg [3:0] num_free;
    reg [3:0] free_cols [0:MAX_BUTTONS-1];

    // particular sol and basis:
    reg [MAX_BUTTONS-1:0] x0;
    reg [MAX_BUTTONS-1:0] basis [0:MAX_BUTTONS-1];

    reg [MAX_BUTTONS-1:0] enum_mask; // current combination mask up to 2^k
    reg [MAX_BUTTONS-1:0] enum_max;
    reg [MAX_BUTTONS-1:0] curr_x;
    reg [7:0] curr_cost;
    reg [MAX_BUTTONS-1:0] best_sol;
    reg [7:0] best_cost;

    reg is_consistent;
    integer i;
    integer j;
    // temp variables for computation
    reg [3:0] found_row;
    reg [MAX_BUTTONS-1:0] sol;
    reg consistent;
    reg val;
    reg [MAX_BUTTONS-1:0] v;
    reg [3:0] fc;
    reg [MAX_BUTTONS-1:0] x_val;
    reg [7:0] cost;
    reg [MAX_BUTTONS-1:0] row_val;

    always@(posedge clk) begin
        if (rst) begin
            state <= S_IDLE;
            done <= 0;
            min_cost <= 8'hFF;
            solution <= 0;
            curr_col <= 0;
            curr_row <= 0;
            is_pivot <= 0;
            num_free <= 0;
        end else begin
            case (state)
                S_IDLE: begin
                    if (start) begin
                        state <= S_INIT;
                        done <= 0;
                        min_cost <= 8'hFF;
                        solution <= 0;
                    end
                end


                S_INIT: begin
                    // build augmented matrix by transposing A:
                    for (i=0; i<MAX_LIGHTS; i=i+1) begin
                        pivot_col[i] <= -1;
                        if (i<m) begin
                            
                            row_val = 0;
                            for (j=0; j<MAX_BUTTONS; j=j+1) begin
                                if (j<n) begin
                                    row_val[j] = A[j][i];
                                end
                            end
                            aug_coef[i] <= row_val;
                        end else begin
                            aug_coef[i] <= 0;
                        end
                    end
                    aug_rhs <= b;
                    curr_col <= 0;
                    curr_row <= 0;
                    is_pivot <= 0;
                    num_free <= 0;
                    state <= S_FIND_PIVOT;
                end


                S_FIND_PIVOT: begin
                    if (curr_col >= n) begin
                        // finished all cols, move to solution extraction
                        state <= S_COMPUTE_X0;
                    end else if (curr_row >= m) begin
                        // no more rows available so this col (and all following) are free
                        free_cols[num_free] <= curr_col;
                        num_free <= num_free + 1;
                        curr_col <= curr_col + 1;

                        // stay in this state to process remaining cols
                    end else begin
                        found_row = m;
                        for (i=0; i<MAX_LIGHTS; i=i+1) begin
                            if (i >= curr_row && i<m && found_row == m) begin
                                if (aug_coef[i][curr_col]) begin
                                    found_row = i; // find first one
                                end
                            end
                        end
                        pivot_row <= found_row;

                        if (found_row == m) begin
                            // no pivot found in this col so it is a free col
                            free_cols[num_free] <= curr_col;
                            num_free <= num_free + 1;
                            curr_col <= curr_col + 1;
                        end else begin
                            state <= S_SWAP;
                        end 
                    end

                end


                S_SWAP: begin
                    if (pivot_row != curr_row) begin
                        aug_coef[curr_row] <= aug_coef[pivot_row];
                        aug_coef[pivot_row] <= aug_coef[curr_row];

                        aug_rhs[curr_row] <= aug_rhs[pivot_row];
                        aug_rhs[pivot_row] <= aug_rhs[curr_row];
                    end

                    pivot_col[curr_row] <= curr_col;
                    is_pivot[curr_col] <= 1;
                    state <= S_SWAP_WAIT;
                end


                S_SWAP_WAIT: begin
                    elim_row <= 0;
                    state <= S_ELIMINATE;
                end


                S_ELIMINATE: begin
                    if (elim_row >= m) begin
                        state <= S_NEXT_COL;
                    end else begin
                        if (elim_row != curr_row && aug_coef[elim_row][curr_col]) begin
                            aug_coef[elim_row] <= aug_coef[elim_row] ^ aug_coef[curr_row];
                            aug_rhs[elim_row] <= aug_rhs[elim_row] ^ aug_rhs[curr_row];
                        end
                        elim_row <= elim_row + 1;
                    end
                end


                S_NEXT_COL: begin
                    curr_col <= curr_col + 1;
                    curr_row <= curr_row + 1;
                    state <= S_FIND_PIVOT;
                end


                S_COMPUTE_X0: begin
                    sol = 0;
                    consistent = 1;

                    for (i=0; i<MAX_LIGHTS; i=i+1) begin
                        if (i<m) begin
                            if (pivot_col[i] >= 0) begin
                                sol[pivot_col[i]] = aug_rhs[i];
                            end else begin
                                if (aug_rhs[i]) begin
                                    consistent = 0;
                                end
                            end
                        end
                    end

                    x0 <= sol;
                    is_consistent <= consistent;

                    if (!consistent) begin
                        min_cost <= 8'hFF;
                        solution <= 0;
                        state <= S_DONE;
                    end else begin
                        state <= S_COMPUTE_BASIS;
                    end
                end


                S_COMPUTE_BASIS: begin
                    // compute basis vectors for each free variable
                    // basis[idx][fc] =1, basis[idx][pc] = R[row_of_pc][fc]
                    for (i=0; i<MAX_BUTTONS; i=i+1) begin
                        v = 0;
                        if (i < num_free) begin
                            v = 0;
                            fc = free_cols[i];
                            v[fc] = 1;

                            for (j=0; j<MAX_LIGHTS; j=j+1) begin
                                if (j<m && pivot_col[j]>=0) begin
                                    if (aug_coef[j][fc]) begin
                                        v[pivot_col[j]] = 1;
                                    end
                                end
                            end
                        end
                        basis[i] <= v;
                    end
                    state <= S_ENUM_INIT;
                end


                S_ENUM_INIT: begin
                    enum_mask <= 0;
                    enum_max <= (1<<num_free) - 1;
                    best_cost <= 8'hFF;
                    best_sol <= 0;
                    state <= S_ENUM_CHECK;
                end


                S_ENUM_CHECK: begin
                    // compute x = x0 XOR (basis vectors)
                    x_val = x0;

                    for (i=0; i<MAX_BUTTONS; i=i+1) begin
                        if (i<num_free && enum_mask[i]) begin
                            x_val = x_val ^ basis[i];
                        end
                    end

                    cost = 0;
                    for (i=0; i<MAX_BUTTONS; i=i+1) begin
                        if (i<n && x_val[i]) begin
                            cost = cost+1;
                        end
                    end

                    curr_x <= x_val;
                    curr_cost <= cost;

                    if (cost < best_cost) begin
                        best_sol <= x_val;
                        best_cost <= cost;
                    end

                    state <= S_ENUM_NEXT;
                end


                S_ENUM_NEXT: begin
                    if (enum_mask >= enum_max) begin
                        min_cost <= best_cost;
                        solution <= best_sol;
                        state <= S_DONE;
                    end else begin
                        enum_mask <= enum_mask + 1;
                        state <= S_ENUM_CHECK;
                    end
                end


                S_DONE: begin
                    done <= 1;
                end

                default: begin
                    state <= S_IDLE;
                end

            endcase
        end
    end


endmodule
