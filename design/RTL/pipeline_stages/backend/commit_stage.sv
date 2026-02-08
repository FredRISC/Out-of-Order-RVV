// ============================================================================
// commit_stage.sv - Commit Stage (In-Order Retirement)
// ============================================================================
// Retires instructions in order from the Reorder Buffer and writes results
// to the architectural register file.

`include "../riscv_header.sv"

module commit_stage #(
    parameter XLEN = 32,
    parameter NUM_INT_REGS = 32
) (
    input clk,
    input rst_n,
    
    // From ROB
    input [XLEN-1:0] rob_result,
    input [4:0] rob_dest_reg,
    input rob_valid,
    input [3:0] rob_instr_type,
    
    // Write to architectural register file
    output reg [4:0] reg_write_addr,
    output reg [XLEN-1:0] reg_write_data,
    output reg reg_write_en,
    
    // Debug: register file readout
    output [NUM_INT_REGS-1:0][XLEN-1:0] debug_reg_file
);

    // Architectural register file
    reg [XLEN-1:0] regs [NUM_INT_REGS-1:0];
    
    // Commit logic
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (int i = 0; i < NUM_INT_REGS; i++)
                regs[i] <= 0;
            reg_write_en <= 1'b0;
        end else if (rob_valid) begin
            // Only write back for arithmetic/load instructions (not branches/stores)
            if (rob_instr_type == `ITYPE_ALU || 
                rob_instr_type == `ITYPE_ALU_IMM ||
                rob_instr_type == `ITYPE_LOAD ||
                rob_instr_type == `ITYPE_JAL ||
                rob_instr_type == `ITYPE_JALR) begin
                
                reg_write_en <= 1'b1;
                reg_write_addr <= rob_dest_reg;
                reg_write_data <= rob_result;
                
                // Update local register file
                if (rob_dest_reg != 5'b0) begin  // x0 is hardwired to 0
                    regs[rob_dest_reg] <= rob_result;
                end
            end else begin
                reg_write_en <= 1'b0;
            end
        end else begin
            reg_write_en <= 1'b0;
        end
    end
    
    // Debug register file readout (asynchronous)
    generate
        genvar i;
        for (i = 0; i < NUM_INT_REGS; i++) begin
            assign debug_reg_file[i] = regs[i];
        end
    endgenerate

endmodule
