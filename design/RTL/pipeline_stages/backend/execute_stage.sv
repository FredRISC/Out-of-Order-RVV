// ============================================================================
// execute_stage.sv - REFACTORED: Encapsulates ALL Functional Units
// ============================================================================
// Improvements:
// - All FUs encapsulated (ALU, MUL, DIV, LSU, VEU)
// - Cleaner interface with top module
// - Easy to add/remove FUs without changing top module
// - CDB arbitration inside (not in top module)
// - Flexible number of FUs per type (parameterized)

`include "RTL/riscv_header.sv"

module execute_stage (
    input clk,
    input rst_n,
    input flush,
    
    // From reservation stations (ALU, MEM, MUL, DIV, VEC)
    input [`XLEN-1:0] alu_op1, alu_op2, // Operand 1 (Register or PC or 0), Operand 2 (Register or Imm)
    input [`XLEN-1:0] alu_pc, alu_imm,
    input alu_predicted_branch,
    input [`XLEN-1:0] alu_predicted_target,
    input [4:0] alu_operation,
    input alu_valid,
    input [5:0] alu_tag,
    
    input [`XLEN-1:0] mem_op1, // Base Address
    input [`DLEN-1:0] mem_op2, // Store Data (Scalar or Vector)
    input [`XLEN-1:0] mem_imm,
    input [4:0] mem_operation,
    input mem_valid,
    input [31:0] mem_vl,
    input [5:0] mem_tag,
    input [`LSQ_TAG_WIDTH-1:0] mem_lsq_tag, // LSQ Entry Tag
    
    input [`XLEN-1:0] mul_op1, mul_op2,
    input [4:0] mul_operation,
    input mul_valid,
    input [5:0] mul_tag,
    
    input [`XLEN-1:0] div_op1, div_op2,
    input [4:0] div_operation,
    input div_valid,
    input [5:0] div_tag,
    
    input [`VLEN-1:0] vec_op1, vec_op2,
    input [4:0] vec_operation,
    input vec_valid,
    input [5:0] vec_tag,
    input [31:0] vec_vl,
    input [31:0] vec_vtype,
    
    // LSQ Tunneling (Dispatch <-> LSQ)
    input lsq_alloc_req,
    input lsq_alloc_is_store,
    input lsq_alloc_is_vector,
    input [31:0] lsq_alloc_vtype,
    input [2:0] lsq_alloc_size,
    input [5:0] alloc_phys_tag,
    output [`LSQ_TAG_WIDTH-1:0] alloc_tag,
    output lsq_full,
    
    // Memory interface (from LSU)
    // Read Port
    output [`XLEN-1:0] dmem_read_addr,
    output dmem_read_en,
    input [`XLEN-1:0] dmem_read_data,
    input dmem_read_valid,
    
    // Write Port
    output [`XLEN-1:0] dmem_write_addr,
    output [`XLEN-1:0] dmem_write_data,
    output dmem_write_en,
    input dmem_write_ready,
    output [3:0] dmem_be,
    
    // Commit Signal for Store
    input commit_lsq,
    
    // Pipeline Flush Request from LSQ (Memory Disambiguation Violation)
    output lsq_flush,
    output [5:0] lsq_violation_tag,
    
    // Pipeline Flush Requests to ROB (Branch & Memory)
    output logic alu_flush_req,
    output logic [5:0] alu_flush_tag,
    output logic [`XLEN-1:0] alu_flush_target,
    
    // Branch Predictor Update Interface
    output logic branch_update_req,
    output logic [`XLEN-1:0] branch_update_pc,
    output logic [`XLEN-1:0] branch_update_target,
    output logic branch_update_taken,

    // CDB 0 Broadcast Interface (Scheduled - ALU/MUL/VEC)
    output logic [`XLEN-1:0] cdb0_result,
    output logic [5:0] cdb0_tag,
    output logic cdb0_valid,
    
    // CDB 1 Broadcast Interface (Unscheduled - LSQ/DIV)
    output logic [`XLEN-1:0] cdb1_result,
    output logic [5:0] cdb1_tag,
    output logic cdb1_valid,

    // Vector CDB 0 (Scheduled - VEU)
    output logic [`DLEN-1:0] vec_cdb0_result,
    output logic [5:0] vec_cdb0_tag,
    output logic vec_cdb0_valid,
    
    // Vector CDB 1 (Unscheduled - LSQ)
    output logic [`DLEN-1:0] vec_cdb1_result,
    output logic [5:0] vec_cdb1_tag,
    output logic vec_cdb1_valid
);

    // ========================================================================
    // Internal Signals: FU Outputs (Multiple per type)
    // ========================================================================
    
    // ALU FU outputs (can have multiple ALUs)
    logic [`XLEN-1:0] alu_results [`NUM_ALU_FUS-1:0];
    logic [5:0] alu_tags [`NUM_ALU_FUS-1:0];
    logic alu_valids [`NUM_ALU_FUS-1:0];
    
    // MUL FU outputs (can have multiple multipliers)
    logic [`XLEN-1:0] mul_results [`NUM_MUL_FUS-1:0];
    logic [5:0] mul_tags [`NUM_MUL_FUS-1:0];
    logic mul_valids [`NUM_MUL_FUS-1:0];
    
    // DIV FU outputs (can have multiple dividers)
    logic [`XLEN-1:0] div_results [`NUM_DIV_FUS-1:0];
    logic [5:0] div_tags [`NUM_DIV_FUS-1:0];
    logic div_valids [`NUM_DIV_FUS-1:0];
    
    // LSU output
    logic [`XLEN-1:0] lsu_scalar_result;
    logic lsu_valid;
    logic [`DLEN-1:0] lsu_vector_result;
    logic [5:0]      lsu_vector_tag;
    logic            lsu_vector_valid;
    
    // VEU output
    logic [`DLEN-1:0] veu_result;
    logic [5:0] vec_result_tag;
    logic vec_result_valid;

    // ========================================================================
    // Generate Multiple ALU Instances (Flexible)
    // ========================================================================
    
    genvar i;
    generate
        for (i = 0; i < `NUM_ALU_FUS; i = i + 1) begin : gen_alus
            alu alu_inst (
                .clk(clk),
                .rst_n(rst_n),
                .operand1(alu_op1),
                .operand2(alu_op2),
                .alu_op(alu_operation),
                .valid_in(alu_valid),
                .result(alu_results[i]),
                .valid_out(alu_valids[i])
            );
            
            // Local pipeline for tag since ALU module wasn't modified to pass it through
            reg [5:0] alu_tag_pipe [`ALU_LATENCY:0]; 
            always @(posedge clk) begin
                if (alu_valid) alu_tag_pipe[0] <= alu_tag;
                for (int j = 1; j <= `ALU_LATENCY; j = j + 1) alu_tag_pipe[j] <= alu_tag_pipe[j-1];
            end
            
            assign alu_tags[i] = (`ALU_LATENCY > 0) ? alu_tag_pipe[`ALU_LATENCY-1] : alu_tag;
        end
    endgenerate

    // ========================================================================
    // Generate Multiple Multiplier Instances (Flexible)
    // ========================================================================
    
    generate
        for (i = 0; i < `NUM_MUL_FUS; i = i + 1) begin : gen_muls
            multiplier mul_inst (
                .clk(clk),
                .rst_n(rst_n),
                .multiplicand(mul_op1),
                .multiplier(mul_op2),
                .valid_in(mul_valid),
                .mul_type(mul_operation[1:0]),
                .product_low(mul_results[i]),
                .product_high(),
                .valid_out(mul_valids[i]),
                .tag_in(mul_tag),
                .tag_out(mul_tags[i])
            );
            
        end
    endgenerate

    // ========================================================================
    // Generate Multiple Divider Instances (Flexible)
    // ========================================================================
    
    generate
        for (i = 0; i < `NUM_DIV_FUS; i = i + 1) begin : gen_divs
            divider div_inst (
                .clk(clk),
                .rst_n(rst_n),
                .dividend(div_op1),
                .divisor(div_op2),
                .valid_in(div_valid),
                .div_type(div_operation[1:0]),
                .quotient(div_results[i]),
                .remainder(),
                .valid_out(div_valids[i]),
                .tag_in(div_tag),
                .tag_out(div_tags[i])
            );
            
        end
    endgenerate

    // ========================================================================
    // Load-Store Unit (Single)
    // ========================================================================
    
    // AGU (Address Generation Unit)
    logic [`XLEN-1:0] agu_addr;
    assign agu_addr = mem_op1 + mem_imm;

    // Decode Load/Store (Assuming bit 0 differentiates if ALU_ADD is ambiguous, 
    // or relying on valid bits from Dispatch if implemented. 
    // Here we use a placeholder check; in real design Dispatch should send distinct ops)
    logic exe_is_store, exe_is_load;
    logic exe_is_strided;
    assign exe_is_store = (mem_operation == 5'b00001); // Defined in Dispatch
    assign exe_is_load  = (mem_operation == 5'b00000 || mem_operation == 5'b00010);
    assign exe_is_strided = (mem_operation == 5'b00010);
    
    logic [5:0] lsu_tag_extended;

    load_store_queue lsq_inst (
        .clk(clk),
        .rst_n(rst_n),
        .flush(flush), 
        
        // Dispatch Allocation Interface (handled in Top/Dispatch, wired separately)
        .alloc_req(lsq_alloc_req), 
        .alloc_is_store(lsq_alloc_is_store),
        .alloc_is_vector(lsq_alloc_is_vector),
        .alloc_vtype(lsq_alloc_vtype),
        .alloc_size(lsq_alloc_size),
        .dispatch_phys_tag(alloc_phys_tag),
        .alloc_tag(alloc_tag),
        .lsq_full(lsq_full),

        // Execute Interface
        .exe_addr(agu_addr),
        .exe_data(mem_op2), // Un-truncated to support full 128-bit Vector Stores
        .exe_lsq_tag(mem_lsq_tag),
        .exe_vl(mem_vl),
        .exe_is_strided(exe_is_strided),
        .exe_load_valid(mem_valid && exe_is_load),
        .exe_store_valid(mem_valid && exe_is_store),
        
        // Result Interface
        // Scalar Port
        .cdb_phys_tag_out(lsu_tag_extended), 
        .lsq_data_out(lsu_scalar_result),
        .lsq_out_valid(lsu_valid),
        // Vector Port
        .vec_cdb_phys_tag_out(lsu_vector_tag),
        .vec_lsq_data_out(lsu_vector_result),
        .vec_lsq_out_valid(lsu_vector_valid),
        
        .commit_lsq(commit_lsq), // Retire load/store
        
        // Memory interface
        .dmem_read_addr(dmem_read_addr),
        .dmem_read_en(dmem_read_en),
        .dmem_read_data(dmem_read_data),
        .dmem_read_valid(dmem_read_valid),
        
        .dmem_write_addr(dmem_write_addr),
        .dmem_write_data(dmem_write_data),
        .dmem_write_en(dmem_write_en),
        .dmem_write_ready(dmem_write_ready),
        .dmem_be(dmem_be), // Let LSQ control byte enables
        
        .flush_pipeline(lsq_flush), // Connected to trigger pipeline flush
        .lsq_violation_tag(lsq_violation_tag),
        
        // Status
        .load_blocked(),
        .store_blocked()
    );
    
    // ========================================================================
    // Vector Execution Unit (Single)
    // ========================================================================
    
    vector_execution_unit veu_inst (
        .clk(clk),
        .rst_n(rst_n),
        .vl(vec_vl),
        .vtype(vec_vtype),
        .vec_src1(vec_op1),
        .vec_src2(vec_op2),
        .vec_op(vec_operation),
        .vec_valid(vec_valid),
        .vec_result(veu_result),
        .vec_result_valid(vec_result_valid),
        .tag_in(vec_tag),
        .tag_out(vec_result_tag),
        .cdb_granted(1'b1),
        .vec_fu_ready()
    );

    // ========================================================================
    // Result Selection From Each FU Type (Priority Encoding)
    // ========================================================================
   
    logic [`XLEN-1:0] alu_result_selected;
    logic [5:0] alu_tag_selected;
    logic alu_result_valid;
    
    // ALU result selection
    always @(*) begin
        integer j;
        alu_result_valid = 1'b0;
        alu_result_selected = 0;
        alu_tag_selected = 0;
        
        for (j = 0; j < `NUM_ALU_FUS; j = j + 1) begin
            if (alu_valids[j]) begin
                alu_result_valid = 1'b1;
                alu_result_selected = alu_results[j];
                alu_tag_selected = alu_tags[j];
                break;
            end
        end
    end
    
    // MUL result selection
    logic [`XLEN-1:0] mul_result_selected;
    logic [5:0] mul_tag_selected;
    logic mul_result_valid;
    
    always @(*) begin
        integer j;
        mul_result_valid = 1'b0;
        mul_result_selected = 0;
        mul_tag_selected = 0;
        for (j = 0; j < `NUM_MUL_FUS; j = j + 1) begin
            if (mul_valids[j]) begin
                mul_result_valid = 1'b1;
                mul_result_selected = mul_results[j];
                mul_tag_selected = mul_tags[j];
                break;
            end
        end
    end

    // DIV result selection
    logic [`XLEN-1:0] div_result_selected;
    logic [5:0] div_tag_selected;
    logic div_result_valid;
    
    always @(*) begin
        integer j;
        div_result_valid = 1'b0;
        div_result_selected = 0;
        div_tag_selected = 0;
        for (j = 0; j < `NUM_DIV_FUS; j = j + 1) begin
            if (div_valids[j]) begin
                div_result_valid = 1'b1;
                div_result_selected = div_results[j];
                div_tag_selected = div_tags[j];
                break;
            end
        end
    end

    // ========================================================================
    // Branch Evaluation (Using the existing ALU Result)
    // ========================================================================
    // ARCHITECTURAL NOTE: In this V1 prototype, unconditional jumps (JAL/JALR) are 
    // resolved late in the Execute stage to simplify the flush/recovery architecture (via ROB).
    // They update the predictor here so Fetch can learn the jump target for next time.
    // Future Upgrade ("Frontend Redirect"): Decode stage should calculate JAL targets and 
    // redirect Fetch immediately without touching the ROB, saving penalty cycles on BTB misses.

    logic actual_taken;
    logic [`XLEN-1:0] actual_target;
    
    logic is_branch, is_jal, is_jalr;
    assign is_branch = (alu_operation >= `ALU_BEQ && alu_operation <= `ALU_BGEU);
    assign is_jal = (alu_operation == `ALU_JAL);
    assign is_jalr = (alu_operation == `ALU_JALR);
    
    always @(*) begin
        actual_taken = 1'b0;
        actual_target = alu_pc + alu_imm; // Default target calculation for JAL and Branch
        
        if (is_jal) begin
            actual_taken = 1'b1;
        end else if (is_jalr) begin
            actual_taken = 1'b1;
            actual_target = (alu_op1 + alu_imm) & ~32'h1; // JALR Target (rs1 + imm, clear LSB); all RISC-V instructions must be aligned to 2-byte boundaries
        end else if (is_branch) begin
            actual_taken = (alu_result_selected == 32'h1); // Uses the native ALU branch evaluation
        end
        
        alu_flush_req = 1'b0;
        alu_flush_target = 32'h0;
        alu_flush_tag = alu_tag_selected;
        
        // Detect mispredictions (Direction mismatch OR Target Aliasing)
        if (alu_result_valid && (is_branch || is_jal || is_jalr)) begin // We predict target address for JAL/JALR/Branch
            if ((actual_taken != alu_predicted_branch) || (actual_taken && (actual_target != alu_predicted_target))) begin
                alu_flush_req = 1'b1; // prediction failed - req sent to the ROB entry to mark it as violation (Delayed Flush)
                alu_flush_target = actual_taken ? actual_target : (alu_pc + 4);
            end
        end
    end
    
    // If prediction failed, update the predictor if branch was taken
    assign branch_update_req = alu_result_valid && (is_branch || is_jal || is_jalr); 
    assign branch_update_pc = alu_pc; // This is the resolved_pc input in branch_predictor module
    assign branch_update_target = actual_target;
    assign branch_update_taken = actual_taken;

    // ========================================================================
    // CDB 0: Scheduled Bus (ALU, MUL)
    // The issue_scheduler guarantees these will NEVER collide!
    // ========================================================================
    always @(*) begin
        cdb0_valid = 1'b0;
        cdb0_result = 0;
        cdb0_tag = 0;
        
        if (alu_result_valid) begin
            cdb0_valid = 1'b1;
            // Jumps write pc + 4 to rd, not the standard ALU result
            if (is_jal || is_jalr) cdb0_result = alu_pc + 4;
            else cdb0_result = alu_result_selected;
            cdb0_tag = alu_tag_selected;
        end 
        else if (mul_result_valid) begin
            cdb0_valid = 1'b1;
            cdb0_result = mul_result_selected;
            cdb0_tag = mul_tag_selected;
        end
        else if (div_result_valid) begin
            cdb0_valid = 1'b1;
            cdb0_result = div_result_selected;
            cdb0_tag = div_tag_selected;
        end
    end

    // ========================================================================
    // CDB 1: Unscheduled Bus (LSQ)
    // These operate outside the scheduler. LSQ gets priority.
    // (Known edge case: DIV drops data if LSQ hits on the same exact cycle).
    // ========================================================================
    always @(*) begin
        cdb1_valid = 1'b0;
        cdb1_result = 0;
        cdb1_tag = 0;
        
        if (lsu_valid) begin
            cdb1_valid = 1'b1;
            cdb1_result = lsu_scalar_result;
            cdb1_tag = lsu_tag_extended; 
        end 
    end

    // ========================================================================
    // Dedicated Vector CDBs (0th for VEU, 1st for LSQ Vector Results)
    // ========================================================================
    always @(*) begin
        vec_cdb0_valid = vec_result_valid;
        vec_cdb0_result = veu_result;
        vec_cdb0_tag = vec_result_tag;
        
        vec_cdb1_valid = lsu_vector_valid;
        vec_cdb1_result = lsu_vector_result;
        vec_cdb1_tag = lsu_vector_tag;
    end

endmodule
