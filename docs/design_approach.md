# Design Philosophy

This document outlines the design philosophy undertaken when solving the puzzles
in Verilog (with the goal of synthesising the design onto an Intel/Altera DE10-lite,
as that's a device I have easy access to test with).

## Constraints / Rules:
* Problem must be solved in HDL. Making a processor in HDL and writing a solution in 
    assembly or other higher level languages is not permitted.
* Everything should be synthesisable, or have a proof of concept that it can be made
    synthesisable
* The input.txt for each problem should be provided to the solver 'as is' with little to
    no changes. This means the solver must interpret the ascii itself, and software
    'preprocessing' is forbidden.


## High-Level Design Philosophy

The approach taken for solving these problems is to apply a clearly designed architecture
that cleanly separates responsibilities, while also keeping the modules (somewhat) simple, and
easy to swap between simulation and FPGA hardware.

Each puzzle's input will be provided to solver modules via a simple byte-addressable ROM module, 
that is intended to provide easy simulation, while being easy to drop in a replacement if synthesising
on real hardware. It will store the ASCII values of each input character in the input file. This
style is also used to add the challenge of reading the input, as simply relying on sequential code in 
testbenches skips the important task of reading input in hardware.

To perform this input-processing, my general approach is to have a (synthesisable) 'decoder' module read 
ascii data from the ROM module, and provide clean, decoded input to a 'solver' module. A high-level approach
that most (if not all) of my solutions have is shown below:

![High-level Module Structure](./img/online-problem_structure.png)

<!-- <img src="./img/online-problem_structure.png" alt="High-level Module Structure" width="720"> -->
