// ============================================================================
// dispatch_stage.sv - Instruction Dispatch to Reservation Stations
// ============================================================================
// Routes instructions to appropriate reservation stations, allocates ROB/LSQ
// entries, and performs register renaming.

`include "../riscv_header.sv"

module dispatch_stage #(
    parameter XLEN = 32,
    parameter INST_WIDTH = 32,
    parameter NUM_INT_REGS = 32,
    parameter ALU_RS_SIZE = 8,
    parameter MEM_RS_SIZE = 8,
    parameter MUL_RS_SIZE = 4,
    parameter DIV_RS_SIZE = 4,
    parameter VEC_RS_SIZE = 8
) (
    input clk,
    input rst_n,
    input stall,
    input flush,
    
    // From decode stage
    input [INST_WIDTH-1:0] instr_in,
    input [3:0] instr_type,
    input [XLEN-1:0] pc_in,
    input valid_in,
    
    // Register file read
    input [XLEN-1:0] rs1_value, rs2_value,
    output [4:0] rs1_addr, rs2_addr,
    
    // Reservation station allocation
    output [3:0] rs_type,  // Which RS to use
    output rs_alloc_valid,
    output rs_alloc_stall,
    
    // ROB allocation
    output rob_alloc_valid,
    output [5:0] rob_alloc_tag,
    
    // LSQ allocation (for loads/stores)
    output lsq_alloc_valid,
    output [3:0] lsq_alloc_tag,
    
    // Output instruction fields
    output [XLEN-1:0] src1_value,
    output [XLEN-1:0] src2_value,
    output [XLEN-1:0] immediate,
    output [4:0] dest_reg,
    output [3:0] alu_op,
    
    output reg valid_out
);

    // Extract fields from instruction
    logic [6:0] opcode;
    logic [4:0] rs1, rs2, rd;
    logic [11:0] imm12;
    logic [3:0] funct3;
    logic [6:0] funct7;
    
    assign opcode = instr_in[6:0];
    assign rd = instr_in[11:7];
    assign funct3 = instr_in[14:12];
    assign rs1 = instr_in[19:15];
    assign rs2 = instr_in[24:20];
    assign funct7 = instr_in[31:25];
    assign imm12 = instr_in[31:20];
    
    assign rs1_addr = rs1;
    assign rs2_addr = rs2;
    assign dest_reg = rd;
    
    // Sign-extend immediate
    logic [XLEN-1:0] imm_extended;
    assign imm_extended = {{(XLEN-12){imm12[11]}}, imm12};
    assign immediate = imm_extended;
    
    // Decode instruction type to determine RS type
    always @(*) begin
        case (instr_type)
            `ITYPE_ALU:      rs_type = 4'b0001;  // ALU_RS
            `ITYPE_ALU_IMM:  rs_type = 4'b0001;  // ALU_RS
            `ITYPE_LOAD:     rs_type = 4'b0010;  // MEM_RS
            `ITYPE_STORE:    rs_type = 4'b0010;  // MEM_RS
            `ITYPE_BRANCH:   rs_type = 4'b0001;  // ALU_RS (for comparison)
            `ITYPE_MUL:      rs_type = 4'b0100;  // MUL_RS
            `ITYPE_DIV:      rs_type = 4'b1000;  // DIV_RS
            `ITYPE_VEC:      rs_type = 4'b1010;  // VEC_RS
            default:         rs_type = 4'b0000;
        endcase
    end
    
    // ALU operation decoding
    always @(*) begin
        case (funct3)
            `FUNCT3_ADD_SUB: alu_op = (funct7[5]) ? `ALU_SUB : `ALU_ADD;
            `FUNCT3_SLL:     alu_op = `ALU_SLL;
            `FUNCT3_SLT:     alu_op = `ALU_SLT;
            `FUNCT3_SLTU:    alu_op = `ALU_SLTU;
            `FUNCT3_XOR:     alu_op = `ALU_XOR;
            `FUNCT3_SR:      alu_op = (funct7[5]) ? `ALU_SRA : `ALU_SRL;
            `FUNCT3_OR:      alu_op = `ALU_OR;
            `FUNCT3_AND:     alu_op = `ALU_AND;
            default:         alu_op = `ALU_ADD;
        endcase
    end
    
    // Source operands
    assign src1_value = rs1_value;
    assign src2_value = rs2_value;
    
    // Control signals
    assign rs_alloc_valid = valid_in && !stall && !flush;
    assign rob_alloc_valid = valid_in && !stall && !flush;
    assign lsq_alloc_valid = (instr_type == `ITYPE_LOAD || instr_type == `ITYPE_STORE) 
                            && valid_in && !stall && !flush;
    
    // Stall if any RS is full (handled by external hazard detection)
    assign rs_alloc_stall = stall;
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            valid_out <= 1'b0;
        else if (flush)
            valid_out <= 1'b0;
        else if (!stall && valid_in)
            valid_out <= 1'b1;
        else
            valid_out <= 1'b0;
    end

endmodule
