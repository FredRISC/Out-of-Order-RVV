// ============================================================================
// tb_vector_mem.sv - Vector LSQ FSM & Block RAM Test
// ============================================================================

`timescale 1ns/1ps
`include "RTL/riscv_header.sv"

module tb_vector_mem;
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

    logic [31:0] instr_mem [0:15];
    assign imem_data = instr_mem[imem_addr >> 2];
    assign imem_valid = 1'b1;
    
    // Functional SRAM for Data Memory
    logic [31:0] dmem_array [0:255];
    assign dmem_write_ready = 1'b1;
    always @(posedge clk) begin
        if (dmem_write_en && dmem_write_ready) dmem_array[dmem_write_addr >> 2] <= dmem_write_data;
    end
    assign dmem_read_data = dmem_read_en ? dmem_array[dmem_read_addr >> 2] : 32'h0;

    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end

    initial begin
        $display("==================================================");
        $display("TEST: Vector LSQ Memory Burst & VEU");
        $display("==================================================");
        for (int i = 0; i < 16; i++) instr_mem[i] = 32'h00000013;
        for (int i = 0; i < 256; i++) dmem_array[i] = 32'h0;
        
        // 1. ADDI x1, x0, 100         (x1 = 100, Mem Address)
        // 2. VSETVLI x4, x0, e32, m1  (Configure VEU)
        // 3. VSE32.V v1, (x1)         (Store v1 to Mem[100..112])
        // 4. VLE32.V v2, (x1)         (Load Mem[100..112] to v2)
        // 5. VADD.VV v3, v2, v2       (v3 = v2 + v2)
        
        instr_mem[0] = 32'h06400093; // ADDI x1, x0, 100
        instr_mem[1] = 32'h01007257; // VSETVLI x4, x0, e32, m1
        instr_mem[2] = 32'h000080A7; // VSE32.V v1, (x1)
        /*instr_mem[3] = 32'h06400093; // ADDI x1, x0, 100
        instr_mem[4] = 32'h06400093; // ADDI x1, x0, 100
        instr_mem[5] = 32'h06400093; // ADDI x1, x0, 100
        instr_mem[6] = 32'h06400093; // ADDI x1, x0, 100
        instr_mem[7] = 32'h06400093; // ADDI x1, x0, 100
        instr_mem[8] = 32'h06400093; // ADDI x1, x0, 100
        instr_mem[9] = 32'h06400093; // ADDI x1, x0, 100
        instr_mem[10] = 32'h06400093; // ADDI x1, x0, 100
        instr_mem[11] = 32'h06400093; // ADDI x1, x0, 100
        instr_mem[12] = 32'h00008107; // VLE32.V v2, (x1)
        instr_mem[13] = 32'h002101D7; // VADD.VV v3, v2, v2
        */

        instr_mem[3] = 32'h00008107; // VLE32.V v2, (x1)
        instr_mem[4] = 32'h002101D7; // VADD.VV v3, v2, v2

        rst_n = 0; #20 rst_n = 1;
        
        // Inject v1 = [4, 3, 2, 1] via backdoor
        begin
            logic [5:0] v1_phys_idx = dut.dispatch_inst.vector_rat_inst.arch_rat[1];
            dut.vphys_regfile_inst.phys_regs[v1_phys_idx] = 128'h00000004_00000003_00000002_00000001;
            dut.vphys_regfile_inst.valid_bits[v1_phys_idx] = 1'b1;
        end

        #800; // Let the burst-reads and bursts-writes complete
        
        $display("\n[RESULTS]");
        begin
            logic [5:0] v3_phys_idx = dut.dispatch_inst.vector_rat_inst.arch_rat[3];
            logic [127:0] v3_result = dut.vphys_regfile_inst.phys_regs[v3_phys_idx];
            
            $display("DataArray3: %0d", dmem_array[28]);
            $display("DataArray2: %0d", dmem_array[27]);
            $display("DataArray1: %0d", dmem_array[26]);
            $display("DataArray0: %0d", dmem_array[25]);

            $display("v3 Element 3: %0d", v3_result[127:96]);
            $display("v3 Element 2: %0d", v3_result[95:64]);
            $display("v3 Element 1: %0d", v3_result[63:32]);
            $display("v3 Element 0: %0d", v3_result[31:0]);
            
            if (v3_result == 128'h00000008_00000006_00000004_00000002)
                $display("[PASS] Vector successfully stored, loaded, and added!");
            else
                $display("[FAIL] Vector math is incorrect.");
        end
        $finish;
    end

    // ========================================================================
    // WHITE-BOX PIPELINE TRACE LOG
    // ========================================================================
    integer cycle = 0;
    always @(posedge clk) begin
        if (rst_n) cycle++;
        
        // 1. Track VSE32.V coming out of Execute Stage
        if (dut.execute_inst.mem_valid && dut.execute_inst.exe_is_store && dut.execute_inst.lsq_inst.lsq[dut.execute_inst.mem_lsq_tag].is_vector) begin
            $display("[Cycle %0d] [EXECUTE] Vector Store: Addr=%0d, VL=%0d, Data=%0h", 
                     cycle, dut.execute_inst.agu_addr, dut.execute_inst.mem_vl, dut.execute_inst.mem_op2);
        end
        
        // 2. Track Vector Store ROB Commit
        if (dut.rob_commit_valid && dut.rob_commit_instr_type == `V_EXT_STORE) begin
            $display("[Cycle %0d] [COMMIT] Vector Store Commits! Sent commit_lsq.", cycle);
        end
        
        // 3. Track Vector Store LSQ FSM
        if (dut.execute_inst.lsq_inst.vec_store_active) begin
            $display("[Cycle %0d] [LSQ FSM] Active! word_idx=%0d, total_words=%0d, lsq_vl=%0d", 
                     cycle, 
                     dut.execute_inst.lsq_inst.vec_store_word_idx,
                     dut.execute_inst.lsq_inst.vec_store_total_words,
                     dut.execute_inst.lsq_inst.lsq[dut.execute_inst.lsq_inst.head].vl);
        end
        
        // 4. Track Physical Memory Writes Element by Element
        if (dmem_write_en) begin
            $display("[Cycle %0d] [MEMORY] WRITE: Addr=%0d, Data=%0d (Hex: %0h), BE=%b", 
                     cycle, dmem_write_addr, dmem_write_data, dmem_write_data, dmem_be);
        end


        // 5. Track VLE32.V coming out of Execute Stage
        if (dut.execute_inst.mem_valid && !dut.execute_inst.exe_is_store && dut.execute_inst.lsq_inst.lsq[dut.execute_inst.mem_lsq_tag].is_vector) begin
            $display("[Cycle %0d] [EXECUTE] Vector Load: Addr=%0d, VL=%0d", 
                     cycle, dut.execute_inst.agu_addr, dut.execute_inst.mem_vl);
        end

        
        // 6. Track Vector Load LSQ FSM
        if (dut.execute_inst.lsq_inst.vec_load_active) begin
            $display("[Cycle %0d] [LSQ FSM] Active! word_idx=%0d, total_words=%0d, lsq_vl=%0d", 
                     cycle, 
                     dut.execute_inst.lsq_inst.vec_load_word_idx,
                     dut.execute_inst.lsq_inst.vec_load_total_words,
                     dut.execute_inst.lsq_inst.lsq[dut.execute_inst.lsq_inst.head].vl);
        end
        // 7. Track Physical Memory Reads Element by Element
        if (dmem_read_en) begin
            $display("[Cycle %0d] [MEMORY] READ: Addr=%0d, Data=%0d (Hex: %0h), BE=%b", 
                     cycle, dmem_read_addr, dmem_read_data, dmem_read_data, dmem_be);
        end
        // 8. Track Vector Load ROB Commit
        if (dut.rob_commit_valid && dut.rob_commit_instr_type == `V_EXT_LOAD) begin
            $display("[Cycle %0d] [COMMIT] Vector Load Commits! Sent commit_lsq.", cycle);
        end
    end
endmodule