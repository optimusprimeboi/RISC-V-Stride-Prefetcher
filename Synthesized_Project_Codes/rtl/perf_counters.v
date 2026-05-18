//============================================================================
// Performance Counters — Hardware counters for cache/prefetch analysis
//============================================================================
`timescale 1ns / 1ps

module perf_counters (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        clear,          // Clear all counters

    // Event inputs
    input  wire        evt_cache_hit,
    input  wire        evt_cache_miss,
    input  wire        evt_pf_hit,      // Demand hit on prefetched line
    input  wire        evt_pf_issued,   // Prefetch request issued
    input  wire        evt_pf_pollution,// Useful line evicted by prefetch
    input  wire        evt_instr_valid, // Instruction retired
    input  wire        dmem_stall,      // Pipeline stalled

    // Counter outputs (directly readable)
    output reg [31:0] cnt_cycles,
    output reg [31:0] cnt_instrs,
    output reg [31:0] cnt_cache_hits,
    output reg [31:0] cnt_cache_misses,
    output reg [31:0] cnt_pf_hits,
    output reg [31:0] cnt_pf_issued,
    output reg [31:0] cnt_pf_pollution,
    output reg [31:0] cnt_stall_cycles
);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n || clear) begin
            cnt_cycles       <= 32'd0;
            cnt_instrs       <= 32'd0;
            cnt_cache_hits   <= 32'd0;
            cnt_cache_misses <= 32'd0;
            cnt_pf_hits      <= 32'd0;
            cnt_pf_issued    <= 32'd0;
            cnt_pf_pollution <= 32'd0;
            cnt_stall_cycles <= 32'd0;
        end else begin
            cnt_cycles <= cnt_cycles + 32'd1;
            if (evt_instr_valid)  cnt_instrs       <= cnt_instrs + 32'd1;
            if (evt_cache_hit)    cnt_cache_hits    <= cnt_cache_hits + 32'd1;
            if (evt_cache_miss)   cnt_cache_misses  <= cnt_cache_misses + 32'd1;
            if (evt_pf_hit)       cnt_pf_hits       <= cnt_pf_hits + 32'd1;
            if (evt_pf_issued)    cnt_pf_issued     <= cnt_pf_issued + 32'd1;
            if (evt_pf_pollution) cnt_pf_pollution  <= cnt_pf_pollution + 32'd1;
            if (dmem_stall)       cnt_stall_cycles  <= cnt_stall_cycles + 32'd1;
        end
    end

endmodule
