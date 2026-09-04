# ==============================================================================
# Makefile for Icarus Verilog & GTKWave Simulation Environment
# ==============================================================================

# Directories
PROJECT_ROOT = ..
RTL_DIR      = $(PROJECT_ROOT)/rtl
TB_DIR       = $(PROJECT_ROOT)/tb
BUILD_DIR    = build

# Toolchain definitions
IVERILOG       = iverilog
VVP            = vvp
GTKWAVE        = gtkwave
IVERILOG_FLAGS = -Wall -g2012 -I$(RTL_DIR) -I$(TB_DIR)

# Discovery
RTL_SRCS     = $(wildcard $(RTL_DIR)/*.v) $(wildcard $(RTL_DIR)/*.sv)
ALL_TBS      = $(wildcard $(TB_DIR)/tb_*.v)

# Targets
.PHONY: all compile compile-all smoke test test-all wave clean help

all: smoke

$(BUILD_DIR):
	mkdir -p $(BUILD_DIR)

# ------------------------------------------------------------------------------
# 1. Compilation Target (Single file or All files)
#    Usage:
#      make compile                  (Compiles all files in rtl/)
#      make compile SRC=smoke_adder.v (Compiles only rtl/smoke_adder.v)
# ------------------------------------------------------------------------------
compile: $(BUILD_DIR)
ifdef SRC
	@SRC_FILE="$(RTL_DIR)/$(patsubst %.v,%,$(SRC)).v"; \
	if [ ! -f "$$SRC_FILE" ]; then \
		echo "Error: File $$SRC_FILE not found in $(RTL_DIR)/"; \
		exit 1; \
	fi; \
	echo "==> [RTL Compile] Checking syntax for single file: $$SRC_FILE <=="; \
	$(IVERILOG) $(IVERILOG_FLAGS) -o $(BUILD_DIR)/check_$(basename $(SRC)).vvp "$$SRC_FILE"; \
	echo "==> [SUCCESS] File [$(SRC)] compiled cleanly with zero errors!"
else
	@echo "==> [RTL Compile All] Checking syntax for all RTL files in $(RTL_DIR)/ <=="; \
	$(IVERILOG) $(IVERILOG_FLAGS) -o $(BUILD_DIR)/rtl_check_all.vvp $(RTL_SRCS); \
	echo "==> [SUCCESS] All RTL files in $(RTL_DIR)/ compiled cleanly with zero errors!"
endif

compile-all:
	@$(MAKE) compile SRC=

# ------------------------------------------------------------------------------
# 2. Smoke Test Target (Alias for testing tb_smoke)
# ------------------------------------------------------------------------------
smoke:
	@$(MAKE) test TB=tb_smoke

# ------------------------------------------------------------------------------
# 3. Testbench Targets (Single TB or All TBs)
#    Usage:
#      make test                     (Runs default TB: tb_smoke)
#      make test TB=tb_smoke         (Runs specific TB: tb/tb_smoke.v)
#      make test-all                 (Runs all testbenches in tb/ sequentially)
# ------------------------------------------------------------------------------
TB ?= tb_smoke

test: $(BUILD_DIR)
	@TB_NAME="$(patsubst %.v,%,$(TB))"; \
	TB_FILE="$(TB_DIR)/$$TB_NAME.v"; \
	if [ ! -f "$$TB_FILE" ]; then \
		echo "Error: Testbench $$TB_FILE not found in $(TB_DIR)/"; \
		exit 1; \
	fi; \
	echo "==> [Testbench: $$TB_NAME] Compiling with Icarus Verilog <=="; \
	$(IVERILOG) $(IVERILOG_FLAGS) -s $$TB_NAME -o $(BUILD_DIR)/sim_$$TB_NAME.vvp "$$TB_FILE" $(RTL_SRCS); \
	echo "==> [Testbench: $$TB_NAME] Running Simulation <=="; \
	$(VVP) $(BUILD_DIR)/sim_$$TB_NAME.vvp; \
	echo "$$TB_NAME" > $(BUILD_DIR)/.last_tb; \
	echo "==> [Finished] Waveform saved to: $(BUILD_DIR)/$$TB_NAME.vcd (Marked as last run)"

test-all: $(BUILD_DIR)
	@echo "=================================================================="; \
	echo "               RUNNING ALL TESTBENCHES IN $(TB_DIR)/              "; \
	echo "=================================================================="; \
	TOTAL=0; PASSED=0; FAILED=0; FAIL_LIST=""; \
	for tb_file in $(ALL_TBS); do \
		tb_name=$$(basename $$tb_file .v); \
		TOTAL=$$((TOTAL + 1)); \
		echo ""; \
		echo "--> Running [$$tb_name] ..."; \
		if $(IVERILOG) $(IVERILOG_FLAGS) -s $$tb_name -o $(BUILD_DIR)/sim_$$tb_name.vvp "$$tb_file" $(RTL_SRCS) > /dev/null 2>&1 && \
		   $(VVP) $(BUILD_DIR)/sim_$$tb_name.vvp; then \
			PASSED=$$((PASSED + 1)); \
			echo "--> [PASS] $$tb_name"; \
		else \
			FAILED=$$((FAILED + 1)); \
			FAIL_LIST="$$FAIL_LIST $$tb_name"; \
			echo "--> [FAIL] $$tb_name"; \
		fi; \
		echo "$$tb_name" > $(BUILD_DIR)/.last_tb; \
	done; \
	echo ""; \
	echo "=================================================================="; \
	echo "                    TEST SUITE SUMMARY REPORT                     "; \
	echo "=================================================================="; \
	echo "  TOTAL TESTS : $$TOTAL"; \
	echo "  PASSED      : $$PASSED"; \
	echo "  FAILED      : $$FAILED"; \
	if [ $$FAILED -gt 0 ]; then \
		echo "  FAILURES    :$$FAIL_LIST"; \
		echo "=================================================================="; \
		exit 1; \
	else \
		echo "  ALL TESTS PASSED SUCCESSFULLY!"; \
		echo "=================================================================="; \
	fi

# ------------------------------------------------------------------------------
# 4. Waveform Viewer Target
#    Usage:
#      make wave                     (Opens waveform of the most recently run TB)
#      make wave TB=tb_smoke         (Opens specific waveform: build/tb_smoke.vcd)
# ------------------------------------------------------------------------------
wave:
ifdef TB
	@TARGET_VCD="$(BUILD_DIR)/$(patsubst %.v,%,$(TB)).vcd"; \
	if [ -f "$$TARGET_VCD" ]; then \
		echo "==> Opening specified waveform [$$TARGET_VCD] in GTKWave <=="; \
		$(GTKWAVE) "$$TARGET_VCD" & \
	else \
		echo "Error: Waveform file [$$TARGET_VCD] not found. Run 'make test TB=$(TB)' first."; \
		exit 1; \
	fi
else
	@if [ -f "$(BUILD_DIR)/.last_tb" ]; then \
		LAST_TB=$$(cat $(BUILD_DIR)/.last_tb); \
		TARGET_VCD="$(BUILD_DIR)/$$LAST_TB.vcd"; \
		if [ -f "$$TARGET_VCD" ]; then \
			echo "==> Opening last executed test waveform [$$TARGET_VCD] in GTKWave <=="; \
			echo "    (Tip: Use 'make wave TB=<name>' to view any specific waveform)"; \
			$(GTKWAVE) "$$TARGET_VCD" & \
		else \
			echo "Error: Last waveform $$TARGET_VCD not found. Run simulation first."; \
		fi \
	else \
		RECENT_VCD=$$(find $(BUILD_DIR) -name "*.vcd" 2>/dev/null | head -n 1); \
		if [ -n "$$RECENT_VCD" ]; then \
			echo "==> Opening found waveform [$$RECENT_VCD] in GTKWave <=="; \
			$(GTKWAVE) "$$RECENT_VCD" & \
		else \
			echo "Error: No .vcd waveform found in $(BUILD_DIR)/. Run 'make test' first."; \
		fi \
	fi
endif

# ------------------------------------------------------------------------------
# 5. Clean Target
# ------------------------------------------------------------------------------
clean:
	@echo "==> Cleaning build artifacts <=="
	rm -rf $(BUILD_DIR)
	rm -f *.vvp *.vcd *.log

# ------------------------------------------------------------------------------
# 6. Help Menu
# ------------------------------------------------------------------------------
help:
	@echo "AI-Accelerator-RTL Simulation Makefile"
	@echo ""
	@echo "RTL Compilation:"
	@echo "  make compile                  : Compile and check syntax of ALL RTL files"
	@echo "  make compile SRC=<file.v>     : Compile and check syntax of a SINGLE file"
	@echo "  make compile-all              : Alias to compile all RTL files"
	@echo ""
	@echo "Testing & Simulation:"
	@echo "  make smoke                    : Run default smoke test (tb_smoke)"
	@echo "  make test                     : Run default testbench (tb_smoke)"
	@echo "  make test TB=<tb_name>        : Run a specific testbench (e.g. make test TB=tb_smoke)"
	@echo "  make test-all                 : Run ALL testbenches in tb/ sequentially with summary"
	@echo ""
	@echo "Waveform Inspection:"
	@echo "  make wave                     : Open GTKWave on the LAST executed testbench waveform"
	@echo "  make wave TB=<tb_name>        : Open GTKWave on a specific testbench waveform"
	@echo ""
	@echo "Maintenance:"
	@echo "  make clean                    : Remove build/ directory and simulation dumps"
