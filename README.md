# Advent of FPGA 2025

This repo contains my attempts at solving Advent of Code 2025 problems in HDL. All works are my own
unless otherwise stated.

Some ideas for solving puzzles my come from [my attempts at solving these problems in software](https://github.com/rates37/aoc-2025).

# Summary of Results

The table below summarises which problems have been successfully solved, the HDL used (Verilog/Hardcaml), and the number of clock cycles used to solve my personal puzzle's input for each day. The 'size' of each puzzle's input has been noted for each day (using my personal puzzle input file). The discussions below often test with various size inputs, not just my personal puzzle inputs. As per [the advent of code rules](https://adventofcode.com/2025/about#faq_copying), sharing of actual inputs is not permitted, so feel free to provide your own input text files (these should be formatted in the exact same format as the Advent of Code site provides). However, in my own investigation and benchmarking of my designs, I wrote my own scripts to generate sample inputs of varying sizes. These functions can be found in [`generate_input.py`](/verilog/scripts/generate_input.py).

| Day | Solved (Verilog/Harcaml/Both)? | Clock Cycles | Input size                                           |
| --- | ------------------------------ | ------------ | ---------------------------------------------------- |
| 1   | Both                           | 19691        | 4780 rotations                                       |
| 2   | Verilog                        | 1729         | 38 ranges                                            |
| 3   | Verilog                        | 20217        | 200 lines (100 chars per line)                       |
| 4   | Verilog                        | 63412        | 137 x 137 grid                                       |
| 5   | Verilog                        | 35614        | 177 ranges, 1000 query IDs                           |
| 6   | Verilog                        | 33157        | 4 numeric rows, 1000 operators, ~3709 chars per line |
| 7   | Verilog                        | 40755        | 142 x 142 grid                                       |
| 8   | Verilog                        | 3342930\*    | 1000 x,y,z coordinates                               |
| 9   | Verilog                        | 129044       | 496 coordinates                                      |
| 10  | Not yet                        |              |                                                      |
| 11  | Verilog                        | 85076        | 583 device names                                     |
| 12  | Not yet                        |              |                                                      |

\* Day 8's solution not guaranteed to produce correct results. However it is overwhelmingly likely to produce correct results on typical puzzle inputs. Refer to the day 8 section below for details.

<!--
Note: day 9 takes a LONG time to run (about 5 minutes on my Macbook Pro) the simulation since simulating the pipeline of 512 segment modules
 -->

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

# Design Approaches / Discussion

## Day 1 Overview:

Day 1's puzzle was about the simulation of a rotary dial with the numbers from 0-99 being rotated left and right, and counting how many times the dial is on zero at the end of a rotation (part 1), as well as how many times the dial head passes zero at any point in the rotation (part 2).

This task very naturally lends itself to a simple FSM that tracks the dial's current position, updating it with each new rotation action that is read in, and incrementing the `part1_result` and `part2_result` accumulator output registers with each rotation. These updates can be calculated in $\mathcal{O}(1)$ time using simple combinational logic / arithmetic.

The general logic flow in my design for day 1 is as follows:

- The decoder module reads the input character by character and converts ASCII into a rotation 'instruction', which is comprised of a single bit to indicate direction, along with a number to indicate how many dial positions to rotate by.

- When the decoder encounters a newline or end of file, it asserts a `valid_pulse` output flag, which triggers the solver module to update its model of the dial, and the puzzle output registers accordingly.

This means that since the decoder is reading input characters one by one and the solver module can perform each instruction with a single clock cycle, the decoder is the bottleneck of the system. This would suggest that the duration to solve the puzzle scales linearly with the number of input characters / number of rotations in the input file.

There isn't much interesting to discuss for day 1's puzzle due to its simplicity and innate serial nature. I'll use this space to give a brief introduction to the general high-level structure of solutions. Each day generally has the following structure:

<p align="center">
<img src="docs/img/online-problem_structure.png" alt="High-level Module Structure" width="720">
</p>

For day 1, this structure has been emphasised by the separate modules / files:

- The solver logic is in [`solver.v`](verilog/day01/solver.v)
- The decoder logic is in [`decoder_fsm.v`](verilog/day01/decoder_fsm.v)
- The encapsulating module is in [`day01_core.v`](verilog/day01/day01_core.v)
- The ROM module is in [`rom.v`](verilog/utils/rom.v)
- The testbench is in [`day01_tb.v`](verilog/day01/day01_tb.v)

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

In the plot below, clock cycles were measured over an average of 5 trials per input size (each trial is a unique randomly generated input with the same number of rotations). Error bars showing stdev are also included.

<p align="center">
<img src="verilog/scripts/benchmarks/day01_benchmark_20251229_172930.png" alt="Plot of clock cycles vs input size" width="720">
</p>

As expected, the number of clock cycles required scales linearly with the number of rotations in the input file.

### Scalability, Efficiency, and Architecture

Since all that this module needs to store is the current dial position and the outputs from part 1 and 2, this design will typically use a constant amount of logic/registers.

For inputs where the accumulated results will exceed $2^{16}-1$, the parameter `OUTPUT_DATA_WIDTH` should be increased, which will increase the number of registers used by the solver module. For inputs where the amount rotated by will exceed $2^{16}-1$, the parameter `INPUT_DATA_WIDTH` should be increased, which will increase the number of registers used in the decoder module, as well as the width of the wire that passes rotation amount from the decoder to the solver module. Both of these cases are highly unlikely given the nature of the puzzle.

### Key Synthesis Metrics:

The design was compiled using Quartus Prime Lite 18.1 with the target device as a 10M50DAF484C7G (the FPGA on the DE10-lite dev board) and produced the following key usage metrics:

| Metric                             | Usage              |
| ---------------------------------- | ------------------ |
| Logic Elements                     | 753 / 49,760 (2%)  |
| Registers                          | 95                 |
| Memory Bits                        | 0 / 1,677,312 (0%) |
| Embedded Multiplier 9-bit elements | 0 / 288 (0%)       |
| Restricted Fmax (Slow 1200mV 85C)  | 20.6 MHz           |

## Day 2:

Day 2's puzzle involved determining the number of 'invalid' numbers in a series of ranges of positive integers. Invalid numbers are defined as follows:

- For part 1: An invalid number is a number with $D$ digits, that is formed by taking a number with $D/2$ digits and repeating it twice. For example, $123123$ is invalid because it can be formed by repeating $123$ twice.

- For part 2: An invalid number is a number with $D$ digits that is formed by repeating a number with $L$ digits (where $L \lt D$) at least twice. For example $121212$ is invalid because it can be formed by repeating $12$ three times.

My approach for this involved reducing this from an iterative programming problem to a simple maths sum. I'll briefly go over the way I arrived at this answer below:

### Journey to solution:

The most straight-forward approach to solving part 1 of this problem might look something like the following:

```
func sum_invalid_in_range(A, B):
    total <- 0
    for x in [A .. B]:
        if first_half(x) == second_half(x):
            total <- total + x
    return x
```

However, this approach is extremely inefficient, since the longer the bounds of the range are, the more valid numbers that will needlessly be inspected.

So rather than iterative over _all_ numbers in the range from $A$ to $B$, we could instead just take the first half of the starting number (call it the "seed"), and check if repeating it twice is less than the upper limit of the range. We can then just increment the first half of the number and continue this process. This way, instead of iterating over all numbers in the range, we are simply iterating over invalid numbers until we exceed the limit of the range. This might look like the following:

```
func sum_invalid_in_range_v2(A, B):
    total <- 0
    current <- first_half(x)
    while current <= B:
        candidate <- repeat_twice(current)
        if A <= candidate  <= B:
            total <- total + candidate
        current <- current + 1
    return total
```

This approach is significantly better, however for large numbers (as ranges in the problem input often cover anywhere the range of 64-bit integers), it still suffers from iteration.

To improve on this, we can make the observation that this sum can be expressed as a scaled arithmetic series. For example, take the range $[123012, 127146]$. The sum of the invalid numbers in this range is the sum: $123123 + 124124 + 125125 + 126126 + 127127$.

While it doesn't look exactly like an arithmetic series, we can express it as the following sum

$$
\begin{align*}
\text{sum} &= &123 &+ &124 &+ &125 &+ &126 &+ &127 &+ \\  &  &123000 &+ &124000 &+ &125000 &+ &126000 &+ &127000 \\
&= &(123 &+ &124 &+ &125 &+ &126 &+ &127) &+ \\  & &1000 ( 123 &+ &124 &+ &125 &+ &126 &+ &127 )
\end{align*}
$$

Which we can re-write as the sum of numbers from $123$ to $127$ (which can be trivially computed as $(123+127)*(127-123+1)/2$) multiplied by $1001$. The multiplier of 1001 is used here, because the numbers in the input range are all length 6, and so to "concatenate" a 3-digit number with itself, we can multiply it by 1001. Different digit lengths would require different multipliers. To put it in a straight-forward (and probably easier-to-read) formula:

$$
\begin{align*} \text{Total Sum} &= \sum_{S=S_{min}}^{S_{max}} (S \times M) \\ &= M \times \sum_{S=S_{min}}^{S_{max}} S \\ &= M \times \frac{(S_{min} + S_{max}) \times Count}{2} \end{align*}
$$

Okay, so now this gives us a $\mathcal{O}(1)$ formula to find the sum of invalid numbers within a given range (using the part 1 definition of invalid numbers), so it's given an $\mathcal{O}(\texttt{num ranges})$ algorithm to solve part 1! Note this assumes all ranges start and end with the same number of digits, if this is not the case, then a range can be decomposed into two or more ranges. For example, the range $[12, 3049]$, we can convert it into three ranges with consistent length of both bounds: $[12-99], [100-999], [1000-3049]$. Since we are dealing with 64-bit integers, the largest number is 20 decimal digits, i.e., the largest possible range will be converted into ten ranges with bounds of equal length.

Great, but part 2 complicates things a little, by allowing any number of repetitions >= 2. This part uses the same core logic as above, but requires careful handling of seeds of different length. I'll start by explaining the general approach, then highlighting the flaw and how my solution overcomes it.

We can easily find multipliers that can "concatenate" a number with itself many times. The multiplier $M$ is a decimal number with 0s in all digit places except those places that are at multiples of $L$ (the length of the seed), where it is 1 (**using zero-indexing of digits**). As an example, to "concatenate" the number 123 with itself three times, we would multiply it by $M = 1001001$.

So, we can simply use seeds of different length from length 1 to half the length of the numbers in the target range. For example, if we are looking at a range $[123456, 753213]$, then we would check seeds of length 1, 2, and 3, since invalid numbers with 6 digits can be formed by any of:

- repeating a 1-digit number 6 times
- repeating a 2-digit number 3 times
- repeating a 3-digit number 2 times

At first glance, it seems like this would work, and produces correct outputs for many ranges, however, it fails to account for the case where an invalid number is included in a sum multiple times because it falls into one or more of these options.

For example, the number 111111 may be:

- generated by the seed 1 being repeated 6 times
- generated by the seed 11 being repeated 3 times
- generated by the seed 111 being repeated 2 times

If we naively sum the results for seeds of length 1,2,3 we will have counted 111111 three times. Instead, we can only check seeds with a length that is a **maximal proper divisor** of the length of the numbers in the target range. This eliminates cases like 12121212 being counted twice by $L=2$ and $L=4$, because 2 is not a maximal proper divisor. However it still doesn't account for the 111111 case, since it would still be counted in $L=2$ and $L=3$ sums.

To account for this, I used an approach similar to that of finding unions of sets. Suppose $A$ is the sum using $L=2$, and $B$ is the sum using $L=3$. We want to find $| A \cup B |$, and to do this, we use the rule: $|A \cup B| = |A| + |B| - |A \cap B|$. So we need to subtract the numbers that lie in both $L=2$ and $L=3$ ranges, because they would otherwise be counted twice. These numbers that lie in the intersection are numbers formed using seeds of length 1. But in general, it's the seeds of length `gcd(2,3)` (`gcd` is the greatest common divisor). So by subtracting the sums using length of the gcd of maximal proper divisors, we can remove this double-counting, and finally arrive at a solution for part 2 that is $\mathcal{O}(1)$ work per range (again with the assumption of using 64-bit integers).

### Implementation of Solution in Hardware

Since this problem has been reduced to effectively the evaluation of a math formula for each range, the implementation side is relatively straight-forward (provided you understand the logic laid out above).

To help with implementation, I first coded up this approach in Python, which can be seen in [my Advent of Code (software) repo](https://github.com/rates37/aoc-2025/blob/main/day02/day02_p2_optimised.py). Rather than manually computing the seed lengths to add and subtract, we can pre-compute these (since there are only 20 different number digit lengths to consider).

My hardware implementation closely aligns with the Python solution linked above. I have:

- A [`period_summer`](verilog/day02/period_summer.v) module, that computes the sum of all $D$-digit numbers in the range $[A, B]$ that are formed by repeating an $L$-digit number, where $D$ and $L$ are inputs to the module.

- A [`range_summer`](verilog/day02/range_summer.v) module, that evaluates a sum for an entire range, performing adding the sums with seeds of length that is a maximal proper divisor, and subtracting the sums with seeds of length that is the gcd of all maximal proper divisors. It then uses a `period_summer` submodule to evaluate each of these sums.

- A [`day02_core`](verilog/day02/day02_core.v) module that encapsulates all solution logic and exposes a similar I/O interface to all other days. This module does the work of decoding input, splitting input ranges (where the lower and upper limits of the range my be of different lengths) into separate ranges where both limits are the same length, and accumulating the results for part 1 and part 2.

### Benchmarking and Evaluation

My day 2 solution was evaluated in a similar manner to day 1. It was similarly evaluated over an average/stdev of 5 runs. Tested with varying the number of input ranges, and those ranges can span the range of 64 bit integers. My puzzle input had 37 ranges to evaluate. The plot below evaluates number of ranges between 10 and 1000 (significantly larger than the real puzzle input).

<p align="center">
<img src="verilog/scripts/benchmarks/day02_benchmark_20251230_010612.png" alt="Plot of clock cycles vs input size" width="720">
</p>

Since the solution I outlined above is $\mathcal{O}(1)$ for each range, we see that the number of clock cycles appears to scale linearly with respect to the number of ranges, and is effectively invariant to the actual numbers that the range spans.

### Scalability, Efficiency, and Architecture

The `period_summer` module takes 5 clock cycles to evaluate a consistent range, and the largest ranges take 3 evaluations of a period to add maximal divisor length sums and subtract gcd length sums, meaning ranges are evaluated in a relatively low number of clock cycles.

There is a possibility for improvement by adding additional `period_summer` submodules to the `range_summer` module, to allow multiple ranges to be processed in parallel. However, given that input is read character-by-character, it is likely that the decoder/parsing stage will quickly become the computation bottleneck. In an effort to save on resource usage, I decided not to add a secondary range summer in my solution, and I decided the module was "efficient enough" and moved on with other days.

### Key Synthesis Metrics:

The design was compiled using Quartus Prime Lite 18.1 with the target device as a 10M50DAF484C7G (the FPGA on the DE10-lite dev board) and produced the following key usage metrics:

| Metric                             | Usage                |
| ---------------------------------- | -------------------- |
| Logic Elements                     | 7,956 / 49,760 (16%) |
| Registers                          | 1353                 |
| Memory Bits                        | 0 / 1,677,312 (0%)   |
| Embedded Multiplier 9-bit elements | 74 / 288 (26%)       |
| Restricted Fmax (Slow 1200mV 85C)  | 13.15 MHz            |

## Day 3:

### Approach Description:

Day three's problem was about selecting batteries from battery banks to achieve a maximum joltage. This puzzle is essentially a task to find the largest increasing subsequences for each row of the input of length 2 (for part 1) and length 12 (for part 2).

A naive approach to solving this (and [the approach I took when initially solving this problem in C++](https://github.com/rates37/aoc-2025/blob/main/day03/day03.cpp)) is to take each row and iterate over it two/twelve times to find the largest increasing subsequence of length 2/12, greedily selecting the largest character found in a given range. Brief pseudocode for this approach is shown below:

```
func get_largest_inc_subseq(s: string, n: integer):
    position <- 1
    total <- 0

    for k in [0 .. n-1]:
        bestChar <- s[pos + 1]
        bestPos <- pos + 1

        // ensure enough characters remain for next loop iteration
        lastIdx <- length(s) - (n-k)

        // scan:
        for i in [pos+1 .. lastIdx]:
            if s[i] > bestChar:
                bestChar <- s[i]
                bestPos <- i

        // add largest character to total and update position:
        total <- total * 10 + int(bestChar)
        pos <- bestPos
    return total
```

However, this approach can be quite inefficient, particularly for long lines, since we are iterating over the same string of characters multiple times. Instead, we can use additional memory to track positions of all seen digits. In pseudocode, this might look like the following:

```
func get_largest_inc_subseq(s: string, n: integer):
    // list of positions where digit d appears:
    posList <- array[10][]

    // single scan to build position lists:
    for i in [1 .. length(s)]:
        d <- int(s[i])
        posList[d].append(i)

    // build output:
    pos <- 0
    total <- 0

    for k in [0 .. n-1]:
        lastIdx <- length(s) - (n-k)

        for d in [9 .. 0]:
            for p in posList[d]:
                if p > pos and p <= lastIdx:
                    total <- total * 10 + d
                    pos <- p
                    go to next iteration of outer loop
    return total
```

This approach sacrifices additional memory to save on the work of scanning the input string multiple times. However in software, this equates to the same amount (if not more) as the original approach.

### Implementation in hardware

Rather than using lists, in hardware, we can use bitmaps and combinational logic to find the next digit to select each iteration much faster.

My approach makes use of 10 position bitmaps to store the input row, where:

- `bitmap[9]` contains a `1` at every index where the digit is a 9
- `bitmap[8]` contains a `1` at every index where the digit is a 8
- ...

For each bitmap from 9 to 0, we can apply a mask to only consider the valid range. If the masked bitmap is not zero, we immediately know that the current digit is the best digit and we don't need to check smaller digits. A priority encoder can then be used to find the first set bit index, so we know how to update the current pos.

This effectively turns a search over a string (may have arbitrary length) into a search over a fixed size 10 possible digits.

Another optimisation made was to use two bitmaps rather than one. This allows the decoder to read in the next line while the current line is being processed, like what is shown in the diagram below.

<p align="center">
<img src="docs/img/day_3_double_buffer_structure.png" alt="Structure of the double buffer approach used in day 3" width="1080">
</p>

This ensures that all logic in the design is being utilised as much as possible, and avoiding data stalls as much as possible.

In retrospect, this design is okay, however the logic depth does get quite extensive, and could likely be improved by introducing additional stages to find the next best digit to select. If I get time before submitting, I'll try and refactor this change.

### Benchmarking and Evaluation

My day 3 solution was evaluated in a similar manner to day 1. It was similarly evaluated over an average/stdev of 5 runs. Tested with varying the number of input ranges, and those ranges can span the range of 64 bit integers. My puzzle input had 37 ranges to evaluate. The plot below evaluates number of ranges between 10 and 1000 (significantly larger than the real puzzle input).

<p align="center">
<img src="verilog/scripts/benchmarks/day03_benchmark_20251230_151221.png" alt="Plot of clock cycles vs input size" width="720">
</p>

As the logic to evaluate a single line takes a constant number of clock cycles, the number of clock cycles used scales approximately linearly with the number of banks (rows) in the input file.

### Scalability

Since the solver only needs to read in 1 (or 2) lines at a time, the number of banks (rows) in the input file can be arbitrarily increased without the design needing to change.

To handle longer input rows (more characters per line), the `MAX_LINE_LEN` parameter in the `day03_core` module can be increased and the logic usage will grow accordingly. My puzzle input only had 100 characters per line and so this was what I tested/benchmarked with. Architecture and efficiency has been discussed above.

### Key Synthesis Metrics:

The design was compiled using Quartus Prime Lite 18.1 with the target device as a 10M50DAF484C7G (the FPGA on the DE10-lite dev board) and produced the following key usage metrics:

| Metric                             | Usage                 |
| ---------------------------------- | --------------------- |
| Logic Elements                     | 10,657 / 49,760 (21%) |
| Registers                          | 2970                  |
| Memory Bits                        | 0 / 1,677,312 (0%)    |
| Embedded Multiplier 9-bit elements | 0 / 288 (0%)          |
| Restricted Fmax (Slow 1200mV 85C)  | 20.61 MHz             |

## Day 4:

Writeup coming soon

### Key Synthesis Metrics:

The design was compiled using Quartus Prime Lite 18.1 with the target device as a 10M50DAF484C7G (the FPGA on the DE10-lite dev board) and produced the following key usage metrics:

| Metric                             | Usage                   |
| ---------------------------------- | ----------------------- |
| Logic Elements                     | 7,641 / 49,760 (15%)    |
| Registers                          | 1271                    |
| Memory Bits                        | 45,000 / 1,677,312 (3%) |
| Embedded Multiplier 9-bit elements | 0 / 288 (0%)            |
| Restricted Fmax (Slow 1200mV 85C)  | 2.55 MHz                |

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

### Why do both Hardcaml and Verilog?

Verilog - for fun

Hardcaml - to learn something new!

# Todos / Task List:

- [ ] Finish day 12 in Verilog
- [ ] Day 10 in Verilog

- [ ] Check todos in completed days to resolve issues, add documentation, etc.
- [ ] Document the hell out of the interesting days:

  - day 5 insertion sort
  - day 8 no requirement for N^2 memory usage, bitonic sort
  - day 9 pipeline to make part 2 N^2 ammortised
  - day 11 CSR graph representation

- [ ] Attempt days 2-X in Hardcaml
- [ ] Write tons of readme stuff to explain
- [ ] Continue benchmarking completed days
