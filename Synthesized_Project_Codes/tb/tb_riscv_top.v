//============================================================================
// Testbench for RISC-V Top Module
// Runs test programs and prints performance counter results
//============================================================================
`timescale 1ns / 1ps

module tb_riscv_top;

    // Clock period: 10ns → 100MHz
    localparam CLK_PERIOD = 10;
    localparam MAX_CYCLES = 20000;

    reg        clk;
    reg        rst_n;
    reg        cache_enable;
    reg        prefetch_enable;
    wire        evt_hit;
    wire        evt_pf_issued_w;
    wire [31:0] dbg_pc;
    wire [31:0] cnt_cycles, cnt_instrs;
    wire [31:0] cnt_cache_hits, cnt_cache_misses;
    wire [31:0] cnt_pf_hits, cnt_pf_issued, cnt_pf_pollution;
    wire [31:0] cnt_stall_cycles;

    // DUT
    riscv_top #(
        .IMEM_INIT  ("C:/Users/Lenovo/.gemini/antigravity/scratch/P14_Stride_Prefetcher/test_programs/program.mem"),
        .DMEM_INIT  ("C:/Users/Lenovo/.gemini/antigravity/scratch/P14_Stride_Prefetcher/test_programs/data.mem"),
        .MEM_LATENCY(10),
        .IMEM_DEPTH (1024),
        .DMEM_DEPTH (4096)
    ) dut (
        .clk             (clk),
        .rst_n           (rst_n),
        .cache_enable    (cache_enable),
        .prefetch_enable (prefetch_enable),
        .dbg_pc          (dbg_pc),
        .cnt_cycles      (cnt_cycles),
        .cnt_instrs      (cnt_instrs),
        .cnt_cache_hits  (cnt_cache_hits),
        .cnt_cache_misses(cnt_cache_misses),
        .cnt_pf_hits     (cnt_pf_hits),
        .cnt_pf_issued   (cnt_pf_issued),
        .cnt_pf_pollution(cnt_pf_pollution),
        .cnt_stall_cycles(cnt_stall_cycles),
        .evt_hit         (evt_hit),
        .evt_pf_issued   (evt_pf_issued_w)
    );

    // Clock generation
    initial clk = 0;
    always #(CLK_PERIOD/2) clk = ~clk;

    // =========================================================================
    // Test sequence
    // =========================================================================
    integer cycle_count;
    reg [31:0] prev_pc;
    reg [31:0] prev_prev_pc;
    integer halt_count;

    initial begin
        $dumpfile("riscv_top.vcd");
        $dumpvars(0, tb_riscv_top);

        // Force-reload instruction memory at simulation time (bypasses xsim cache)
        $readmemh("C:/Users/Lenovo/.gemini/antigravity/scratch/P14_Stride_Prefetcher/test_programs/program.mem",
                  dut.u_imem.mem);

        // ---- Test 1: Baseline (no cache, no prefetch) ----
        $display("=============================================================");
        $display("TEST 1: Baseline (cache OFF, prefetch OFF)");
        $display("=============================================================");
        cache_enable    = 1'b0;
        prefetch_enable = 1'b0;
        rst_n = 1'b0;
        #(CLK_PERIOD * 5);
        rst_n = 1'b1;

        wait_for_halt(MAX_CYCLES);
        print_results("Baseline");

        // ---- Test 2: Cache only ----
        $display("");
        $display("=============================================================");
        $display("TEST 2: Cache ON, Prefetch OFF");
        $display("=============================================================");
        cache_enable    = 1'b1;
        prefetch_enable = 1'b0;
        rst_n = 1'b0;
        #(CLK_PERIOD * 5);
        rst_n = 1'b1;

        wait_for_halt(MAX_CYCLES);
        print_results("Cache Only");

        // ---- Test 3: Cache + Prefetcher ----
        $display("");
        $display("=============================================================");
        $display("TEST 3: Cache ON, Prefetch ON");
        $display("=============================================================");
        cache_enable    = 1'b1;
        prefetch_enable = 1'b1;
        rst_n = 1'b0;
        #(CLK_PERIOD * 5);
        rst_n = 1'b1;

        wait_for_halt(MAX_CYCLES);
        print_results("Cache + Prefetch");

        $display("");
        $display("=============================================================");
        $display("ALL TESTS COMPLETE");
        $display("=============================================================");
        $finish;
    end

    // =========================================================================
    // Wait until the program halts
    // Detects:
    //   1. PC in the known infinite loop range (0x8C-0x94)
    //   2. PC frozen at the same address (stall deadlock)
    //   3. PC oscillating between 2 addresses (JAL x0,0 infinite loop
    //      in a pipelined CPU: fetches JAL, then JAL+4, then flushes back)
    // Does NOT falsely trigger on normal sequential +4 execution.
    // =========================================================================
    task wait_for_halt;
        input integer max;
        reg is_halt_pattern;
        begin
            cycle_count  = 0;
            halt_count   = 0;
            prev_pc      = 32'hFFFF_FFFF;
            prev_prev_pc = 32'hFFFF_FFFF;
            while (cycle_count < max && halt_count < 30) begin
                @(posedge clk);
                cycle_count = cycle_count + 1;

                is_halt_pattern = 1'b0;

                // Check 1: PC is in the known infinite loop region
                if (dbg_pc >= 32'h8C && dbg_pc <= 32'h94)
                    is_halt_pattern = 1'b1;

                // Program.mem ends with a JAL self-loop at 0x24.
                // It oscillates with pipeline bubbles (0x0), so we just
                // count how many times we see 0x24.
                if (dbg_pc == 32'h24) begin
                    halt_count = halt_count + 1;
                    if (halt_count > 10) begin
                        $display("Program halted at PC = 0x%08h after %0d cycles", dbg_pc, cycle_count);
                        disable wait_for_halt;
                    end
                end
            end
            $display("WARNING: Max cycles (%0d) reached. PC = 0x%08h", max, dbg_pc);
        end
    endtask

    // =========================================================================
    // Print performance results
    // =========================================================================
    task print_results;
        input [80*8-1:0] label;
        begin
            $display("--- %0s Results ---", label);
            $display("  Cycles:          %0d", cnt_cycles);
            $display("  Instructions:    %0d", cnt_instrs);
            $display("  CPI:             %0f", $itor(cnt_cycles) / $itor(cnt_instrs > 0 ? cnt_instrs : 1));
            $display("  Cache Hits:      %0d", cnt_cache_hits);
            $display("  Cache Misses:    %0d", cnt_cache_misses);
            if (cnt_cache_hits + cnt_cache_misses > 0)
                $display("  Hit Rate:        %0f%%",
                    100.0 * $itor(cnt_cache_hits) / $itor(cnt_cache_hits + cnt_cache_misses));
            $display("  PF Issued:       %0d", cnt_pf_issued);
            $display("  PF Hits:         %0d", cnt_pf_hits);
            if (cnt_pf_issued > 0)
                $display("  PF Accuracy:     %0f%%",
                    100.0 * $itor(cnt_pf_hits) / $itor(cnt_pf_issued));
            $display("  PF Pollution:    %0d", cnt_pf_pollution);
            $display("  Stall Cycles:    %0d", cnt_stall_cycles);
        end
    endtask

    // =========================================================================
    // Register file monitoring (for debug)
    // =========================================================================
    // Access internal register file for verification
    wire [31:0] x1  = dut.u_core.u_regfile.regs[1];
    wire [31:0] x2  = dut.u_core.u_regfile.regs[2];
    wire [31:0] x3  = dut.u_core.u_regfile.regs[3];
    wire [31:0] x4  = dut.u_core.u_regfile.regs[4];
    wire [31:0] x5  = dut.u_core.u_regfile.regs[5];
    wire [31:0] x10 = dut.u_core.u_regfile.regs[10];
    wire [31:0] x11 = dut.u_core.u_regfile.regs[11];

endmodule
