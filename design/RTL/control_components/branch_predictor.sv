// ============================================================================
// components/branch_predictor.sv - Simple Static Branch Predictor
// ============================================================================

module branch_predictor #(
    parameter XLEN = 32,
    parameter BHT_SIZE = 256
) (
    input clk,
    input rst_n,
    
    // Prediction request
    input [XLEN-1:0] pc,
    output reg predicted_branch,
    output reg [XLEN-1:0] predicted_target,
    
    // Update on branch resolution
    input [XLEN-1:0] resolved_pc,
    input [XLEN-1:0] resolved_target,
    input branch_taken,
    input branch_update_en
);

    reg [1:0] branch_history [BHT_SIZE-1:0];  // 2-bit saturating counter
    
    logic [7:0] pc_hash;
    assign pc_hash = pc[9:2];  // Hash PC to BHT index
    
    always @(*) begin
        predicted_branch = branch_history[pc_hash][1];
        // Static prediction: backward branches taken, forward not taken
        predicted_target = (pc[XLEN-1:0] + 32'h0) & {{(XLEN-2){1'b1}}, 2'b00};
    end
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (int i = 0; i < BHT_SIZE; i++)
                branch_history[i] <= 2'b01;  // Weakly not taken
        end else if (branch_update_en) begin
            logic [7:0] update_idx;
            update_idx = resolved_pc[9:2];
            
            if (branch_taken && (branch_history[update_idx] != 2'b11)) begin
                branch_history[update_idx] <= branch_history[update_idx] + 1;
            end else if (!branch_taken && (branch_history[update_idx] != 2'b00)) begin
                branch_history[update_idx] <= branch_history[update_idx] - 1;
            end
        end
    end

endmodule
