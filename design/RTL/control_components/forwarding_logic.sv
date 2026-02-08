// ============================================================================
// forwarding_logic.sv - UPDATED for RAT+PHYSICAL
// ============================================================================
// Provides operand forwarding from CDB results
// In RAT+PHYSICAL: CDB carries PHYSICAL register tags (not arch reg tags)

`include "riscv_header.sv"

module forwarding_logic (
    input clk,
    input rst_n,
    
    // CDB broadcast (from execute stage)
    input [XLEN-1:0] cdb_result,
    input [5:0] cdb_tag,           // PHYSICAL register tag (6 bits!)
    input cdb_valid,
    
    // Request: which physical regs do we need?
    input [5:0] req_src1_tag,      // Physical reg tag for source 1
    input [5:0] req_src2_tag,      // Physical reg tag for source 2
    
    // Forwarded values
    output logic [XLEN-1:0] forwarded_src1,
    output logic [XLEN-1:0] forwarded_src2,
    
    // Availability flags
    output logic src1_available,
    output logic src2_available
);

    // Latch CDB result for one cycle (for forwarding to next instruction)
    logic [XLEN-1:0] cdb_result_latched;
    logic [5:0] cdb_tag_latched;
    logic cdb_valid_latched;
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cdb_result_latched <= 0;
            cdb_tag_latched <= 0;
            cdb_valid_latched <= 1'b0;
        end else begin
            cdb_result_latched <= cdb_result;
            cdb_tag_latched <= cdb_tag;
            cdb_valid_latched <= cdb_valid;
        end
    end
    
    // Forward src1
    always @(*) begin
        if (cdb_valid && (cdb_tag == req_src1_tag)) begin
            forwarded_src1 = cdb_result;        // Direct from CDB (fastest)
            src1_available = 1'b1;
        end else if (cdb_valid_latched && (cdb_tag_latched == req_src1_tag)) begin
            forwarded_src1 = cdb_result_latched; // From latch (1 cycle old)
            src1_available = 1'b1;
        end else begin
            forwarded_src1 = 0;
            src1_available = 1'b0;
        end
    end
    
    // Forward src2
    always @(*) begin
        if (cdb_valid && (cdb_tag == req_src2_tag)) begin
            forwarded_src2 = cdb_result;
            src2_available = 1'b1;
        end else if (cdb_valid_latched && (cdb_tag_latched == req_src2_tag)) begin
            forwarded_src2 = cdb_result_latched;
            src2_available = 1'b1;
        end else begin
            forwarded_src2 = 0;
            src2_available = 1'b0;
        end
    end

endmodule

// ============================================================================
// KEY CHANGES FROM CLASSIC TO RAT+PHYSICAL
// ============================================================================
//
// Before (Classic):
//   - CDB tags were physical register IDs or ROB IDs
//   - Forwarding logic matched arbitrary tag types
//   - Inconsistent between rename schemes
//
// After (RAT+PHYSICAL):
//   - CDB tags are ALWAYS PHYSICAL register IDs (6 bits, 0-63)
//   - Forwarding logic matches physical register tags
//   - Consistent and clear
//
// This module:
//   - Compares incoming CDB tags with requested physical reg tags
//   - If match: forward the CDB result
//   - Tracks current + previous cycle (for multi-cycle dependencies)
//
// ============================================================================
