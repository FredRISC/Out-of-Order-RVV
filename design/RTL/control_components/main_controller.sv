// ============================================================================
// main_controller.sv - Main Pipeline Controller
// ============================================================================
// Controls pipeline sequencing, stall signals, and operational modes

`include "../riscv_header.sv"

module main_controller (
    input clk,
    input rst_n,
    
    // Status signals
    input rs_full,
    input rob_full,
    input lsq_full,
    input branch_mispredict,
    
    // Control outputs
    output reg stall_fetch,
    output reg stall_decode,
    output reg stall_dispatch,
    output reg flush_pipeline,
    
    // Pipeline mode
    output reg [1:0] pipeline_mode  // 00=reset, 01=normal, 10=stall, 11=flush
);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            pipeline_mode <= 2'b00;
            stall_fetch <= 1'b0;
            stall_decode <= 1'b0;
            stall_dispatch <= 1'b0;
            flush_pipeline <= 1'b0;
        end else begin
            // Generate stalls based on resource availability
            if (rs_full || rob_full || lsq_full) begin
                pipeline_mode <= 2'b10;  // STALL mode
                stall_dispatch <= 1'b1;
                stall_decode <= 1'b1;
                stall_fetch <= 1'b1;
            end else begin
                pipeline_mode <= 2'b01;  // NORMAL mode
                stall_dispatch <= 1'b0;
                stall_decode <= 1'b0;
                stall_fetch <= 1'b0;
            end
            
            // Flush on branch mispredict
            if (branch_mispredict) begin
                pipeline_mode <= 2'b11;  // FLUSH mode
                flush_pipeline <= 1'b1;
            end else begin
                flush_pipeline <= 1'b0;
            end
        end
    end

endmodule
