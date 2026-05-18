//============================================================================
// RISC-V Top Module — Integrates RV32I Core + L1 Cache + Stride Prefetcher
// Target: Zybo Z7-10 (XC7Z010-1CLG400C)
//============================================================================
`timescale 1ns / 1ps

module riscv_top #(
    parameter IMEM_INIT  = "program.mem",
    parameter DMEM_INIT  = "data.mem",
    parameter MEM_LATENCY = 10,
    parameter IMEM_DEPTH  = 1024,
    parameter DMEM_DEPTH  = 4096
)(
    input  wire        clk,
    input  wire        rst_n,

    // Configuration inputs (directly controlled or from switches)
    input  wire        cache_enable,     // Enable L1 cache (sw[0])
    input  wire        prefetch_enable,  // Enable prefetcher (sw[1])

    // Debug / performance counter outputs
    output wire [31:0] dbg_pc,
    output wire [31:0] cnt_cycles,
    output wire [31:0] cnt_instrs,
    output wire [31:0] cnt_cache_hits,
    output wire [31:0] cnt_cache_misses,
    output wire [31:0] cnt_pf_hits,
    output wire [31:0] cnt_pf_issued,
    output wire [31:0] cnt_pf_pollution,
    output wire [31:0] cnt_stall_cycles,
    
    // Pulse outputs for heartbeat LEDs
    output wire        evt_hit,
    output wire        evt_pf_issued
);

    // =========================================================================
    // Internal wires
    // =========================================================================

    // Instruction memory
    wire [31:0] imem_addr, imem_rdata;

    // Core ↔ Cache
    wire [31:0] cpu_dmem_addr, cpu_dmem_wdata, cpu_dmem_rdata;
    wire        cpu_dmem_we, cpu_dmem_re;
    wire [2:0]  cpu_dmem_funct3;
    wire [31:0] cpu_dmem_pc;
    wire        cpu_dmem_stall;
    wire        instr_valid;

    // Cache ↔ Main Memory (demand path)
    wire [31:0]  cache_mem_addr;
    wire         cache_mem_re, cache_mem_we;
    wire [31:0]  cache_mem_wdata;
    wire [1:0]   cache_mem_wsize;
    wire [127:0] cache_mem_rdata;
    wire         cache_mem_ready;

    // Cache events (internal wires; routed out via evt_hit / evt_pf_issued ports)
    wire int_evt_hit, evt_miss, evt_pf_hit, evt_pf_pollution;
    wire [31:0] evt_miss_addr, evt_miss_pc;
    wire evt_load;
    wire [31:0] evt_load_addr, evt_load_pc;

    // Prefetcher ↔ Main Memory
    wire [31:0]  pf_mem_addr;
    wire         pf_mem_re;
    wire [127:0] pf_mem_rdata;
    wire         pf_mem_ready;

    wire         pf_fill_valid;
    wire [31:0]  pf_fill_addr;
    wire [127:0] pf_fill_data;
    wire         int_evt_pf_issued;

    // Route internal events to output ports
    assign evt_hit       = int_evt_hit;
    assign evt_pf_issued = int_evt_pf_issued;

    // =========================================================================
    // Memory Arbiter - Registered, demand has absolute priority
    // Latches requests cleanly to prevent 1-cycle race on bus handoff
    // =========================================================================
    reg  [31:0]  arb_mem_addr;
    reg          arb_mem_re;
    reg          arb_mem_we;
    reg  [31:0]  arb_mem_wdata;
    reg  [1:0]   arb_mem_wsize;
    wire [127:0] arb_mem_rdata;
    wire         arb_mem_ready;

    localparam ARB_IDLE     = 2'd0;
    localparam ARB_DEMAND   = 2'd1;
    localparam ARB_PREFETCH = 2'd2;
    reg [1:0] arb_state;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            arb_state     <= ARB_IDLE;
            arb_mem_re    <= 1'b0;
            arb_mem_we    <= 1'b0;
            arb_mem_addr  <= 32'd0;
            arb_mem_wdata <= 32'd0;
            arb_mem_wsize <= 2'b10;
        end else begin
            case (arb_state)
                ARB_IDLE: begin
                    arb_mem_re <= 1'b0;
                    arb_mem_we <= 1'b0;
                    if (cache_mem_re || cache_mem_we) begin
                        arb_state     <= ARB_DEMAND;
                        arb_mem_addr  <= cache_mem_addr;
                        arb_mem_re    <= cache_mem_re;
                        arb_mem_we    <= cache_mem_we;
                        arb_mem_wdata <= cache_mem_wdata;
                        arb_mem_wsize <= cache_mem_wsize;
                    end else if (pf_mem_re) begin
                        arb_state     <= ARB_PREFETCH;
                        arb_mem_addr  <= pf_mem_addr;
                        arb_mem_re    <= 1'b1;
                        arb_mem_we    <= 1'b0;
                        arb_mem_wdata <= 32'd0;
                        arb_mem_wsize <= 2'b10;
                    end
                end
                ARB_DEMAND: begin
                    // Hold signals (cache also holds mem_re high)
                    arb_mem_addr  <= cache_mem_addr;
                    arb_mem_re    <= cache_mem_re;
                    arb_mem_we    <= cache_mem_we;
                    arb_mem_wdata <= cache_mem_wdata;
                    arb_mem_wsize <= cache_mem_wsize;
                    if (arb_mem_ready) begin
                        arb_state  <= ARB_IDLE;
                        arb_mem_re <= 1'b0;
                        arb_mem_we <= 1'b0;
                    end
                end
                ARB_PREFETCH: begin
                    // Cannot preempt mid-transaction because main_memory does not support abort.
                    // Must wait for prefetch to finish before granting bus to demand.
                    if (arb_mem_ready) begin
                        arb_state  <= ARB_IDLE;
                        arb_mem_re <= 1'b0;
                        arb_mem_we <= 1'b0;
                    end
                end
                default: arb_state <= ARB_IDLE;
            endcase
        end
    end

    // Route memory response to the correct requester
    assign cache_mem_rdata = arb_mem_rdata;
    assign cache_mem_ready = arb_mem_ready && (arb_state == ARB_DEMAND);
    assign pf_mem_rdata    = arb_mem_rdata;
    assign pf_mem_ready    = arb_mem_ready && (arb_state == ARB_PREFETCH);


    // =========================================================================
    // Module Instantiations
    // =========================================================================

    // Instruction Memory
    instruction_memory #(
        .DEPTH    (IMEM_DEPTH),
        .INIT_FILE(IMEM_INIT)
    ) u_imem (
        .addr (imem_addr),
        .rdata(imem_rdata)
    );

    // RV32I Core
    rv32i_core u_core (
        .clk        (clk),
        .rst_n      (rst_n),
        .imem_addr  (imem_addr),
        .imem_rdata (imem_rdata),
        .dmem_addr  (cpu_dmem_addr),
        .dmem_wdata (cpu_dmem_wdata),
        .dmem_we    (cpu_dmem_we),
        .dmem_re    (cpu_dmem_re),
        .dmem_funct3(cpu_dmem_funct3),
        .dmem_pc    (cpu_dmem_pc),
        .dmem_rdata (cpu_dmem_rdata),
        .dmem_stall (cpu_dmem_stall),
        .instr_valid(instr_valid),
        .pc_out     (dbg_pc)
    );

    // L1 Data Cache
    l1_data_cache u_cache (
        .clk           (clk),
        .rst_n         (rst_n),
        .enable        (cache_enable),
        .cpu_addr      (cpu_dmem_addr),
        .cpu_wdata     (cpu_dmem_wdata),
        .cpu_we        (cpu_dmem_we),
        .cpu_re        (cpu_dmem_re),
        .cpu_funct3    (cpu_dmem_funct3),
        .cpu_rdata     (cpu_dmem_rdata),
        .cpu_stall     (cpu_dmem_stall),
        .mem_addr      (cache_mem_addr),
        .mem_re        (cache_mem_re),
        .mem_we        (cache_mem_we),
        .mem_wdata     (cache_mem_wdata),
        .mem_wsize     (cache_mem_wsize),
        .mem_rdata     (cache_mem_rdata),
        .mem_ready     (cache_mem_ready),
        .pf_fill_valid (pf_fill_valid),
        .pf_fill_addr  (pf_fill_addr),
        .pf_fill_data  (pf_fill_data),
        .cpu_pc        (cpu_dmem_pc),
        .evt_hit       (int_evt_hit),
        .evt_miss      (evt_miss),
        .evt_miss_addr (evt_miss_addr),
        .evt_miss_pc   (evt_miss_pc),
        .evt_pf_hit    (evt_pf_hit),
        .evt_pf_pollution(evt_pf_pollution),
        .evt_load      (evt_load),
        .evt_load_addr (evt_load_addr),
        .evt_load_pc   (evt_load_pc)
    );

    // Stride Prefetcher
    stride_prefetcher #(
        .NUM_ENTRIES(8),
        .ADDR_MAX   (32'h0000_FFFF)
    ) u_prefetcher (
        .clk          (clk),
        .rst_n        (rst_n),
        .enable       (prefetch_enable),
        .load_valid   (evt_load),
        .load_pc      (evt_load_pc),
        .load_addr    (evt_load_addr),
        .pf_mem_addr  (pf_mem_addr),
        .pf_mem_re    (pf_mem_re),
        .pf_mem_rdata (pf_mem_rdata),
        .pf_mem_ready (pf_mem_ready),
        .pf_fill_valid(pf_fill_valid),
        .pf_fill_addr (pf_fill_addr),
        .pf_fill_data (pf_fill_data),
        .evt_pf_issued(int_evt_pf_issued)
    );

    // Main Data Memory
    main_memory #(
        .DEPTH   (DMEM_DEPTH),
        .LATENCY (MEM_LATENCY),
        .INIT_FILE(DMEM_INIT)
    ) u_dmem (
        .clk   (clk),
        .rst_n (rst_n),
        .addr  (arb_mem_addr),
        .re    (arb_mem_re),
        .we    (arb_mem_we),
        .wdata (arb_mem_wdata),
        .wsize (arb_mem_wsize),
        .rdata (arb_mem_rdata),
        .ready (arb_mem_ready)
    );

    // Performance Counters
    perf_counters u_perf (
        .clk             (clk),
        .rst_n           (rst_n),
        .clear           (1'b0),
        .evt_cache_hit   (int_evt_hit),
        .evt_cache_miss  (evt_miss),
        .evt_pf_hit      (evt_pf_hit),
        .evt_pf_issued   (int_evt_pf_issued),
        .evt_pf_pollution(evt_pf_pollution),
        .evt_instr_valid (instr_valid),
        .dmem_stall      (cpu_dmem_stall),
        .cnt_cycles      (cnt_cycles),
        .cnt_instrs      (cnt_instrs),
        .cnt_cache_hits  (cnt_cache_hits),
        .cnt_cache_misses(cnt_cache_misses),
        .cnt_pf_hits     (cnt_pf_hits),
        .cnt_pf_issued   (cnt_pf_issued),
        .cnt_pf_pollution(cnt_pf_pollution),
        .cnt_stall_cycles(cnt_stall_cycles)
    );

    // LED logic moved to fpga_top.v to allow pulse stretching.

endmodule
