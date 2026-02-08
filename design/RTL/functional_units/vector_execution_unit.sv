// ============================================================================
// vector_execution_unit.sv - Vector ALU with 4 Parallel Lanes
// ============================================================================
// RVV v1.0 subset: element-wise operations with chaining support
// VLEN=128, 4 lanes of 32-bit elements

`include "../riscv_header.sv"

module vector_execution_unit #(
    parameter VLEN = 128,
    parameter VLMAX = 16,
    parameter ELEN = 32,
    parameter NUM_VEC_LANES = 4,
    parameter NUM_VEC_REGS = 32
) (
    input clk,
    input rst_n,
    
    // Vector configuration (from VSETVLI)
    input [31:0] vl,  // Current vector length
    input [31:0] vtype,
    
    // Operand interface
    input [VLEN-1:0] vec_src1,
    input [VLEN-1:0] vec_src2,
    input [3:0] vec_op,
    input vec_valid,
    
    // Result interface
    output reg [VLEN-1:0] vec_result,
    output reg vec_result_valid,
    
    // Vector register file interface (optional)
    input [4:0] vreg_rd_addr1, vreg_rd_addr2, vreg_wr_addr,
    output [VLEN-1:0] vreg_rd_data1, vreg_rd_data2,
    input [VLEN-1:0] vreg_wr_data,
    input vreg_wr_en
);

    // Lane interface: 4 parallel 32-bit lanes
    logic [ELEN-1:0] lane_src1 [NUM_VEC_LANES-1:0];
    logic [ELEN-1:0] lane_src2 [NUM_VEC_LANES-1:0];
    logic [ELEN-1:0] lane_result [NUM_VEC_LANES-1:0];
    logic [3:0] lane_op;
    logic lane_valid;
    
    // Distribute operands across lanes
    genvar i;
    generate
        for (i = 0; i < NUM_VEC_LANES; i++) begin
            always @(*) begin
                lane_src1[i] = vec_src1[(i+1)*ELEN-1 : i*ELEN];
                lane_src2[i] = vec_src2[(i+1)*ELEN-1 : i*ELEN];
            end
        end
    endgenerate
    
    assign lane_op = vec_op;
    assign lane_valid = vec_valid;
    
    // ========================================================================
    // Lane Execution Units (element-wise operations)
    // ========================================================================
    
    generate
        for (i = 0; i < NUM_VEC_LANES; i++) begin : gen_lanes
            vector_lane #(
                .ELEN(ELEN)
            ) lane (
                .clk(clk),
                .rst_n(rst_n),
                .operand1(lane_src1[i]),
                .operand2(lane_src2[i]),
                .vec_op(vec_op),
                .valid_in(vec_valid),
                .result(lane_result[i]),
                .valid_out()
            );
        end
    endgenerate
    
    // ========================================================================
    // Combine lane results
    // ========================================================================
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            vec_result_valid <= 1'b0;
        end else if (vec_valid) begin
            // Combine all lane results into VLEN-bit output
            for (int j = 0; j < NUM_VEC_LANES; j++) begin
                vec_result[(j+1)*ELEN-1 : j*ELEN] <= lane_result[j];
            end
            vec_result_valid <= 1'b1;
        end else begin
            vec_result_valid <= 1'b0;
        end
    end

endmodule
