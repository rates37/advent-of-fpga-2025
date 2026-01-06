#!/user/bin/python3
import random
import math
import string
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

    grid = [["." for _ in range(w)] for _ in range(h)]

    # put initial position in middle of first row
    start_col = w // 2
    grid[0][start_col] = "S"

    # add splitters
    for r in range(1, h):
        for c in range(w):
            if random.random() < 0.25:  # seems to give a good balance
                grid[r][c] = "^"

    # Write the grid to the output file
    with open(output_filename, "w") as f:
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

            if grid[r][c] == "^":
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

            if grid[r][c] == "^":
                next_counts[c - 1] = next_counts.get(c - 1, 0) + count
                next_counts[c + 1] = next_counts.get(c + 1, 0) + count
            else:
                next_counts[c] = next_counts.get(c, 0) + count

        current_counts = next_counts
        if not current_counts:
            break
    total_timelines += sum(current_counts.values())

    return part1_answer, total_timelines


def gen_day09(
    n: int, output_filename: str, seed: int = DEFAULT_SEED
) -> tuple[int, int]:
    # n = number of 2D coordinates in the input file
    # output_filename = self explanatory
    # returns two ints: (part1_answer, part2_answer)
    random.seed(seed)

    # generate input: a rectilinear polygon

    # assert minimums
    if n < 4:
        n = 4
    if n % 2 != 0:
        n += 1
    # start with a large counter clockwise bounding box
    padding = 5000
    limit = 95000
    poly = [(padding, padding), (limit, padding), (limit, limit), (padding, limit)]
    current_vertex_count = 4

    def insertects_any(p1, p2, current_poly, ignore_indices):
        if p1 == p2:
            return False
        x1, y1 = p1
        x2, y2 = p2
        minX, maxX = min(x1, x2), max(x1, x2)
        minY, maxY = min(y1, y2), max(y1, y2)

        num_v = len(current_poly)
        for i in range(num_v):
            if i in ignore_indices:
                continue

            p3 = current_poly[i]
            p4 = current_poly[(i + 1) % num_v]
            x3, y3 = p3
            x4, y4 = p4
            # check overlap for rect segments:
            is_A_vert = x1 == x2
            is_B_vert = x3 == x4

            if is_A_vert and is_B_vert:
                if x1 == x3:
                    if max(minY, min(y3, y4)) < min(maxY, max(y3, y4)):
                        return True
            elif not is_A_vert and not is_B_vert:
                if y1 == y3:
                    if max(minX, min(x3, x4)) < min(maxX, max(x3, x4)):
                        return True
            else:
                if is_A_vert:
                    vx, vyMin, vyMax = x1, minY, maxY
                    hy, hxMin, hxMax = y3, min(x3, x4), max(x3, x4)
                    if hxMin < vx < hxMax and vyMin < hy < vyMax:
                        return True
                else:
                    hy, hxMin, hxMax = y1, minX, maxX
                    vx, vyMin, vyMax = x3, min(y3, y4), max(y3, y4)
                    if hxMin < vx < hxMax and vyMin < hy < vyMax:
                        return True
        return False

    while current_vertex_count < n:
        # pick a random corner to cut:
        idx = random.randint(0, len(poly) - 1)
        p_prev = poly[idx - 1]
        p_curr = poly[idx]
        p_next = poly[(idx + 1) % len(poly)]

        len1 = abs(p_curr[0] - p_prev[0]) + abs(p_curr[1] - p_prev[1])
        len2 = abs(p_curr[0] - p_next[0]) + abs(p_curr[1] - p_next[1])

        if len1 < 20 or len2 < 20:
            continue  # deem this as too small to make a cut

        # determine size of cut:
        cut1 = random.randint(5, min(len1 // 2, 5000))  # depth along incoming edge
        cut2 = random.randint(5, min(len2 // 2, 5000))  # depth outgoing edge

        # determine directions:
        # from prev to curr:
        dx1 = (
            (p_curr[0] - p_prev[0]) // max(1, abs(p_curr[0] - p_prev[0]))
            if p_curr[0] != p_prev[0]
            else 0
        )
        dy1 = (
            (p_curr[1] - p_prev[1]) // max(1, abs(p_curr[1] - p_prev[1]))
            if p_curr[1] != p_prev[1]
            else 0
        )

        # from curr to next:
        dx2 = (
            (p_next[0] - p_curr[0]) // max(1, abs(p_next[0] - p_curr[0]))
            if p_next[0] != p_curr[0]
            else 0
        )
        dy2 = (
            (p_next[1] - p_curr[1]) // max(1, abs(p_next[1] - p_curr[1]))
            if p_next[1] != p_curr[1]
            else 0
        )

        # add new points:
        p_a = (
            p_curr[0] - dx1 * cut1,
            p_curr[1] - dy1 * cut1,
        )  # back from curr along incoming edge
        p_c = (
            p_curr[0] + dx2 * cut2,
            p_curr[1] + dy2 * cut2,
        )  # forward from curr along outgoing edge
        p_b = (
            p_a[0] + (p_c[0] - p_curr[0]),
            p_a[1] + (p_c[1] - p_curr[1]),
        )  # the new "inner" corner

        ignore_list = {(idx - 1) % len(poly), idx}
        if not insertects_any(p_a, p_b, poly, ignore_list) and not insertects_any(
            p_b, p_c, poly, ignore_list
        ):
            if idx == len(poly) - 1:
                new_poly = poly[:idx] + [p_a, p_b, p_c]
            else:
                new_poly = poly[:idx] + [p_a, p_b, p_c] + poly[idx + 1 :]
            poly = new_poly
            current_vertex_count += 2
    # write to output file:
    with open(output_filename, "w") as f:
        for x, y in poly:
            f.write(f"{x},{y}\n")

    # solve this problem:
    segments = []
    for i in range(len(poly)):
        segments.append((poly[i], poly[(i + 1) % len(poly)]))

    def get_area(p1, p2):
        return (abs(p1[0] - p2[0]) + 1) * (abs(p1[1] - p2[1]) + 1)

    best_area_p1 = 0
    for i in range(len(poly)):
        for j in range(i):
            best_area_p1 = max(best_area_p1, get_area(poly[i], poly[j]))

    def is_rect_in_poly(p1, p2, segs):
        x1, y1 = p1
        x2, y2 = p2
        minX, maxX = min(x1, x2), max(x1, x2)
        minY, maxY = min(y1, y2), max(y1, y2)

        # edge intersection checK:
        for (sx1, sy1), (sx2, sy2) in segs:
            if sx1 == sx2:
                if minX < sx1 < maxX:
                    sy_min = min(sy1, sy2)
                    sy_max = max(sy1, sy2)
                    if max(minY, sy_min) < min(maxY, sy_max):
                        return False
            else:
                if minY < sy1 < maxY:
                    sx_min = min(sx1, sx2)
                    sx_max = max(sx1, sx2)
                    if max(minX, sx_min) < min(maxX, sx_max):
                        return False
        # point in poly:
        cx = (minX + maxX) / 2
        cy = (minY + maxY) / 2
        intersections = 0

        for (sx1, sy1), (sx2, sy2) in segs:
            if sx1 == sx2:
                sy_min = min(sy1, sy2)
                sy_max = max(sy1, sy2)
                if sy_min < cy < sy_max:
                    if sx1 > cx:
                        intersections += 1

        return (intersections % 2) == 1

    best_area_p2 = 0
    for i in range(len(poly)):
        p1 = poly[i]
        for j in range(i):
            p2 = poly[j]
            area = get_area(p1, p2)
            if area > best_area_p2 and is_rect_in_poly(p1, p2, segments):
                best_area_p2 = area

    return best_area_p1, best_area_p2


def gen_day11(
    n: int, output_filename: str, seed: int = DEFAULT_SEED
) -> tuple[int, int]:
    # n = number of nodes in the graph
    # output_filename = self explanatory
    # returns two ints: (part1_answer, part2_answer)
    random.seed(seed)

    # set min nodes to at least 10
    if n < 15:
        print(f"warning: using n={n} is too low for number of nodes, defaulting to 15")
        n = 15

    fixed_nodes = {"you", "svr", "out", "dac", "fft"}

    def get_random_name():
        return "".join(random.choices(string.ascii_lowercase, k=3))

    all_names = set(fixed_nodes)
    while len(all_names) < n:
        all_names.add(get_random_name())
    fillers = list(all_names - fixed_nodes)
    random.shuffle(fillers)

    specials = ["dac", "fft"]
    random.shuffle(specials)
    s1, s2 = specials

    # insert svr and you early, and s1/2 near the middle, and out near the end
    node_list = (
        [None] * n
    )  # this list will be a topological ordering, edges only go from nodes i->j where i < j to ensure DAG
    svr_idx = random.randint(0, n // 10)
    out_idx = random.randint((n * 3) // 4, (n * 9) // 10)
    span = out_idx - svr_idx
    s1_idx = svr_idx + (span // 3) + random.randint(-1, 1)
    s2_idx = svr_idx + (2 * span // 3) + random.randint(-1, 1)
    reserved_indices = {svr_idx, out_idx, s1_idx, s2_idx}
    you_idx = random.choice([i for i in range(out_idx) if i not in reserved_indices])
    reserved_indices.add(you_idx)

    # place nodes in list:
    node_list[svr_idx] = "svr"
    node_list[out_idx] = "out"
    node_list[s1_idx] = s1
    node_list[s2_idx] = s2
    node_list[you_idx] = "you"

    # fill remaining places:
    filler_idx = 0
    for i in range(n):
        if node_list[i] is None:
            node_list[i] = fillers[filler_idx]
            filler_idx += 1

    # graph:
    adj = {name: [] for name in node_list}

    def add_edge(u, v):
        if v not in adj[u]:
            adj[u].append(v)

    # add minimal path so that solutions are non zero (not really necessary)
    add_edge("svr", s1)
    add_edge(s1, s2)
    add_edge(s2, "out")
    add_edge("you", "out")

    for i, u in enumerate(node_list):
        possible_targets = node_list[i + 1 :]
        if not possible_targets:
            continue
        num_cables = random.choice(list(range(1, 17)))  # limit out degree to 16
        targets = random.sample(
            possible_targets, k=min(num_cables, len(possible_targets))
        )
        for v in targets:
            add_edge(u, v)

    # generate solution:
    memo = {}  # map from (current, target) tuple to num of paths from curr to target

    def count_paths(curr, target):
        if curr == target:
            return 1
        state = (curr, target)
        if state in memo:
            return memo[state]

        total = 0
        for n in adj[curr]:
            total += count_paths(n, target)
        memo[state] = total
        return total

    part1_answer = count_paths("you", "out")
    path1 = count_paths("svr", s1)
    path2 = count_paths(s1, s2)
    path3 = count_paths(s2, "out")
    part2_answer = path1 * path2 * path3

    # write output file:
    with open(output_filename, "w") as f:
        output_keys = list(adj.keys())
        random.shuffle(output_keys)

        for k in output_keys:
            neighbours = adj[k]
            if neighbours:
                f.write(f"{k}: {' '.join(neighbours)}\n")
    return part1_answer, part2_answer


if __name__ == "__main__":
    # print(gen_day07(142, "day07-142.txt", 42))
    print(gen_day09(30, "day09-30.txt"))
