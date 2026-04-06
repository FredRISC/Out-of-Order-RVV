// ============================================================================
// load_store_queue.sv - Load-Store Queue with Memory Hazard Detection
// ============================================================================
// Implements load/store queues with address hazard detection (WAR, RAW, WAW)
// and store-to-load forwarding.

`include "RTL/riscv_header.sv"

module load_store_queue (
    input clk,
    input rst_n,
    input flush,

    // 1. Dispatch Allocation Interface (In-Order)
    input alloc_req,
    input alloc_is_store,
    input alloc_is_vector, // Identify vector mem ops at dispatch
    input [31:0] alloc_vtype, // vtype from dispatch
    input [2:0] alloc_size,
    input [5:0] dispatch_phys_tag, // Phys tag of the instruction to be sent to CDB
    output logic [`LSQ_TAG_WIDTH-1:0] alloc_tag, // queue entry's id sent to dispatch_stage for matching after addr calculation
    output lsq_full,
    
    // 2. Execution Interface (Out-of-Order Address Calculation)
    input [`XLEN-1:0] exe_addr,  // Calculated address
    input [(`DLEN-1):0] exe_data,  // Store data (Expanded to `DLEN)
    input [`LSQ_TAG_WIDTH-1:0] exe_lsq_tag, // Which entry to update? = earlier sent alloc_tag 
    input [31:0] exe_vl,        // Vector Length arriving from Execute
    input exe_is_strided,       //  Identifies a strided load
    input exe_load_valid,
    input exe_store_valid,
    
    // 3. CDB 1 Interface
    // Scalar CDB Port (for scalar loads and all stores)
    output logic [`XLEN-1:0] lsq_data_out, // Data to CDB
    output logic [5:0] cdb_phys_tag_out, // PReg tag for CDB and ROB wakeup
    output logic lsq_out_valid, // Valid signal for CDB and ROB wakeup (stores also use this to wake up ROB)
    
    // Vector CDB Port (for vector loads)
    output logic [(`DLEN-1):0] vec_lsq_data_out,
    output logic [5:0] vec_cdb_phys_tag_out,
    output logic vec_lsq_out_valid,

    // 4. Commit Interface
    input commit_lsq, // From ROB/Commit: Retire the oldest load/store
    
    // 5. Dual Memory Interface
    // Read Port
    output logic [`XLEN-1:0] dmem_read_addr,
    output logic dmem_read_en,
    input [`XLEN-1:0] dmem_read_data,
    input dmem_read_valid,
    
    // Write Port
    output logic [`XLEN-1:0] dmem_write_addr,
    output logic [`XLEN-1:0] dmem_write_data,
    output logic dmem_write_en,
    input dmem_write_ready, // Handshake: memory is ready to accept the store
    output logic [3:0] dmem_be,
    
    // 6. Disambiguation (Speculative Load)
    output logic flush_pipeline, // Asserted if store-load ordering violation detected
    output logic [5:0] lsq_violation_tag, // PReg tag of the violating load
    
    // 7. Status (retained outputs for compatibility, logic internal)
    output load_blocked,
    output store_blocked
);

    // ========================================================================
    // Unified Queue Entry Structure
    // ========================================================================
    typedef struct packed {
        logic is_store;
        logic is_vector;            // Tracks if this is a VLE/VSE
        logic [`XLEN-1:0] address;   // Target address for load/store
        logic [(`DLEN-1):0] data;      // Data to store, or data loaded (128-bit)
        logic [31:0] vl;            // Vector Length (Number of elements)
        logic [31:0] vtype;         // Vector Type (Contains SEW)
        logic [`XLEN-1:0] stride;    // NEW: Byte stride between elements
        logic [5:0] phys_tag; // Physical tag
        logic [2:0] mem_size; // Size and sign-extension behavior
        logic addr_valid;     // Is address ready?
        logic data_valid;     // Is data ready?
        logic broadcasted;    // Has the tag been broadcast on CDB?
        logic valid;
        logic sent_to_mem; // Track if request sent to memory
        logic committed;   // Ready to retire/write to memory
    } lsq_entry_t;
    
    lsq_entry_t lsq [`LSQ_SIZE-1:0]; 
    
    logic [$clog2(`LSQ_SIZE)-1:0] head, tail, commit_ptr;
    logic [$clog2(`LSQ_SIZE)-1:0] next_tail;
    
    assign next_tail = tail + 1;
    
    // Output Allocation Tags (to Dispatch)
    assign alloc_tag = tail;
    assign lsq_full = lsq[tail].valid; // Bulletproof circular buffer full logic
    assign load_blocked = 1'b0; 
    assign store_blocked = 1'b0;
    
    // ========================================================================
    // Data Formatting Function (Sign/Zero Extension based on offset)
    // ========================================================================
    function logic [`XLEN-1:0] format_data(input [`XLEN-1:0] raw_data, input [2:0] size, input [1:0] offset);
        logic [7:0] b;
        logic [15:0] h;
        begin
            case (offset)
                2'b00: b = raw_data[7:0];
                2'b01: b = raw_data[15:8];
                2'b10: b = raw_data[23:16];
                2'b11: b = raw_data[31:24];
            endcase
            h = offset[1] ? raw_data[31:16] : raw_data[15:0];
            case (size)
                3'b000: format_data = {{24{b[7]}}, b}; // LB
                3'b100: format_data = {24'b0, b};      // LBU
                3'b001: format_data = {{16{h[15]}}, h};// LH
                3'b101: format_data = {16'b0, h};      // LHU
                default: format_data = raw_data;       // LW (3'b010)
            endcase
        end
    endfunction
    
    // ========================================================================
    // Vector Memory Subsystem Helper Functions
    // ========================================================================
    function logic [`XLEN-1:0] get_end_addr(input [`XLEN-1:0] start_addr, input is_vec, input [31:0] vl, input [31:0] vtype, input [2:0] size);
        logic [31:0] bytes_per_elem;
        begin
            if (is_vec) begin
                case (vtype[5:3]) // SEW
                    3'b000: bytes_per_elem = 1; // e8
                    3'b001: bytes_per_elem = 2; // e16
                    3'b010: bytes_per_elem = 4; // e32
                    3'b011: bytes_per_elem = 8; // e64
                    default: bytes_per_elem = 4;
                endcase
                get_end_addr = (vl == 0) ? start_addr : (start_addr + (vl * bytes_per_elem) - 1);
            end else begin
                case (size)
                    3'b000, 3'b100: get_end_addr = start_addr; // Byte
                    3'b001, 3'b101: get_end_addr = start_addr + 1; // Halfword
                    default: get_end_addr = start_addr + 3; // Word
                endcase
            end
        end
    endfunction
    
    function logic [7:0] get_total_words(input [31:0] vl, input [31:0] vtype);
        // Re-using the logic from above, total words = ceil((vl * bytes_per_elem) / 4)
        logic [`XLEN-1:0] end_offset;
        end_offset = get_end_addr(0, 1'b1, vl, vtype, 3'b000);
        get_total_words = 8'((end_offset >> 2) + 1); 
    endfunction
    
    function logic [`XLEN-1:0] get_stride(input [31:0] vtype);
        // Default unit-stride based on SEW
        begin
            case (vtype[5:3])
                3'b000: get_stride = 32'd1; // e8
                3'b001: get_stride = 32'd2; // e16
                3'b010: get_stride = 32'd4; // e32
                3'b011: get_stride = 32'd8; // e64
                default: get_stride = 32'd4;
            endcase
        end
    endfunction

    // ========================================================================
    // Load Request Selector (Scan from Head for Ready Loads) 
    // ========================================================================
    logic issue_load_ready;
    logic [`LSQ_TAG_WIDTH-1:0] issue_load_idx;
    logic issue_load_valid;
    logic [`LSQ_TAG_WIDTH-1:0] mem_inflight_idx;
    logic mem_inflight_valid;
    logic [`LSQ_TAG_WIDTH-1:0] ptr_load_select; 

    always @(*) begin
        issue_load_valid = 1'b0;
        issue_load_idx = 0;
        ptr_load_select = 0;

        // Scan from Head (Oldest) to Tail
        for (int i = 0; i < `LSQ_SIZE; i++) begin
            ptr_load_select = head + i[`LSQ_TAG_WIDTH-1:0];
            if (ptr_load_select == tail && !lsq_full) break; // Checked all younger entries
    
            // A load is ready to issue (no memory load response pending and address/data ready)
            issue_load_ready = lsq[ptr_load_select].valid && !lsq[ptr_load_select].is_store && lsq[ptr_load_select].addr_valid && 
                !lsq[ptr_load_select].data_valid && !lsq[ptr_load_select].sent_to_mem && !mem_inflight_valid;
            if (issue_load_ready) begin // prepare to issue it in the next cycle
                issue_load_idx = ptr_load_select; // record the ptr for tracking
                issue_load_valid = 1'b1; // mark that we have a load to issue in the next cycle
                break;
            end
        end
    end

    // ========================================================================
    // Disambiguation & Forwarding Logic 
    // (Word accesses (LW/SW) must have addresses ending in 00 (byte offset 0). Halfwords must end in 0)
    // ========================================================================
    logic [`XLEN-1:0] forwarded_data;
    logic forwarding_valid;
    logic [`XLEN-1:0] exe_end_addr;
    logic [`XLEN-1:0] ptr_end_addr;
    logic [`LSQ_TAG_WIDTH-1:0] ptr_disambiguation;
    logic [`LSQ_TAG_WIDTH-1:0] ptr_forwarding;

    always @(*) begin
        flush_pipeline = 1'b0;
        lsq_violation_tag = 6'b0;
        forwarding_valid = 1'b0;
        forwarded_data = 0;
        exe_end_addr = 0;
        ptr_disambiguation = 0;
        ptr_forwarding = 0;
        ptr_end_addr = 0;

        if (exe_store_valid) begin // Check at the moment we receive the calculated st address from execute stage
            // 1. DISAMBIGUATION: Range Overlap Check
            exe_end_addr = get_end_addr(exe_addr, lsq[exe_lsq_tag].is_vector, exe_vl, lsq[exe_lsq_tag].vtype, lsq[exe_lsq_tag].mem_size);
            for (int i = 1; i < `LSQ_SIZE; i++) begin
                ptr_disambiguation = exe_lsq_tag + i[`LSQ_TAG_WIDTH-1:0]; //check younger load entries
                if (ptr_disambiguation == tail && !lsq_full) break; // Checked all younger entries
                
                // check younger loads that has already calculated its address
                if (lsq[ptr_disambiguation].valid && !lsq[ptr_disambiguation].is_store && lsq[ptr_disambiguation].addr_valid) begin
                    ptr_end_addr = get_end_addr(lsq[ptr_disambiguation].address, lsq[ptr_disambiguation].is_vector, lsq[ptr_disambiguation].vl, lsq[ptr_disambiguation].vtype, lsq[ptr_disambiguation].mem_size);
                    if ((lsq[ptr_disambiguation].address <= exe_end_addr) && (ptr_end_addr >= exe_addr)) begin
                        flush_pipeline = 1'b1;
                        lsq_violation_tag = lsq[ptr_disambiguation].phys_tag; // mark the younger load as violation
                    end
                end
            end
        end 
        else if (exe_load_valid) begin // Check at the moment we receive the calculated ld address from execute stage
            // 2. FORWARDING AND RANGE CONFLICTS
            exe_end_addr = get_end_addr(exe_addr, lsq[exe_lsq_tag].is_vector, exe_vl, lsq[exe_lsq_tag].vtype, lsq[exe_lsq_tag].mem_size);
            if (exe_lsq_tag != head) begin // Check if older entries exist
                for (int i = 1; i < `LSQ_SIZE; i++) begin               
                    ptr_forwarding = exe_lsq_tag - i[`LSQ_TAG_WIDTH-1:0]; //check older entries
                    
                    // If it's an older store with valid address, check for Range Overlap
                    if (lsq[ptr_forwarding].valid && lsq[ptr_forwarding].is_store && lsq[ptr_forwarding].addr_valid) begin
                        ptr_end_addr = get_end_addr(lsq[ptr_forwarding].address, lsq[ptr_forwarding].is_vector, lsq[ptr_forwarding].vl, lsq[ptr_forwarding].vtype, lsq[ptr_forwarding].mem_size);
                        if ((lsq[ptr_forwarding].address <= exe_end_addr) && (ptr_end_addr >= exe_addr)) begin
                            // Only forward if both are identical, scalar, word-aligned accesses
                            if (!lsq[ptr_forwarding].is_vector && !lsq[exe_lsq_tag].is_vector && (lsq[ptr_forwarding].address == exe_addr) && (lsq[ptr_forwarding].mem_size == 3'b010)) begin 
                                forwarded_data = lsq[ptr_forwarding].data[`XLEN-1:0];
                                forwarding_valid = 1'b1; 
                            end 
                            else begin
                                flush_pipeline = 1'b1;
                                lsq_violation_tag = lsq[exe_lsq_tag].phys_tag;
                            end
                            break; // Stop searching older stores once we find the youngest overlapping one!
                        end
                    end
                    if (ptr_forwarding == head) break; // Checked all older entries
                end
            end
        end
    end
    
    // ========================================================================
    // State Updates (Allocation, Memory Return, Commit, Retirement)
    // ========================================================================
    logic [`LSQ_TAG_WIDTH-1:0] broadcast_idx;
    
    // Vector FSM Registers
    logic vec_load_active;
    logic [7:0] vec_load_word_idx;
    logic [7:0] vec_load_total_words;
    assign vec_load_total_words = get_total_words(lsq[mem_inflight_idx].vl, lsq[mem_inflight_idx].vtype);
    logic vec_store_active;
    logic [7:0] vec_store_word_idx;
    logic [7:0] vec_store_total_words;
    assign vec_store_total_words = get_total_words(lsq[head].vl, lsq[head].vtype);

    logic [`XLEN-1:0] read_addr;
    logic read_en;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (int i = 0; i < `LSQ_SIZE; i++) begin
                lsq[i].valid <= 1'b0;
            end
            head <= 0;
            tail <= 0;
            commit_ptr <= 0;
            mem_inflight_valid <= 1'b0;
            vec_load_active <= 1'b0;
            vec_load_word_idx <= 8'b0;
            vec_store_active <= 1'b0;
            vec_store_word_idx <= 8'b0;
        end else if (flush) begin
            // ONLY wipe speculative entries. Committed stores MUST drain to memory!
            for (int i = 0; i < `LSQ_SIZE; i++) begin
                if (!lsq[i].committed) begin
                    lsq[i].valid <= 1'b0;
                end
            end
            tail <= commit_ptr; // Roll back the allocation pointer safely
            mem_inflight_valid <= 1'b0;
            vec_load_active <= 1'b0;
            vec_load_word_idx <= 8'b0;
            // DO NOT reset head, commit_ptr, or the vec_store FSM.
        end else begin
            // 1. Allocation (Dispatch)
            if (alloc_req && !lsq_full) begin
                lsq[tail].valid <= 1'b1;
                lsq[tail].is_store <= alloc_is_store;
                lsq[tail].is_vector <= alloc_is_vector;
                lsq[tail].vl <= 32'b0;
                lsq[tail].vtype <= alloc_vtype; // Vtype is established at allocation
                lsq[tail].stride <= get_stride(alloc_vtype); // Default unit-stride. Will be overwritten by exe_data for vlse32.v
                lsq[tail].mem_size <= alloc_size; // Record data width at dispatch!
                lsq[tail].phys_tag <= dispatch_phys_tag;
                lsq[tail].addr_valid <= 1'b0;
                lsq[tail].data_valid <= 1'b0;
                lsq[tail].broadcasted <= 1'b0;
                lsq[tail].sent_to_mem <= 1'b0;
                lsq[tail].committed <= 1'b0;
                tail <= next_tail;
            end
            
            // 2. Obtaining target address from execute_stage
            if (exe_load_valid) begin // Load address calculation has finished
                lsq[exe_lsq_tag].address <= exe_addr; // Calculated load address
                lsq[exe_lsq_tag].addr_valid <= 1'b1; // Mark the address as valid
                lsq[exe_lsq_tag].vl <= exe_vl;
                
                if (exe_is_strided) begin
                    lsq[exe_lsq_tag].stride <= exe_data[`XLEN-1:0]; // Dynamically update the stride!
                end
                
                if (forwarding_valid) begin
                    lsq[exe_lsq_tag].data <= { {(`DLEN-`XLEN){1'b0}}, format_data(forwarded_data, lsq[exe_lsq_tag].mem_size , exe_addr[1:0]) };
                    lsq[exe_lsq_tag].data_valid <= 1'b1;
                end
                // else: wait for memory read request issue/response
                // Other fields remain unchanged
            end
            if (exe_store_valid) begin // Store address calculation has finished
                lsq[exe_lsq_tag].address <= exe_addr; // Calculated store address
                lsq[exe_lsq_tag].data <= exe_data; // Data to be stored to Memory
                lsq[exe_lsq_tag].addr_valid <= 1'b1; // Mark the address as valid
                lsq[exe_lsq_tag].vl <= exe_vl;
                lsq[exe_lsq_tag].data_valid <= 1'b1; // Mark the data as valid. 
                // The store can wake up in ROB now, but remains in LSQ until retired/committed by ROB and issued to memory
            end
            
            // 3. Issuing Load Memory Request FSM
            dmem_read_en <= 1'b0; // Default de-assert 
            if (issue_load_valid && !mem_inflight_valid) begin
                lsq[issue_load_idx].sent_to_mem <= 1'b1; // Mark sent so scanner skips it
                mem_inflight_idx <= issue_load_idx; // Record the idx of correponding lsq entry
                dmem_read_addr <= lsq[issue_load_idx].address; // Start with the first word address
                vec_load_word_idx <= 'd0;    
                mem_inflight_valid <= 1'b1; // Request for the first/next vector element     
                dmem_read_en <= 1'b1; // Pulled up for a cycle                                   
                if (lsq[issue_load_idx].is_vector) begin
                    vec_load_active <= 1'b1;
                end
            end
            
            // 4. Receiving Load Memory Response
            if (dmem_read_valid && mem_inflight_valid) begin 
                if (vec_load_active) begin // vector load response handling (data comes back one word at a time)
                    case (vec_load_word_idx)
                        8'd0: lsq[mem_inflight_idx].data[31:0]   <= dmem_read_data; // or format_data(...) 
                        8'd1: lsq[mem_inflight_idx].data[63:32]  <= dmem_read_data;
                        8'd2: lsq[mem_inflight_idx].data[95:64]  <= dmem_read_data;
                        8'd3: lsq[mem_inflight_idx].data[127:96] <= dmem_read_data;
                    endcase
                    
                    if (vec_load_word_idx == (vec_load_total_words - 1) || vec_load_word_idx == ((`DLEN/32) - 1)) begin
                        lsq[mem_inflight_idx].data_valid <= 1'b1; // This will prompt the change of issue_load_valid and issue_load_idx
                        vec_load_word_idx <= 'd0;
                        mem_inflight_valid <= 1'b0; 
                        vec_load_active <= 1'b0; // Entire vector request done
                    end 
                    else begin
                        vec_load_word_idx <= vec_load_word_idx + 'd1; // Advance to next element
                        dmem_read_addr <= lsq[mem_inflight_idx].address + ((vec_load_word_idx + 'd1) * lsq[mem_inflight_idx].stride);
                        dmem_read_en <= 1'b1;                                                
                    end
                end 
                else begin // scalar load response finishes in one beat
                    lsq[mem_inflight_idx].data <= { {(`DLEN-`XLEN){1'b0}}, format_data(dmem_read_data, lsq[mem_inflight_idx].mem_size, lsq[mem_inflight_idx].address[1:0]) };
                    lsq[mem_inflight_idx].data_valid <= 1'b1;
                    mem_inflight_valid <= 1'b0; // Scalar request done
                end
            end
            
            // 5. Commit Pointer Advance 
            if (commit_lsq && lsq[commit_ptr].valid) begin
                lsq[commit_ptr].committed <= 1'b1;
                commit_ptr <= commit_ptr + 1; // ptr < commit_ptr means committed
            end
            
            // 6. Memory Write & Queue Retirement (Popping Head)
            if (head != commit_ptr) begin // Head has been marked as committed
                if (!lsq[head].is_store) begin // Load at head can retire as soon as committed (broadcast happened before this, so ROB can assert commit)
                    lsq[head].valid <= 1'b0; // Free the entry
                    head <= head + 1; // Advance head pointer
                end else begin
                    if (lsq[head].is_vector) begin
                        if (!vec_store_active) begin
                            vec_store_active <= 1'b1; // Trigger vector store enable (below always block)
                            vec_store_word_idx <= 'd0;
                        end 
                        else if (dmem_write_ready) begin // Memory has consumed an element request
                            if (vec_store_word_idx == (vec_store_total_words - 1) || vec_store_word_idx == ((`DLEN/32) - 1)) begin
                                vec_store_active <= 1'b0; // Vector Store completely finished
                                lsq[head].valid <= 1'b0; // Retire head
                                head <= head + 1; // Advance head pointer
                            end 
                            else begin
                                vec_store_word_idx <= vec_store_word_idx + 'd1; // Advance to next 32-bit chunk
                            end
                        end
                    end 
                    else if (lsq[head].committed && dmem_write_ready) begin // Scalar store
                        lsq[head].valid <= 1'b0;
                        head <= head + 1;
                    end
                end
            end
            
            // 7. CDB Broadcast Acknowledgment
            // Mark the entry as broadcasted so the decoupled scanner moves to the next one.
            if (lsq_out_valid || (vec_lsq_out_valid)) begin
                lsq[broadcast_idx].broadcasted <= 1'b1;
            end
        end
    end
    
    // ========================================================================
    // Store Operation: Drive Memory Write Port
    // ========================================================================
    
    logic [1:0] byte_offset;
    assign byte_offset = lsq[head].address[1:0];
    
    // Generate Byte Enables and formatting store data
    always @(*) begin
        dmem_be = 4'b0000;
        dmem_write_data = 32'h0;
        dmem_write_addr = 32'h0;
        dmem_write_en = 1'b0;
        
        if (lsq[head].is_vector) begin
            dmem_write_addr = lsq[head].address + (vec_store_word_idx * lsq[head].stride);
            dmem_be = 4'b1111; // Vector accesses assumed word-aligned (full byte enable) for this FSM prototype
            dmem_write_en = lsq[head].is_store && lsq[head].committed && vec_store_active && dmem_write_ready; 

            case (vec_store_word_idx)
                8'd0: dmem_write_data = lsq[head].data[31:0];
                8'd1: dmem_write_data = lsq[head].data[63:32];
                8'd2: dmem_write_data = lsq[head].data[95:64];
                8'd3: dmem_write_data = lsq[head].data[127:96];
                default: dmem_write_data = 32'h0;
            endcase
            
        end 
        else begin
            dmem_write_addr = {lsq[head].address[`XLEN-1:2], 2'b00}; // Word-aligned memory bus
            dmem_write_en = lsq[head].is_store && lsq[head].committed && dmem_write_ready; // Pulled up only for a cycle
            if(lsq[head].mem_size == 3'b000) begin // SB (Store Byte)
                dmem_be = 4'b0001 << byte_offset; 
                dmem_write_data = {4{lsq[head].data[7:0]}}; // Replicate byte, dmem_be masks it
            end 
            else if(lsq[head].mem_size == 3'b001) begin // SH (Store Halfword)
                dmem_be = byte_offset[1] ? 4'b1100 : 4'b0011; // RISC-V specifies halfwords must be 2-byte aligned. byte_offset[0] is ignored.
                dmem_write_data = {2{lsq[head].data[15:0]}};
            end 
            else begin // SW (Store Word)
                dmem_be = 4'b1111;
                dmem_write_data = lsq[head].data[`XLEN-1:0];
            end
        end
    end

    // ========================================================================
    // CDB Interface: Decoupled Broadcast Scanner
    // ========================================================================
    logic [`LSQ_TAG_WIDTH-1:0] ptr_broadcast_select;

    always @(*) begin
        lsq_data_out = 0;
        lsq_out_valid = 1'b0;
        cdb_phys_tag_out = 0;
        vec_lsq_data_out = 0;
        vec_lsq_out_valid = 1'b0;
        vec_cdb_phys_tag_out = 0;
        broadcast_idx = 0;
        ptr_broadcast_select = 0;

        // Scan from Head to Tail for oldest un-broadcasted ready entry
        for (int i = 0; i < `LSQ_SIZE; i++) begin
            ptr_broadcast_select = head + i[`LSQ_TAG_WIDTH-1:0];
            if (ptr_broadcast_select == tail && !lsq_full) break;
            // An entry is ready to broadcast when:
            // - A load has its data ready from memory.
            // - A store has its address ready from the AGU.
            if (lsq[ptr_broadcast_select].valid && !lsq[ptr_broadcast_select].broadcasted) begin
                if ((!lsq[ptr_broadcast_select].is_store && lsq[ptr_broadcast_select].data_valid) || 
                    (lsq[ptr_broadcast_select].is_store && lsq[ptr_broadcast_select].addr_valid)) begin
                    
                    if (lsq[ptr_broadcast_select].is_vector) begin // Vector Load AND Store -> Vector CDB
                        vec_lsq_out_valid = 1'b1;
                        vec_cdb_phys_tag_out = lsq[ptr_broadcast_select].phys_tag;
                        vec_lsq_data_out = lsq[ptr_broadcast_select].data;
                    end else begin // Scalar Load or Scalar Store -> Scalar CDB
                        lsq_out_valid = 1'b1;
                        cdb_phys_tag_out = lsq[ptr_broadcast_select].phys_tag;
                        lsq_data_out = lsq[ptr_broadcast_select].data[`XLEN-1:0]; // Truncate for scalar bus
                    end
                    broadcast_idx = ptr_broadcast_select; // Record the idx for acknowledgment in the next cycle
                    break;
                end
            end
        end
    end

endmodule
