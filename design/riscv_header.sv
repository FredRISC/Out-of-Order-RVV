// ============================================================================
// riscv_header.sv
// ============================================================================
// Include this in ALL modules with: `include "riscv_header.sv"

`ifndef RISCV_HEADER_SV
`define RISCV_HEADER_SV

// ============================================================================
// INSTRUCTION SET ARCHITECTURE (RISC-V RV32IM)
// ============================================================================

parameter XLEN = 32;              // Scalar register width
parameter INST_WIDTH = 32;        // Instruction width

// Instruction types (for routing in dispatch)
parameter logic [3:0] `ITYPE_ALU = 4'h0;       // ADD, SUB, AND, OR, XOR, SLL, SRL, SRA, SLT, SLTU
parameter logic [3:0] `ITYPE_ALU_IMM = 4'h1;  // ADDI, ANDI, ORI, XORI, SLLI, SRLI, SRAI
parameter logic [3:0] `ITYPE_LOAD = 4'h2;     // LW, LH, LB, LBU, LHU
parameter logic [3:0] `ITYPE_STORE = 4'h3;    // SW, SH, SB
parameter logic [3:0] `ITYPE_BRANCH = 4'h4;   // BEQ, BNE, BLT, BGE, BLTU, BGEU
parameter logic [3:0] `ITYPE_JAL = 4'h5;      // JAL, JALR
parameter logic [3:0] `ITYPE_LUI = 4'h6;      // LUI, AUIPC
parameter logic [3:0] `ITYPE_MUL = 4'h7;      // MUL, MULH, MULHSU, MULHU (RV32M)
parameter logic [3:0] `ITYPE_DIV = 4'h8;      // DIV, DIVU, REM, REMU (RV32M)
parameter logic [3:0] `ITYPE_VEC = 4'h9;      // VADD, VMUL, etc (RVV)

// Exception codes
parameter EXCEPTION_CODE_WIDTH = 4;
parameter logic [EXCEPTION_CODE_WIDTH-1:0] `EXC_EXTERNAL_INT = 4'h0;
parameter logic [EXCEPTION_CODE_WIDTH-1:0] `EXC_ILLEGAL_INSTR = 4'h2;
parameter logic [EXCEPTION_CODE_WIDTH-1:0] `EXC_INSTR_MISALIGN = 4'h0;
parameter logic [EXCEPTION_CODE_WIDTH-1:0] `EXC_LOAD_MISALIGN = 4'h4;
parameter logic [EXCEPTION_CODE_WIDTH-1:0] `EXC_STORE_MISALIGN = 4'h6;

// ============================================================================
// REGISTER FILES
// ============================================================================

// Scalar registers
parameter NUM_INT_REGS = 32;           // x0-x31 (architectural)

// Vector registers
parameter NUM_VEC_REGS = 32;           // v0-v31 (architectural)

// ============================================================================
// PHYSICAL REGISTERS (RAT+PHYSICAL SPECIFIC)
// ============================================================================

parameter NUM_PHYS_REGS = 64;          // 64 physical registers total
                                        // 32 for arch (x0-x31)
                                        // 32 extra for speculation

parameter PHYS_REG_TAG_WIDTH = 6;      // 6 bits to address 64 phys regs (0-63)

// ============================================================================
// PIPELINE STRUCTURE
// ============================================================================

// Reservation stations
parameter ALU_RS_SIZE = 8;             // ALU reservation station entries
parameter MEM_RS_SIZE = 8;             // Load/Store RS entries
parameter MUL_RS_SIZE = 4;             // Multiplier RS entries
parameter DIV_RS_SIZE = 4;             // Divider RS entries
parameter VEC_RS_SIZE = 8;             // Vector RS entries

// Reorder Buffer
parameter ROB_SIZE = 16;               // Instruction window size

// Load-Store Queue
parameter LSQ_LQ_SIZE = 8;             // Load queue depth
parameter LSQ_SQ_SIZE = 8;             // Store queue depth

// ============================================================================
// FUNCTIONAL UNIT LATENCIES (PIPELINED)
// ============================================================================

parameter MUL_LATENCY = 4;             // Multiplier: 4-cycle pipeline
parameter DIV_LATENCY = 6;             // Divider: 6-cycle pipeline

// ============================================================================
// VECTOR EXTENSION (RVV)
// ============================================================================

parameter VLEN = 128;                  // Vector register width (bits)
parameter VLMAX = 16;                  // Max vector length (elements for 32-bit)
parameter ELEN = 32;                   // Element width (bits)
parameter NUM_VEC_LANES = 4;           // Number of parallel lanes

// ============================================================================
// CDB (COMMON DATA BUS)
// ============================================================================

parameter CDB_TAG_WIDTH = 6;           // Matches PHYS_REG_TAG_WIDTH in RAT+PHYSICAL
                                        // CDB broadcasts PHYSICAL register tags

// ============================================================================
// FORWARDING & OPERAND DELIVERY
// ============================================================================

// In RAT+PHYSICAL:
// - Operands identified by PHYSICAL register tags (6 bits)
// - CDB carries physical reg tags
// - Forwarding logic matches phys reg tags
// - Results stored in physical_register_file (not ROB)

// ============================================================================
// DEBUG / SIMULATION
// ============================================================================

parameter SIMULATION = 1;              // Set 0 for synthesis
parameter DEBUG_LEVEL = 1;             // Debug verbosity (0-3)

`endif // RISCV_HEADER_SV
