from pathlib import Path
import os


from generate_input import (
    gen_day01,
    gen_day02,
    gen_day03,
    gen_day04,
    gen_day05,
    gen_day06_4_row as gen_day06,
    gen_day07,
    gen_day08,
    gen_day09,
    gen_day11,
)

INPUT_SIZES = {
    1: 4780,  # 4780 rotations
    2: 38,  # 38 ranges
    3: 200,  # 200 lines, random line length between 12 and 100
    4: 137,  # 137 x 137 grid of paper/empty
    5: (177, 1000),  # 177 ranges, 1000 queries
    6: 1000,  # 1000 operators, always 4 rows
    7: 142,  # 142 x 142 grid of tachyon splitters
    8: 1000,  # 1000 xyz coords
    9: 496,  # 496 xy coords
    11: 583,  # 583 device names
}

GENERATORS = {
    1: gen_day01,
    2: gen_day02,
    3: gen_day03,
    4: gen_day04,
    5: gen_day05,
    6: gen_day06,
    7: gen_day07,
    8: gen_day08,
    9: gen_day09,
    11: gen_day11,
}

NAME_IN_OUTPUT_DIR = "input1.txt"


def main() -> None:
    scripts_dir = Path(__file__).resolve().parent
    root_dir = scripts_dir.parent
    results = []

    for day in sorted(GENERATORS.keys()):
        gen_func = GENERATORS[day]
        n = INPUT_SIZES[day]
        seed = sum(ord(c) for c in "Advent of FPGA")

        # set output path:
        day_folder = f"day{day:02d}"
        output_dir = root_dir / day_folder
        output_file = output_dir / NAME_IN_OUTPUT_DIR
        # ensure path exists:
        os.makedirs(output_dir, exist_ok=True)

        try:
            p1, p2 = gen_func(n=n, output_filename=str(output_file), seed=seed)
            results.append((day, p1, p2))
        except Exception as e:
            print(f"Failed to generate input for day {day} with: {e}")

    print("Expected results for generated files:")
    print("| Day | Part 1 Answer | Part 2 Answer |")
    print("| --- | --- | --- |")
    for day, p1, p2 in results:
        print(f"| {day:02d} | {p1} | {p2} |")


if __name__ == "__main__":
    main()
