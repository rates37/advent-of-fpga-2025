import os
import subprocess
import tempfile
import statistics
import re
from pathlib import Path
from datetime import datetime
import numpy as np
import matplotlib.pyplot as plt
from generate_input import gen_day01, gen_day02, gen_day03
from typing import Callable

CLOCK_CYCLE_RE = re.compile(r"Took\s+(\d+)\s+clock cycles")


def general_benchmark(
    # general function inputs:
    lo: int = 10,
    hi: int = 1000,
    n: int = 10,
    repeats: int = 5,
    timeout: int = 5,
    # day-specific configurations:
    day_dirname: str = "",  # name of the day to be tested in the format dayXX, for example "day01", "day10", ...
    input_generator_function: Callable[[int, str, int], tuple[int, int]]
    | None = None,  # function to generate input file. arguments are [n: int, fname: str, seed: int]
    input_desc: str = "",  # short description of input to include on graph
    day_name: str = "Day X",  # name of day to include as graph title
) -> dict:
    """Generic benchmark function to generalise functionality for all verilog testbenches

    Args:
        lo (int, optional): The smallest input size to benchmark. Defaults to 10.
        hi (int, optional): The largest input size to benchmark. Defaults to 1000.
        n (int, optional): The number of sample points (will be linearly spaced between lo and hi). Defaults to 10.
        repeats (int, optional): Number of trials per input size. Defaults to 5.
        timeout (int, optional): Number of seconds to run each simulation for. Defaults to 5.

    # Todo: write key assumptions / requirements for this function to work
    """
    # validate inputs:
    if not input_generator_function:
        raise ValueError("input file generator function must be provided.")

    # setup:
    sizes = np.linspace(lo, hi, n, dtype=int)
    results = {size: [] for size in sizes}
    root = Path(__file__).resolve().parent
    day_dir = (root / f"../{day_dirname}").resolve()

    # check day_dirname exists
    if not day_dir.exists():
        raise RuntimeError(
            f"{day_dirname} directory was not found. are you running this function from the scripts folder?"
        )

    original_cwd = Path.cwd()

    try:
        os.chdir(day_dir)

        # test all size inputs:
        for size in sizes:
            print(f"doing size {size}")
            # repeat for each trial:
            for trial in range(repeats):
                # use a tempfile to generate input into (avoid clutteringg wd)
                with tempfile.NamedTemporaryFile(
                    mode="w", suffix=".txt", delete=False
                ) as tmp:
                    input_path = Path(tmp.name)

                    # generate input file:
                    expected_results = input_generator_function(
                        n=size, output_filename=str(input_path), seed=trial
                    )

                    # run simulator:
                    try:
                        proc = subprocess.run(
                            ["make", "run", f"INPUT_FILE={input_path}"],
                            capture_output=True,
                            text=True,
                            timeout=timeout,
                        )
                    except subprocess.TimeoutExpired:
                        print(f"\tTrial {trial}: timed out")
                        continue

                    stdout = proc.stdout + proc.stderr

                    # check expected results appear in the simulation output:
                    if (str(expected_results[0]) not in stdout) or (
                        str(expected_results[0]) not in stdout
                    ):
                        raise RuntimeError(
                            f"Incorrect output for size={size}, trial={trial}\n\texpected: {expected_results}\nSimulation output:{stdout}"
                        )

                    # record clock cycles:
                    mat = CLOCK_CYCLE_RE.search(stdout)
                    if not mat:
                        raise RuntimeError(
                            f"Number of clock cycles not found in output for size={size}, trial={trial}\nOutput: {stdout}"
                        )
                    cycles = int(mat.group(1))
                    results[size].append(cycles)

                    # remove temp file:
                    input_path.unlink(missing_ok=True)
    finally:
        os.chdir(original_cwd)

    # save results to file:
    out_dir = root / "benchmarks"
    out_dir.mkdir(exist_ok=True)
    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    csv_path = out_dir / f"{day_dirname}_benchmark_{timestamp}.csv"

    with open(csv_path, "w", encoding="utf-8") as f:
        # header row:
        f.write("input_size,trial,clock_cycles\n")

        # data rows:
        for s, vs in results.items():
            for i, v in enumerate(vs):
                f.write(f"{s},{i + 1},{v}\n")

    print(f"Saved results to {csv_path}")

    # plot results:
    means = []
    stdevs = []
    for s, vs in results.items():
        means.append(statistics.mean(vs))
        stdevs.append(statistics.stdev(vs) if len(vs) > 1 else 0)

    plt.figure(figsize=(8, 5))
    plt.errorbar(sizes, means, yerr=stdevs, fmt="o-", label="Mean clock cycles")
    plt.xlabel(f"Input size ({input_desc})")
    plt.ylabel(f"Total Clock cycles (average of {repeats} per size)")
    plt.title(f"{day_name} Clock cycles vs Input size")
    plt.legend()
    plot_path = out_dir / f"{day_dirname}_benchmark_{timestamp}.png"
    plt.savefig(plot_path, dpi=300)
    plt.close()
    print(f"Saved plot to {plot_path}")

    return results


def benchmark_day01(
    lo: int = 10, hi: int = 1000, n: int = 10, repeats: int = 5, timeout: int = 5
) -> dict:
    return general_benchmark(
        lo,
        hi,
        n,
        repeats,
        timeout,
        day_dirname="day01",
        input_generator_function=gen_day01,
        input_desc="number of rotations in input file",
        day_name="Day 1",
    )


def benchmark_day02(
    lo: int = 10, hi: int = 1000, n: int = 10, repeats: int = 5, timeout: int = 5
) -> dict:
    return general_benchmark(
        lo,
        hi,
        n,
        repeats,
        timeout,
        day_dirname="day02",
        input_generator_function=gen_day02,
        input_desc="number of ranges in input file",
        day_name="Day 2",
    )


def benchmark_day03(
    lo: int = 10, hi: int = 1000, n: int = 10, repeats: int = 5, timeout: int = 5
) -> dict:
    return general_benchmark(
        lo,
        hi,
        n,
        repeats,
        timeout,
        day_dirname="day03",
        input_generator_function=gen_day03,
        input_desc="number of banks",
        day_name="Day 3",
    )


if __name__ == "__main__":
    print(benchmark_day03(lo=10, hi=1000, n=4, repeats=1, timeout=20))
