// ============================================================================
// components/hazard_detection.sv - Hazard Detection and Stall Logic
// ============================================================================
module hazard_detection #(
    parameter ALU_RS_SIZE = 8,
    parameter MEM_RS_SIZE = 8,
    parameter MUL_RS_SIZE = 4,
    parameter DIV_RS_SIZE = 4,
    parameter VEC_RS_SIZE = 8,
    parameter ROB_SIZE = 16,
    parameter LSQ_SIZE = 16
) (
    input alu_rs_full,
    input mem_rs_full,
    input mul_rs_full,
    input div_rs_full,
    input vec_rs_full,
    input rob_full,
    input lsq_full,
    
    output reg stall_fetch,
    output reg stall_decode,
    output reg stall_dispatch
);

    always @(*) begin
        // Dispatch stalls if any RS is full
        stall_dispatch = alu_rs_full | mem_rs_full | mul_rs_full | 
                        div_rs_full | vec_rs_full | rob_full | lsq_full;
        
        // Back-propagate stalls
        stall_decode = stall_dispatch;
        stall_fetch = stall_decode;
    end

endmodule