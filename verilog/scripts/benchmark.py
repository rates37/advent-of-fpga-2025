import os
import subprocess
import tempfile
import statistics
import re
from pathlib import Path
from datetime import datetime
import numpy as np
import matplotlib.pyplot as plt
from generate_input import gen_day01

CLOCK_CYCLE_RE = re.compile(r"Took\s+(\d+)\s+clock cycles")

def benchmark_day01(lo: int = 10, hi: int = 1000, n: int = 10, repeats: int = 5, timeout: int = 5) -> dict:
    """Benchmark the day01 solver

    Args:
        lo (int, optional): The smallest input size to benchmark. Defaults to 10.
        hi (int, optional): The largest input size to benchmark. Defaults to 1000.
        n (int, optional): The number of sample points (will be linearly spaced between lo and hi). Defaults to 10.
        repeats (int, optional): Number of trials per input size. Defaults to 5.
        timeout (int, optional): Number of seconds to run each simulation for. Defaults to 5.
    """

    # setup:
    sizes = np.linspace(lo, hi, n, dtype=int)
    results = {size: [] for size in sizes}
    root = Path(__file__).resolve().parent
    day01_dir = (root/"../day01").resolve()

    # check day01 exists
    if not day01_dir.exists():
        raise RuntimeError("day01 directory was not found. are you running this function from the scripts folder?")

    original_cwd = Path.cwd()
    
    try:
        os.chdir(day01_dir)

        # test all size inputs:
        for size in sizes:
            # repeat for each trial:
            for trial in range(repeats):
                # use a tempfile to generate input into (avoid clutteringg wd)
                with tempfile.NamedTemporaryFile(mode="w", suffix=".txt", delete=False) as tmp:
                    input_path = Path(tmp.name)

                    # generate input file:
                    expected_results = gen_day01(n=size, output_filename=str(input_path), seed=trial)

                    # run simulator:
                    try:
                        proc = subprocess.run(
                            ["make", "run", f"INPUT_FILE={input_path}"],
                            capture_output=True,
                            text=True, timeout=timeout
                        )
                    except subprocess.TimeoutExpired:
                        print(f"\tTrial {trial}: timed out")
                        continue
                    
                    stdout = proc.stdout + proc.stderr

                    # check expected results appear in the simulation output:
                    if (str(expected_results[0]) not in stdout) or (str(expected_results[0]) not in stdout):
                        raise RuntimeError(f"Incorrect output for size={size}, trial={trial}\n\texpected: {expected_results}\nSimulation output:{stdout}")

                    # record clock cycles:
                    mat = CLOCK_CYCLE_RE.search(stdout)
                    if not mat:
                        raise RuntimeError(f"Number of clock cycles not found in output for size={size}, trial={trial}\nOutput: {stdout}")
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
    csv_path = out_dir / f"day01_benchmark_{timestamp}.csv"

    with open(csv_path, "w", encoding="utf-8") as f:
        # header row:
        f.write("input_size,trial,clock_cycles\n")

        # data rows:
        for s,vs in results.items():
            for i,v in enumerate(vs):
                f.write(f"{s},{i+1},{v}\n")
            
    print(f"Saved results to {csv_path}")

    # plot results:
    means = []
    stdevs = []
    for s, vs in results.items():
        means.append(statistics.mean(vs))
        stdevs.append(statistics.stdev(vs) if len(vs) > 1 else 0)

    plt.figure(figsize=(8,5))
    plt.errorbar(sizes, means, yerr=stdevs, fmt="o-", label="Mean clock cycles")
    plt.xlabel("Input size (number of rotations in input file)")
    plt.ylabel(f"Total Clock cycles (average of {repeats} per size)")
    plt.title("Day 1 Clock cycles vs Input size")
    plt.legend()
    plot_path = out_dir / f"day01_benchmark_{timestamp}.png"
    plt.savefig(plot_path, dpi=300)
    plt.close()
    print(f"Saved results to {plot_path}")

    return results


if __name__ == "__main__":
    print(benchmark_day01(lo=10, hi=1000, n=4, repeats=5, timeout=2))
