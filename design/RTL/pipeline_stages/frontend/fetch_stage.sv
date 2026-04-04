// ============================================================================
// fetch_stage.sv - Instruction Fetch Stage
// ============================================================================
// Retrieves instructions from instruction memory and manages program counter

`include "../riscv_header.sv"

module fetch_stage (
    input clk,
    input rst_n,
    input stall,
    input flush,
    input [`XLEN-1:0] flush_pc,
    input predicted_branch_in, // From branch predictor
    input [`XLEN-1:0] predicted_target_in,
    
    output reg [`XLEN-1:0] pc_out,
    output reg [`INST_WIDTH-1:0] instr_out,
    output reg valid_out,
    
    output reg [`XLEN-1:0] imem_addr,
    input [`INST_WIDTH-1:0] imem_data,
    input imem_valid
);

    reg [`XLEN-1:0] pc_current;
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            // On reset, initialize PC to 0 and invalidate output
            pc_current <= 32'h0;
            valid_out <= 1'b0;
        end else if (flush) begin
            // On flush, update PC to requested target and invalidate output.
            // This will cause the target instruction to be fetched in the next cycle.
            pc_current <= flush_pc;
            valid_out <= 1'b1;
        end else if (!stall && imem_valid) begin
            // Fetch new instruction if not stalled and instruction memory is valid
            instr_out <= imem_data;
            pc_out <= pc_current;
            valid_out <= 1'b1;
            
            // Use predictor to determine next PC
            if (predicted_branch_in)
                pc_current <= predicted_target_in;
            else
                pc_current <= pc_current + 32'h4;
        end
    end
    
    //Interface Decoupling and Reserved for potential Address Translation (virtual to physical)
    always @(*) 
        imem_addr = pc_current;

endmodule
