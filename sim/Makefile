# ==============================================================================
# Makefile for Icarus Verilog & GTKWave Simulation
# ==============================================================================

# Directories
PROJECT_ROOT = ..
RTL_DIR      = $(PROJECT_ROOT)/rtl
TB_DIR       = $(PROJECT_ROOT)/tb
MODEL_DIR    = $(PROJECT_ROOT)/model
BUILD_DIR    = build

# Simulator flags
IVERILOG       = iverilog
VVP            = vvp
GTKWAVE        = gtkwave
IVERILOG_FLAGS = -Wall -g2012 -I $(RTL_DIR) -I $(TB_DIR)

# Default Testbench target (change via `make TB=your_tb` or `make run TB=your_tb`)
TB           ?= tb_mac
TOP_MODULE   ?= $(TB)

# Source files (all .v and .sv in rtl and tb)
RTL_SRCS     = $(wildcard $(RTL_DIR)/*.v) $(wildcard $(RTL_DIR)/*.sv)
TB_SRCS      = $(wildcard $(TB_DIR)/*.v) $(wildcard $(TB_DIR)/*.sv)

# Targets
OUTPUT_VVP   = $(BUILD_DIR)/$(TOP_MODULE).vvp
VCD_FILE     = $(BUILD_DIR)/dump.vcd

.PHONY: all compile run sim wave clean help

all: run

$(BUILD_DIR):
	mkdir -p $(BUILD_DIR)

# Compilation target
compile: $(BUILD_DIR)
	@echo "==> Compiling with Icarus Verilog: $(TOP_MODULE) <=="
	$(IVERILOG) $(IVERILOG_FLAGS) -s $(TOP_MODULE) -o $(OUTPUT_VVP) $(RTL_SRCS) $(TB_SRCS)

# Simulation target
run sim: compile
	@echo "==> Running simulation: $(TOP_MODULE) <=="
	cd $(BUILD_DIR) && $(VVP) $(notdir $(OUTPUT_VVP))

# Waveform viewing target
wave:
	@if [ -f $(VCD_FILE) ]; then \
		echo "==> Opening waveform in GTKWave <=="; \
		$(GTKWAVE) $(VCD_FILE) & \
	elif [ -f dump.vcd ]; then \
		echo "==> Opening waveform in GTKWave <=="; \
		$(GTKWAVE) dump.vcd & \
	else \
		echo "Error: $(VCD_FILE) or dump.vcd not found. Run 'make sim' first."; \
	fi

# Clean target
clean:
	@echo "==> Cleaning simulation artifacts <=="
	rm -rf $(BUILD_DIR)
	rm -f *.vvp *.vcd *.log

# Help target
help:
	@echo "Usage:"
	@echo "  make              : Compile and run default testbench ($(TB))"
	@echo "  make compile      : Only compile RTL & TB"
	@echo "  make sim          : Compile and run simulation"
	@echo "  make wave         : Open waveform with GTKWave"
	@echo "  make clean        : Remove build directory and simulation dumps"
	@echo "  make TB=<tb_name> : Run a specific testbench (e.g., make TB=tb_mac)"
