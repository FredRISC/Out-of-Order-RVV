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
    
    // Pass through register addresses (ID)
    assign rs1_addr = rs1;
    assign rs2_addr = rs2;
    assign dest_reg = rd;
    
    // Pass through source operands
    assign src1_value = rs1_value;
    assign src2_value = rs2_value;

    // Sign-extend immediate
    logic [XLEN-1:0] imm_extended;
    assign imm_extended = {{(XLEN-12){imm12[11]}}, imm12};
    assign immediate = imm_extended;
    
    
    // ALU operation decoding - alu_op is used by functional units to determine operation type
    always @(*) begin
        if (instr_type == `V_EXT_VEC) begin
            // Vector Operation Decoding (based on funct6)
            // Note: We currently ONLY support Vector-Vector (.VV) OPVV operations. 
            // RISC-V use funct3 to distinguish between .VV, .VX, and .VI
            // .VV ops use funct3 = 3'b000 (OPIVV - Integer Vector-Vector) or 3'b010 (OPMVV - Mask/Miscellaneous Vector-Vector).
            // .VX (Scalar) and .VI (Immediate) are filtered out here to prevent mis-execution.
            if (funct3 == 3'b000 || funct3 == 3'b010) begin
                case (funct7[6:1]) // funct6 is top 6 bits of funct7
                    6'b000000: alu_op = `VEC_OP_ADD;
                    6'b000010: alu_op = `VEC_OP_SUB;
                    6'b100101: begin // This funct6 is shared by VMUL.VV and VSLL.VV
                        case(funct3)
                            3'b010: alu_op = `VEC_OP_MUL; // VMUL.VV (OPMVV)
                            3'b000: alu_op = `VEC_OP_SLL; // VSLL.VV (OPIVV)
                            default: alu_op = `UNKNOWN_VEC_OP;
                        endcase
                    end
                    6'b001001: alu_op = `VEC_OP_AND;
                    6'b001010: alu_op = `VEC_OP_OR;
                    6'b001011: alu_op = `VEC_OP_XOR;
                    6'b101000: alu_op = `VEC_OP_SRL;
                    default:   alu_op = `UNKNOWN_VEC_OP; // Default for unhandled funct6
                endcase
            end else begin
                alu_op = `UNKNOWN_VEC_OP;
            end
        end else begin
            // Scalar ALU Operation Decoding
            case (funct3)
                `FUNCT3_ADD_SUB: alu_op = (funct7[5] && instr_type != `IBASE_ALU_IMM) ? `ALU_SUB : `ALU_ADD;
                `FUNCT3_SLL:     alu_op = `ALU_SLL;
                `FUNCT3_SLT:     alu_op = `ALU_SLT;
                `FUNCT3_SLTU:    alu_op = `ALU_SLTU;
                `FUNCT3_XOR:     alu_op = `ALU_XOR;
                `FUNCT3_SR:      alu_op = (funct7[5]) ? `ALU_SRA : `ALU_SRL;
                `FUNCT3_OR:      alu_op = `ALU_OR;
                `FUNCT3_AND:     alu_op = `ALU_AND;
                default:         alu_op = `ALU_ADD; // Default for address calcs (LOAD/STORE) and other ops
                                                   // This is safer than UNKNOWN_ALU_OP, which could fail address generation.
            endcase
        end
    end

    // Decode instruction type to determine RS type
    always @(*) begin
        case (instr_type)
            `IBASE_ALU:      rs_type = 4'b0001;  // ALU_RS
            `IBASE_ALU_IMM:  rs_type = 4'b0001;  // ALU_RS
            `IBASE_LOAD:     rs_type = 4'b0010;  // MEM_RS
            `IBASE_STORE:    rs_type = 4'b0010;  // MEM_RS
            `IBASE_LUI:      rs_type = 4'b0001;  // ALU_RS
            `IBASE_AUIPC:    rs_type = 4'b0001;  // ALU_RS
            `IBASE_JAL:      rs_type = 4'b0001;  // ALU_RS
            `IBASE_JALR:     rs_type = 4'b0001;  // ALU_RS
            `IBASE_BRANCH:   rs_type = 4'b0001;  // ALU_RS (for comparison)
            `M_EXT_MUL:      rs_type = 4'b0100;  // MUL_RS
            `M_EXT_DIV:      rs_type = 4'b1000;  // DIV_RS
            `V_EXT_VEC:      rs_type = 4'b1010;  // VEC_RS
            `V_EXT_LOAD:     rs_type = 4'b0010;  // MEM_RS (Vector Loads go to MEM RS)
            `V_EXT_STORE:    rs_type = 4'b0010;  // MEM_RS (Vector Stores go to MEM RS)
            default:         rs_type = 4'b0000;
        endcase
    end
    
    // Control signals
    assign rs_alloc_valid = valid_in && !stall && !flush;
    assign rob_alloc_valid = valid_in && !stall && !flush;
    assign lsq_alloc_valid = (instr_type == `IBASE_LOAD || instr_type == `IBASE_STORE) 
                            && valid_in && !stall && !flush;
    
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
