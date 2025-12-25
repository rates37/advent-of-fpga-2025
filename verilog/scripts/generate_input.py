#!/user/bin/python3
import random


DEFAULT_SEED = sum(ord(c) for c in 'Advent of FPGA')

# generate day 1 inputs:
def gen_day01(n: int, output_filename: str, seed: int = DEFAULT_SEED) -> tuple[int, int]:
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
        #allow distances over 100 (part 2)
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

