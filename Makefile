# ARGUS simulation build system (Icarus Verilog)
#
# Usage:
#   make <name>        Compile+run tb/<name>_tb.sv against its RTL
#   make all           Run every testbench in tb/
#   make clean         Remove build artifacts
#
# A testbench passes if it prints "TEST PASSED" and never prints "TEST FAILED".
# Any $fatal / non-zero exit is also a failure.

IVERILOG ?= iverilog
VVP      ?= vvp
IFLAGS   ?= -g2012 -Wall -Irtl -Itb
SIM_TIMEOUT ?= 15

RTL_DIR  := rtl
TB_DIR   := tb
BUILD    := sim/build

# All testbenches are named <name>_tb.sv
TBS      := $(wildcard $(TB_DIR)/*_tb.sv)
NAMES    := $(patsubst $(TB_DIR)/%_tb.sv,%,$(TBS))

.PHONY: all clean list $(NAMES)

# Default: run everything
all:
	@pass=0; fail=0; \
	for n in $(NAMES); do \
	  $(MAKE) --no-print-directory $$n || fail=$$((fail+1)); \
	  if [ $$? -eq 0 ]; then pass=$$((pass+1)); fi; \
	done; \
	echo "=================================================="; \
	echo "REGRESSION COMPLETE"; \
	echo "=================================================="

list:
	@echo "Available testbenches:"; \
	for n in $(NAMES); do echo "  $$n"; done

# Pattern rule: compile a single testbench with all RTL on the include path.
# We compile every rtl/*.sv so module dependencies resolve; iverilog only
# elaborates the top module named <name>_tb.
$(NAMES): %: $(BUILD)/%.vvp
	@echo "---- RUN $@ ----"; \
	out=$$( $(VVP) $(BUILD)/$@.vvp & p=$$!; \
	        ( sleep $(SIM_TIMEOUT); kill $$p 2>/dev/null ) & w=$$!; \
	        wait $$p 2>/dev/null; kill $$w 2>/dev/null ); \
	echo "$$out"; \
	if echo "$$out" | grep -q "TEST FAILED"; then \
	  echo "RESULT: $@ FAILED"; exit 1; \
	elif echo "$$out" | grep -q "TEST PASSED"; then \
	  echo "RESULT: $@ PASSED"; \
	else \
	  echo "RESULT: $@ INCONCLUSIVE (no PASS/FAIL marker or timed out)"; exit 1; \
	fi

$(BUILD)/%.vvp: $(TB_DIR)/%_tb.sv $(wildcard $(RTL_DIR)/*.sv)
	@mkdir -p $(BUILD)
	$(IVERILOG) $(IFLAGS) -s $*_tb -o $@ $(wildcard $(RTL_DIR)/*.sv) $<

clean:
	rm -rf $(BUILD) *.vcd *.vvp
