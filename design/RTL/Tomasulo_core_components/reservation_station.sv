// ============================================================================
// reservation_station.sv - Generic Reservation Station
// ============================================================================
// Implements a single reservation station for the Tomasulo algorithm.
// Holds instructions waiting for operands and executes when ready.

`include "../riscv_header.sv"

module reservation_station #(
    parameter RS_SIZE = 8,
    parameter XLEN = 32,
    parameter RS_TAG_WIDTH = 3
) (
    input clk,
    input rst_n,
    input flush,
    
    // Dispatch interface
    input [XLEN-1:0] src1_value,
    input [RS_TAG_WIDTH-1:0] src1_tag,
    input src1_valid,
    input [XLEN-1:0] src2_value,
    input [RS_TAG_WIDTH-1:0] src2_tag,
    input src2_valid,
    input [XLEN-1:0] immediate,
    input [3:0] alu_op,
    input dispatch_valid,
    
    // CDB broadcast interface
    input [XLEN-1:0] cdb_result,
    input [RS_TAG_WIDTH-1:0] cdb_tag,
    input cdb_valid,
    
    // Execute interface
    output [XLEN-1:0] operand1,
    output [XLEN-1:0] operand2,
    output [3:0] execute_op,
    output execute_valid,
    
    // Status
    output rs_full,
    output [RS_TAG_WIDTH-1:0] assigned_tag
);

    // ========================================================================
    // Reservation Station Entry Structure
    // ========================================================================
    
    typedef struct packed {
        logic [XLEN-1:0] src1_val;
        logic [XLEN-1:0] src2_val;
        logic [XLEN-1:0] imm_val;
        logic [RS_TAG_WIDTH-1:0] src1_tag_val;
        logic [RS_TAG_WIDTH-1:0] src2_tag_val;
        logic src1_ready;
        logic src2_ready;
        logic [3:0] alu_op_val;
        logic busy;
    } rs_entry_t;
    
    rs_entry_t [RS_SIZE-1:0] rs_entries;
    logic [RS_SIZE-1:0] entry_ready;
    
    // Free list management
    logic [$clog2(RS_SIZE)-1:0] next_free_idx;
    logic [$clog2(RS_SIZE)-1:0] issue_idx;
    
    // ========================================================================
    // Entry Allocation
    // ========================================================================
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (int i = 0; i < RS_SIZE; i++) begin
                rs_entries[i].busy <= 1'b0;
            end
            next_free_idx <= 0;
        end else if (flush) begin
            for (int i = 0; i < RS_SIZE; i++) begin
                rs_entries[i].busy <= 1'b0;
            end
        end else if (dispatch_valid && !rs_full) begin
            // Allocate new entry
            rs_entries[next_free_idx].src1_val <= src1_value;
            rs_entries[next_free_idx].src2_val <= src2_value;
            rs_entries[next_free_idx].imm_val <= immediate;
            rs_entries[next_free_idx].src1_tag_val <= src1_tag;
            rs_entries[next_free_idx].src2_tag_val <= src2_tag;
            rs_entries[next_free_idx].src1_ready <= src1_valid;
            rs_entries[next_free_idx].src2_ready <= src2_valid;
            rs_entries[next_free_idx].alu_op_val <= alu_op;
            rs_entries[next_free_idx].busy <= 1'b1;
            
            // Advance free pointer
            next_free_idx <= next_free_idx + 1;
        end
    end
    
    // ========================================================================
    // Operand Forwarding from CDB
    // ========================================================================
    
    always @(posedge clk) begin
        if (cdb_valid) begin
            for (int i = 0; i < RS_SIZE; i++) begin
                if (rs_entries[i].busy && !rs_entries[i].src1_ready) begin
                    if (rs_entries[i].src1_tag_val == cdb_tag) begin
                        rs_entries[i].src1_val <= cdb_result;
                        rs_entries[i].src1_ready <= 1'b1;
                    end
                end
                if (rs_entries[i].busy && !rs_entries[i].src2_ready) begin
                    if (rs_entries[i].src2_tag_val == cdb_tag) begin
                        rs_entries[i].src2_val <= cdb_result;
                        rs_entries[i].src2_ready <= 1'b1;
                    end
                end
            end
        end
    end
    
    // ========================================================================
    // Ready Detection and Issue Selection
    // ========================================================================
    
    always @(*) begin
        for (int i = 0; i < RS_SIZE; i++) begin
            entry_ready[i] = rs_entries[i].busy && 
                           rs_entries[i].src1_ready && 
                           rs_entries[i].src2_ready;
        end
    end
    
    // Priority encoder: select first ready entry
    always @(*) begin
        issue_idx = 0;
        for (int i = 0; i < RS_SIZE; i++) begin
            if (entry_ready[i]) begin
                issue_idx = i;
                break;
            end
        end
    end
    
    // ========================================================================
    // Execution Port
    // ========================================================================
    
    assign execute_valid = (entry_ready != 0);
    assign operand1 = rs_entries[issue_idx].src1_val;
    assign operand2 = rs_entries[issue_idx].src2_val;
    assign execute_op = rs_entries[issue_idx].alu_op_val;
    
    // Mark entry as free after execution
    always @(posedge clk) begin
        if (execute_valid) begin
            rs_entries[issue_idx].busy <= 1'b0;
        end
    end
    
    // ========================================================================
    // Status Signals
    // ========================================================================
    
    assign rs_full = (next_free_idx == 0) && (rs_entries[0].busy);
    assign assigned_tag = next_free_idx;

endmodule
