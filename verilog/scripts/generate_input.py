#!/user/bin/python3
import random
import math
import functools as ft

DEFAULT_SEED = sum(ord(c) for c in "Advent of FPGA")


# generate day 1 inputs:
def gen_day01(
    n: int, output_filename: str, seed: int = DEFAULT_SEED
) -> tuple[int, int]:
    # n = input size
    # output_filename = self explanatory
    # returns two ints: (part1_answer, part2_answer)

    DIAL_SIZE = 100
    START_POS = 50

    rng = random.Random(seed)

    # Generate rotations file:
    rotations: list[tuple[str, int]] = []
    for _ in range(n):
        direction = rng.choice(["L", "R"])
        # allow distances over 100 (part 2)
        distance = rng.randint(1, 300)
        rotations.append((direction, distance))

    with open(output_filename, "w", encoding="utf-8") as f:
        for d, dist in rotations:
            f.write(f"{d}{dist}\n")

    # find part 1 answer:
    position = START_POS
    part1 = 0

    for direction, value in rotations:
        mod_value = value % DIAL_SIZE

        if direction == "R":
            position += mod_value
            if position > 99:
                position -= 100
        else:
            position -= mod_value
            if position < 0:
                position += 100

        if position == 0:
            part1 += 1

    # part 2:
    position = START_POS
    part2 = 0

    for direction, value in rotations:
        mod_value = value % DIAL_SIZE
        part2 += value // DIAL_SIZE

        # cursed to handle all cases
        if direction == "R":
            position += mod_value
            if position > 99:
                part2 += 1
                position -= 100
        else:
            old_position = position
            position -= mod_value
            if position < 0:
                if old_position != 0:
                    part2 += 1
                position += 100
            if position == 0:
                part2 += 1

    return part1, part2


