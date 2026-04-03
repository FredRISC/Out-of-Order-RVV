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

    // Pipeline stages
    reg [XLEN-1:0] q_pipe [DIV_LATENCY-1:0];
    reg [XLEN-1:0] r_pipe [DIV_LATENCY-1:0];
    reg stage_valid [DIV_LATENCY-1:0];
    reg [1:0] div_type_pipe [DIV_LATENCY-1:0];
    
    wire is_signed = ~div_type[0];
    
    // Combinational math for Stage 0 (RISC-V Compliant)
    logic [XLEN-1:0] q_comb, r_comb;
    
    // Behavioral modeling of division with RISC-V specified edge cases handled
    // Replace this with real divider IP. This is just for functional correctness in the prototype.
    always @(*) begin
        q_comb = 32'b0;
        r_comb = 32'b0;
        
        if (divisor == 32'h0) begin
            // RISC-V Spec: Divide by zero
            q_comb = 32'hFFFFFFFF; // -1
            r_comb = dividend;     // remainder = dividend
        end else if (is_signed && dividend == 32'h80000000 && divisor == 32'hFFFFFFFF) begin
            // RISC-V Spec: Signed Overflow (-2^31 / -1); maximum negative number divided by -1
            q_comb = 32'h80000000;
            r_comb = 32'h0;
        end else begin
            // Normal Division
            if (is_signed) begin
                q_comb = $signed(dividend) / $signed(divisor);
                r_comb = $signed(dividend) % $signed(divisor);
            end else begin
                q_comb = dividend / divisor;
                r_comb = dividend % divisor;
            end
        end
    end
    
    // Behavioral Pipeline Delay
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (int i = 0; i < DIV_LATENCY; i++) begin
                q_pipe[i] <= 0;
                r_pipe[i] <= 0;
                stage_valid[i] <= 1'b0;
                div_type_pipe[i] <= 2'b0;
            end
        end else begin
            // Stage 0: Latch the combinational result
            if (valid_in) begin
                q_pipe[0] <= q_comb;
                r_pipe[0] <= r_comb;
                stage_valid[0] <= 1'b1;
                div_type_pipe[0] <= div_type;
            end else begin
                stage_valid[0] <= 1'b0;
            end
            
            // Pipeline stages 1 to N: Shift forward
            for (int i = 1; i < DIV_LATENCY; i++) begin
                q_pipe[i] <= q_pipe[i-1];
                r_pipe[i] <= r_pipe[i-1];
                stage_valid[i] <= stage_valid[i-1];
                div_type_pipe[i] <= div_type_pipe[i-1];
            end
        end
    end
    
    // Output Routing (Mux the quotient or remainder based on requested instruction)
    always @(*) begin
        valid_out = stage_valid[DIV_LATENCY-1];
        
        if (div_type_pipe[DIV_LATENCY-1][1]) begin 
            // bit 1 is high for REM / REMU
            quotient = r_pipe[DIV_LATENCY-1];
            remainder = r_pipe[DIV_LATENCY-1];
        end else begin
            // bit 1 is low for DIV / DIVU
            quotient = q_pipe[DIV_LATENCY-1];
            remainder = r_pipe[DIV_LATENCY-1];
        end
    end

endmodule
