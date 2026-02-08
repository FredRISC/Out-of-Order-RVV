// ============================================================================
// alu.sv - Arithmetic Logic Unit (1-cycle combinational)
// ============================================================================

`include "../riscv_header.sv"

module alu #(
    parameter XLEN = 32
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
                `ALU_SRA:  result <= operand1 >>> operand2[4:0];
                `ALU_SLT:  result <= ($signed(operand1) < $signed(operand2)) ? 32'h1 : 32'h0;
                `ALU_SLTU: result <= (operand1 < operand2) ? 32'h1 : 32'h0;
                default:   result <= 32'h0;
            endcase
        end else begin
            valid_out <= 1'b0;
        end
    end

endmodule
