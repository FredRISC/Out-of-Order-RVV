// ============================================================================
// rat.sv (Register Alias Table)
// ============================================================================
// Maps architectural registers to PHYSICAL registers
// Key difference from rename_table:
//   - Maps to physical register IDs, not ROB IDs
//   - Tracks which phys reg holds which arch reg's value

`include "riscv_header.sv"

module rat (
    input clk,
    input rst_n,
    
    // Read (lookup which physical regs hold these arch regs)
    input [4:0] src1_arch,
    input [4:0] src2_arch,
    output logic [5:0] src1_phys,      // Physical reg ID
    output logic [5:0] src2_phys,      // Physical reg ID
    
    // Write (allocate new physical reg for destination)
    input [4:0] dst_arch,
    output logic [5:0] dst_phys,       // New physical reg ID
    
    // Rename enable
    input rename_en,
    
    // On commit (update to reflect last committed writer)
    input [4:0] commit_arch,
    input [5:0] commit_phys,
    input commit_en
);

    logic [5:0] rat_entries [NUM_INT_REGS-1:0];
    
    // Read: combinational lookup
    assign src1_phys = rat_entries[src1_arch];
    assign src2_phys = rat_entries[src2_arch];
    
    // Allocate: round-robin or free list lookup
    // For simplicity, use simple scheme
    logic [5:0] alloc_counter;
    assign dst_phys = alloc_counter;
    
    // Sequential updates
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            // Initialize: arch reg i maps to phys reg i (0-31)
            for (int i = 0; i < NUM_INT_REGS; i++)
                rat_entries[i] <= i[5:0];
            alloc_counter <= 32;  // Start allocating from 32
        end else begin
            if (rename_en) begin
                rat_entries[dst_arch] <= dst_phys;
                alloc_counter <= alloc_counter + 1;
                if (alloc_counter >= 63)
                    alloc_counter <= 32;  // Wrap around
            end
            if (commit_en)
                rat_entries[commit_arch] <= commit_phys;  // Update on commit
        end
    end

endmodule