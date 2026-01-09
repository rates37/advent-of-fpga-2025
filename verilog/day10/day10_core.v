module day10_core #(
    parameter N_ADDR_BITS = 16,
    parameter MAX_LIGHTS = 10,
    parameter MAX_BUTTONS = 13
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
    // fsm:
    localparam S_IDLE = 0;
    localparam S_START_PARSE = 1;
    localparam S_WAIT_PARSE = 2;
    localparam S_RESET_SOLVERS = 3;
    localparam S_START_SOLVE = 4;
    localparam S_WAIT_SOLVE = 5;
    localparam S_ACCUMULATE = 6;
    localparam S_DONE = 7;
    reg [2:0] state;
    reg [31:0] line_count;
    reg [63:0] part1_total;
    reg [63:0] part2_total;
    reg [2:0] reset_wait;

    // parser signals:
    reg parser_start;
    wire parser_done_line;
    wire [MAX_LIGHTS-1:0] lights_target;
    wire [MAX_LIGHTS-1:0] button_matrix [0:MAX_BUTTONS-1];
    wire [8:0] joltage_target [0:MAX_LIGHTS-1];
    wire [3:0] n_lights;
    wire [3:0] n_buttons;
    wire parse_error;

    parser #(
        .MAX_LIGHTS(MAX_LIGHTS),
        .MAX_BUTTONS(MAX_BUTTONS),
        .MAX_JOLTAGE_BITS(9),
        .N_ADDR_BITS(N_ADDR_BITS)
    ) u_parser_0 (
        .clk(clk),
        .rst(rst),
        .start(parser_start),
        .done_line(parser_done_line),
        .rom_data(rom_data),
        .rom_valid(rom_valid),
        .rom_addr(rom_addr),
        .lights_target(lights_target),
        .button_matrix(button_matrix),
        .joltage_target(joltage_target),
        .n_lights(n_lights),
        .n_buttons(n_buttons),
        .parse_error(parse_error)
    );

    // gf2 solver signals:
    reg gf2_start;
    reg gf2_rst;
    wire [7:0] gf2_min_cost;
    wire gf2_done;
    gf2_solver #(
        .MAX_LIGHTS(MAX_LIGHTS),
        .MAX_BUTTONS(MAX_BUTTONS)
    ) u_gf2_solver_0 (
        .clk(clk),
        .rst(gf2_rst),
        .start(gf2_start),
        .A(button_matrix),
        .b(lights_target),
        .m(n_lights),
        .n(n_buttons),
        .min_cost(gf2_min_cost),
        .done(gf2_done)
    );

    // ilp solver signals:
    reg ilp_start;
    reg ilp_rst;
    wire [15:0] ilp_min_cost;
    wire ilp_done;

    ilp_solver #(
        .MAX_LIGHTS(MAX_LIGHTS),
        .MAX_BUTTONS(MAX_BUTTONS),
        .MAX_JOLTAGE_BITS(9),
        .MAX_PRESS_BITS(8)
    ) u_ilp_solver_0 (
        .clk(clk),
        .rst(ilp_rst),
        .start(ilp_start),
        .A(button_matrix),
        .b(joltage_target),
        .m(n_lights),
        .n(n_buttons),
        .min_cost(ilp_min_cost),
        .done(ilp_done)
    );

    always @(posedge clk) begin
        if (rst) begin
            state <= S_IDLE;
            parser_start <= 0;
            gf2_start <= 0;
            ilp_start <= 0;
            gf2_rst <= 1;
            ilp_rst <= 1;
            part1_total <= 0;
            part2_total <= 0;
            done <= 0;
            line_count <= 0;
            reset_wait <= 0;

        end else begin
            case (state)
                S_IDLE: begin
                    parser_start <= 1;
                    state <= S_START_PARSE;
                end

                
                S_START_PARSE: begin
                    $display("Parsed %0d lines", line_count);
                    parser_start <= 0;
                    state <= S_WAIT_PARSE;
                end

                
                S_WAIT_PARSE: begin
                    if (parser_done_line) begin
                        // wait for parser to finish reading a line
                        if (parse_error) begin
                            // eof -> finished
                            state <= S_DONE;
                        end else begin
                            gf2_rst <= 1;
                            ilp_rst <= 1;
                            reset_wait <= 0;
                            state <= S_RESET_SOLVERS;
                        end
                    end
                end

                
                S_RESET_SOLVERS: begin
                    // hold for a few cycles, not necessary but running into timing issues and running out of time :') 
                    reset_wait <= reset_wait + 1;
                    if (reset_wait >= 3) begin
                        gf2_rst <= 0;
                        ilp_rst <= 0;
                        state <= S_START_SOLVE;
                    end 
                end

                
                S_START_SOLVE: begin
                    gf2_start <= 1;
                    ilp_start <= 1;
                    state <= S_WAIT_SOLVE;
                    
                end

                
                S_WAIT_SOLVE: begin
                    gf2_start <= 0;
                    ilp_start <= 0;
                    if (gf2_done && ilp_done) begin
                        state <= S_ACCUMULATE;
                    end
                end

                
                S_ACCUMULATE: begin
                    part1_total <= part1_total + gf2_min_cost;
                    part2_total <= part2_total + ilp_min_cost;
                    line_count <= line_count + 1;

                    parser_start <= 1;
                    state <= S_START_PARSE;
                end

                
                S_DONE: begin
                    if (!done) begin
                        part1_result <= part1_total;
                        part2_result <= part2_total;
                        done <= 1;
                    end
                end

                default: begin
                    state <= S_IDLE;
                end
            endcase
        end
    end

