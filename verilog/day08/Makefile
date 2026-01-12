IVERILOG := iverilog
VVP := vvp

SRCS := day08_tb.v \
		day08_core.v \
		heap_sort.v \
		../utils/rom.v \
		../utils/ram.v 

OUT := day08_tb.out

BITONIC_TB_SRCS := bitonic_sort.v \
				   bitonic_sort_tb.v \
				   ../utils/ram.v

BITONIC_OUT := bitonic_tb.out

# parameters:
INPUT_FILE ?= input.txt

IVERILOG_PARAMS := -Pday08_tb.INPUT_DATA_FILENAME=\"$(INPUT_FILE)\"

# taegets:
all: $(OUT)

$(OUT): $(SRCS)
	$(IVERILOG) -g2005-sv -o $(OUT) $(IVERILOG_PARAMS) $(SRCS)

.PHONY: $(OUT) # force re-building so that you can change the filename without needing to `make clean` first
#                otherwise nothing to be done

run: $(OUT)
	$(VVP) $(OUT)

clean:
	rm -f $(OUT)

$(BITONIC_OUT): $(BITONIC_TB_SRCS)
	$(IVERILOG) -g2005-sv -o $(BITONIC_OUT) $(BITONIC_TB_SRCS)

test_bitonic: $(BITONIC_OUT)
	$(VVP) $(BITONIC_OUT)

