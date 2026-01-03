import os
import subprocess
import itertools
import tempfile
import statistics
import re
from pathlib import Path
from datetime import datetime
import numpy as np
import matplotlib.pyplot as plt
from generate_input import (
    gen_day01,
    gen_day02,
    gen_day03,
    gen_day04,
    gen_day07,
    gen_day05,
)
from generate_input import gen_day06_4_row as gen_day06
from typing import Callable, Any, Sequence

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
        raise RuntimeError(f"{day_dirname} directory was not found at {day_dir}")

    original_cwd = Path.cwd()

    try:
        os.chdir(day_dir)

        # test all size inputs:
        for size in sizes:
            print(f"\t{day_name}: Running tests for size = {size}")
            # repeat for each trial:
            for trial in range(repeats):
                print(f"\t\trunning trial {trial + 1}")
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


# similar version of the function above but to sweep across parameters
def benchmark_sweep(
    day_dirname: str,
    day_name: str,
    input_generator_function: Callable[..., Any],
    # parameter sweep dict, e.g, {'num_ranges': [10, 50, 100], 'num_queries': [100, 1000]}
    param_grid: dict[str, Sequence[int]],
    # adapter to convert param dict to generator's expected input argument
    # e.g., lambda p: (p['num_ranges'], p['num_queries'])
    arg_adapter: Callable[[dict[str, int]], Any] = lambda p: list(p.values())[0],
    repeats: int = 5,
    timeout: int = 5,
) -> dict:
    root = Path(__file__).resolve().parent
    day_dir = (root / f"../{day_dirname}").resolve()

    if not day_dir.exists():
        raise RuntimeError(f"Directory not found: {day_dir}")

    # Generate all combinations of parameters
    param_names = list(param_grid.keys())
    param_values = list(param_grid.values())
    # Create a list of dicts, e.g., [{'x': 10, 'y': 5}, {'x': 10, 'y': 10}, and so on]
    sweep_configs = [
        dict(zip(param_names, v)) for v in itertools.product(*param_values)
    ]

    results = []

    original_cwd = Path.cwd()
    out_dir = root / "benchmarks"
    out_dir.mkdir(exist_ok=True)
    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")

    try:
        os.chdir(day_dir)
        print(f"Benchmarking {day_name}")
        print(f"Sweeping over parameters: {param_names}")

        for config in sweep_configs:
            config_str = ", ".join([f"{k}={v}" for k, v in config.items()])
            print(f"\tTesting: {config_str}")
            gen_arg = arg_adapter(config)

            trial_cycles = []

            for t in range(repeats):
                with tempfile.NamedTemporaryFile(
                    mode="w", suffix=".txt", delete=False
                ) as tmp:
                    input_path = Path(tmp.name)
                    try:
                        expected = input_generator_function(
                            n=gen_arg, output_filename=str(input_path), seed=t
                        )

                        proc = subprocess.run(
                            ["make", "run", f"INPUT_FILE={input_path}"],
                            capture_output=True,
                            text=True,
                            timeout=timeout,
                        )
                        stdout = proc.stdout + proc.stderr

                        if expected and (str(expected[0]) not in stdout):
                            print(f"\t\tTrial {t}: Output mismatch (Warning)")
                        match = CLOCK_CYCLE_RE.search(stdout)
                        if match:
                            trial_cycles.append(int(match.group(1)))
                        else:
                            print(f"\t\tTrial {t}: No clock cycles found")
                    except subprocess.TimeoutExpired:
                        print(f"\t\tTrial {t}: Timed out")
                    except Exception as e:
                        print(f"\t\tTrial {t}: Error {e}")
                    finally:
                        input_path.unlink(missing_ok=True)
            if trial_cycles:
                avg_cycles = statistics.mean(trial_cycles)
                std_cycles = (
                    statistics.stdev(trial_cycles) if len(trial_cycles) > 1 else 0
                )

                record = config.copy()
                record["mean_cycles"] = avg_cycles
                record["stdev_cycles"] = std_cycles
                results.append(record)
            else:
                print(f"\t\tSkipping {config_str} due to failures.")

    finally:
        os.chdir(original_cwd)

    # save results
    if not results:
        print("NO results collected")
        return {}

    csv_path = out_dir / f"{day_dirname}_benchmark_{timestamp}.csv"
    keys = list(results[0].keys())

    with open(csv_path, "w") as f:
        f.write(",".join(keys) + "\n")
        for r in results:
            f.write(",".join(str(r[k]) for k in keys) + "\n")
    print(f"Saved CSV to {csv_path}")

    # visualise:
    visualise_results(results, param_names, day_name, out_dir, day_dirname, timestamp)
    return results


