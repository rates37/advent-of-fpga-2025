import sys

def main(filename: str) -> None:
    # reset:
    p1_result = 0
    p2_result = 0
    curr_x = 0

    # S_LOAD_INPUT:
    try:
        with open(filename, 'r') as f:
            lines = f.readlines()
    except FileNotFoundError:
        print(f"Error: could not open file: {filename}")
        return
    
    grid_mem = [line.strip("\n") for line in lines] # dont store \n chars in ram
    row_len = [len(r) for r in grid_mem]
    max_x = max(row_len, default=0)
    max_y = len(grid_mem)

    # perform horizontal passes:
    while curr_x < max_x:
        # S_SCAN_COL
        def is_col_empty(x):
            # this is done in a single cycle in hardware (unwrapped for loop)
            for y in range(max_y):
                if x < row_len[y] and grid_mem[y][x].strip():
                    return False
            return True

        if is_col_empty(curr_x):
            curr_x += 1
            continue

        # start of a block:
        # reset block accumulators
        # done in the transition from S_SCAN_COL to S_PROCESS_COL
        p1_nums = [0 for _ in range(max_y)]
        p2_acc = 0
        is_first_p2 = True
        operator = '+'

        # S_PROCESS_COL:
        while curr_x < max_x and not is_col_empty(curr_x):
            # update operator:
            if curr_x < row_len[max_y-1]:
                char = grid_mem[max_y-1][curr_x]
                if char in "*+":
                    operator = char
            
            # numeric accumulation (done in parallel)
            col_val = 0
            col_has_digit = False
            for y in range(max_y - 1):
                if curr_x < row_len[y]:
                    char = grid_mem[y][curr_x]
                    if char.isdigit():
                        # part 1: store num
                        p1_nums[y] = p1_nums[y] * 10 + int(char)

                        # part 2: update acc
                        col_val = col_val * 10 + int(char)
                        col_has_digit = True
            
            # update part 2 block accumulator:
            if col_has_digit:
                if is_first_p2:
                    p2_acc = col_val
                    is_first_p2 = False
                else:
                    if operator == "*":
                        p2_acc *= col_val
                    else:
                        p2_acc += col_val
            
            curr_x += 1

        # S_BLOCK_REDUCE:
        p1_block_acc = p1_nums[0]
        for y in range(1, max_y-1):
            if operator == "*":
                p1_block_acc *= p1_nums[y]
            else:
                p1_block_acc += p1_nums[y]

        # update accumulators before going back to scan next col:
        p1_result += p1_block_acc
        p2_result += p2_acc

    # S_DONE
    # print results:
    print(f"Results for {filename}")
    print(f"\tPart 1: {p1_result}")
    print(f"\tPart 2: {p2_result}")

if __name__ == "__main__":
    if len(sys.argv) > 1:
        main(sys.argv[1])
    else:
        print("Usage: python3 reference_sol.py <input_filename.txt>")
