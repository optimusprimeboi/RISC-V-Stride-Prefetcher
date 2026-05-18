//============================================================================
// Stride-Based Hardware Prefetcher (Chen-Baer RPT Design)
// 
// Reference Prediction Table (RPT) with 8 entries:
//   - Direct-mapped by PC[4:2] for O(1) lookup (no CAM)
//   - Tracks last address, stride, and confidence state
//   - Issues prefetch requests 2 strides ahead when confident
//
// State machine per entry:
//   INIT → TRANSIENT → STEADY (prefetch active)
//   Mismatch from STEADY → back to INIT
//============================================================================
`timescale 1ns / 1ps

module stride_prefetcher #(
    parameter NUM_ENTRIES  = 8,
    parameter ADDR_MAX     = 32'h0000_FFFF  // Valid address range
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire        enable,         // Prefetcher enable

    // Cache load notification (from L1 cache)
    input  wire        load_valid,     // A cache read occurred
    input  wire [31:0] load_pc,        // PC of the load instruction
    input  wire [31:0] load_addr,      // Address being loaded

    // Main memory interface for prefetch
    output reg  [31:0] pf_mem_addr,    // Prefetch memory address
    output reg         pf_mem_re,      // Prefetch read request
    input  wire [127:0] pf_mem_rdata,  // Memory read data
    input  wire        pf_mem_ready,   // Memory response valid

    // Prefetch fill to cache
    output reg         pf_fill_valid,  // Fill cache with prefetched data
    output reg  [31:0] pf_fill_addr,   // Address of prefetched line
    output reg [127:0] pf_fill_data,   // Prefetched cache line data

    // Performance counters
    output reg         evt_pf_issued   // Prefetch request issued
);

    // =========================================================================
    // RPT Entry Definition
    // =========================================================================
    // State encoding
    localparam ST_INIT      = 2'b00;
    localparam ST_TRANSIENT = 2'b01;
    localparam ST_STEADY    = 2'b10;

    localparam IDX_BITS = $clog2(NUM_ENTRIES);

    reg        rpt_valid     [0:NUM_ENTRIES-1];
    reg [31:0] rpt_pc        [0:NUM_ENTRIES-1];  // Tag: PC of load instr
    reg [31:0] rpt_prev_addr [0:NUM_ENTRIES-1];  // Last miss address
    reg [31:0] rpt_stride    [0:NUM_ENTRIES-1];  // Detected stride
    reg [1:0]  rpt_state     [0:NUM_ENTRIES-1];  // Confidence state

    // =========================================================================
    // Direct-mapped index from PC (no CAM search needed)
    // =========================================================================
    wire [IDX_BITS-1:0] pc_index = load_pc[IDX_BITS+1:2]; // PC[4:2] for 8 entries

    // =========================================================================
    // Prefetcher FSM
    // =========================================================================
    localparam PF_IDLE       = 3'd0;
    localparam PF_LOOKUP     = 3'd1;
    localparam PF_UPDATE     = 3'd2;
    localparam PF_REQUEST    = 3'd3;
    localparam PF_WAIT       = 3'd4;
    localparam PF_FILL       = 3'd5;

    reg [2:0]  pf_state;
    reg [31:0] pending_pc;
    reg [31:0] pending_addr;
    reg [31:0] prefetch_addr;
    reg [IDX_BITS-1:0] pending_idx;  // Direct-mapped index
    reg        found_entry;

    integer i;

    // =========================================================================
    // RPT Lookup — Direct-mapped (combinational, single entry check)
    // =========================================================================
    wire lookup_hit = rpt_valid[pending_idx] && (rpt_pc[pending_idx] == pending_pc);

    // =========================================================================
    // Main FSM
    // =========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            pf_state      <= PF_IDLE;
            pf_mem_re     <= 1'b0;
            pf_mem_addr   <= 32'd0;
            pf_fill_valid <= 1'b0;
            pf_fill_addr  <= 32'd0;
            pf_fill_data  <= 128'd0;
            evt_pf_issued <= 1'b0;
            pending_pc    <= 32'd0;
            pending_addr  <= 32'd0;
            prefetch_addr <= 32'd0;
            pending_idx   <= {IDX_BITS{1'b0}};
            for (i = 0; i < NUM_ENTRIES; i = i + 1) begin
                rpt_valid[i]     <= 1'b0;
                rpt_pc[i]        <= 32'd0;
                rpt_prev_addr[i] <= 32'd0;
                rpt_stride[i]    <= 32'd0;
                rpt_state[i]     <= ST_INIT;
            end
        end else begin
            // Default: clear single-cycle signals
            evt_pf_issued <= 1'b0;
            pf_fill_valid <= 1'b0;
            // NOTE: pf_mem_re is cleared explicitly per-state, not here,
            // so PF_WAIT can hold it high without a default conflict.

            if (!enable) begin
                pf_state <= PF_IDLE;
            end else begin
                case (pf_state)
                    // ---------------------------------------------------------
                    PF_IDLE: begin
                        pf_mem_re <= 1'b0; // Ensure cleared when idle
                        if (load_valid) begin
                            pending_pc   <= load_pc;
                            pending_addr <= {load_addr[31:4], 4'b0000}; // Block-aligned
                            pending_idx  <= pc_index; // Latch the direct-mapped index
                            pf_state     <= PF_LOOKUP;
                        end
                    end

                    // ---------------------------------------------------------
                    PF_LOOKUP: begin
                        found_entry <= lookup_hit;
                        pf_state    <= PF_UPDATE;
                    end

                    // ---------------------------------------------------------
                    PF_UPDATE: begin
                        if (found_entry) begin
                            if (pending_addr == rpt_prev_addr[pending_idx]) begin
                                // Access to the same block — ignore to prevent event thrashing
                                pf_state <= PF_IDLE;
                            end else begin
                                if (rpt_state[pending_idx] == ST_INIT) begin
                                    rpt_stride[pending_idx]    <= pending_addr - rpt_prev_addr[pending_idx];
                                    rpt_prev_addr[pending_idx] <= pending_addr;
                                    rpt_state[pending_idx]     <= ST_TRANSIENT;
                                    prefetch_addr <= pending_addr + ((pending_addr - rpt_prev_addr[pending_idx]) << 1);
                                    pf_state      <= PF_REQUEST;
                                end else if (rpt_state[pending_idx] == ST_TRANSIENT) begin
                                    if ((pending_addr - rpt_prev_addr[pending_idx]) == rpt_stride[pending_idx]) begin
                                        rpt_prev_addr[pending_idx] <= pending_addr;
                                        rpt_state[pending_idx]     <= ST_STEADY;
                                        prefetch_addr <= pending_addr + (rpt_stride[pending_idx] << 1);
                                        pf_state <= PF_REQUEST;
                                    end else begin
                                        rpt_stride[pending_idx]    <= pending_addr - rpt_prev_addr[pending_idx];
                                        rpt_prev_addr[pending_idx] <= pending_addr;
                                        rpt_state[pending_idx]     <= ST_TRANSIENT;
                                        pf_state <= PF_IDLE;
                                    end
                                end else begin // ST_STEADY
                                    if ((pending_addr - rpt_prev_addr[pending_idx]) == rpt_stride[pending_idx]) begin
                                        rpt_prev_addr[pending_idx] <= pending_addr;
                                        prefetch_addr <= pending_addr + (rpt_stride[pending_idx] << 1);
                                        pf_state <= PF_REQUEST;
                                    end else begin
                                        rpt_stride[pending_idx]    <= pending_addr - rpt_prev_addr[pending_idx];
                                        rpt_prev_addr[pending_idx] <= pending_addr;
                                        rpt_state[pending_idx]     <= ST_INIT;
                                        pf_state <= PF_IDLE;
                                    end
                                end
                            end
                        end else begin
                            // New entry — direct-mapped, just overwrite the slot
                            rpt_valid[pending_idx]     <= 1'b1;
                            rpt_pc[pending_idx]        <= pending_pc;
                            rpt_prev_addr[pending_idx] <= pending_addr;
                            rpt_stride[pending_idx]    <= 32'd0;
                            rpt_state[pending_idx]     <= ST_INIT;
                            pf_state <= PF_IDLE;
                        end
                    end

                    // ---------------------------------------------------------
                    PF_REQUEST: begin
                        // Validate prefetch address
                        if (prefetch_addr < ADDR_MAX && prefetch_addr[1:0] == 2'b00) begin
                            pf_mem_addr   <= {prefetch_addr[31:4], 4'b0000}; // line-aligned
                            pf_mem_re     <= 1'b1;
                            evt_pf_issued <= 1'b1;
                            pf_state      <= PF_WAIT;
                        end else begin
                            // Invalid address — skip prefetch
                            pf_state <= PF_IDLE;
                        end
                    end

                    // ---------------------------------------------------------
                    PF_WAIT: begin
                        // pf_mem_re stays high (set in PF_REQUEST, not cleared by default)
                        if (pf_mem_ready) begin
                            pf_mem_re     <= 1'b0;
                            pf_fill_valid <= 1'b1;
                            pf_fill_addr  <= pf_mem_addr; // Use latched address, not prefetch_addr
                            pf_fill_data  <= pf_mem_rdata;
                            pf_state      <= PF_FILL;
                        end
                    end

                    // ---------------------------------------------------------
                    PF_FILL: begin
                        // Fill was presented to cache for one cycle
                        pf_fill_valid <= 1'b0;
                        pf_state      <= PF_IDLE;
                    end

                    default: pf_state <= PF_IDLE;
                endcase
            end
        end
    end

endmodule
