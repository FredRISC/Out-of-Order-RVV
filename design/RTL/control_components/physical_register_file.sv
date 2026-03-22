// ============================================================================
// physical_register_file.sv - Speculative data storage
// ============================================================================
// Holds SPECULATIVE DATA during execution
// Results from functional units written here via CDB
// This is separate from architectural registers!

`include "riscv_header.sv"

module physical_register_file (
    input clk,
    input rst_n,
    
    // Write port 0 (from CDB 0 - Scheduled ALUs)
    input [5:0] write_addr0,        // Physical register ID (0-63)
    input [XLEN-1:0] write_data0,
    input write_en0,
    
    // Write port 1 (from CDB 1 - Unscheduled LSQ/DIV)
    input [5:0] write_addr1,
    input [XLEN-1:0] write_data1,
    input write_en1,
    
    // Read ports (read operands)
    input [5:0] read_addr1,
    input [5:0] read_addr2,
    output logic [XLEN-1:0] read_data1,
    output logic [XLEN-1:0] read_data2,
    
    // commit interface (read to update Arch Reg)
    input [5:0] commit_read_addr,
    output logic [XLEN-1:0] commit_read_data,
    
    // Valid Status signals (Used for RS operand ready checking)
    output logic [NUM_PHYS_REGS-1:0] status_valid,  // indicates which PRegs have valid data (written by CDB)
    
    // Allocation (clear valid bit)
    input [5:0] alloc_addr,
    input alloc_en // = valid_out && (dest_reg != x0) from dispatch stage; used to clear valid bit on allocation
);

    logic [XLEN-1:0] phys_regs [NUM_PHYS_REGS-1:0];
    logic [NUM_PHYS_REGS-1:0] valid_bits;
    
    // Combinational reads
    assign read_data1 = phys_regs[read_addr1];
    assign read_data2 = phys_regs[read_addr2];
    assign commit_read_data = phys_regs[commit_read_addr];
    // p0 is always valid (x0 constant)
    assign status_valid = {valid_bits[NUM_PHYS_REGS-1:1], 1'b1};
    
    // Write on CDB result
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (int i = 0; i < NUM_PHYS_REGS; i++) begin
                phys_regs[i] <= 32'h0;
                valid_bits[i] <= 1'b0;
            end
        end else begin
            if (write_en0) begin
                phys_regs[write_addr0] <= write_data0;
                valid_bits[write_addr0] <= 1'b1; 
            end
            if (write_en1) begin
                phys_regs[write_addr1] <= write_data1;
                valid_bits[write_addr1] <= 1'b1; 
            end
            if (alloc_en)
                valid_bits[alloc_addr] <= 1'b0; // Clear valid bit on allocation
        end
    end

endmodule