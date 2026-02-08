// ============================================================================
// vector_register_file.sv
// ============================================================================
// Holds ARCHITECTURAL VECTOR REGISTER STATE
// Same concept as scalar register_file but for vectors

`include "riscv_header.sv"

module vector_register_file (
    input clk,
    input rst_n,
    
    // Read ports
    input [4:0] read_addr1,
    input [4:0] read_addr2,
    output logic [VLEN-1:0] read_data1,
    output logic [VLEN-1:0] read_data2,
    
    // Write port (from commit)
    input [4:0] write_addr,
    input [VLEN-1:0] write_data,
    input write_en
);

    logic [VLEN-1:0] v_registers [NUM_VEC_REGS-1:0];
    
    // Combinational reads
    assign read_data1 = v_registers[read_addr1];
    assign read_data2 = v_registers[read_addr2];
    
    // Sequential writes
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (int i = 0; i < NUM_VEC_REGS; i++)
                v_registers[i] <= 0;
        end else if (write_en) begin
            v_registers[write_addr] <= write_data;
        end
    end

endmodule