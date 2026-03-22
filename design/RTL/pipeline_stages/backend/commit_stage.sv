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
    input [4:0] rob_dest_reg,
    input [5:0] rob_dest_phys,
    input rob_valid,
    input [3:0] rob_instr_type,
    
    // To/From Physical Register File (Reading speculative result)
    output logic [5:0] commit_read_addr,
    input [XLEN-1:0] commit_read_data,
    
    // Write to architectural register file
    output logic [4:0] reg_write_addr,
    output logic [XLEN-1:0] reg_write_data,
    output logic reg_write_en
);

    // Commit is purely combinational routing to the architectural register file
    always @(*) begin
        reg_write_en = 1'b0;
        reg_write_addr = 5'b0;
        reg_write_data = commit_read_data; // Data fetched from PRF
        commit_read_addr = rob_dest_phys;  // Tell PRF which register to read
        
        // Only write if there is a valid commit, the destination is not x0,
        // and it is a scalar integer instruction.
        if (rob_valid && rob_dest_reg != 5'b0 && rob_instr_type != `V_EXT_VEC && rob_instr_type != `V_EXT_LOAD) begin
            reg_write_en = 1'b1;
            reg_write_addr = rob_dest_reg;
        end
    end

endmodule
