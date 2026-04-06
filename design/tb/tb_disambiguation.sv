// ============================================================================
// tb_disambiguation.sv - Memory Disambiguation & Flush Recovery
// ============================================================================

`timescale 1ns/1ps
`include "RTL/riscv_header.sv"

module tb_disambiguation;
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
    logic [31:0] dmem_array [0:255];
    assign dmem_write_ready = 1'b1;
    always @(posedge clk) begin
        if (dmem_write_en && dmem_write_ready) dmem_array[dmem_write_addr >> 2] <= dmem_write_data;
    end
    assign dmem_read_data = dmem_read_en ? dmem_array[dmem_read_addr >> 2] : 32'hDEADBEEF;

    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end

    initial begin
        $display("==================================================");
        $display("TEST: LSQ Memory Disambiguation & Flush Recovery");
        $display("==================================================");
        for (int i = 0; i < 16; i++) instr_mem[i] = 32'h00000013; // NOPs
        for (int i = 0; i < 256; i++) dmem_array[i] = 32'h0;      // Clear RAM
        
        // 1. ADDI x1, x0, 100   (x1 = 100, Store Data)
        // 2. ADDI x2, x0, 256   (x2 = 256, Load Address)
        // 3. ADDI x4, x0, 16    (x4 = 16)
        // 4. ADDI x5, x0, 16    (x5 = 16)
        // 5. MUL  x6, x4, x5    (x6 = 256, Store Address -> Takes 4 cycles!)
        // 6. SW   x1, 0(x6)     (Mem[256] = 100 -> Waits for MUL!)
        // 7. LW   x3, 0(x2)     (x3 = Mem[256]  -> Executes early, reads 0, gets FLUSHED)
        
        instr_mem[0] = 32'h06400093; // ADDI x1, x0, 100
        instr_mem[1] = 32'h10000113; // ADDI x2, x0, 256
        instr_mem[2] = 32'h01000213; // ADDI x4, x0, 16
        instr_mem[3] = 32'h01000293; // ADDI x5, x0, 16
        instr_mem[4] = 32'h02520333; // MUL  x6, x4, x5
        instr_mem[5] = 32'h00132023; // SW   x1, 0(x6)
        instr_mem[6] = 32'h00012183; // LW   x3, 0(x2)
        
        rst_n = 0; #20 rst_n = 1;
        #1200; // Let pipeline resolve the flush and re-execute
        
        $display("\n[RESULTS]");
        $display("x1 (Store Data)    : %0d", debug_reg_file[1]);
        $display("x6 (Store Address) : %0d", debug_reg_file[6]);
        $display("x3 (Loaded Data)   : %0d", debug_reg_file[3]);
        
        if (debug_reg_file[3] == 100)
            $display("[PASS] Disambiguation flushed the pipeline and the Load successfully re-executed!");
        else
            $display("[FAIL] Load got %0d instead of 100.", debug_reg_file[3]);
            
        $finish;
    end
    
    // Pipeline Tracker
    integer cycle = 0;
    always @(posedge clk) begin
        if (rst_n) cycle++;
        if (dut.execute_inst.mem_valid && dut.execute_inst.exe_is_load) 
            $display("[Cycle %0d] LW executed at address %0d", cycle, dut.execute_inst.agu_addr);
        if (dut.execute_inst.mem_valid && dut.execute_inst.exe_is_store) 
            $display("[Cycle %0d] SW executed at address %0d", cycle, dut.execute_inst.agu_addr);
        if (dut.lsq_flush_req)
            $display("[Cycle %0d] LSQ VIOLATION DETECTED! FLUSHING PIPELINE!", cycle);
    end
endmodule