// ============================================================================
// reorder_buffer.sv - Reorder Buffer Implementation
// ============================================================================
// Maintains in-order instruction tracking for precise exceptions and commits

`include "../riscv_header.sv"

module reorder_buffer #(
    parameter ROB_SIZE = 16,
    parameter XLEN = 32
) (
    input clk,
    input rst_n,
    input flush,
    
    // Allocation interface (from decode)
    input [3:0] alloc_instr_type,
    input [4:0] alloc_dest_reg,
    input alloc_valid,
    output [5:0] alloc_tag,
    output rob_full,
    
    // Result interface (from CDB)
    input [XLEN-1:0] result_data,
    input [5:0] result_tag,
    input result_valid,
    
    // Commit interface
    output commit_valid,
    output [3:0] commit_instr_type,
    output [XLEN-1:0] commit_data,
    output [4:0] commit_dest_reg,
    output reg_write_en
);

    typedef struct packed {
        logic [3:0] instr_type;
        logic [4:0] dest_reg;
        logic [XLEN-1:0] result_value;
        logic result_ready;
        logic valid;
    } rob_entry_t;
    
    rob_entry_t [ROB_SIZE-1:0] rob_entries;
    logic [$clog2(ROB_SIZE)-1:0] head_ptr, tail_ptr;
    logic [$clog2(ROB_SIZE)-1:0] next_tail;
    
    // ========================================================================
    // Entry Allocation
    // ========================================================================
    
    assign rob_full = (next_tail == head_ptr) && rob_entries[tail_ptr].valid;
    assign alloc_tag = tail_ptr;
    assign next_tail = tail_ptr + 1;
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (int i = 0; i < ROB_SIZE; i++)
                rob_entries[i].valid <= 1'b0;
            head_ptr <= 0;
            tail_ptr <= 0;
        end else if (flush) begin
            for (int i = 0; i < ROB_SIZE; i++)
                rob_entries[i].valid <= 1'b0;
            head_ptr <= 0;
            tail_ptr <= 0;
        end else if (alloc_valid && !rob_full) begin
            rob_entries[tail_ptr].instr_type <= alloc_instr_type;
            rob_entries[tail_ptr].dest_reg <= alloc_dest_reg;
            rob_entries[tail_ptr].result_ready <= 1'b0;
            rob_entries[tail_ptr].valid <= 1'b1;
            tail_ptr <= next_tail;
        end
    end
    
    // ========================================================================
    // Result Broadcast Capture
    // ========================================================================
    
    always @(posedge clk) begin
        if (result_valid && rob_entries[result_tag].valid) begin
            rob_entries[result_tag].result_value <= result_data;
            rob_entries[result_tag].result_ready <= 1'b1;
        end
    end
    
    // ========================================================================
    // Commit Logic
    // ========================================================================
    
    assign commit_valid = rob_entries[head_ptr].valid && rob_entries[head_ptr].result_ready;
    assign commit_instr_type = rob_entries[head_ptr].instr_type;
    assign commit_data = rob_entries[head_ptr].result_value;
    assign commit_dest_reg = rob_entries[head_ptr].dest_reg;
    assign reg_write_en = commit_valid && 
                         (rob_entries[head_ptr].instr_type == `ITYPE_ALU ||
                          rob_entries[head_ptr].instr_type == `ITYPE_ALU_IMM ||
                          rob_entries[head_ptr].instr_type == `ITYPE_LOAD ||
                          rob_entries[head_ptr].instr_type == `ITYPE_JAL ||
                          rob_entries[head_ptr].instr_type == `ITYPE_JALR);
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            head_ptr <= 0;
        end else if (commit_valid) begin
            rob_entries[head_ptr].valid <= 1'b0;
            head_ptr <= head_ptr + 1;
        end
    end

endmodule
