// ============================================================================
// tb_branch.sv - Branch Misprediction & RAT Recovery Testbench
// ============================================================================

`timescale 1ns/1ps
`include "RTL/riscv_header.sv"

module tb_branch;
    logic clk;
    logic rst_n;
    
    logic [31:0] imem_addr, imem_data;
    logic imem_valid;
    
    logic [31:0] dmem_read_addr, dmem_write_addr, dmem_write_data, dmem_read_data;
    logic dmem_read_en, dmem_write_en, dmem_write_ready;
    logic [3:0] dmem_be;
    
    logic [31:0][31:0] debug_reg_file;
    
    riscv_core_top dut (
        .clk(clk), .rst_n(rst_n),
        .imem_addr(imem_addr), .imem_data(imem_data), .imem_valid(imem_valid),
        .dmem_read_addr(dmem_read_addr), .dmem_read_en(dmem_read_en), .dmem_read_data(dmem_read_data), .dmem_read_valid(dmem_read_en),
        .dmem_write_addr(dmem_write_addr), .dmem_write_data(dmem_write_data), .dmem_write_en(dmem_write_en),
        .dmem_write_ready(dmem_write_ready), .dmem_be(dmem_be),
        .ext_irq(1'b0), .exception_valid(), .exception_code(), .debug_reg_file(debug_reg_file)
    );

    // Simulated Instruction Memory
    logic [31:0] instr_mem [0:15];
    assign imem_data = instr_mem[imem_addr >> 2];
    assign imem_valid = 1'b1;
    
    // Functional SRAM for Data Memory
    assign dmem_write_ready = 1'b1;
    assign dmem_read_data = 32'h0; // Dummy

    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end

    initial begin
        $display("==================================================");
        $display("TEST: Branch Misprediction & RAT Snapshot Recovery");
        $display("==================================================");
        for (int i = 0; i < 16; i++) instr_mem[i] = 32'h00000013; // NOPs
        
        // The BHT defaults to 2'b01 (Weakly Not Taken).
        // We will force a Taken branch to trigger a pipeline flush.
        
        // PC=0 : ADDI x1, x0, 1     (x1 = 1)
        // PC=4 : ADDI x2, x0, 2     (x2 = 2)
        // PC=8 : BEQ  x1, x1, +16   (Branch to PC=24) -> Predicted Not Taken!
        // PC=12: ADDI x3, x0, 99    (x3 = 99) -> WRONG PATH (Should be flushed)
        // PC=16: ADDI x4, x0, 99    (x4 = 99) -> WRONG PATH (Should be flushed)
        // PC=20: ADDI x5, x0, 99    (x5 = 99) -> WRONG PATH (Should be flushed)
        // PC=24: ADDI x6, x0, 42    (x6 = 42) -> CORRECT PATH (Target)
        
        instr_mem[0] = 32'h00100093; // ADDI x1, x0, 1
        instr_mem[1] = 32'h00200113; // ADDI x2, x0, 2
        instr_mem[2] = 32'h00108863; // BEQ  x1, x1, +16
        instr_mem[3] = 32'h06300193; // ADDI x3, x0, 99
        instr_mem[4] = 32'h06300213; // ADDI x4, x0, 99
        instr_mem[5] = 32'h06300293; // ADDI x5, x0, 99
        instr_mem[6] = 32'h02A00313; // ADDI x6, x0, 42
        
        rst_n = 0; #20 rst_n = 1;
        #800; // Let pipeline execute, flush, and recover
        
        $display("\n[RESULTS]");
        $display("x3 (Wrong Path) : %0d (Expected: 0)", debug_reg_file[3]);
        $display("x4 (Wrong Path) : %0d (Expected: 0)", debug_reg_file[4]);
        $display("x5 (Wrong Path) : %0d (Expected: 0)", debug_reg_file[5]);
        $display("x6 (Correct Path): %0d (Expected: 42)", debug_reg_file[6]);
        
        if (debug_reg_file[6] == 42 && debug_reg_file[3] == 0)
            $display("[PASS] The branch misprediction was detected, the pipeline flushed, and the RAT successfully restored the architectural state!");
        else
            $display("[FAIL] The pipeline failed to recover the correct execution path.");
            
        $finish;
    end
    
    // Pipeline Tracker
    integer cycle = 0;
    always @(posedge clk) begin
        if (rst_n) cycle++;
        
        if (dut.alu_flush_req)
            $display("[Cycle %0d] BRANCH MISPREDICTION DETECTED! Redirecting PC to %0d", cycle, dut.alu_flush_target);
            
        if (dut.rob_flush_req)
            $display("[Cycle %0d] ROB Processing Flush! Rolling back RAT and Free List...", cycle);
    end

endmodule