def visualise_results(
    results: list[dict],
    param_names: list[str],
    day_name: str,
    out_dir: Path,
    file_prefix: str,
    timestamp: str,
):
    if len(param_names) == 1:
        # 1D Plot (just line plot)
        p1 = param_names[0]
        # sort results to ensure correct plotting order
        results.sort(key=lambda r: r[p1])

        x_vals = [r[p1] for r in results]
        y_vals = [r["mean_cycles"] for r in results]
        y_errs = [r["stdev_cycles"] for r in results]

        plt.figure(figsize=(8, 5))
        plt.errorbar(
            x_vals, y_vals, yerr=y_errs, fmt="o-", capsize=5, linewidth=2, markersize=6
        )
        plt.xlabel(p1.replace("_", " ").title(), fontsize=12)
        plt.ylabel("Clock Cycles", fontsize=12)
        plt.title(f"{day_name}: Performance vs {p1}", fontsize=14)
        plt.grid(True, alpha=0.3, linestyle="--")

        plot_path = out_dir / f"{file_prefix}_plot_{timestamp}.png"
        plt.savefig(plot_path, dpi=300, bbox_inches="tight")
        plt.close()
        print(f"Saved 1D plot to {plot_path}")

    elif len(param_names) == 2:
        # 2D Analysis - multiline plots to see behaviour of each parameter type
        p1, p2 = param_names[0], param_names[1]

        # View 1: p1 on x-axis
        out_path1 = out_dir / f"{file_prefix}_vary_{p1}_{timestamp}.png"
        _plot_multiline_view(
            results, x_param=p1, line_param=p2, day_name=day_name, out_path=out_path1
        )

        # View 2: p2 on x-axis
        out_path2 = out_dir / f"{file_prefix}_vary_{p2}_{timestamp}.png"
        _plot_multiline_view(
            results, x_param=p2, line_param=p1, day_name=day_name, out_path=out_path2
        )

    else:
        print(
            f"Visualization currently only supports 1 or 2 variables (found {len(param_names)})."
        )


def _plot_multiline_view(
    results: list[dict], x_param: str, line_param: str, day_name: str, out_path: Path
):
    # Helper function to generate a multiline plot.
    # Find unique values for the parameter that defines the separate lines
    unique_line_vals = sorted(list(set(r[line_param] for r in results)))
    plt.figure(figsize=(10, 6))

    # Use colormap to ensure distinct colors
    colors = plt.cm.viridis(np.linspace(0, 0.9, len(unique_line_vals)))

    for i, line_val in enumerate(unique_line_vals):
        # Filter data for this line
        subset = [r for r in results if r[line_param] == line_val]
        # sort by the x parameter
        subset.sort(key=lambda r: r[x_param])

        x_vals = [r[x_param] for r in subset]
        y_vals = [r["mean_cycles"] for r in subset]
        err_vals = [r["stdev_cycles"] for r in subset]

        # Format label nicer
        label_str = f"{line_param.replace('_', ' ').title()}: {line_val}"

        plt.errorbar(
            x_vals,
            y_vals,
            yerr=err_vals,
            fmt="o-",
            label=label_str,
            capsize=3,
            color=colors[i],
            alpha=0.8,
        )

    # Formatting
    plt.xlabel(x_param.replace("_", " ").title(), fontsize=12)
    plt.ylabel("Clock Cycles (Mean ± Std Dev)", fontsize=12)
    plt.title(f"{day_name}\nVarying {x_param} (grouped by {line_param})", fontsize=14)

    # Place legend outside if there are many items, otherwise inside top-left
    if len(unique_line_vals) > 5:
        plt.legend(
            bbox_to_anchor=(1.05, 1),
            loc="upper left",
            title=line_param.replace("_", " ").title(),
        )
    else:
        plt.legend(loc="best")

    plt.grid(True, alpha=0.3, linestyle="--")
    plt.tight_layout()

    plt.savefig(out_path, dpi=300, bbox_inches="tight")
    plt.close()
    print(f"Saved 2D multiline view to {out_path}")


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
    lo: int = 10, hi: int = 1000, n: int = 10, repeats: int = 5, timeout: int = 20
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


