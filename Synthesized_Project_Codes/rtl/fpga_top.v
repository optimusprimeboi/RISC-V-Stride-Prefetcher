//============================================================================
// FPGA Wrapper — Maps riscv_top to Zybo Z7-10 physical pins
// Includes clock divider for manageable clock speed
//============================================================================
`timescale 1ns / 1ps

module fpga_top (
    input  wire       clk,      // 125 MHz board clock
    input  wire       rst_n,    // BTN0 (active-low)
    input  wire [3:0] sw,       // Slide switches
    output wire [3:0] led       // LEDs
);

    // =========================================================================
    // Clock divider: 125MHz → ~50MHz (divide by 2 + MMCM if needed)
    // For simplicity, use a simple toggle divider
    // =========================================================================
    reg clk_div;
    always @(posedge clk) begin
        clk_div <= ~clk_div;
    end

    wire sys_clk = clk_div;  // ~62.5 MHz

    // =========================================================================
    // Synchronize reset
    // =========================================================================
    reg [2:0] rst_sync;
    wire rst_n_sync = rst_sync[2];

    always @(posedge sys_clk or negedge rst_n) begin
        if (!rst_n)
            rst_sync <= 3'b000;
        else
            rst_sync <= {rst_sync[1:0], 1'b1};
    end

    // =========================================================================
    // Pulse Stretchers (Makes 16ns pulses visible to the human eye ~50ms)
    // =========================================================================
    reg [21:0] hit_stretch, pf_stretch;
    (* mark_debug = "true" *) wire evt_hit_w;
    (* mark_debug = "true" *) wire evt_pf_w;

    always @(posedge sys_clk or negedge rst_n_sync) begin
        if (!rst_n_sync) begin
            hit_stretch <= 22'd0;
            pf_stretch  <= 22'd0;
        end else begin
            if (evt_hit_w) hit_stretch <= 22'h3FFFFF;
            else if (hit_stretch > 0) hit_stretch <= hit_stretch - 1;

            if (evt_pf_w)  pf_stretch <= 22'h3FFFFF;
            else if (pf_stretch > 0)  pf_stretch <= pf_stretch - 1;
        end
    end

    // =========================================================================
    // LED Status
    // LED 0: Cache Enabled (Switch 0)
    // LED 1: Prefetch Enabled (Switch 1)
    // LED 2: Cache Hit "Heartbeat" (Flashes when hitting)
    // LED 3: Prefetch "Heartbeat"  (Flashes when prefetching)
    // =========================================================================
    assign led[0] = sw[0];
    assign led[1] = sw[1];
    assign led[2] = (hit_stretch > 0);
    assign led[3] = (pf_stretch > 0);

    // =========================================================================
    // RISC-V System
    // =========================================================================
    (* mark_debug = "true" *) wire [31:0] dbg_pc;
    wire [31:0] cnt_cycles, cnt_instrs;
    wire [31:0] cnt_cache_hits, cnt_cache_misses;
    wire [31:0] cnt_pf_hits, cnt_pf_issued, cnt_pf_pollution;
    wire [31:0] cnt_stall_cycles;

    riscv_top #(
        .IMEM_INIT  ("C:/Users/Lenovo/.gemini/antigravity/scratch/P14_Stride_Prefetcher/test_programs/program.mem"),
        .DMEM_INIT  ("C:/Users/Lenovo/.gemini/antigravity/scratch/P14_Stride_Prefetcher/test_programs/data.mem"),
        .MEM_LATENCY(10),
        .IMEM_DEPTH (1024),
        .DMEM_DEPTH (4096)
    ) u_system (
        .clk             (sys_clk),
        .rst_n           (rst_n_sync),
        .cache_enable    (sw[0]),
        .prefetch_enable (sw[1]),
        .dbg_pc          (dbg_pc),
        .cnt_cycles      (cnt_cycles),
        .cnt_instrs      (cnt_instrs),
        .cnt_cache_hits  (cnt_cache_hits),
        .cnt_cache_misses(cnt_cache_misses),
        .cnt_pf_hits     (cnt_pf_hits),
        .cnt_pf_issued   (cnt_pf_issued),
        .cnt_pf_pollution(cnt_pf_pollution),
        .cnt_stall_cycles(cnt_stall_cycles),
        .evt_hit         (evt_hit_w),
        .evt_pf_issued   (evt_pf_w)
    );

endmodule
