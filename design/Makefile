# ============================================================================
# Makefile - Compilation and Simulation Script
# ============================================================================

# Compiler settings
IVERILOG = iverilog
VVP = vvp
VLOG_FLAGS = -g2009
OUTPUT = riscv_sim

# Verilator settings
VERILATOR = verilator
VFLAGS = --binary --timing --Wno-fatal --top-module tb_disambiguation

# Source files
SOURCES = \
	RTL/riscv_header.sv \
	RTL/pipeline_stages/frontend/fetch_stage.sv \
	RTL/pipeline_stages/frontend/decode_stage.sv \
	RTL/pipeline_stages/frontend/dispatch_stage.sv \
	RTL/pipeline_stages/backend/issue_stage.sv \
	RTL/pipeline_stages/backend/reg_read_stage.sv \
	RTL/pipeline_stages/backend/execute_stage.sv \
	RTL/OoO_Core_Modules/reservation_station.sv \
	RTL/OoO_Core_Modules/reorder_buffer.sv \
	RTL/OoO_Core_Modules/load_store_queue.sv \
	RTL/OoO_Core_Modules/issue_scheduler.sv \
	RTL/functional_units/alu.sv \
	RTL/functional_units/multiplier.sv \
	RTL/functional_units/divider.sv \
	RTL/functional_units/vector_execution_unit.sv \
	RTL/functional_units/vector_lane.sv \
	RTL/control_components/physical_register_file.sv \
	RTL/control_components/vector_physical_register_file.sv \
	RTL/control_components/rat.sv \
	RTL/control_components/vector_rat.sv \
	RTL/control_components/free_list.sv \
	RTL/control_components/vector_free_list.sv \
	RTL/control_components/branch_predictor.sv \
	RTL/control_components/main_controller.sv \
	RTL/control_components/vector_csr.sv \
	RTL/riscv_core_top.sv \
	tb/tb_LsqForwarding_vadd.sv \
	tb/tb_disambiguation.sv \
	tb/tb_vector_mem.sv \


# Default target
.PHONY: all
all: compile

# Verilator targets
.PHONY: verilate
verilate:
	@echo "Compiling RISC-V OoO Processor with Verilator..."
	$(VERILATOR) $(VFLAGS) -I. $(SOURCES)

.PHONY: sim-verilator
sim-verilator: verilate
	@echo "Running Verilator simulation..."
	./obj_dir/Vtb_disambiguation

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
	rm -rf obj_dir
	@echo "Clean complete"

# Help target
.PHONY: help
help:
	@echo "Available targets:"
	@echo "  make sim-verilator - Compile and run using Verilator"
	@echo "  make compile  - Compile all sources"
	@echo "  make sim      - Compile and run simulation"
	@echo "  make test     - Same as sim"
	@echo "  make waves    - Generate VCD waveform"
	@echo "  make clean    - Remove build artifacts"
	@echo "  make help     - Show this help"
