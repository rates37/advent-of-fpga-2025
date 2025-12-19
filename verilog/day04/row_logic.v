// purely combinational module to compute next row logic
module row_logic #(
    parameter MAX_COLS = 150,
    parameter LOG2_MAX_COLS = 8
) (
    // 3-row input window (need 3 rows to compute next row)
    input wire [MAX_COLS-1:0] row_prev,
    input wire [MAX_COLS-1:0] row_curr,
    input wire [MAX_COLS-1:0] row_next,

    // number of columns to consider:
    input wire [LOG2_MAX_COLS:0] n_cols,

    // output: which cells in current row are accessible:
    //  i.e., next state of the current row
    output wire [MAX_COLS-1:0] accessible
);

    // for each cell, count neighbours 
    genvar j;
    generate
        for (j=0; j<MAX_COLS; j=j+1) begin : cell_logic
            wire [3:0] neighbour_count;
            wire is_occupied;
            wire in_bounds;

            // check bounds:
            assign in_bounds = (j < n_cols);

            // check if occupied:
            assign is_occupied = row_curr[j] & in_bounds;

            // count the neighbours:
            wire n0, n1, n2, n3, n4, n5, n6, n7;
            /*
                Neighbours are in shape:

                (-1,-1) -> n0 (top left)
                (-1, 0) -> n1 (directly above)
                (-1, 1) -> n2 (top right)
                ( 0,-1) -> n3 (directly left)
                ( 0, 1) -> n4 (directly right)
                ( 1,-1) -> n5 (bottom left)
                ( 1, 0) -> n6 (directly below)
                ( 1, 1) -> n7 (bottom right)
             */
            assign n0 = (j>0) ? row_prev[j-1] : 0;
            assign n1 = row_prev[j];
            assign n2 = (j<MAX_COLS-1) ? row_prev[j+1] : 0;

            assign n3 = (j>0) ? row_curr[j-1] : 0;
            assign n4 = (j<MAX_COLS-1) ? row_curr[j+1] : 0;

            assign n5 = (j>0) ? row_next[j-1] : 0;
            assign n6 = row_next[j];
            assign n7 = (j<MAX_COLS-1) ? row_next[j+1] : 0;

            // sum neighbours:
            assign neighbour_count = n0+n1+n2+n3+n4+n5+n6+n7;
            assign accessible[j] = is_occupied & (neighbour_count < 4);
        end
    endgenerate
endmodule