endmodule


module parser #(
    parameter MAX_LIGHTS = 10,
    parameter MAX_BUTTONS = 13,
    parameter MAX_JOLTAGE_BITS = 9,
    parameter N_ADDR_BITS = 16
)  (
    input wire clk,
    input wire rst,
    
    // control:
    input wire start, // tells to start parsing a single line
    output reg done_line,

    // rom interface:
    input wire [7:0] rom_data,
    input wire rom_valid,
    output reg [N_ADDR_BITS:0] rom_addr,
        
    // Outputs
    output reg [MAX_LIGHTS-1:0] lights_target, // part 1 target
    output reg [MAX_LIGHTS-1:0] button_matrix [0:MAX_BUTTONS-1],  // Button->Light mapping
    output reg [MAX_JOLTAGE_BITS-1:0] joltage_target [0:MAX_LIGHTS-1], // Part 2 target (integer)
    output reg [3:0] n_lights,
    output reg [3:0] n_buttons,
    output reg parse_error
);

    // parsing states
    localparam S_IDLE = 0;
    localparam S_WAIT_ROM = 1;
    localparam S_PARSE_LIGHTS = 2;
    localparam S_WAIT_PAREN_OPEN = 3;
    localparam S_PARSE_BUTTON = 4;
    localparam S_PARSE_JOLTAGE = 5;
    localparam S_DONE = 6;
    localparam S_ERROR = 7;
    reg [2:0] state;

    reg [3:0] light_idx;
    reg [3:0] button_idx;
    reg [3:0] joltage_idx;
    reg [3:0] button_light_idx;
    reg [MAX_JOLTAGE_BITS-1:0] num_acc;
    reg parsing_number;

    wire is_digit = (rom_data  >= "0") && (rom_data <= "9");
    wire [3:0] digit_val = rom_data[3:0];
    integer i;
    reg waited;

    always @(posedge clk) begin
        if (rst) begin
            state <= S_IDLE;
            done_line <= 0;
            rom_addr <= 0;
            n_lights <= 0;
            n_buttons <= 0;
            light_idx <= 0;
            button_idx <= 0;
            joltage_idx <= 0;
            button_light_idx <= 0;
            num_acc <= 0;
            parsing_number <= 0;
            lights_target <= 0;
            waited <= 0;
            parse_error <= 0;

            for (i=0; i<MAX_BUTTONS; i=i+1) begin
                button_matrix[i] <= 0;
            end

            for (i=0; i<MAX_LIGHTS; i=i+1) begin
                joltage_target[i] <= 0;
            end

        end else begin
            case (state) 
                S_IDLE: begin
                    if (start) begin
                        done_line <= 0;
                        n_lights <= 0;
                        n_buttons <= 0;
                        light_idx <= 0;
                        button_idx <= 4'd0;
                        joltage_idx <= 4'd0;
                        button_light_idx <= 4'd0;
                        num_acc <= 0;
                        parsing_number <= 1'b0;
                        lights_target <= 10'd0;
                        waited <= 0;
                        parse_error <= 0;
                        for (i=0; i<MAX_BUTTONS; i=i+1) begin
                            button_matrix[i] <= 0;
                        end

                        for (i=0; i<MAX_LIGHTS; i=i+1) begin
                            joltage_target[i] <= 0;
                        end
                        state <= S_WAIT_ROM;
                    end
                end

                S_WAIT_ROM: begin
                    // wait additional cycle to load from ROM (shouldn't be necessary but running into a timing issue somewhere)
                    waited <= ~waited;
                    if (waited) begin
                        waited <= 0;

                        // check EOF:
                        if (!rom_valid || rom_data == 0) begin
                            state <= S_DONE;
                            parse_error <= 1;
                        end else if (rom_data == "[") begin
                            state <= S_PARSE_LIGHTS;
                            rom_addr <= rom_addr + 1;
                        end else begin
                            rom_addr <= rom_addr + 1;
                        end
                    end
                end


                S_PARSE_LIGHTS: begin
                    waited <= ~waited;
                    if (waited) begin
                        waited <= 0;
                        
                        if (rom_data == ".") begin
                            lights_target[light_idx] <= 0;
                            light_idx <= light_idx + 1;
                            rom_addr <= rom_addr + 1;
                        end else if (rom_data == "#") begin
                            lights_target[light_idx] <= 1;
                            light_idx <= light_idx + 1;
                            rom_addr <= rom_addr + 1;
                        end else if (rom_data == "]") begin
                            n_lights <= light_idx;
                            rom_addr <= rom_addr + 1;
                            state <= S_WAIT_PAREN_OPEN;
                        end else begin
                            state <= S_ERROR;
                        end
                    end
                end


                S_WAIT_PAREN_OPEN: begin
                    // try to parse the next button (starts with a '(' )
                    waited <= ~waited;
                    if (waited) begin
                        waited <= 0;

                        if (rom_data == "(") begin
                            button_light_idx <= 0;
                            num_acc <= 0;
                            parsing_number <= 1'b0;
                            rom_addr <= rom_addr + 1;
                            state <= S_PARSE_BUTTON;
                        end else if (rom_data == "{") begin
                            num_acc <= 0;
                            parsing_number <= 0;
                            rom_addr <= rom_addr + 1;
                            state <= S_PARSE_JOLTAGE;
                        end else begin
                            // ignore other chars
                            rom_addr <= rom_addr + 1;
                        end
                    end
                end


                S_PARSE_BUTTON: begin
                    waited <= ~waited;
                    if (waited) begin
                        waited <= 0;

                        if (is_digit) begin
                            num_acc <= (num_acc << 3) + (num_acc << 1) + digit_val;
                            parsing_number <= 1'b1;
                            rom_addr <= rom_addr + 1;
                        end else if (rom_data == ",") begin
                            if (parsing_number) begin
                                button_matrix[button_idx][num_acc[3:0]] <= 1'b1;
                                button_light_idx <= button_light_idx + 1;
                                num_acc <= 0;
                                parsing_number <= 1'b0;
                            end
                            rom_addr <= rom_addr + 1;
                        end else if (rom_data == ")") begin
                            if (parsing_number) begin
                                button_matrix[button_idx][num_acc[3:0]] <= 1;
                                button_light_idx <= button_light_idx + 1;
                            end
                            button_idx <= button_idx + 1;
                            rom_addr <= rom_addr + 1;
                            state <= S_WAIT_PAREN_OPEN;
                        end else begin
                            rom_addr <= rom_addr + 1;
                        end
                    end
                end


                S_PARSE_JOLTAGE: begin
                    waited <= ~waited;
                    if (waited) begin
                        waited <= 0;

                        if (is_digit) begin
                            num_acc <= (num_acc << 3) + (num_acc << 1) + digit_val;
                            parsing_number <= 1'b1;
                            rom_addr <= rom_addr + 1;
                        end else if (rom_data == ",") begin
                            if (parsing_number) begin
                                joltage_target[joltage_idx] <= num_acc;
                                joltage_idx <= joltage_idx + 1;
                                num_acc <= 0;
                                parsing_number <= 1'b0;
                            end
                            rom_addr <= rom_addr + 1;
                        end else if (rom_data == "}") begin
                            if (parsing_number) begin
                                joltage_target[joltage_idx] <= num_acc;
                                joltage_idx <= joltage_idx + 1;
                            end
                            n_buttons <= button_idx;
                            rom_addr <= rom_addr + 1;
                            state <= S_DONE;
                        end else begin
                            rom_addr <= rom_addr + 1;
                        end
                    end
                end


                S_DONE: begin
                    done_line <= 1;
                    state <= S_IDLE;
                end

                S_ERROR: begin
                    done_line <= 1;
                    state <= S_IDLE;
                    parse_error <= 1;
                end
                
                default: begin
                    state <= S_IDLE;
                end
            endcase
        end
    end

endmodule
