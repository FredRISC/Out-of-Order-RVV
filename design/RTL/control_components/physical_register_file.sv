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
    
    // Write port (from CDB - result broadcast)
    input [5:0] write_addr,        // Physical register ID (0-63)
    input [XLEN-1:0] write_data,
    input write_en,
    
    // Read ports (for operand forwarding)
    input [5:0] read_addr1,
    input [5:0] read_addr2,
    output logic [XLEN-1:0] read_data1,
    output logic [XLEN-1:0] read_data2,
    
    // Status bits (when result available)
    input [5:0] status_wr_addr,
    input status_wr_en,
    output logic [NUM_PHYS_REGS-1:0] status_valid  // Bit per physical reg
);

    logic [XLEN-1:0] phys_regs [NUM_PHYS_REGS-1:0];
    logic [NUM_PHYS_REGS-1:0] valid_bits;
    
    // Combinational reads
    assign read_data1 = phys_regs[read_addr1];
    assign read_data2 = phys_regs[read_addr2];
    assign status_valid = valid_bits;
    
    // Write on CDB result
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (int i = 0; i < NUM_PHYS_REGS; i++) begin
                phys_regs[i] <= 32'h0;
                valid_bits[i] <= 1'b0;
            end
        end else begin
            if (write_en)
                phys_regs[write_addr] <= write_data;
            if (status_wr_en)
                valid_bits[status_wr_addr] <= 1'b1;
        end
    end

endmodule