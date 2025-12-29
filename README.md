# Advent of FPGA 2025

This repo contains my attempts at solving Advent of Code 2025 problems in HDL. All works are my own
unless otherwise stated.

Some ideas for solving puzzles my come from [my attempts at solving these problems in software](https://github.com/rates37/aoc-2025).

# Summary of Results

<!-- todo: table of results -->
---

# How to run:

## Verilog:

<!-- todo: add setup instructions? -->

Uses [iverilog](https://steveicarus.github.io/iverilog/) as a simulator, for simplicity and ease of use. Each subdirectory in the [`verilog`](verilog/) has a Makefile to compile/run the testbench for that specific puzzle. `make run` will run the testbench with the puzzle input from `input.txt`. To change where the input file is read from, use the `INPUT_FILE` argument, a shown in the example below:

```sh
user@machine ~/advent-of-fpga-2025 $ cd ./verilog/day02

user@machine ~/advent-of-fpga-2025/day02 $ make run
iverilog -o day02_tb.out -Pday02_tb.INPUT_DATA_FILENAME=\"input.txt\" day02_tb.v day02_core.v ../utils/rom.v period_summer.v range_summer.v 
vvp day02_tb.out
INFO: Day02 solver started.
Day 2 Complete
Part 1 Result: 40398804950
Part 2 Result: 65794984339
Took 1729 clock cycles
day02_tb.v:90: $finish called at 17385000 (1ps)

user@machine ~/advent-of-fpga-2025/day02 $ make run INPUT_FILE="sample_input.txt"
iverilog -o day02_tb.out -Pday02_tb.INPUT_DATA_FILENAME=\"sample_input.txt\" day02_tb.v day02_core.v ../utils/rom.v period_summer.v range_summer.v 
vvp day02_tb.out
INFO: Day02 solver started.
Day 2 Complete
Part 1 Result: 1227775554
Part 2 Result: 4174379265
Took 561 clock cycles
day02_tb.v:90: $finish called at 5705000 (1ps)
```

As per [the advent of code rules](https://adventofcode.com/2025/about#faq_copying), sharing of actual inputs is not permitted, so feel free to provide your own input text files (these should be formatted in the exact same format as the Advent of Code site provides). However, in my own investigation and benchmarking of my designs, I wrote my own scripts to generate sample inputs of varying sizes. These functions can be found in ['generate_input.py'](/verilog/scripts/generate_input.py).


# Design Approaches / Discussion

## Day 1 Overview:

Day 1's puzzle was about the simulation of a rotary dial with the numbers from 0-99 being rotated left and right, and counting how many times the dial is on zero at the end of a rotation (part 1), as well as how many times the dial head passes zero at any point in the rotation (part 2).

This task very naturally lends itself to a simple FSM that tracks the dial's current position, updating it with each new rotation action that is read in, and incrementing the `part1_result` and `part2_result` accumulator output registers with each rotation. These updates can be calculated in $\mathcal{O}(1)$ time using simple combinational logic / arithmetic.

The general logic flow in my design for day 1 is as follows:

* The decoder module reads the input character by character and converts ASCII into a rotation 'instruction', which is comprised of a single bit to indicate direction, along with a number to indicate how many dial positions to rotate by. 

* When the decoder encounters a newline or end of file, it asserts a `valid_pulse` output flag, which triggers the solver module to update its model of the dial, and the puzzle output registers accordingly.

This means that since the decoder is reading input characters one by one and the solver module can perform each instruction with a single clock cycle, the decoder is the bottleneck of the system. This would suggest that the duration to solve the puzzle scales linearly with the number of input characters / number of rotations in the input file.

There isn't much interesting to discuss for day 1's puzzle due to its simplicity and innate serial nature. I'll use this space to give a brief introduction to the general high-level structure of solutions. Each day generally has the following structure:

<img src="docs/img/online-problem_structure.png" alt="High-level Module Structure" width="720">

For day 1, this structure has been emphasised by the separate modules / files:

* The solver logic is in [`solver.v`](verilog/day01/solver.v)
* The decoder logic is in [`decoder_fsm.v`](verilog/day01/decoder_fsm.v)
* The encapsulating module is in [`day01_core.v`](verilog/day01/day01_core.v)
* The ROM module is in [`rom.v`](verilog/utils/rom.v)
* The testbench is in [`day01_tb.v`](verilog/day01/day01_tb.v)

For future days, often the decoding and solving logic are either able be done in parallel or are more inter-related, and have just been written directly into the encapsulating "core" module.

The `day01_core` module header is shown below (every day's core module has an almost identical header, with only minor differences being in the parameters):

```v
module day01_core #(
    parameter N_ADDR_BITS = 16, // number of bits required to fully address the ROM module (i.e., bits to count number of characters in input file)
    parameter INPUT_DATA_WIDTH = 16,
    parameter OUTPUT_DATA_WIDTH = 16
) (
    // Synchronous inputs:
    input wire clk,
    input wire rst,

    // IO to interface with ROM:
    input wire [7:0] rom_data,
    input wire rom_valid,
    output reg [N_ADDR_BITS:0] rom_addr,

    // results:
    output wire [OUTPUT_DATA_WIDTH-1:0] part1_result,
    output wire [OUTPUT_DATA_WIDTH-1:0] part2_result,
    output reg done
);
```


### Benchmarking and Evaluation

This design's performance was evaluated on various input sizes ranging from 10 to 1000 rotations, using the number of clock cycles as a rudimentary performance benchmark. To run these benchmarks yourself, you can use the `benchmark_day01` function from [`benchmark.py`](verilog/scripts/benchmark.py#L152) (will generate test input files, run the testbench and check that the expected answers are correct, and output a plot like the one seen below, as well as raw csv data from the benchmarks).

<img src="verilog/scripts/benchmarks/day01_benchmark_20251229_172930.png" alt="Plot of clock cycles vs input size" width="720">

As expected, the number of clock cycles required scales linearly with the number of rotations in the input file.


### Scalability, Efficiency, and Architecture

Since all that this module needs to store is the current dial position and the outputs from part 1 and 2, this design will typically use a constant amount of logic/registers.

For inputs where the accumulated results will exceed $2^{16}-1$, the parameter `OUTPUT_DATA_WIDTH` should be increased, which will increase the number of registers used by the solver module. For inputs where the amount rotated by will exceed $2^{16}-1$, the parameter `INPUT_DATA_WIDTH` should be increased, which will increase the number of registers used in the decoder module, as well as the width of the wire that passes rotation amount from the decoder to the solver module. Both of these cases are highly unlikely given the nature of the puzzle.



## Day 2:

Writeup coming soon


## Day 3:

Writeup coming soon


## Day 4:

Writeup coming soon


## Day 5:

Writeup coming soon


## Day 6:

Writeup coming soon


## Day 7:

Writeup coming soon


## Day 8:

Currently unsolved


## Day 9:

Writeup coming soon


## Day 10:

Currently unsolved


## Day 11:

Writeup coming soon


## Day 12:

Currently unsolved





# Usage Notice
This project is open source under the MIT License.
While you are legally allowed to copy and reuse the code, I kindly ask that you
do not take credit for my work, and if you are also competing in [Advent of FPGA](https://blog.janestreet.com/advent-of-fpga-challenge-2025/),
then please uphold the integrity of the competition, by not taking ideas from these
works (at least until the competition submission period has passed).


# FAQs:

### Why Verilog?

I like Verilog for its combination of simplicity and fairly easy to imagine exactly what hardware circuit it might synthesize to. Other HDLs introduce useful abstractions which I definitely appreciate, but I find the comparatively manual nature of 2001 Verilog charming. 

I also taught Verilog through a Digital Systems course at my university for four years in a row which has made me quite familiar with it.


### Why is your Ocaml / Hardcaml weird?
I started learning Ocaml in mid-December 2025, I'm very new to the language so I'm not familiar with the idiomatic way to do things just yet (I'm open to feedback if you have any!).



# Todos / Task List:

- [ ] Finish day 11
- [ ] Finish day 12
- [ ] Day 10
- [ ] Day 8

- [ ] Check todos in completed days to resolve issues, add documentation, etc.
- [ ] Document the hell out of the interesting days (day 2, 3, 5, 6, 9)

- [ ] Attempt days 1-X in Hardcaml
- [ ] Write tons of readme stuff to explain
- [ ] Continue benchmarking completed days
- [ ] Attempt synthesis / running on DE-10 lite or DE1-SoC w/ Quartus

### Low priority / Not sure if can be bothered/possible
- [ ] Move from iverilog to verilator for better simulation speed