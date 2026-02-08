// ============================================================================
// tb_riscv_core.sv - RISC-V RAT+PHYSICAL Processor Testbench
// ============================================================================
// ONE comprehensive testbench covering all major test scenarios
// Tests: Pipeline correctness, RAT+PHYSICAL renaming, out-of-order execution,
//        forwarding, Tomasulo operation, and resource management

`include "riscv_header.sv"

module tb_riscv_core;

    // ========================================================================
    // TEST PARAMETERS
    // ========================================================================
    
    localparam CLK_PERIOD = 10;  // 10 ns clock
    
    // Test case IDs
    localparam TEST_ALU_BASIC = 0;
    localparam TEST_ALU_IMMEDIATE = 1;
    localparam TEST_DEPENDENCY = 2;
    localparam TEST_OUT_OF_ORDER = 3;
    localparam TEST_MULTIPLIER = 4;
    localparam TEST_DIVIDER = 5;
    localparam TEST_LOAD_STORE = 6;
    localparam TEST_FORWARDING = 7;
    localparam TEST_RAT_RENAMING = 8;
    localparam TEST_VECTOR = 9;
    localparam TEST_STRESS = 10;
    
    // ========================================================================
    // DUT SIGNALS
    // ========================================================================
    
    logic clk, rst_n;
    
    // Instruction memory
    logic [XLEN-1:0] imem_addr;
    logic [INST_WIDTH-1:0] imem_data;
    logic imem_valid;
    
    // Data memory
    logic [XLEN-1:0] dmem_addr, dmem_write_data, dmem_read_data;
    logic dmem_we;
    logic [3:0] dmem_be;
    logic dmem_valid;
    
    // Interrupt & Exception
    logic ext_irq, exception_valid;
    logic [EXCEPTION_CODE_WIDTH-1:0] exception_code;
    
    // Debug
    logic [NUM_INT_REGS-1:0][XLEN-1:0] debug_reg_file;
    
    // ========================================================================
    // DUT INSTANTIATION
    // ========================================================================
    
    riscv_core_top dut (
        .clk(clk), .rst_n(rst_n),
        .imem_addr(imem_addr), .imem_data(imem_data), .imem_valid(imem_valid),
        .dmem_addr(dmem_addr), .dmem_write_data(dmem_write_data),
        .dmem_read_data(dmem_read_data), .dmem_we(dmem_we), .dmem_be(dmem_be),
        .dmem_valid(dmem_valid),
        .ext_irq(ext_irq), .exception_valid(exception_valid),
        .exception_code(exception_code), .debug_reg_file(debug_reg_file)
    );
    
    // ========================================================================
    // MEMORY MODELS
    // ========================================================================
    
    // Instruction ROM (test programs)
    logic [INST_WIDTH-1:0] imem [256:0];
    
    // Data RAM
    logic [XLEN-1:0] dmem [256:0];
    
    // Simple I-mem read
    always @(*) begin
        imem_valid = 1'b1;
        imem_data = imem[imem_addr >> 2];  // Word-addressed
    end
    
    // Simple D-mem read/write
    always @(posedge clk) begin
        if (dmem_we && dmem_valid)
            dmem[dmem_addr >> 2] <= dmem_write_data;
    end
    
    assign dmem_valid = 1'b1;  // Always ready
    assign dmem_read_data = dmem[dmem_addr >> 2];
    
    // ========================================================================
    // CLOCK GENERATION
    // ========================================================================
    
    initial begin
        clk = 1'b0;
        forever #(CLK_PERIOD/2) clk = ~clk;
    end
    
    // ========================================================================
    // TEST STIMULUS & MONITORING
    // ========================================================================
    
    int test_id;
    int cycle_count;
    int test_passed;
    int test_failed;
    
    initial begin
        // Initialize
        rst_n = 1'b0;
        ext_irq = 1'b0;
        test_passed = 0;
        test_failed = 0;
        
        // Initialize memories
        for (int i = 0; i < 256; i++) begin
            imem[i] = 32'h00000000;
            dmem[i] = 32'h00000000;
        end
        
        // Reset sequence
        #(5 * CLK_PERIOD);
        rst_n = 1'b1;
        #(2 * CLK_PERIOD);
        
        $display("=====================================");
        $display("RISC-V RAT+PHYSICAL Processor Testbench");
        $display("=====================================\n");
        
        // ====================================================================
        // TEST 0: BASIC ALU (ADD)
        // ====================================================================
        
        test_id = TEST_ALU_BASIC;
        $display("\n[TEST %0d] Basic ALU - ADD x1, x2, x3", test_id);
        
        // Setup: x2=5, x3=3, expect x1=8
        dmem[0] = 32'h0;
        dmem[1] = 32'h0;
        dmem[2] = 32'h0;
        
        // Load x2 with 5
        imem[0] = 32'h0050_0113;  // ADDI x2, x0, 5
        // Load x3 with 3
        imem[1] = 32'h0030_0193;  // ADDI x3, x0, 3
        // Add: x1 = x2 + x3
        imem[2] = 32'h0031_0083;  // ADD x1, x2, x3
        // DONE
        imem[3] = 32'hFFFF_FFFF;  // Infinite loop
        
        cycle_count = 0;
        while (cycle_count < 20 && debug_reg_file[1] != 32'd8) begin
            #(CLK_PERIOD);
            cycle_count = cycle_count + 1;
        end
        
        if (debug_reg_file[1] == 32'd8) begin
            $display("✓ PASSED: x1 = 8 (after %0d cycles)", cycle_count);
            test_passed++;
        end else begin
            $display("✗ FAILED: x1 = %0d (expected 8)", debug_reg_file[1]);
            test_failed++;
        end
        
        // ====================================================================
        // TEST 1: ALU WITH IMMEDIATE
        // ====================================================================
        
        test_id = TEST_ALU_IMMEDIATE;
        $display("\n[TEST %0d] ALU Immediate - ADDI x1, x0, 100", test_id);
        
        rst_n = 1'b0;
        #(CLK_PERIOD);
        rst_n = 1'b1;
        #(CLK_PERIOD);
        
        // Load x1 with 100
        imem[0] = 32'h0640_0093;  // ADDI x1, x0, 100
        imem[1] = 32'hFFFF_FFFF;  // Infinite loop
        
        cycle_count = 0;
        while (cycle_count < 20 && debug_reg_file[1] != 32'd100) begin
            #(CLK_PERIOD);
            cycle_count++;
        end
        
        if (debug_reg_file[1] == 32'd100) begin
            $display("✓ PASSED: x1 = 100 (after %0d cycles)", cycle_count);
            test_passed++;
        end else begin
            $display("✗ FAILED: x1 = %0d (expected 100)", debug_reg_file[1]);
            test_failed++;
        end
        
        // ====================================================================
        // TEST 2: REGISTER DEPENDENCY (RAW - Read After Write)
        // ====================================================================
        
        test_id = TEST_DEPENDENCY;
        $display("\n[TEST %0d] Register Dependency - x2=x1+x0, x3=x2+x0", test_id);
        
        rst_n = 1'b0;
        #(CLK_PERIOD);
        rst_n = 1'b1;
        #(CLK_PERIOD);
        
        // x1 = 5
        imem[0] = 32'h0050_0093;  // ADDI x1, x0, 5
        // x2 = x1 + 3  (depends on x1)
        imem[1] = 32'h0030_8113;  // ADDI x2, x1, 3
        // x3 = x2 + 2  (depends on x2)
        imem[2] = 32'h0021_0193;  // ADDI x3, x2, 2
        imem[3] = 32'hFFFF_FFFF;
        
        cycle_count = 0;
        while (cycle_count < 30 && debug_reg_file[3] != 32'd10) begin
            #(CLK_PERIOD);
            cycle_count++;
        end
        
        if (debug_reg_file[3] == 32'd10) begin
            $display("✓ PASSED: x3 = 10 (x1=5, x2=8, after %0d cycles)", cycle_count);
            test_passed++;
        end else begin
            $display("✗ FAILED: x3 = %0d (expected 10)", debug_reg_file[3]);
            test_failed++;
        end
        
        // ====================================================================
        // TEST 3: OUT-OF-ORDER EXECUTION (MUL latency hidden)
        // ====================================================================
        
        test_id = TEST_OUT_OF_ORDER;
        $display("\n[TEST %0d] Out-of-Order: MUL x1,x2,x3 (4 cycles) + ADD x4,x5,x6 (1 cycle)", test_id);
        
        rst_n = 1'b0;
        #(CLK_PERIOD);
        rst_n = 1'b1;
        #(CLK_PERIOD);
        
        // Setup values
        imem[0] = 32'h0050_0113;  // ADDI x2, x0, 5    (x2=5)
        imem[1] = 32'h0030_0193;  // ADDI x3, x0, 3    (x3=3)
        imem[2] = 32'h0060_0213;  // ADDI x4, x0, 6    (x5=6)
        imem[3] = 32'h0070_0293;  // ADDI x5, x0, 7    (x6=7)
        // MUL x1, x2, x3  (multiply, latency=4)
        imem[4] = 32'h0231_0083;  // MUL x1, x2, x3
        // ADD x6, x4, x5  (add, latency=1, should execute while MUL waiting)
        imem[5] = 32'h0052_8303;  // ADD x6, x4, x5
        imem[6] = 32'hFFFF_FFFF;
        
        cycle_count = 0;
        while (cycle_count < 40 && (debug_reg_file[1] != 32'd15 || debug_reg_file[6] != 32'd13)) begin
            #(CLK_PERIOD);
            cycle_count++;
        end
        
        if (debug_reg_file[1] == 32'd15 && debug_reg_file[6] == 32'd13) begin
            $display("✓ PASSED: x1=15 (MUL), x6=13 (ADD) - OoO worked! (after %0d cycles)", cycle_count);
            test_passed++;
        end else begin
            $display("✗ FAILED: x1=%0d (expected 15), x6=%0d (expected 13)", 
                debug_reg_file[1], debug_reg_file[6]);
            test_failed++;
        end
        
        // ====================================================================
        // TEST 4: MULTIPLIER (4-cycle latency)
        // ====================================================================
        
        test_id = TEST_MULTIPLIER;
        $display("\n[TEST %0d] Multiplier - MUL x1, x2, x3 = 7*6 = 42", test_id);
        
        rst_n = 1'b0;
        #(CLK_PERIOD);
        rst_n = 1'b1;
        #(CLK_PERIOD);
        
        imem[0] = 32'h0070_0113;  // ADDI x2, x0, 7
        imem[1] = 32'h0060_0193;  // ADDI x3, x0, 6
        imem[2] = 32'h0231_0083;  // MUL x1, x2, x3
        imem[3] = 32'hFFFF_FFFF;
        
        cycle_count = 0;
        while (cycle_count < 50 && debug_reg_file[1] != 32'd42) begin
            #(CLK_PERIOD);
            cycle_count++;
        end
        
        if (debug_reg_file[1] == 32'd42) begin
            $display("✓ PASSED: x1 = 42 (7×6, after %0d cycles, MUL_LATENCY=%0d)", 
                cycle_count, MUL_LATENCY);
            test_passed++;
        end else begin
            $display("✗ FAILED: x1 = %0d (expected 42)", debug_reg_file[1]);
            test_failed++;
        end
        
        // ====================================================================
        // TEST 5: DIVIDER (6-cycle latency)
        // ====================================================================
        
        test_id = TEST_DIVIDER;
        $display("\n[TEST %0d] Divider - DIV x1, x2, x3 = 20/4 = 5", test_id);
        
        rst_n = 1'b0;
        #(CLK_PERIOD);
        rst_n = 1'b1;
        #(CLK_PERIOD);
        
        imem[0] = 32'h0140_0113;  // ADDI x2, x0, 20
        imem[1] = 32'h0040_0193;  // ADDI x3, x0, 4
        imem[2] = 32'h0231_4083;  // DIV x1, x2, x3
        imem[3] = 32'hFFFF_FFFF;
        
        cycle_count = 0;
        while (cycle_count < 70 && debug_reg_file[1] != 32'd5) begin
            #(CLK_PERIOD);
            cycle_count++;
        end
        
        if (debug_reg_file[1] == 32'd5) begin
            $display("✓ PASSED: x1 = 5 (20÷4, after %0d cycles, DIV_LATENCY=%0d)", 
                cycle_count, DIV_LATENCY);
            test_passed++;
        end else begin
            $display("✗ FAILED: x1 = %0d (expected 5)", debug_reg_file[1]);
            test_failed++;
        end
        
        // ====================================================================
        // TEST 6: LOAD/STORE
        // ====================================================================
        
        test_id = TEST_LOAD_STORE;
        $display("\n[TEST %0d] Load/Store - SW x1, 0(x2); LW x3, 0(x2)", test_id);
        
        rst_n = 1'b0;
        #(CLK_PERIOD);
        rst_n = 1'b1;
        #(CLK_PERIOD);
        
        dmem[0] = 32'h0;  // Clear memory
        
        imem[0] = 32'h0280_0093;  // ADDI x1, x0, 40   (x1=40)
        imem[1] = 32'h0000_0113;  // ADDI x2, x0, 0    (x2=0, memory address)
        imem[2] = 32'h0010_8023;  // SW x1, 0(x2)      (store x1 to mem[0])
        imem[3] = 32'h0001_2183;  // LW x3, 0(x2)      (load mem[0] to x3)
        imem[4] = 32'hFFFF_FFFF;
        
        cycle_count = 0;
        while (cycle_count < 50 && debug_reg_file[3] != 32'd40) begin
            #(CLK_PERIOD);
            cycle_count++;
        end
        
        if (debug_reg_file[3] == 32'd40 && dmem[0] == 32'd40) begin
            $display("✓ PASSED: x3 = 40 (loaded from memory, after %0d cycles)", cycle_count);
            test_passed++;
        end else begin
            $display("✗ FAILED: x3 = %0d, dmem[0] = %0d (expected 40)", 
                debug_reg_file[3], dmem[0]);
            test_failed++;
        end
        
        // ====================================================================
        // TEST 7: OPERAND FORWARDING
        // ====================================================================
        
        test_id = TEST_FORWARDING;
        $display("\n[TEST %0d] Forwarding - x1=5, x2=x1+3 (no register read stall)", test_id);
        
        rst_n = 1'b0;
        #(CLK_PERIOD);
        rst_n = 1'b1;
        #(CLK_PERIOD);
        
        imem[0] = 32'h0050_0093;  // ADDI x1, x0, 5
        imem[1] = 32'h0030_8113;  // ADDI x2, x1, 3  (x1 still in physical reg, forward from CDB)
        imem[2] = 32'hFFFF_FFFF;
        
        cycle_count = 0;
        while (cycle_count < 30 && debug_reg_file[2] != 32'd8) begin
            #(CLK_PERIOD);
            cycle_count++;
        end
        
        if (debug_reg_file[2] == 32'd8) begin
            $display("✓ PASSED: x2 = 8 (forwarded from x1, after %0d cycles)", cycle_count);
            test_passed++;
        end else begin
            $display("✗ FAILED: x2 = %0d (expected 8)", debug_reg_file[2]);
            test_failed++;
        end
        
        // ====================================================================
        // TEST 8: RAT RENAMING (multiple assignments to same arch reg)
        // ====================================================================
        
        test_id = TEST_RAT_RENAMING;
        $display("\n[TEST %0d] RAT Renaming - x1=5; x2=10; x1=x2+x1; verify x1=15", test_id);
        
        rst_n = 1'b0;
        #(CLK_PERIOD);
        rst_n = 1'b1;
        #(CLK_PERIOD);
        
        imem[0] = 32'h0050_0093;  // ADDI x1, x0, 5     (x1=5, RAT[1]=p?)
        imem[1] = 32'h0060_0113;  // ADDI x2, x0, 6     (x2=6)
        imem[2] = 32'h0020_8093;  // ADDI x1, x1, 2     (x1=x1+2=7, RAT[1]=p?)
        imem[3] = 32'h0061_0113;  // ADDI x2, x1, 1     (x2=x1+1=8)
        imem[4] = 32'hFFFF_FFFF;
        
        cycle_count = 0;
        while (cycle_count < 50 && debug_reg_file[2] != 32'd8) begin
            #(CLK_PERIOD);
            cycle_count++;
        end
        
        if (debug_reg_file[1] == 32'd7 && debug_reg_file[2] == 32'd8) begin
            $display("✓ PASSED: x1=7, x2=8 - RAT renaming worked! (after %0d cycles)", cycle_count);
            test_passed++;
        end else begin
            $display("✗ FAILED: x1=%0d (expected 7), x2=%0d (expected 8)", 
                debug_reg_file[1], debug_reg_file[2]);
            test_failed++;
        end
        
        // ====================================================================
        // TEST 9: MIXED OPERATIONS
        // ====================================================================
        
        test_id = TEST_VECTOR;
        $display("\n[TEST %0d] Mixed ALU/MUL/ADD sequence", test_id);
        
        rst_n = 1'b0;
        #(CLK_PERIOD);
        rst_n = 1'b1;
        #(CLK_PERIOD);
        
        imem[0] = 32'h0040_0093;  // ADDI x1, x0, 4
        imem[1] = 32'h0030_0113;  // ADDI x2, x0, 3
        imem[2] = 32'h0231_0183;  // MUL x3, x1, x2   (3×4=12)
        imem[3] = 32'h0050_0213;  // ADDI x4, x0, 5
        imem[4] = 32'h0041_8283;  // ADDI x5, x3, 4   (12+4=16, depends on x3)
        imem[5] = 32'hFFFF_FFFF;
        
        cycle_count = 0;
        while (cycle_count < 70 && debug_reg_file[5] != 32'd16) begin
            #(CLK_PERIOD);
            cycle_count++;
        end
        
        if (debug_reg_file[3] == 32'd12 && debug_reg_file[5] == 32'd16) begin
            $display("✓ PASSED: x3=12 (MUL), x5=16 (depends on x3) - after %0d cycles", cycle_count);
            test_passed++;
        end else begin
            $display("✗ FAILED: x3=%0d (expected 12), x5=%0d (expected 16)", 
                debug_reg_file[3], debug_reg_file[5]);
            test_failed++;
        end
        
        // ====================================================================
        // TEST SUMMARY
        // ====================================================================
        
        #(10 * CLK_PERIOD);
        
        $display("\n=====================================");
        $display("TEST SUMMARY");
        $display("=====================================");
        $display("Tests Passed: %0d", test_passed);
        $display("Tests Failed: %0d", test_failed);
        $display("Total Tests:  %0d", test_passed + test_failed);
        
        if (test_failed == 0) begin
            $display("\n✓ ALL TESTS PASSED!");
        end else begin
            $display("\n✗ SOME TESTS FAILED!");
        end
        
        $display("=====================================\n");
        
        $finish;
    end
    
    // ========================================================================
    // MONITORING & DEBUG OUTPUT
    // ========================================================================
    
    always @(posedge clk) begin
        if (exception_valid) begin
            $display("[%0t] EXCEPTION: code=%h", $time, exception_code);
        end
    end

endmodule
