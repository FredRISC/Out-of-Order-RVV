// ============================================================================
// load_store_queue.sv - Load-Store Queue with Memory Hazard Detection
// ============================================================================
// Implements load/store queues with address hazard detection (WAR, RAW, WAW)
// and store-to-load forwarding.

`include "../riscv_header.sv"

module load_store_queue #(
    parameter LSQ_LQ_SIZE = 8,
    parameter LSQ_SQ_SIZE = 8,
    parameter XLEN = 32
) (
    input clk,
    input rst_n,
    input flush,
    
    // Load interface
    input [XLEN-1:0] load_addr,
    input load_valid,
    output [XLEN-1:0] load_data,
    output load_data_valid,
    output load_blocked,
    
    // Store interface
    input [XLEN-1:0] store_addr,
    input [XLEN-1:0] store_data,
    input store_valid,
    output store_blocked,
    
    // Memory interface
    output [XLEN-1:0] dmem_addr,
    output [XLEN-1:0] dmem_write_data,
    output dmem_we,
    input [XLEN-1:0] dmem_read_data,
    input dmem_valid,
    
    // Status
    output lsq_lq_full,
    output lsq_sq_full
);

    // ========================================================================
    // Load Queue Entry
    // ========================================================================
    
    typedef struct packed {
        logic [XLEN-1:0] address;
        logic [XLEN-1:0] data;
        logic valid;
        logic complete;
        logic forwarded;
    } lq_entry_t;
    
    // ========================================================================
    // Store Queue Entry
    // ========================================================================
    
    typedef struct packed {
        logic [XLEN-1:0] address;
        logic [XLEN-1:0] data;
        logic valid;
        logic complete;
        logic [2:0] index;  // Position in queue
    } sq_entry_t;
    
    lq_entry_t [LSQ_LQ_SIZE-1:0] load_queue;
    sq_entry_t [LSQ_SQ_SIZE-1:0] store_queue;
    
    logic [$clog2(LSQ_LQ_SIZE)-1:0] lq_head, lq_tail;
    logic [$clog2(LSQ_SQ_SIZE)-1:0] sq_head, sq_tail;
    
    // ========================================================================
    // Address Hazard Detection
    // ========================================================================
    
    logic [XLEN-1:0] forwarded_data;
    logic forwarding_valid;
    
    always @(*) begin
        forwarding_valid = 1'b0;
        forwarded_data = 0;
        
        // Check if load address matches any pending store (store-to-load forwarding)
        for (int i = 0; i < LSQ_SQ_SIZE; i++) begin
            if (store_queue[i].valid && (store_queue[i].address == load_addr)) begin
                // Found matching store - forward data
                forwarded_data = store_queue[i].data;
                forwarding_valid = 1'b1;
            end
        end
    end
    
    assign load_data = forwarding_valid ? forwarded_data : dmem_read_data;
    assign load_data_valid = forwarding_valid || dmem_valid;
    
    // ========================================================================
    // WAR Detection: Store waits if younger than unexecuted load
    // ========================================================================
    
    logic store_war_blocked;
    always @(*) begin
        store_war_blocked = 1'b0;
        
        // Check if any load to same address hasn't executed yet
        for (int i = 0; i < LSQ_LQ_SIZE; i++) begin
            if (load_queue[i].valid && !load_queue[i].complete) begin
                if (load_queue[i].address == store_addr) begin
                    store_war_blocked = 1'b1;
                end
            end
        end
    end
    
    // ========================================================================
    // RAW Detection: Load waits for older store to same address
    // ========================================================================
    
    logic load_raw_blocked;
    always @(*) begin
        load_raw_blocked = 1'b0;
        
        // Check if any older store to same address hasn't completed
        for (int i = 0; i < LSQ_SQ_SIZE; i++) begin
            if (store_queue[i].valid && !store_queue[i].complete) begin
                if (store_queue[i].address == load_addr) begin
                    load_raw_blocked = 1'b1;
                end
            end
        end
    end
    
    // ========================================================================
    // WAW Detection: Younger store waits for older store to same address
    // ========================================================================
    
    logic store_waw_blocked;
    always @(*) begin
        store_waw_blocked = 1'b0;
        
        // Check if any older store to same address hasn't completed
        for (int i = 0; i < LSQ_SQ_SIZE; i++) begin
            if (store_queue[i].valid && !store_queue[i].complete) begin
                if (store_queue[i].address == store_addr) begin
                    store_waw_blocked = 1'b1;
                end
            end
        end
    end
    
    // ========================================================================
    // Queue Management
    // ========================================================================
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (int i = 0; i < LSQ_LQ_SIZE; i++)
                load_queue[i].valid <= 1'b0;
            for (int i = 0; i < LSQ_SQ_SIZE; i++)
                store_queue[i].valid <= 1'b0;
            lq_head <= 0;
            lq_tail <= 0;
            sq_head <= 0;
            sq_tail <= 0;
        end else if (flush) begin
            for (int i = 0; i < LSQ_LQ_SIZE; i++)
                load_queue[i].valid <= 1'b0;
            for (int i = 0; i < LSQ_SQ_SIZE; i++)
                store_queue[i].valid <= 1'b0;
        end else begin
            // Allocate load queue entry
            if (load_valid && !lsq_lq_full && !load_raw_blocked) begin
                load_queue[lq_tail].address <= load_addr;
                load_queue[lq_tail].valid <= 1'b1;
                load_queue[lq_tail].complete <= 1'b0;
                load_queue[lq_tail].forwarded <= forwarding_valid;
                lq_tail <= lq_tail + 1;
            end
            
            // Allocate store queue entry
            if (store_valid && !lsq_sq_full && !store_war_blocked && !store_waw_blocked) begin
                store_queue[sq_tail].address <= store_addr;
                store_queue[sq_tail].data <= store_data;
                store_queue[sq_tail].valid <= 1'b1;
                store_queue[sq_tail].complete <= 1'b0;
                sq_tail <= sq_tail + 1;
            end
            
            // Mark load as complete
            if (dmem_valid && load_valid) begin
                load_queue[lq_head].complete <= 1'b1;
            end
            
            // Retire load
            if (load_queue[lq_head].complete) begin
                load_queue[lq_head].valid <= 1'b0;
                lq_head <= lq_head + 1;
            end
            
            // Retire store
            if (store_queue[sq_head].complete) begin
                store_queue[sq_head].valid <= 1'b0;
                sq_head <= sq_head + 1;
            end
        end
    end
    
    // ========================================================================
    // Memory Access
    // ========================================================================
    
    assign dmem_addr = (load_valid && !load_raw_blocked) ? load_addr : store_addr;
    assign dmem_write_data = store_queue[sq_head].data;
    assign dmem_we = (store_valid && !store_war_blocked && !store_waw_blocked);
    
    // ========================================================================
    // Status Signals
    // ========================================================================
    
    assign lsq_lq_full = (lq_tail + 1 == lq_head);
    assign lsq_sq_full = (sq_tail + 1 == sq_head);
    assign load_blocked = load_raw_blocked;
    assign store_blocked = store_war_blocked || store_waw_blocked;

endmodule
