// ============================================================================
// exception_handler.sv - Exception and Interrupt Handler
// ============================================================================
// Handles exceptions, interrupts, and pipeline flushing

`include "../riscv_header.sv"

module exception_handler (
    input clk,
    input rst_n,
    
    // Exception inputs
    input ext_irq,
    input illegal_instr,
    input instr_misalign,
    input load_misalign,
    input store_misalign,
    
    // Flush signals
    output reg flush_pipeline,
    output reg [EXCEPTION_CODE_WIDTH-1:0] exception_code,
    output reg exception_valid
);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            flush_pipeline <= 1'b0;
            exception_valid <= 1'b0;
            exception_code <= 0;
        end else begin
            flush_pipeline <= 1'b0;
            exception_valid <= 1'b0;
            
            // Priority encoding for exceptions
            if (instr_misalign) begin
                exception_valid <= 1'b1;
                exception_code <= `EXC_INSTR_MISALIGN;
                flush_pipeline <= 1'b1;
            end else if (illegal_instr) begin
                exception_valid <= 1'b1;
                exception_code <= `EXC_ILLEGAL_INSTR;
                flush_pipeline <= 1'b1;
            end else if (load_misalign) begin
                exception_valid <= 1'b1;
                exception_code <= `EXC_LOAD_MISALIGN;
                flush_pipeline <= 1'b1;
            end else if (store_misalign) begin
                exception_valid <= 1'b1;
                exception_code <= `EXC_STORE_MISALIGN;
                flush_pipeline <= 1'b1;
            end else if (ext_irq) begin
                exception_valid <= 1'b1;
                exception_code <= 5'h11;  // External interrupt
                flush_pipeline <= 1'b1;
            end
        end
    end

endmodule
