// ============================================================================
// Makefile - Compilation and Simulation Script
// ============================================================================

# Compiler settings
IVERILOG = iverilog
VVP = vvp
VLOG_FLAGS = -g2009
OUTPUT = riscv_sim

# Source files
SOURCES = \
	riscv_header.sv \
	fetch_stage_SEPARATE.sv \
	decode_stage_SEPARATE.sv \
	dispatch_stage.sv \
	execute_stage.sv \
	writeback_stage.sv \
	commit_stage.sv \
	exception_handler.sv \
	main_controller.sv \
	forwarding_logic.sv \
	reservation_station.sv \
	reorder_buffer.sv \
	load_store_queue.sv \
	alu.sv \
	multiplier.sv \
	divider.sv \
	vector_execution_unit.sv \
	vector_lane.sv \
	register_file.sv \
	vector_register_file.sv \
	rename_table.sv \
	free_list.sv \
	common_data_bus.sv \
	branch_predictor.sv \
	hazard_detection.sv \
	riscv_core_top.sv \
	tb_riscv_core.sv

# Default target
.PHONY: all
all: compile

# Compilation target
.PHONY: compile
compile: $(SOURCES)
	@echo "Compiling RISC-V OoO Processor..."
	$(IVERILOG) $(VLOG_FLAGS) -I. $(SOURCES) -o $(OUTPUT)
	@echo "Compilation successful: $(OUTPUT)"

# Simulation target
.PHONY: sim
sim: compile
	@echo "Running simulation..."
	$(VVP) $(OUTPUT)

# Waveform target (for GTKWave)
.PHONY: waves
waves: compile
	@echo "Running simulation with waveform..."
	$(VVP) $(OUTPUT) -vcd

# Test target
.PHONY: test
test: sim

# Clean target
.PHONY: clean
clean:
	@echo "Cleaning build artifacts..."
	rm -f $(OUTPUT)
	rm -f *.vcd
	rm -f *.o
	@echo "Clean complete"

# Help target
.PHONY: help
help:
	@echo "Available targets:"
	@echo "  make compile  - Compile all sources"
	@echo "  make sim      - Compile and run simulation"
	@echo "  make test     - Same as sim"
	@echo "  make waves    - Generate VCD waveform"
	@echo "  make clean    - Remove build artifacts"
	@echo "  make help     - Show this help"
