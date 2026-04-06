// ============================================================================
// components/branch_predictor.sv - 2-bit BHT/BTB Branch Predictor
// ============================================================================

`include "RTL/riscv_header.sv"

module branch_predictor (
    input clk,
    input rst_n,
    
    // Prediction request
    input [`XLEN-1:0] pc,
    output reg predicted_branch,
    output reg [`XLEN-1:0] predicted_target,
    
    // Update on branch resolution
    input [`XLEN-1:0] resolved_pc,
    input [`XLEN-1:0] resolved_target,
    input branch_taken,
    input branch_update_en
);

    reg [1:0] branch_history [`BHT_SIZE-1:0];  // 2-bit BHT
    reg [`XLEN-1:0] target_history [`BHT_SIZE-1:0]; // BTB for target addresses
    
    logic [7:0] pc_hash;
    assign pc_hash = pc[9:2];  // Hash PC to BHT index
    
    always @(*) begin
        predicted_branch = branch_history[pc_hash][1];
        predicted_target = (predicted_branch) ? target_history[pc_hash] : (pc + 4);
    end
    
    // Update BHT and BTB on branch resolution
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (int i = 0; i < `BHT_SIZE; i++) begin
                branch_history[i] <= 2'b01;  // Weakly not taken
                target_history[i] <= 32'h0;
            end
        end else if (branch_update_en) begin
            logic [7:0] update_idx;
            update_idx = resolved_pc[9:2];
            
            if (branch_taken && (branch_history[update_idx] != 2'b11)) begin
                branch_history[update_idx] <= branch_history[update_idx] + 1;
                target_history[update_idx] <= resolved_target; // Update target on taken branches
            end else if (!branch_taken && (branch_history[update_idx] != 2'b00)) begin
                branch_history[update_idx] <= branch_history[update_idx] - 1;
                // Do not update target on not-taken branches
            end
        end
    end

endmodule
