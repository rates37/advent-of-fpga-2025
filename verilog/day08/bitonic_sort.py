import random
import sys

# reference bitonic sort implementation used for verilog implementation


def bitonic_sort(lst: list) -> list:
    n = len(lst)

    # pad list to power of 2 length
    n_padded = 1
    while n_padded < n:
        n_padded <<= 1
    l_padded = lst[:]
    l_padded.extend(([sys.maxsize] * (n_padded - n)))

    print(f"Inptu size: {n}, Padded size: {len(l_padded)}")

    k = 2
    while k <= n_padded:
        j = k // 2

        while j > 0:
            for i in range(n_padded):
                l = i ^ j

                if l > i:
                    val_i = l_padded[i]
                    val_l = l_padded[l]

                    ascending = (i & k) == 0
                    should_swap = False
                    if ascending:
                        if val_i > val_l:
                            should_swap = True
                    else:
                        if val_i < val_l:
                            should_swap = True

                    if should_swap:
                        l_padded[i], l_padded[l] = l_padded[l], l_padded[i]
            j //= 2
        k *= 2

    return l_padded[:n]


if __name__ == "__main__":
    random.seed(69420)
    l = [random.randint(0, 1000) for _ in range(10)]
    print(*bitonic_sort(l), sep="\n")