def benchmark_day04(
    lo: int = 10, hi: int = 1000, n: int = 10, repeats: int = 5, timeout: int = 20
) -> dict:
    return general_benchmark(
        lo,
        hi,
        n,
        repeats,
        timeout,
        day_dirname="day04",
        input_generator_function=gen_day04,
        input_desc="dimension of grid",
        day_name="Day 4",
    )


def benchmark_day05(
    num_ranges_lo: int = 10,
    num_ranges_hi: int = 200,
    num_ranges_count: int = 5,
    num_queries_lo: int = 100,
    num_queries_hi: int = 1000,
    num_queries_count: int = 5,
    repeats: int = 5,
    timeout: int = 5,
) -> dict:
    range_sizes = np.linspace(
        num_ranges_lo, num_ranges_hi, num_ranges_count, dtype=int
    ).tolist()
    queries_sizes = np.linspace(
        num_queries_lo, num_queries_hi, num_queries_count, dtype=int
    ).tolist()

    return benchmark_sweep(
        day_dirname="day05_optimised",
        day_name="Day 5",
        input_generator_function=gen_day05,
        param_grid={"num_ranges": range_sizes, "num_queries": queries_sizes},
        arg_adapter=lambda p: (p["num_ranges"], p["num_queries"]),
        repeats=repeats,
        timeout=timeout,
    )


def benchmark_day06(
    lo: int = 10, hi: int = 1000, n: int = 10, repeats: int = 5, timeout: int = 20
) -> dict:
    return general_benchmark(
        lo,
        hi,
        n,
        repeats,
        timeout,
        day_dirname="day06",
        input_generator_function=gen_day06,
        input_desc="Number of math problems to solve",
        day_name="Day 6",
    )


def benchmark_day07(
    lo: int = 10, hi: int = 250, n: int = 10, repeats: int = 5, timeout: int = 20
) -> dict:
    return general_benchmark(
        lo,
        hi,
        n,
        repeats,
        timeout,
        day_dirname="day07",
        input_generator_function=gen_day07,
        input_desc="Dimension of grid",
        day_name="Day 7",
    )


def benchmark_all() -> None:
    benchmark_day01(lo=10, hi=1000, n=5, repeats=5)
    benchmark_day02(lo=10, hi=100, n=5, repeats=5)
    benchmark_day03(lo=10, hi=1000, n=5, repeats=5)
    benchmark_day04(lo=10, hi=140, n=5, repeats=5, timeout=30)

    benchmark_day06(lo=10, hi=1000, n=5, repeats=5, timeout=5)


if __name__ == "__main__":
    # print(benchmark_day02(lo=10, hi=1000, n=4, repeats=5, timeout=30))
    # benchmark_day03(lo=10, hi=1000, n=4, repeats=5, timeout=30)
    # benchmark_day07(lo=10, hi=250, n=5, repeats=5, timeout=5)
    # benchmark_day04(lo=10, hi=249, n=4, repeats=5, timeout=30)
    print(benchmark_day05())
    # benchmark_all()
