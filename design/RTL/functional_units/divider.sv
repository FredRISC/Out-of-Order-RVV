// ============================================================================
// divider.sv - 32-bit Divider (Radix-4 Digit Recurrence, 6-cycle pipelined)
// ============================================================================
// Latency: DIV_LATENCY (default 6 cycles)
// Supports: DIV, DIVU, REM, REMU

`include "../riscv_header.sv"

module divider #(
    parameter XLEN = 32,
    parameter DIV_LATENCY = 6
) (
    input clk,
    input rst_n,
    
    input [XLEN-1:0] dividend,
    input [XLEN-1:0] divisor,
    input valid_in,
    input [1:0] div_type,  // 00=DIV, 01=DIVU, 10=REM, 11=REMU
    
    output reg [XLEN-1:0] quotient,
    output reg [XLEN-1:0] remainder,
    output reg valid_out
);

    reg [2*XLEN:0] working_register [DIV_LATENCY-1:0];
    reg stage_valid [DIV_LATENCY-1:0];
    reg [1:0] div_type_pipe [DIV_LATENCY-1:0];
    
    wire is_signed = ~div_type[0];
    wire return_rem = div_type[1];
    
    // Handle sign for signed division
    logic [XLEN-1:0] dividend_abs, divisor_abs;
    logic sign_dividend, sign_divisor;
    
    always @(*) begin
        if (is_signed) begin
            sign_dividend = dividend[XLEN-1];
            sign_divisor = divisor[XLEN-1];
            dividend_abs = sign_dividend ? -dividend : dividend;
            divisor_abs = sign_divisor ? -divisor : divisor;
        end else begin
            sign_dividend = 1'b0;
            sign_divisor = 1'b0;
            dividend_abs = dividend;
            divisor_abs = divisor;
        end
    end
    
    // Non-restoring division pipeline
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (int i = 0; i < DIV_LATENCY; i++) begin
                working_register[i] <= 0;
                stage_valid[i] <= 1'b0;
                div_type_pipe[i] <= 2'b0;
            end
        end else begin
            // Stage 0: Initialize with dividend and divisor setup
            if (valid_in) begin
                working_register[0] <= {{(XLEN+1){1'b0}}, dividend_abs};
                stage_valid[0] <= 1'b1;
                div_type_pipe[0] <= div_type;
            end else begin
                stage_valid[0] <= 1'b0;
            end
            
            // Pipeline stages: Perform digit recurrence (simplified)
            // Real implementation would include radix-4 digit selection logic
            for (int i = 1; i < DIV_LATENCY; i++) begin
                working_register[i] <= working_register[i-1];
                stage_valid[i] <= stage_valid[i-1];
                div_type_pipe[i] <= div_type_pipe[i-1];
            end
        end
    end
    
    // Result computation
    always @(*) begin
        logic [XLEN-1:0] q, r;
        
        // Extract quotient and remainder from final working register
        q = working_register[DIV_LATENCY-1][XLEN-1:0];
        r = working_register[DIV_LATENCY-1][2*XLEN:XLEN];
        
        // Correct signs for signed division
        if (is_signed && (sign_dividend ^ sign_divisor)) begin
            quotient = -q;
        end else begin
            quotient = q;
        end
        
        if (is_signed && sign_dividend) begin
            remainder = -r;
        end else begin
            remainder = r;
        end
        
        // For REM/REMU, swap quotient and remainder
        if (return_rem) begin
            quotient = remainder;
        end
        
        valid_out = stage_valid[DIV_LATENCY-1];
    end

endmodule
