// ============================================================================
// riscv_core_top.sv
// ============================================================================
// ARCHITECTURE: 6-stage OoO processor with RAT + PRF renaming scheme
// Key Notes: 
// - ROB is for in-oreder commit only, no data storage
// - Speculative data stored in physical_register_file
// commit state is tracked by arch_RAT and arch_free_list

`include "RTL/riscv_header.sv"

module riscv_core_top (
    input clk,
    input rst_n,
    
    output [`XLEN-1:0] imem_addr,
    input [`INST_WIDTH-1:0] imem_data,
    input imem_valid,
    
    // Data Memory - Dual Port Assumption
    // Read Port
    output [`XLEN-1:0] dmem_read_addr,
    output dmem_read_en,
    input [`XLEN-1:0] dmem_read_data,
    input dmem_read_valid,
    
    // Write Port
    output [`XLEN-1:0] dmem_write_addr,
    output [`XLEN-1:0] dmem_write_data,
    output dmem_write_en,
    input dmem_write_ready, // Add to top level interface
    output [3:0] dmem_be,
    
    input ext_irq,
    output exception_valid,
    output [`EXCEPTION_CODE_WIDTH-1:0] exception_code,
    output [`NUM_INT_REGS-1:0][`XLEN-1:0] debug_reg_file
);
    
    // ========================================================================
    // INTERNAL SIGNALS
    // ========================================================================
    
    // Pipeline stage signals
    logic [`XLEN-1:0] fetch_pc, decode_pc;
    logic [`INST_WIDTH-1:0] fetch_instr, decode_instr;
    logic [3:0] decode_instr_type;
    logic fetch_valid, decode_valid, dispatch_valid;
    logic [3:0] dispatch_rs_type;
    logic fetch_predicted_branch, decode_predicted_branch, dispatch_predicted_branch;
    logic [`XLEN-1:0] fetch_predicted_target, decode_predicted_target, dispatch_predicted_target;
    logic dispatch_rs_alloc, dispatch_rob_alloc, dispatch_lsq_alloc;
    logic dispatch_src1_valid, dispatch_src2_valid;
    logic dispatch_lsq_is_store;
    logic dispatch_lsq_is_vector;
    logic [31:0] dispatch_lsq_vtype;
    logic [`LSQ_TAG_WIDTH-1:0] dispatch_lsq_tag, lsq_alloc_tag_from_exec;
    logic [2:0] dispatch_lsq_size;
    
    // Dispatch outputs
    logic [`XLEN-1:0] dispatch_imm, dispatch_pc;
    logic [4:0] dispatch_dest_reg;
    logic [4:0] dispatch_alu_op;
    logic dispatch_use_rs1, dispatch_use_rs2, dispatch_use_pc;
    logic [31:0] dispatch_vtype;
    logic dispatch_use_vl;

    
    // RAT signals (Register Alias Table)
    logic [5:0] rat_src1_phys, rat_src2_phys, rat_dst_phys, rat_dst_old_phys;
    
    // Physical register file signals
    logic [`XLEN-1:0] phys_reg_data1, phys_reg_data2;
    logic [`XLEN-1:0] phys_reg_data_commit;
    logic [`NUM_PHYS_REGS-1:0] phys_reg_status;
    logic [5:0] commit_read_addr_wire;
    
    // RS signals (5 types)
    logic alu_rs_full, mem_rs_full, mul_rs_full, div_rs_full, vec_rs_full;
    logic [4:0] alu_operation, mem_operation, vec_operation, mul_operation, div_operation;
    logic alu_valid, mem_valid, mul_valid, div_valid, vec_valid;
    logic [`LSQ_TAG_WIDTH-1:0] mem_lsq_tag; // To Execute
    
    // Dual CDBs
    logic [`XLEN-1:0] cdb0_result;
    logic [5:0] cdb0_tag;
    logic cdb0_valid;
    logic [`XLEN-1:0] cdb1_result;
    logic [5:0] cdb1_tag;
    logic cdb1_valid;
    
    // Vector CDBs
    logic [`VLEN-1:0] vec_cdb0_result;
    logic [5:0] vec_cdb0_tag;
    logic vec_cdb0_valid;
    
    logic [`VLEN-1:0] vec_cdb1_result;
    logic [5:0] vec_cdb1_tag;
    logic vec_cdb1_valid;
    
    // Vector CSR Signals
    logic [5:0] spec_vl_tag;
    logic [31:0] spec_vtype;
    logic vtype_update_en;
    logic [31:0] new_vtype;

    // Vector PRF and Free List Signals
    logic [5:0] free_vphys_reg;
    logic free_vlist_valid;
    logic [`NUM_PHYS_REGS-1:0] vphys_reg_status;

    // Free list signals
    logic [5:0] free_phys_reg;
    logic free_list_valid;
    
    // Issue Stage -> RegRead Stage Wires
    logic alu_issue_valid, mem_issue_valid, mul_issue_valid, div_issue_valid, vec_issue_valid;
    logic [5:0] alu_issue_src1_tag, alu_issue_src2_tag, alu_issue_dest_tag;
    logic [5:0] mem_issue_src1_tag, mem_issue_src2_tag, mem_issue_dest_tag, mem_issue_vl_tag;
    logic [5:0] mul_issue_src1_tag, mul_issue_src2_tag, mul_issue_dest_tag;
    logic [5:0] div_issue_src1_tag, div_issue_src2_tag, div_issue_dest_tag;
    logic [5:0] vec_issue_src1_tag, vec_issue_src2_tag, vec_issue_dest_tag, vec_issue_vl_tag;
    logic [`XLEN-1:0] alu_issue_imm, alu_issue_pc, mem_issue_imm;
    logic [`XLEN-1:0] vec_issue_vtype;
    logic alu_issue_predicted_branch;
    logic [`XLEN-1:0] alu_issue_predicted_target;
    logic [4:0] alu_issue_op, mem_issue_op, mul_issue_op, div_issue_op, vec_issue_op;
    logic alu_issue_use_rs1, alu_issue_use_rs2, alu_issue_use_pc, mem_issue_use_rs1, mem_issue_use_rs2, mem_issue_use_vl, vec_issue_use_vl;
    logic [`LSQ_TAG_WIDTH-1:0] mem_issue_lsq_tag;

    // RegRead Stage -> Execute Stage Wires (To be driven by reg_read_stage)
    logic [`XLEN-1:0] alu_op1, alu_op2, mem_op1, mul_op1, mul_op2, div_op1, div_op2;
    logic [`XLEN-1:0] alu_pc_exec, alu_imm_exec;
    logic alu_predicted_branch_exec;
    logic [`XLEN-1:0] alu_predicted_target_exec;
    logic [`DLEN-1:0] mem_op2;
    logic [`XLEN-1:0] mem_imm_exec;
    logic [31:0] mem_vl_exec;
    logic [`VLEN-1:0] vec_op1, vec_op2;
    logic [31:0] vec_vl_exec, vec_vtype_exec;
    logic [5:0] alu_tag, mem_tag, mul_tag, div_tag, vec_tag; 
    
    // PRF Read Ports Wiring
    logic [5:0] prf_read_addrs [0:9];
    logic [`XLEN-1:0] prf_read_datas [0:9];
    logic [5:0] vprf_read_addr1, vprf_read_addr2, vprf_read_addr3;
    logic [`VLEN-1:0] vprf_read_data1, vprf_read_data2, vprf_read_data3;
    // ROB signals (TRACKING ONLY, not data)
    logic rob_full, rob_commit_valid;
    logic [4:0] rob_commit_dest_arch_reg;
    logic [5:0] rob_commit_dest_phys_reg;  // Physical reg holding the result
    logic [5:0] rob_commit_old_phys_reg;   // Old physical reg to free
    logic [3:0] rob_commit_instr_type;
    logic rob_flush_req;
    logic [`XLEN-1:0] rob_flush_pc;
    logic [31:0] rob_commit_vtype;
    
    logic branch_update_req, branch_update_taken;
    logic [`XLEN-1:0] branch_update_pc, branch_update_target;
    logic alu_flush_req;
    logic [5:0] alu_flush_tag;
    logic [`XLEN-1:0] alu_flush_target;
     
    // Control signals
    logic flush_pipeline;
    logic stall_fetch, stall_decode, stall_dispatch;
    logic [`XLEN-1:0] flush_target_pc_wire;

    logic lsq_full;
    logic lsq_flush_req;
    logic [5:0] lsq_violation_tag;

    // ========================================================================
    // STAGE 1: FETCH
    // ========================================================================
    
    fetch_stage fetch_inst (.clk(clk), .rst_n(rst_n), .stall(stall_fetch), .flush(flush_pipeline),
        .flush_pc(flush_target_pc_wire), .pc_out(fetch_pc), .instr_out(fetch_instr),
        .valid_out(fetch_valid), .imem_addr(imem_addr), .imem_data(imem_data), .imem_valid(imem_valid),
        .predicted_branch_in(fetch_predicted_branch), .predicted_target_in(fetch_predicted_target));

    // ========================================================================
    // STAGE 2: DECODE
    // ========================================================================
    
    decode_stage decode_inst (.clk(clk), .rst_n(rst_n), .flush(flush_pipeline), .stall(stall_decode),
        .instr_in(fetch_instr), .pc_in(fetch_pc), .predicted_branch_in(fetch_predicted_branch), .predicted_target_in(fetch_predicted_target), .valid_in(fetch_valid),
        .instr_type_out(decode_instr_type), .pc_out(decode_pc),
        .predicted_branch_out(decode_predicted_branch), .predicted_target_out(decode_predicted_target),
        .instr_out(decode_instr), .valid_out(decode_valid));

    // ========================================================================
    // VECTOR CSR
    // ========================================================================
    vector_csr vcsr_inst (.clk(clk), .rst_n(rst_n), .flush(flush_pipeline),
        .spec_vl_tag(spec_vl_tag), .spec_vtype(spec_vtype),
        .vtype_update_en(vtype_update_en), .new_vtype(new_vtype), .vsetvli_phys_tag(free_phys_reg),
        .commit_req(rob_commit_valid && rob_commit_instr_type == `V_EXT_CONFIG),
        .commit_vtype(rob_commit_vtype), .commit_vl_tag(rob_commit_dest_phys_reg)); 


    // ========================================================================
    // PHYSICAL REGISTER FILE (Speculative data storage)
    // ========================================================================
    
    logic decode_instr_type_is_vec;
    assign decode_instr_type_is_vec = (decode_instr_type == `V_EXT_VEC || decode_instr_type == `V_EXT_LOAD || decode_instr_type == `V_EXT_STORE);

    physical_register_file phys_regfile_inst (.clk(clk), .rst_n(rst_n),
        .write_addr0(cdb0_tag), .write_data0(cdb0_result), .write_en0(cdb0_valid),
        .write_addr1(cdb1_tag), .write_data1(cdb1_result), .write_en1(cdb1_valid),
        .read_addrs(prf_read_addrs), .read_datas(prf_read_datas),
        .commit_read_addr(commit_read_addr_wire),
        .commit_read_data(phys_reg_data_commit),
        .status_valid(phys_reg_status),
        .alloc_addr(rat_dst_phys), 
        .alloc_en(dispatch_valid && !decode_instr_type_is_vec)); 

    vector_physical_register_file vphys_regfile_inst (.clk(clk), .rst_n(rst_n),
        .write_addr0(vec_cdb0_tag), .write_data0(vec_cdb0_result), .write_en0(vec_cdb0_valid),
        .write_addr1(vec_cdb1_tag), .write_data1(vec_cdb1_result), .write_en1(vec_cdb1_valid),
        .read_addr1(vprf_read_addr1), .read_addr2(vprf_read_addr2), .read_addr3(vprf_read_addr3),
        .read_data1(vprf_read_data1), .read_data2(vprf_read_data2), .read_data3(vprf_read_data3),
        .status_valid(vphys_reg_status),
        .commit_read_addr(6'b0), .commit_read_data(),
        .alloc_addr(rat_dst_phys), 
        .alloc_en(dispatch_valid && decode_instr_type_is_vec));

    // ========================================================================
    // FREE LIST (Returns freed physical registers)
    // ========================================================================

    logic rob_commit_type_is_vec;
    assign rob_commit_type_is_vec = (rob_commit_instr_type == `V_EXT_VEC || rob_commit_instr_type == `V_EXT_LOAD || rob_commit_instr_type == `V_EXT_STORE);

    logic commit_free_list;
    assign commit_free_list = (rob_commit_valid && !rob_commit_type_is_vec);
    logic commit_vector_free_list;
    assign commit_vector_free_list = (rob_commit_valid && rob_commit_type_is_vec);

    free_list free_list_inst (.clk(clk), .rst_n(rst_n), .flush(flush_pipeline),
        .alloc_req(dispatch_valid && !decode_instr_type_is_vec), .alloc_phys(free_phys_reg),
        .alloc_valid(free_list_valid),
        .commit_phys(rob_commit_dest_phys_reg),
        .free_phys(rob_commit_old_phys_reg), 
        .commit_en(commit_free_list));
        
    vector_free_list v_free_list_inst (.clk(clk), .rst_n(rst_n), .flush(flush_pipeline),
        .alloc_req(dispatch_valid && decode_instr_type_is_vec),
        .alloc_phys(free_vphys_reg), .alloc_valid(free_vlist_valid),
        .commit_phys(rob_commit_dest_phys_reg),
        .free_phys(rob_commit_old_phys_reg),
        .commit_en(commit_vector_free_list));

    // ========================================================================
    // STAGE 3: DISPATCH
    // ========================================================================
    
    logic commit_rat;
    assign commit_rat = rob_commit_valid && !rob_commit_type_is_vec && (rob_commit_instr_type != `IBASE_STORE);
    logic commit_vrat;
    assign commit_vrat = rob_commit_valid && (rob_commit_instr_type == `V_EXT_VEC || rob_commit_instr_type == `V_EXT_LOAD);

    logic dispatch_src1_valid_wire;
    assign dispatch_src1_valid_wire = (decode_instr_type == `V_EXT_VEC) ? vphys_reg_status[rat_src1_phys] : phys_reg_status[rat_src1_phys];
    logic dispatch_src2_valid_wire;
    assign dispatch_src2_valid_wire = (decode_instr_type == `V_EXT_VEC || decode_instr_type == `V_EXT_STORE) ? vphys_reg_status[rat_src2_phys] : phys_reg_status[rat_src2_phys];
    logic dispatch_src1_is_vec;
    logic dispatch_src2_is_vec;

    dispatch_stage dispatch_inst (.clk(clk), .rst_n(rst_n), .stall(stall_dispatch), .flush(flush_pipeline),
        .instr_in(decode_instr), .instr_type(decode_instr_type), .pc_in(decode_pc), 
        .predicted_branch_in(decode_predicted_branch), .predicted_target_in(decode_predicted_target), .valid_in(decode_valid),
        .free_phys_reg(free_phys_reg),
        .free_vphys_reg(free_vphys_reg),
        .commit_arch_reg(rob_commit_dest_arch_reg), .commit_phys_reg(rob_commit_dest_phys_reg), .commit_rat(commit_rat),
        .commit_vrat(commit_vrat),
        .phys_rs1(rat_src1_phys), .phys_rs2(rat_src2_phys), .phys_rd(rat_dst_phys), .phys_rd_old(rat_dst_old_phys),
        .imm_out(dispatch_imm), .pc_out(dispatch_pc),
        .use_rs1_out(dispatch_use_rs1), .use_rs2_out(dispatch_use_rs2), .use_pc_out(dispatch_use_pc),
        .use_vl_out(dispatch_use_vl),
        .dispatch_src1_is_vec(dispatch_src1_is_vec), .dispatch_src2_is_vec(dispatch_src2_is_vec),
        .dispatch_predicted_branch(dispatch_predicted_branch),
        .dispatch_predicted_target(dispatch_predicted_target),
        .spec_vtype(spec_vtype), .vtype_out(dispatch_vtype),
        .vtype_update_en(vtype_update_en), .new_vtype(new_vtype),
        .dest_reg(dispatch_dest_reg),
        .alu_op(dispatch_alu_op), .valid_out(dispatch_valid),
        .rs_type(dispatch_rs_type), .rs_alloc_valid(dispatch_rs_alloc),
        .rob_alloc_valid(dispatch_rob_alloc),
        .lsq_alloc_tag_in(lsq_alloc_tag_from_exec), .dispatch_lsq_tag(dispatch_lsq_tag), 
        .lsq_alloc_req(dispatch_lsq_alloc), .lsq_alloc_is_store(dispatch_lsq_is_store),
        .lsq_alloc_is_vector(dispatch_lsq_is_vector), .lsq_alloc_vtype(dispatch_lsq_vtype),
        .lsq_alloc_size(dispatch_lsq_size)
    );

    // ========================================================================
    // ISSUE STAGE (Encapsulating all RS and Scheduler)
    // ========================================================================
    
    issue_stage issue_stage_inst (
        .clk(clk), .rst_n(rst_n), .flush(flush_pipeline),
        .dispatch_valid(dispatch_rs_alloc), .dispatch_rs_type(dispatch_rs_type),
        .dispatch_src1_tag(rat_src1_phys), .dispatch_src1_valid(dispatch_src1_valid_wire),
        .dispatch_src2_tag(rat_src2_phys), .dispatch_src2_valid(dispatch_src2_valid_wire),
        .dispatch_use_rs1(dispatch_use_rs1), .dispatch_use_rs2(dispatch_use_rs2), .dispatch_use_pc(dispatch_use_pc),
        .dispatch_use_vl(dispatch_use_vl), .dispatch_vl_tag(spec_vl_tag), .dispatch_vl_valid(phys_reg_status[spec_vl_tag]),
        .dispatch_imm(dispatch_imm), .dispatch_vtype(dispatch_vtype), .dispatch_pc(dispatch_pc),
        .dispatch_alu_op(dispatch_alu_op), .dispatch_dest_tag(rat_dst_phys),
        .dispatch_predicted_branch(dispatch_predicted_branch),
        .dispatch_predicted_target(dispatch_predicted_target),
        .dispatch_src1_is_vec(dispatch_src1_is_vec), .dispatch_src2_is_vec(dispatch_src2_is_vec),
        .dispatch_lsq_tag(dispatch_lsq_tag),
        .cdb0_tag(cdb0_tag), .cdb0_valid(cdb0_valid),
        .cdb1_tag(cdb1_tag), .cdb1_valid(cdb1_valid),
        .vec_cdb0_tag(vec_cdb0_tag), .vec_cdb0_valid(vec_cdb0_valid),
        .vec_cdb1_tag(vec_cdb1_tag), .vec_cdb1_valid(vec_cdb1_valid),
        .mem_fu_ready(1'b1), 
        .div_fu_ready(1'b1), // Replace with actual DIV busy signal if unpipelined
        .vec_fu_ready(1'b1), // VEU is one cycle now; Need optimization for high-latency operations like VMUL/VDIV
        .alu_rs_full(alu_rs_full), .mem_rs_full(mem_rs_full),
        .mul_rs_full(mul_rs_full), .div_rs_full(div_rs_full), .vec_rs_full(vec_rs_full),
        
        .alu_issue_valid(alu_issue_valid), .alu_issue_src1_tag(alu_issue_src1_tag),
        .alu_issue_src2_tag(alu_issue_src2_tag), .alu_issue_dest_tag(alu_issue_dest_tag),
        .alu_issue_use_rs1(alu_issue_use_rs1), .alu_issue_use_rs2(alu_issue_use_rs2), .alu_issue_use_pc(alu_issue_use_pc),
        .alu_issue_imm(alu_issue_imm), .alu_issue_pc(alu_issue_pc), .alu_issue_op(alu_issue_op),
        .alu_issue_predicted_branch(alu_issue_predicted_branch),
        .alu_issue_predicted_target(alu_issue_predicted_target),
        
        .mem_issue_valid(mem_issue_valid), .mem_issue_src1_tag(mem_issue_src1_tag),
        .mem_issue_src2_tag(mem_issue_src2_tag), .mem_issue_dest_tag(mem_issue_dest_tag),
        .mem_issue_use_rs1(mem_issue_use_rs1), .mem_issue_use_rs2(mem_issue_use_rs2),
        .mem_issue_imm(mem_issue_imm), .mem_issue_op(mem_issue_op), .mem_issue_lsq_tag(mem_issue_lsq_tag), .mem_issue_use_vl(mem_issue_use_vl), .mem_issue_vl_tag(mem_issue_vl_tag),
        
        .mul_issue_valid(mul_issue_valid), .mul_issue_src1_tag(mul_issue_src1_tag),
        .mul_issue_src2_tag(mul_issue_src2_tag), .mul_issue_dest_tag(mul_issue_dest_tag),
        .mul_issue_op(mul_issue_op),
        
        .div_issue_valid(div_issue_valid), .div_issue_src1_tag(div_issue_src1_tag),
        .div_issue_src2_tag(div_issue_src2_tag), .div_issue_dest_tag(div_issue_dest_tag),
        .div_issue_op(div_issue_op),
        
        .vec_issue_valid(vec_issue_valid), .vec_issue_src1_tag(vec_issue_src1_tag),
        .vec_issue_src2_tag(vec_issue_src2_tag), .vec_issue_dest_tag(vec_issue_dest_tag),
        .vec_issue_op(vec_issue_op), .vec_issue_use_vl(vec_issue_use_vl), .vec_issue_vl_tag(vec_issue_vl_tag), .vec_issue_vtype(vec_issue_vtype)
    );

    // ========================================================================
    // REG_READ STAGE (Payload/Bypass)
    // ========================================================================
    
    reg_read_stage reg_read_stage_inst (
        .clk(clk), .rst_n(rst_n), .flush(flush_pipeline),
        .alu_issue_valid(alu_issue_valid), .alu_issue_src1_tag(alu_issue_src1_tag), .alu_issue_src2_tag(alu_issue_src2_tag),
        .alu_issue_dest_tag(alu_issue_dest_tag), .alu_issue_imm(alu_issue_imm), .alu_issue_pc(alu_issue_pc),
        .alu_issue_predicted_branch(alu_issue_predicted_branch),
        .alu_issue_predicted_target(alu_issue_predicted_target),
        .alu_issue_op(alu_issue_op), .alu_use_rs1(alu_issue_use_rs1), .alu_use_rs2(alu_issue_use_rs2), .alu_use_pc(alu_issue_use_pc),
        .mem_issue_valid(mem_issue_valid), .mem_issue_src1_tag(mem_issue_src1_tag), .mem_issue_src2_tag(mem_issue_src2_tag),
        .mem_issue_dest_tag(mem_issue_dest_tag), .mem_issue_imm(mem_issue_imm), .mem_issue_op(mem_issue_op),
        .mem_issue_lsq_tag(mem_issue_lsq_tag), .mem_use_rs1(mem_issue_use_rs1), .mem_use_rs2(mem_issue_use_rs2), .mem_issue_vl_tag(mem_issue_vl_tag), .mem_use_vl(mem_issue_use_vl),
        .mul_issue_valid(mul_issue_valid), .mul_issue_src1_tag(mul_issue_src1_tag), .mul_issue_src2_tag(mul_issue_src2_tag),
        .mul_issue_dest_tag(mul_issue_dest_tag), .mul_issue_op(mul_issue_op),
        .div_issue_valid(div_issue_valid), .div_issue_src1_tag(div_issue_src1_tag), .div_issue_src2_tag(div_issue_src2_tag),
        .div_issue_dest_tag(div_issue_dest_tag), .div_issue_op(div_issue_op),
        .vec_issue_valid(vec_issue_valid), .vec_issue_src1_tag(vec_issue_src1_tag), .vec_issue_src2_tag(vec_issue_src2_tag),
        .vec_issue_dest_tag(vec_issue_dest_tag), .vec_issue_op(vec_issue_op),
        .vec_issue_vl_tag(vec_issue_vl_tag), .vec_use_vl(vec_issue_use_vl), .vec_issue_vtype(vec_issue_vtype),
        .prf_read_addrs(prf_read_addrs), .prf_read_datas(prf_read_datas),
        .vprf_read_addr1(vprf_read_addr1), .vprf_read_addr2(vprf_read_addr2), .vprf_read_addr3(vprf_read_addr3),
        .vprf_read_data1(vprf_read_data1), .vprf_read_data2(vprf_read_data2), .vprf_read_data3(vprf_read_data3),
        .cdb0_valid(cdb0_valid), .cdb0_tag(cdb0_tag), .cdb0_result(cdb0_result),
        .cdb1_valid(cdb1_valid), .cdb1_tag(cdb1_tag), .cdb1_result(cdb1_result),
        .vec_cdb0_valid(vec_cdb0_valid), .vec_cdb0_tag(vec_cdb0_tag), .vec_cdb0_result(vec_cdb0_result),
        .vec_cdb1_valid(vec_cdb1_valid), .vec_cdb1_tag(vec_cdb1_tag), .vec_cdb1_result(vec_cdb1_result),
        .alu_valid_exec(alu_valid), .mem_valid_exec(mem_valid), .mul_valid_exec(mul_valid), .div_valid_exec(div_valid), .vec_valid_exec(vec_valid),
        .alu_op1_exec(alu_op1), .alu_op2_exec(alu_op2), .mem_op1_exec(mem_op1), .mem_op2_exec(mem_op2), .mem_imm_exec(mem_imm_exec), .mem_vl_exec(mem_vl_exec),
        .alu_pc_exec(alu_pc_exec), .alu_imm_exec(alu_imm_exec), .alu_predicted_branch_exec(alu_predicted_branch_exec),
        .alu_predicted_target_exec(alu_predicted_target_exec),
        .mul_op1_exec(mul_op1), .mul_op2_exec(mul_op2), .div_op1_exec(div_op1), .div_op2_exec(div_op2),
        .vec_op1_exec(vec_op1), .vec_op2_exec(vec_op2),
        .vec_vl_exec(vec_vl_exec), .vec_vtype_exec(vec_vtype_exec),
        .alu_tag_exec(alu_tag), .mem_tag_exec(mem_tag), .mul_tag_exec(mul_tag), .div_tag_exec(div_tag), .vec_tag_exec(vec_tag),
        .alu_op_exec(alu_operation), .mem_op_exec(mem_operation), .vec_op_exec(vec_operation),
        .mul_op_exec(mul_operation), .div_op_exec(div_operation), .mem_lsq_tag_exec(mem_lsq_tag)
    );

    // ========================================================================
    // STAGE 4: EXECUTE (Encapsulated FUs)
    // ========================================================================
    
    execute_stage execute_inst (.clk(clk), .rst_n(rst_n),
        .flush(flush_pipeline),
        // LSQ Allocation Tunneling
        .lsq_alloc_req(dispatch_lsq_alloc), .lsq_alloc_is_store(dispatch_lsq_is_store),
        .lsq_alloc_is_vector(dispatch_lsq_is_vector), .lsq_alloc_vtype(dispatch_lsq_vtype),
        .lsq_alloc_size(dispatch_lsq_size),
        .alloc_phys_tag(rat_dst_phys), .alloc_tag(lsq_alloc_tag_from_exec),
        .lsq_full(lsq_full),
        .alu_op1(alu_op1), .alu_op2(alu_op2), .alu_operation(alu_operation),
        .alu_pc(alu_pc_exec), .alu_imm(alu_imm_exec), .alu_predicted_branch(alu_predicted_branch_exec),
        .alu_predicted_target(alu_predicted_target_exec),
        .alu_valid(alu_valid), .alu_tag(alu_tag),
        .mem_op1(mem_op1), .mem_op2(mem_op2), .mem_imm(mem_imm_exec), .mem_vl(mem_vl_exec), .mem_operation(mem_operation),
        .mem_valid(mem_valid), .mem_tag(mem_tag), .mem_lsq_tag(mem_lsq_tag),
        .mul_op1(mul_op1), .mul_op2(mul_op2), .mul_operation(mul_operation), .mul_valid(mul_valid), .mul_tag(mul_tag),
        .div_op1(div_op1), .div_op2(div_op2), .div_operation(div_operation), .div_valid(div_valid), .div_tag(div_tag),
        .vec_op1(vec_op1), .vec_op2(vec_op2), .vec_operation(vec_operation),
        .vec_valid(vec_valid), .vec_tag(vec_tag),
        .vec_vl(vec_vl_exec), .vec_vtype(vec_vtype_exec),
        .dmem_read_addr(dmem_read_addr), .dmem_read_en(dmem_read_en), 
        .dmem_read_data(dmem_read_data), .dmem_read_valid(dmem_read_valid),
        .dmem_write_addr(dmem_write_addr), .dmem_write_data(dmem_write_data), 
        .dmem_write_en(dmem_write_en), .dmem_be(dmem_be),
        .dmem_write_ready(dmem_write_ready), // Default to 1'b1 in testbench if no complex memory
        .commit_lsq(rob_commit_valid && (rob_commit_instr_type == `IBASE_STORE || rob_commit_instr_type == `IBASE_LOAD || rob_commit_instr_type == `V_EXT_STORE || rob_commit_instr_type == `V_EXT_LOAD)),
        .alu_flush_req(alu_flush_req), .alu_flush_tag(alu_flush_tag), .alu_flush_target(alu_flush_target),
        .lsq_flush(lsq_flush_req), .lsq_violation_tag(lsq_violation_tag),
        .branch_update_req(branch_update_req), .branch_update_pc(branch_update_pc), .branch_update_target(branch_update_target), .branch_update_taken(branch_update_taken),
        .cdb0_result(cdb0_result), .cdb0_tag(cdb0_tag), .cdb0_valid(cdb0_valid),
        .cdb1_result(cdb1_result), .cdb1_tag(cdb1_tag), .cdb1_valid(cdb1_valid),
        .vec_cdb0_result(vec_cdb0_result), .vec_cdb0_tag(vec_cdb0_tag), .vec_cdb0_valid(vec_cdb0_valid),
        .vec_cdb1_result(vec_cdb1_result), .vec_cdb1_tag(vec_cdb1_tag), .vec_cdb1_valid(vec_cdb1_valid));

 
    // ========================================================================
    // REORDER BUFFER (Essentially the Commit Stage)
    // ========================================================================
    // There is NO Architectural Register File. Architectural state is tracked through arch_RAT
    // The ROB retiring the instruction and updating the RAT/Free List IS the commit.
    
    reorder_buffer rob_inst (.clk(clk), .rst_n(rst_n), .flush(flush_pipeline),
        .alloc_pc(decode_pc), // Pass PC directly from Decode for tracking
        .alloc_instr_type(decode_instr_type), .alloc_dest_reg(dispatch_dest_reg),
        .alloc_phys_reg(rat_dst_phys),
        .alloc_old_phys_reg(rat_dst_old_phys),
        .alloc_valid(dispatch_rob_alloc), .alloc_vtype(new_vtype), .rob_full(rob_full),
        .result0_tag(cdb0_tag), .result0_valid(cdb0_valid),
        .result1_tag(cdb1_tag), .result1_valid(cdb1_valid),
        .vec_result0_tag(vec_cdb0_tag), .vec_result0_valid(vec_cdb0_valid),
        .vec_result1_tag(vec_cdb1_tag), .vec_result1_valid(vec_cdb1_valid),
        .alu_flush_req(alu_flush_req), .alu_flush_tag(alu_flush_tag), .alu_flush_target(alu_flush_target),
        .lsq_violation_req(lsq_flush_req), .lsq_violation_tag(lsq_violation_tag),
        .commit_valid(rob_commit_valid), .commit_instr_type(rob_commit_instr_type),
        .commit_dest_reg(rob_commit_dest_arch_reg),
        .commit_dest_phys(rob_commit_dest_phys_reg),
        .commit_old_phys(rob_commit_old_phys_reg),
        .commit_vtype(rob_commit_vtype),
        .rob_flush_req(rob_flush_req), .rob_flush_pc(rob_flush_pc));

    assign commit_read_addr_wire = rob_commit_dest_phys_reg; // Peek into PRF

    
    // Debug tracking for Testbench (Simulates an ARF observer)
    logic [`NUM_INT_REGS-1:0][`XLEN-1:0] debug_reg_file_internal;
    assign debug_reg_file = debug_reg_file_internal;
    
    always @(posedge clk or negedge rst_n) begin
        integer i;
        if (!rst_n) begin
            for (i=0; i<`NUM_INT_REGS; i++) debug_reg_file_internal[i] <= '0;
        end else if (rob_commit_valid && (rob_commit_dest_arch_reg != 5'b0) && 
        !(rob_commit_instr_type == `V_EXT_VEC || rob_commit_instr_type == `V_EXT_LOAD || rob_commit_instr_type == `V_EXT_STORE)) begin
            // Grab the committed data directly from the PRF and store it purely for the TB to verify
            debug_reg_file_internal[rob_commit_dest_arch_reg] <= phys_reg_data_commit;
        end
    end

    // ========================================================================
    // SUPPORT MODULES
    // ========================================================================
    
    main_controller controller_inst (.clk(clk), .rst_n(rst_n),
        .rs_full(alu_rs_full || mem_rs_full || mul_rs_full || div_rs_full || vec_rs_full),
        .rob_full(rob_full), .lsq_full(lsq_full),
        .free_list_empty(!free_list_valid), // Wired from Free List
        .rob_flush_req(rob_flush_req), .rob_flush_pc(rob_flush_pc),
        .stall_fetch(stall_fetch), .stall_decode(stall_decode), .stall_dispatch(stall_dispatch),
        .flush_pipeline(flush_pipeline), .flush_target_pc(flush_target_pc_wire), .pipeline_mode());
    
    
    branch_predictor branch_pred_inst (.clk(clk), .rst_n(rst_n), .pc(fetch_pc),
        .predicted_branch(fetch_predicted_branch), .predicted_target(fetch_predicted_target), 
        .resolved_pc(branch_update_pc), .resolved_target(branch_update_target),
        .branch_taken(branch_update_taken), .branch_update_en(branch_update_req));
    

endmodule