def gen_day02(
    n: int, output_filename: str, seed: int = DEFAULT_SEED
) -> tuple[int, int]:
    # n = input size
    # output_filename = self explanatory
    # returns two ints: (part1_answer, part2_answer)

    # functions to solve this task (taken from my solution at https://github.com/rates37/aoc-2025/blob/main/day02/day02_p2_optimised.py)
    def get_periods_and_ops(D: int) -> list[tuple[int, int]]:
        ops = [
            [],
            [(1, 1)],
            [(1, 1)],
            [(2, 1)],
            [(1, 1)],
            [(2, 1), (3, 1), (1, -1)],
            [(1, 1)],
            [(4, 1)],
            [(3, 1)],
            [(2, 1), (5, 1), (1, -1)],
            [(1, 1)],
            [(4, 1), (6, 1), (2, -1)],
            [(1, 1)],
            [(2, 1), (7, 1), (1, -1)],
            [(3, 1), (5, 1), (1, -1)],
            [(8, 1)],
            [(1, 1)],
            [(6, 1), (9, 1), (3, -1)],
            [(1, 1)],
        ]
        return ops[D - 1]

    def sum_series(lo: int, hi: int) -> int:
        # S_n = n * (a_1 + a_n) / 2 where:
        # n is number of terms being added
        # a_1 is first term
        # a_n is final term
        # since all terms are one after the other, n = (a_n - a_1 + 1)
        return (hi - lo + 1) * (lo + hi) // 2

    def solve_period_range(D: int, L: int, lo: int, hi: int) -> int:
        # get multiplier:
        mult = 0
        for i in range(20):
            if (i + 1) * L <= D:
                mult += 10 ** (i * L)
        if not mult:
            return 0

        # get bounds for range:
        lower = max(math.ceil(lo / mult), 10 ** (L - 1))
        upper = min(math.floor(hi / mult), 10 ** (L) - 1)

        return mult * sum_series(lower, upper)

    def solve_range_p2(lo: int, hi: int) -> int:
        total = 0

        # split into ranges of the same digit length:
        current = lo
        while current <= hi:
            current_str = str(current)
            D = len(current_str)
            limit = 10**D - 1  # 9999..9 (D times)
            current_range_end = min(hi, limit)

            # calculate sum for range from current -> current_range_end with D digits:
            ops = get_periods_and_ops(D)

            temp_sum = 0
            for length, sign in ops:
                val = solve_period_range(D, length, current, current_range_end)
                temp_sum += val * sign

            total += temp_sum
            current = 10**D
        return total

    def solve_range_p1(lo: int, hi: int) -> int:
        total = 0
        current = lo

        while current <= hi:
            currentStr = str(current)
            D = len(currentStr)
            limit = 10**D - 1
            current_range_end = min(hi, limit)

            if D % 2:
                current = current_range_end + 1
                continue

            # only even length numbers need to be considered:
            L = D // 2
            M = 10**L + 1

            lower = max((current + M - 1) // M, 10 ** (L - 1))
            upper = min(current_range_end // M, 10**L - 1)
            if upper >= lower:
                total += M * sum_series(lower, upper)
            current = current_range_end + 1
        return total

    # setup:
    random.seed(seed)
    MAX_GAP = 2**40  # maximum difference between lower and upper value of range
    MAX_VAL = (1 << 60) - 1

    # generate ranges and answers:
    ranges = []
    p1_ans = 0
    p2_ans = 0
    while len(ranges) < n:
        # geenrate input randomly:
        n_bits = random.randint(1, 62)
        lo = random.randrange(1 < (n_bits - 1), min(1 << n_bits, MAX_VAL))
        width = random.randint(0, MAX_GAP)
        hi = min(width + lo, MAX_VAL)

        # enforce 64-bit expected results:
        p1 = solve_range_p1(lo, hi)
        p2 = solve_range_p2(lo, hi)
        if p1_ans + p1 > MAX_VAL or p2_ans + p2 > MAX_VAL:
            continue

        p1_ans += p1
        p2_ans += p2

        ranges.append((lo, hi))

    # write to output file:
    with open(output_filename, "w") as f:
        f.write(",".join(f"{lo}-{hi}" for (lo, hi) in ranges))

    return (p1_ans, p2_ans)


def gen_day03(
    n: int, output_filename: str, seed: int = DEFAULT_SEED
) -> tuple[int, int]:
    # n = input size
    # output_filename = self explanatory
    # returns two ints: (part1_answer, part2_answer)

    # function to solve task:
    def get_bank_joltage_n(bank: str, n: int = 2):
        selected = [""] * n
        pos = -1

        for j in range(n):
            m = bank[pos + 1]
            mPos = pos + 1
            for i in range(pos + 1, len(bank) - (n - j - 1)):
                if bank[i] > m:
                    m = bank[i]
                    mPos = i
            selected[j] = m
            pos = mPos
        total = 0
        for c in selected:
            total = total * 10 + int(c)
        return total

    # setup:
    random.seed(seed)

    # generate inputs and expected outputs:
    banks = []
    p1_ans = 0
    p2_ans = 0

    for _ in range(n):
        bank_length = random.randint(12, 100)
        bank = "".join(random.choice("123456789") for _ in range(bank_length))
        banks.append(bank)
        p1_ans += get_bank_joltage_n(bank, 2)
        p2_ans += get_bank_joltage_n(bank, 12)

    # write to file:
    with open(output_filename, "w") as f:
        f.write("\n".join(banks))

    return p1_ans, p2_ans


def gen_day04(
    n: int, output_filename: str, seed: int = DEFAULT_SEED
) -> tuple[int, int]:
    # n = input size
    # output_filename = self explanatory
    # returns two ints: (part1_answer, part2_answer)

    random.seed(seed)
    density = random.uniform(
        0.45, 0.65
    )  # gives a relatively even spread without trivialising

    grid = []
    for _ in range(n):
        row = ["@" if random.random() < density else "." for _ in range(n)]
        grid.append(row)

    # calculate expected answers:
    DIRS = [
        (-1, -1),
        (-1, 0),
        (-1, 1),
        (0, -1),
        (0, 1),
        (1, -1),
        (1, 0),
        (1, 1),
    ]

    def count_neighbors(grid, r, c):
        h = len(grid)
        w = len(grid[0])
        cnt = 0
        for dr, dc in DIRS:
            nr, nc = r + dr, c + dc
            if 0 <= nr < h and 0 <= nc < w:
                if grid[nr][nc] == "@":
                    cnt += 1
        return cnt

    def find_accessible(grid):
        h = len(grid)
        w = len(grid[0])
        acc = []
        for r in range(h):
            for c in range(w):
                if grid[r][c] == "@" and count_neighbors(grid, r, c) < 4:
                    acc.append((r, c))
        return acc

    p1_ans = 0
    for r in range(n):
        for c in range(n):
            if grid[r][c] == "@" and count_neighbors(grid, r, c) < 4:
                p1_ans += 1
    p2_ans = 0
    grid_copy = [r[:] for r in grid]

    while True:
        accessible = find_accessible(grid_copy)
        if not accessible:
            break

        p2_ans += len(accessible)
        for r, c in accessible:
            grid_copy[r][c] = "."

    # write to output file:
    with open(output_filename, "w") as f:
        for r in grid:
            f.write("".join(r) + "\n")
    return (p1_ans, p2_ans)


def gen_day05(
    n: tuple[int, int], output_filename: str, seed: int = DEFAULT_SEED
) -> tuple[int, int]:
    # n = num ranges, num queries
    # output_filename = self explanatory
    # returns two ints: (part1_answer, part2_answer)

    def merge_intervals(intervals):
        if not intervals:
            return []
        intervals = sorted(intervals)
        merged = [intervals[0]]
        for l, r in intervals[1:]:
            pl, pr = merged[-1]
            if l <= pr + 1:
                merged[-1][1] = max(pr, r)
            else:
                merged.append([l, r])
        return merged

    def union_size(intervals):
        intervals = merge_intervals(intervals)
        total = 0
        for l, r in intervals:
            total += r - l + 1
        return total

    MAX_RANGE = int(10e5)
    INT64_MAX = (1 << 50) - 1

    n_ranges, n_queries = n
    random.seed(seed)

    ranges = []
    merged = []

    # generate ranges:
    while len(ranges) < n_ranges:
        bits = random.randint(1, 50)
        lo = random.randrange(0, 1 << (bits - 1))
        width = random.randint(0, MAX_RANGE)
        hi = lo + width

        if hi > INT64_MAX:
            hi = INT64_MAX

        # check answers are still within 64 bit integer range
        possible_next = ranges + [[lo, hi]]
        next_merged = merge_intervals(possible_next)
        size = union_size(next_merged)

        if size > INT64_MAX:
            continue

        ranges.append([lo, hi])
        merged = next_merged

    # generate query ids:
    minId = max(0, min(min(r) for r in ranges))
    maxId = min(INT64_MAX, max(max(r) for r in ranges))
    queries = [random.randint(minId, maxId) for _ in range(n_queries)]

    # calculate p1 answer:
    p1_ans = 0
    for q in queries:
        for l, r in merge_intervals(ranges):
            if l <= q <= r:
                p1_ans += 1
    p2_ans = union_size(merged)

    # write to output file:
    with open(output_filename, "w") as f:
        for l, r in ranges:
            f.write(f"{l}-{r}\n")
        f.write("\n")
        for q in queries:
            f.write(f"{q}\n")
    return p1_ans, p2_ans


def gen_day06(
    n: tuple[int, int], output_filename: str, seed: int = DEFAULT_SEED
) -> tuple[int, int]:
    # n = number of rows, number of operators
    # output_filename = self explanatory
    # returns two ints: (part1_answer, part2_answer)
    random.seed(seed)
    n_rows, n_ops = n

    problems = []
    for _ in range(n_ops):
        op = random.choice(["+", "*"])
        if op == "+":
            nums = [random.randint(1, 9999) for _ in range(n_rows)]
        else:
            # lower limit when taking product to reduce chances of overflow
            nums = [random.randint(1, 120) for _ in range(n_rows)]
        problems.append((nums, op))

    # determine per-problem widths:
    widths = [max(len(str(x)) for x in nums) for nums, _ in problems]
    rows = [[] for _ in range(n_rows + 1)]
    for (nums, op), w in zip(problems, widths):
        # difficult to deduce the input format, but it seems the numbers that
        # are a smaller width than others in the same column are randomly
        # left / right aligned (and not floating in the middle)
        align_left = random.choice([True, False])
        for r, v in enumerate(nums):
            s = str(v)
            cell = s.ljust(w) if align_left else s.rjust(w)
            rows[r].extend(cell)
        rows[n_rows].extend(op + " " * (w - 1))

        # add separator column:
        for i in range(n_rows + 1):
            rows[i].append(" ")

    lines = ["".join(r).rstrip() for r in rows]

    # write to output file:
    with open(output_filename, "w") as f:
        f.write("\n".join(lines))

    # solver logic, based on my solution in https://github.com/rates37/aoc-2025/blob/main/day06/day06.hs
    def to_op(c: str):
        if c == "*":
            return lambda a, b: a * b
        else:
            return lambda a, b: a + b

    def part1(lines):
        num_lines = lines[:-1]
        op_line = lines[-1]

        nums = [list(map(int, l.split())) for l in num_lines]
        ops = [to_op(c) for c in op_line.split()]

        output = 0
        for col_val, op in zip(zip(*nums), ops):
            output += ft.reduce(op, col_val)
        return output

    def split_on_empty(cols):
        blocks = []
        current_block = []
        for c in cols:
            if c.isspace():
                if current_block:
                    blocks.append(current_block)
                    current_block = []
            else:
                current_block.append(c)
        if current_block:
            blocks.append(current_block)
        return blocks

    def parse_col_number(col):
        digits = "".join(c for c in col if c.isdigit())
        return int(digits) if digits else None

    def process_part2_block(cols):
        block_str = "".join(cols)
        operator_char = "+"
        for ch in block_str:
            if ch in "+*":
                operator_char = ch
                break
        op = to_op(operator_char)
        nums = [parse_col_number(c) for c in cols if parse_col_number(c) is not None]
        return ft.reduce(op, nums) if nums else 0

    def part2(lines):
        max_len = max(len(line) for line in lines)
        padded_lines = [line.ljust(max_len) for line in lines]

        cols = ["".join(c) for c in zip(*padded_lines)]
        blocks = split_on_empty(cols)
        return sum(process_part2_block(b) for b in blocks)

    return part1(lines), part2(lines)

def gen_day06_4_row(
    n: int, output_filename: str, seed: int = DEFAULT_SEED
) -> tuple[int, int]:
    # n = number of operators, always uses 4 rows of numbers (like real puzzle input)
    # output_filename = self explanatory
    # returns two ints: (part1_answer, part2_answer)
    return gen_day06((4, int(n)), output_filename, seed)


def gen_day07(
    n: int, output_filename: str, seed: int = DEFAULT_SEED
) -> tuple[int, int]:
    # n = dimensions of the grid
    # output_filename = self explanatory
    # returns two ints: (part1_answer, part2_answer)
    random.seed(seed)
    
    # generate input
    n = max(n, 5)
    w = h = n
    
    grid = [['.' for _ in range(w)] for _ in range(h)]
    
    # put initial position in middle of first row
    start_col = w // 2
    grid[0][start_col] = 'S'
    
    # add splitters
    for r in range(1, h):
        for c in range(w):
            if random.random() < 0.25: # seems to give a good balance
                grid[r][c] = '^'
                
    # Write the grid to the output file
    with open(output_filename, 'w') as f:
        for row in grid:
            f.write("".join(row) + "\n")
            
    # --- 2. Solve Part 1 (Boolean Reachability) ---
    # We need to count how many unique splitters are hit.
    # We merge beams that land on the same spot (using a set).
    
    splitters_hit = set()
    active_cols = {start_col}
    
    # part 1:
    for r in range(h):
        next_active = set()
        for c in active_cols:
            if c < 0 or c >= w:
                continue
            
            if grid[r][c] == '^':
                splitters_hit.add((r, c))
                next_active.add(c - 1)
                next_active.add(c + 1)
            else:
                next_active.add(c)
        
        active_cols = next_active
        if not active_cols:
            break
            
    part1_answer = len(splitters_hit)
    
    # part 2:
    current_counts = {start_col: 1}
    total_timelines = 0
    
    for r in range(h):
        next_counts = {}
        for c, count in current_counts.items():
            if c < 0 or c >= w:
                total_timelines += count
                continue
            
            if grid[r][c] == '^':
                next_counts[c - 1] = next_counts.get(c - 1, 0) + count
                next_counts[c + 1] = next_counts.get(c + 1, 0) + count
            else:
                next_counts[c] = next_counts.get(c, 0) + count
                
        current_counts = next_counts
        if not current_counts:
            break
    total_timelines += sum(current_counts.values())

    return part1_answer, total_timelines


if __name__ == "__main__":
    print(gen_day07(142, "day07-142.txt", 42))
