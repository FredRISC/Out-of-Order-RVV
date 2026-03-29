// ============================================================================
// alu.sv - Arithmetic Logic Unit (1-cycle combinational)
// ============================================================================

`include "../riscv_header.sv"

module alu #(
    parameter XLEN = 32,
    parameter VLEN = 128
) (
    input clk,
    input rst_n,
    
    input [XLEN-1:0] operand1,
    input [XLEN-1:0] operand2,
    input [3:0] alu_op,
    input valid_in,
    
    output reg [XLEN-1:0] result,
    output reg valid_out
);

    // VLMAX Calculation for VSETVLI
    logic [31:0] sew_val;
    logic [31:0] lmul_val;
    logic [31:0] vlmax;
    
    // operand2 encodes vtype for VSETVLI in zimm[10:0]
    always @(*) begin
        // Decode SEW (Standard Element Width) from operand2[5:3]
        case (operand2[5:3])
            3'b000: sew_val = 32'd8;
            3'b001: sew_val = 32'd16;
            3'b010: sew_val = 32'd32;
            3'b011: sew_val = 32'd64;
            default: sew_val = 32'd32;
        endcase
        
        // Decode LMUL (Vector Length Multiplier) from operand2[2:0]
        case (operand2[2:0])
            3'b000: lmul_val = 32'd1;
            3'b001: lmul_val = 32'd2;
            3'b010: lmul_val = 32'd4;
            3'b011: lmul_val = 32'd8;
            default: lmul_val = 32'd1; // Note: Fractional LMUL treated as 1 for basic prototype
        endcase
        
        vlmax = (VLEN * lmul_val) / sew_val;
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            result <= 0;
            valid_out <= 1'b0;
        end else if (valid_in) begin
            valid_out <= 1'b1;
            case (alu_op)
                `ALU_ADD:  result <= operand1 + operand2;
                `ALU_SUB:  result <= operand1 - operand2;
                `ALU_AND:  result <= operand1 & operand2;
                `ALU_OR:   result <= operand1 | operand2;
                `ALU_XOR:  result <= operand1 ^ operand2;
                `ALU_SLL:  result <= operand1 << operand2[4:0];
                `ALU_SRL:  result <= operand1 >> operand2[4:0];
                `ALU_SRA:  result <= $signed(operand1) >>> operand2[4:0];
                `ALU_SLT:  result <= ($signed(operand1) < $signed(operand2)) ? 32'h1 : 32'h0;
                `ALU_SLTU: result <= (operand1 < operand2) ? 32'h1 : 32'h0;
                `ALU_VSETVL: result <= ((operand1 > vlmax) || (operand1 == 32'h0)) ? vlmax : operand1; // vsetvli; operand1 = AVL
                default:   result <= 32'h0;
            endcase
        end else begin
            valid_out <= 1'b0;
        end
    end

endmodule
