module common_data_bus #(
    parameter XLEN = 32,
    parameter RS_TAG_WIDTH = 4,
    parameter NUM_FUS = 5  // Number of functional units
) (
    input clk,
    input rst_n,
    
    // Result inputs from functional units
    input [NUM_FUS-1:0] fu_valid,
    input [XLEN-1:0] fu_result [NUM_FUS-1:0],
    input [RS_TAG_WIDTH-1:0] fu_tag [NUM_FUS-1:0],
    
    // CDB output (single winner via arbitration)
    output reg [XLEN-1:0] cdb_result,
    output reg [RS_TAG_WIDTH-1:0] cdb_tag,
    output reg cdb_valid
);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cdb_valid <= 1'b0;
            cdb_result <= 0;
            cdb_tag <= 0;
        end else begin
            cdb_valid <= 1'b0;
            
            // Priority arbiter: lower index = higher priority
            for (int i = 0; i < NUM_FUS; i++) begin
                if (fu_valid[i] && !cdb_valid) begin
                    cdb_valid <= 1'b1;
                    cdb_result <= fu_result[i];
                    cdb_tag <= fu_tag[i];
                end
            end
        end
    end

endmodule