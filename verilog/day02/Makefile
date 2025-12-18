IVERILOG := iverilog
VVP := vvp

SRCS := day02_tb.v \
		day02_core.v \
		../utils/rom.v \
		period_summer.v \
		range_summer.v 

OUT := day01_tb.out

# parameters:
INPUT_FILE ?= input.txt

IVERILOG_PARAMS := -Pday02_tb.INPUT_DATA_FILENAME=\"$(INPUT_FILE)\"

# taegets:
all: $(OUT)

$(OUT): $(SRCS)
	$(IVERILOG) -o $(OUT) $(IVERILOG_PARAMS) $(SRCS)

.PHONY: $(OUT) # force re-building so that you can change the filename without needing to `make clean` first
#                otherwise nothing to be done

run: $(OUT)
	$(VVP) $(OUT)

clean:
	rm -f $(OUT)
