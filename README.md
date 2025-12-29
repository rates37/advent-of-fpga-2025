# Advent of FPGA 2025

This repo contains my attempts at solving Advent of Code 2025 problems in HDL. All works are my own
unless otherwise stated (this will be clearly stated in file headers and readmes where possible).

Some ideas for solving puzzles my come from [my attempts at solving these problems in software](https://github.com/rates37/aoc-2025).

# Summary of Results

<!-- todo: table of results -->


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

## Day 1:

Writeup coming soon


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


# Usage Notice
This project is open source under the MIT License.
While you are legally allowed to copy and reuse the code, I kindly ask that you
do not take credit for my work, and if you are also competing in [Advent of FPGA](https://blog.janestreet.com/advent-of-fpga-challenge-2025/),
then please uphold the integrity of the competition, by not taking ideas from these
works (at least until the competition submission period has passed).
