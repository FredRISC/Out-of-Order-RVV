// ============================================================================
// multiplier.sv - 32-bit Multiplier (2-bit Booth, 4-cycle pipelined)
// ============================================================================
// Latency: `MUL_LATENCY (default 4 cycles)
// Supports: MUL, MULH, MULHSU, MULHU

`include "RTL/riscv_header.sv"

module multiplier (
    input clk,
    input rst_n,
    
    input [`XLEN-1:0] multiplicand,
    input [`XLEN-1:0] multiplier,
    input valid_in,
    input [1:0] mul_type,  // 00=MUL, 01=MULH, 10=MULHSU, 11=MULHU
    
    output reg [`XLEN-1:0] product_low,
    output reg [`XLEN-1:0] product_high,
    output reg valid_out,
    input [5:0] tag_in,
    output reg [5:0] tag_out
);
    // Behavioral modeling of multiplication
    // Replace this with real multiplier IP. This is just for functional correctness in the prototype.

    // Pipeline stages for partial product accumulation
    reg [63:0] pp_accum [`MUL_LATENCY-1:0];
    reg stage_valid [`MUL_LATENCY-1:0];
    reg [1:0] mul_type_pipe [`MUL_LATENCY-1:0];
    reg [5:0] tag_pipe [`MUL_LATENCY-1:0];
    
    // Sign extension for signed multiplications
    logic [`XLEN:0] mcand_extended, mplier_extended;
    
    always @(*) begin
        case (mul_type)
            2'b00, 2'b01: begin  // MUL, MULH (signed)
                mcand_extended = {{multiplicand[`XLEN-1]}, multiplicand};
                mplier_extended = {{multiplier[`XLEN-1]}, multiplier};
            end
            2'b10: begin  // MULHSU (signed x unsigned)
                mcand_extended = {{multiplicand[`XLEN-1]}, multiplicand};
                mplier_extended = {1'b0, multiplier};
            end
            2'b11: begin  // MULHU (unsigned)
                mcand_extended = {1'b0, multiplicand};
                mplier_extended = {1'b0, multiplier};
            end
        endcase
    end
    
    // Partial product generation and pipelined accumulation
    always @(posedge clk or negedge rst_n) begin
        integer i;
        if (!rst_n) begin
            for (i = 0; i < `MUL_LATENCY; i++) begin
                pp_accum[i] <= 0;
                stage_valid[i] <= 1'b0;
                mul_type_pipe[i] <= 2'b0;
                tag_pipe[i] <= 6'b0;
            end
        end else begin
            // Stage 0: Initial partial products
            if (valid_in) begin
                // Simplified: Use full multiplication (can be optimized with Booth)
                pp_accum[0] <= $signed(mcand_extended) * $signed(mplier_extended);
                stage_valid[0] <= 1'b1;
                mul_type_pipe[0] <= mul_type;
                tag_pipe[0] <= tag_in;
            end else begin
                stage_valid[0] <= 1'b0;
            end
            
            // Pipeline stages 1-3: Forward through pipeline
            for (i = 1; i < `MUL_LATENCY; i++) begin
                pp_accum[i] <= pp_accum[i-1];
                stage_valid[i] <= stage_valid[i-1];
                mul_type_pipe[i] <= mul_type_pipe[i-1];
                tag_pipe[i] <= tag_pipe[i-1];
            end
        end
    end
    
    // Output selection based on multiply type
    always @(*) begin
        case (mul_type_pipe[`MUL_LATENCY-1])
            2'b00: begin  // MUL (lower 32 bits)
                product_low = pp_accum[`MUL_LATENCY-1][`XLEN-1:0];
                product_high = 32'h0;
            end
            2'b01, 2'b10, 2'b11: begin  // MULH* (upper 32 bits)
                product_low = pp_accum[`MUL_LATENCY-1][`XLEN-1:0];
                product_high = pp_accum[`MUL_LATENCY-1][2*`XLEN-1:`XLEN];
            end
        endcase
        valid_out = stage_valid[`MUL_LATENCY-1];
        tag_out = tag_pipe[`MUL_LATENCY-1];
    end

endmodule
