// ============================================================================
// writeback_stage.sv - Writeback Stage with CDB Arbitration
// ============================================================================

`include "../riscv_header.sv"

module writeback_stage #(
    parameter XLEN = 32
) (
    input clk,
    input rst_n,
    
    // Results from execute stage
    input [XLEN-1:0] result_data,
    input [7:0] result_tag,
    input result_valid,
    
    // CDB broadcast output
    output reg [XLEN-1:0] cdb_result,
    output reg [7:0] cdb_tag,
    output reg cdb_valid
);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cdb_valid <= 1'b0;
            cdb_result <= 0;
            cdb_tag <= 0;
        end else if (result_valid) begin
            cdb_valid <= 1'b1;
            cdb_result <= result_data;
            cdb_tag <= result_tag;
        end else begin
            cdb_valid <= 1'b0;
        end
    end

endmodule
