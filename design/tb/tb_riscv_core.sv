// ============================================================================
// tb_riscv_core.sv - Minimum Viable Testbench for Tenstorrent Resume
// ============================================================================
// Focuses on self-checking the ALU PRF bypass and LSQ Store-to-Load Forwarding

`timescale 1ns/1ps
`include "../riscv_header.sv"

module tb_riscv_core;

    logic clk;
    logic rst_n;
    
    // Memory Interfaces
    logic [31:0] imem_addr;
    logic [31:0] imem_data;
    logic imem_valid;
    
    logic [31:0] dmem_read_addr;
    logic dmem_read_en;
    logic [31:0] dmem_read_data;
    logic dmem_read_valid;
    
    logic [31:0] dmem_write_addr;
    logic [31:0] dmem_write_data;
    logic dmem_write_en;
    logic dmem_write_ready;
    logic [3:0] dmem_be;
    
    // Debug Interface (Mimics Architectural Register File)
    logic [31:0][31:0] debug_reg_file;
    
    // Core Instantiation
    riscv_core_top dut (
        .clk(clk),
        .rst_n(rst_n),
        .imem_addr(imem_addr),
        .imem_data(imem_data),
        .imem_valid(imem_valid),
        .dmem_read_addr(dmem_read_addr),
        .dmem_read_en(dmem_read_en),
        .dmem_read_data(dmem_read_data),
        .dmem_read_valid(dmem_read_valid),
        .dmem_write_addr(dmem_write_addr),
        .dmem_write_data(dmem_write_data),
        .dmem_write_en(dmem_write_en),
        .dmem_write_ready(dmem_write_ready),
        .dmem_be(dmem_be),
        .ext_irq(1'b0),
        .exception_valid(),
        .exception_code(),
        .debug_reg_file(debug_reg_file)
    );

    // Simulated Instruction Memory (Holds our test program)
    logic [31:0] instr_mem [0:15];
    
    assign imem_data = instr_mem[imem_addr >> 2]; // Word aligned addressing
    assign imem_valid = 1'b1;
    
    // Dummy Data Memory (Always ready)
    assign dmem_write_ready = 1'b1;
    assign dmem_read_valid = dmem_read_en;
    assign dmem_read_data = 32'hDEADBEEF; // If the load reads memory instead of forwarding, it gets this garbage

    // Clock Generation
    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end

    // Test Sequence
    initial begin
        $display("==================================================");
        $display("FredRISC Verification Suite");
        $display("==================================================");
        
        // Initialize all memory to NOPs (ADDI x0, x0, 0)
        for (int i = 0; i < 16; i++) instr_mem[i] = 32'h00000013;
        
        // TEST 1: LSQ Forwarding
        // 1. ADDI x1, x0, 42    (x1 = 42) -> Data to store
        // 2. ADDI x2, x0, 256   (x2 = 256) -> Memory Address
        // 3. SW   x1, 0(x2)     (Mem[256] = 42) -> Enters LSQ
        // 4. LW   x3, 0(x2)     (x3 = Mem[256]) -> Should hit in LSQ and forward 42 instantly!
        
        instr_mem[0] = 32'h02A00093; // ADDI x1, x0, 42
        instr_mem[1] = 32'h10000113; // ADDI x2, x0, 256
        instr_mem[2] = 32'h00112023; // SW x1, 0(x2)
        instr_mem[3] = 32'h00012183; // LW x3, 0(x2)
        
        // TEST 2: Vector Execution (VSETVLI + VADD.VV)
        // 5. VSETVLI x4, x0, e32, m1   -> Configures VEU for 32-bit elements
        // 6. VADD.VV v3, v1, v2        -> Adds vector registers
        
        instr_mem[4] = 32'h01007257; // VSETVLI x4, x0, e32, m1
        instr_mem[5] = 32'h022081D7; // VADD.VV v3, v1, v2

        rst_n = 0;
        #20 rst_n = 1; // Release reset
        
        // --- WHITE-BOX TEST SETUP: Mock Vector Registers ---
        // Because we don't have vector memory loads in our test program yet,
        // we use "backdoor access" to inject data directly into physical p1 and p2.
        // This proves the Vector Execution Unit does the math correctly!
        dut.vphys_regfile_inst.phys_regs[1] = 128'h00000004_00000003_00000002_00000001; // v1
        dut.vphys_regfile_inst.phys_regs[2] = 128'h00000010_00000010_00000010_00000010; // v2
        dut.vphys_regfile_inst.valid_bits[1] = 1'b1;
        dut.vphys_regfile_inst.valid_bits[2] = 1'b1;

        // Let the pipeline run for 30 cycles
        #300;
        
        $display("\n--- TEST 1: Store-to-Load Forwarding ---");
        $display("x1 (Store Data) : %0d", debug_reg_file[1]);
        $display("x2 (Mem Address): %0d", debug_reg_file[2]);
        $display("x3 (Loaded Data): %0d", debug_reg_file[3]);
        
        if (debug_reg_file[3] == 42) begin
            $display("[PASS] Store-to-Load Forwarding Successful!");
            $display("The Load bypassed the memory and grabbed the speculative store data directly from the LSQ.");
        end else begin
            $display("[FAIL] Load received %0h instead of 42.", debug_reg_file[3]);
        end
        
        $display("\n--- TEST 2: Vector Execution ---");
        begin
            logic [5:0] v3_phys_idx;
            logic [127:0] v3_result;
            
            // Use hierarchical paths to peek into the RAT and find out where architectural v3 was mapped!
            v3_phys_idx = dut.dispatch_inst.vector_rat_inst.arch_rat[3];
            v3_result = dut.vphys_regfile_inst.phys_regs[v3_phys_idx];
            
            $display("v3 Physical Tag : p%0d", v3_phys_idx);
            $display("v3 Element 3    : %0d", v3_result[127:96]);
            $display("v3 Element 2    : %0d", v3_result[95:64]);
            $display("v3 Element 1    : %0d", v3_result[63:32]);
            $display("v3 Element 0    : %0d", v3_result[31:0]);
            
            // Expected: v1 + v2 = (4+16), (3+16), (2+16), (1+16)
            if (v3_result == 128'h00000014_00000013_00000012_00000011) begin
                $display("[PASS] Vector VADD.VV Execution Successful!");
            end else begin
                $display("[FAIL] Vector result incorrect.");
            end
        end

        $display("==================================================");
        $finish;
    end

endmodule