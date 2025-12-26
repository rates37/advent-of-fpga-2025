#!/user/bin/python3
import random
import math

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
    # random.seed(seed)
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
