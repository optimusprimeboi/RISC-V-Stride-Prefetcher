//============================================================================
// L1 Data Cache — Direct-Mapped, Write-Through
// 128 bytes, 16-byte blocks (4 words), 8 lines
// Address: [31:7] tag | [6:4] index | [3:2] word_off | [1:0] byte_off
//
// FSM States:
//   S_IDLE     : Check hit/miss. HIT → return data combinationally, no stall.
//                MISS → latch request, go to S_MISS
//   S_MISS     : Drive mem_re=1, wait for memory ready. On ready → S_FILL
//   S_FILL     : Fill cache line, hold stall=1 for one cycle so pipeline
//                sees the loaded rdata before it advances. → S_IDLE
//   S_WRITE    : Drive mem_we=1 for write-through. On ready → S_IDLE
//============================================================================
`timescale 1ns / 1ps

module l1_data_cache (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        enable,        // 1=cache enabled, 0=bypass

    // CPU interface (from pipeline MEM stage)
    input  wire [31:0] cpu_addr,
    input  wire [31:0] cpu_wdata,
    input  wire        cpu_we,
    input  wire        cpu_re,
    input  wire [2:0]  cpu_funct3,
    output wire [31:0] cpu_rdata,
    output wire        cpu_stall,

    // Main memory interface
    output reg  [31:0] mem_addr,
    output reg         mem_re,
    output reg         mem_we,
    output reg  [31:0] mem_wdata,
    output reg  [1:0]  mem_wsize,
    input  wire [127:0] mem_rdata,
    input  wire        mem_ready,

    // Prefetch fill port (from stride prefetcher)
    input  wire        pf_fill_valid,
    input  wire [31:0] pf_fill_addr,
    input  wire [127:0] pf_fill_data,

    // CPU PC for prefetcher (from pipeline MEM stage)
    input  wire [31:0] cpu_pc,

    // Performance events
    output reg         evt_hit,
    output reg         evt_miss,
    output reg  [31:0] evt_miss_addr,  // Latched miss address (stable for prefetcher)
    output reg  [31:0] evt_miss_pc,    // Latched miss PC (stable for prefetcher)
    output reg         evt_pf_hit,
    output reg         evt_pf_pollution,
    output reg         evt_load,
    output reg  [31:0] evt_load_addr,
    output reg  [31:0] evt_load_pc
);

    // =========================================================================
    // Cache parameters
    // =========================================================================
    localparam NUM_LINES   = 8;
    localparam TAG_WIDTH   = 25;   // bits [31:7]
    localparam INDEX_WIDTH = 3;    // bits [6:4]

    // =========================================================================
    // Cache storage
    // =========================================================================
    reg                  valid     [0:NUM_LINES-1];
    reg                  prefetched[0:NUM_LINES-1];
    reg [TAG_WIDTH-1:0]  tags      [0:NUM_LINES-1];
    reg [127:0]          data      [0:NUM_LINES-1];

    // =========================================================================
    // Address decode (from CPU — combinational)
    // =========================================================================
    wire [TAG_WIDTH-1:0]   addr_tag  = cpu_addr[31:7];
    wire [INDEX_WIDTH-1:0] addr_idx  = cpu_addr[6:4];
    wire [1:0]             word_off  = cpu_addr[3:2];
    wire [1:0]             byte_off  = cpu_addr[1:0];

    // =========================================================================
    // Hit detection (combinational)
    // =========================================================================
    wire cache_hit = enable && valid[addr_idx] && (tags[addr_idx] == addr_tag);

    // =========================================================================
    // Word selection from a 128-bit cache line
    // =========================================================================
    function [31:0] sel_word;
        input [127:0] line;
        input [1:0]   woff;
        begin
            case (woff)
                2'b00: sel_word = line[31:0];
                2'b01: sel_word = line[63:32];
                2'b10: sel_word = line[95:64];
                2'b11: sel_word = line[127:96];
            endcase
        end
    endfunction

    // =========================================================================
    // Load formatter
    // =========================================================================
    function [31:0] format_load;
        input [2:0]  funct3;
        input [1:0]  boff;
        input [31:0] word;
        begin
            case (funct3)
                3'b000: case (boff)
                    2'b00: format_load = {{24{word[7]}},   word[7:0]};
                    2'b01: format_load = {{24{word[15]}},  word[15:8]};
                    2'b10: format_load = {{24{word[23]}},  word[23:16]};
                    2'b11: format_load = {{24{word[31]}},  word[31:24]};
                endcase
                3'b001:
                    if (boff[1]) format_load = {{16{word[31]}}, word[31:16]};
                    else         format_load = {{16{word[15]}}, word[15:0]};
                3'b010: format_load = word;
                3'b100: case (boff)
                    2'b00: format_load = {24'd0, word[7:0]};
                    2'b01: format_load = {24'd0, word[15:8]};
                    2'b10: format_load = {24'd0, word[23:16]};
                    2'b11: format_load = {24'd0, word[31:24]};
                endcase
                3'b101:
                    if (boff[1]) format_load = {16'd0, word[31:16]};
                    else         format_load = {16'd0, word[15:0]};
                default: format_load = word;
            endcase
        end
    endfunction



    // =========================================================================
    // FSM
    // =========================================================================
    localparam S_IDLE  = 3'd0;
    localparam S_MISS  = 3'd1;  // Waiting for memory (mem_re held high)
    localparam S_FILL  = 3'd2;  // Cache filled, hold stall 1 more cycle
    localparam S_WRITE = 3'd3;  // Write-through (mem_we held high)

    reg [2:0]  state;
    reg        stall_reg;
    assign cpu_stall = stall_reg;

    reg [31:0] miss_rdata;
    assign cpu_rdata = (state == S_IDLE && cpu_re && cache_hit) ? 
                       format_load(cpu_funct3, byte_off, sel_word(data[addr_idx], word_off)) : 
                       miss_rdata;

    // Latched request (stable across memory wait)
    reg [31:0]          req_addr;
    reg [2:0]           req_funct3;
    reg [127:0]         fill_data_latch; // latched mem_rdata

    integer i;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state     <= S_IDLE;
            stall_reg <= 1'b0;
            mem_re    <= 1'b0;
            mem_we    <= 1'b0;
            mem_addr  <= 32'd0;
            mem_wdata <= 32'd0;
            mem_wsize <= 2'b10;
            miss_rdata <= 32'd0;
            req_addr  <= 32'd0;
            req_funct3<= 3'd0;
            fill_data_latch <= 128'd0;
            evt_hit   <= 1'b0;
            evt_miss  <= 1'b0;
            evt_miss_addr <= 32'd0;
            evt_miss_pc   <= 32'd0;
            evt_pf_hit <= 1'b0;
            evt_pf_pollution <= 1'b0;
            evt_load         <= 1'b0;
            evt_load_addr    <= 32'd0;
            evt_load_pc      <= 32'd0;
            for (i = 0; i < NUM_LINES; i = i + 1) begin
                valid[i]      <= 1'b0;
                prefetched[i] <= 1'b0;
            end
        end else begin
            // Default: clear single-cycle event pulses
            evt_hit          <= 1'b0;
            evt_miss         <= 1'b0;
            evt_pf_hit       <= 1'b0;
            evt_pf_pollution <= 1'b0;
            evt_load         <= 1'b0;

            // ---- Prefetch Fill Port (Asynchronous to CPU FSM) ----
            if (enable && pf_fill_valid) begin
                // If the prefetcher returns data for the exact line the CPU is currently
                // waiting for in S_MISS, ignore it to prevent race conditions. The CPU
                // FSM will fill it anyway.
                if (pf_fill_addr[31:4] == req_addr[31:4] && state == S_MISS) begin
                    // Do nothing — demand fill wins
                end else begin
                    // Check if we are evicting a valid, un-prefetched line (pollution)
                    if (valid[pf_fill_addr[6:4]] && !prefetched[pf_fill_addr[6:4]] &&
                        tags[pf_fill_addr[6:4]] != pf_fill_addr[31:7])
                        evt_pf_pollution <= 1'b1;

                    valid[pf_fill_addr[6:4]]      <= 1'b1;
                    prefetched[pf_fill_addr[6:4]] <= 1'b1;
                    tags[pf_fill_addr[6:4]]       <= pf_fill_addr[31:7];
                    data[pf_fill_addr[6:4]]       <= pf_fill_data;
                end
            end

            case (state)
                // ------------------------------------------------------------------
                S_IDLE: begin
                    stall_reg <= 1'b0;
                    mem_re    <= 1'b0;
                    mem_we    <= 1'b0;

                    if (cpu_re) begin
                        if (enable) begin
                            evt_load      <= 1'b1;
                            evt_load_addr <= cpu_addr;
                            evt_load_pc   <= cpu_pc;
                        end
                        if (cache_hit) begin
                            // ---- HIT: data is combinationally available ----
                            evt_hit   <= 1'b1;
                            stall_reg <= 1'b0; // No stall on hit
                            // cpu_rdata is combinationally assigned above
                            if (prefetched[addr_idx]) begin
                                evt_pf_hit            <= 1'b1;
                                prefetched[addr_idx]  <= 1'b0;
                            end
                        end else begin
                            // ---- MISS: go fetch from memory ----
                            if (enable) begin
                                evt_miss      <= 1'b1;
                                evt_miss_addr <= cpu_addr;
                                evt_miss_pc   <= cpu_pc;
                            end
                            stall_reg  <= 1'b1;
                            req_addr   <= cpu_addr;
                            req_funct3 <= cpu_funct3;
                            mem_re     <= 1'b1;
                            mem_addr   <= {cpu_addr[31:4], 4'b0000}; // line-aligned
                            state      <= S_MISS;
                        end
                    end else if (cpu_we) begin
                        // ---- WRITE-THROUGH ----
                        // Update cache if hit
                        if (cache_hit) begin
                            prefetched[addr_idx] <= 1'b0;
                            case (cpu_funct3)
                                3'b000: begin
                                    case ({word_off, byte_off})
                                        4'b0000: data[addr_idx][7:0]     <= cpu_wdata[7:0];
                                        4'b0001: data[addr_idx][15:8]    <= cpu_wdata[7:0];
                                        4'b0010: data[addr_idx][23:16]   <= cpu_wdata[7:0];
                                        4'b0011: data[addr_idx][31:24]   <= cpu_wdata[7:0];
                                        4'b0100: data[addr_idx][39:32]   <= cpu_wdata[7:0];
                                        4'b0101: data[addr_idx][47:40]   <= cpu_wdata[7:0];
                                        4'b0110: data[addr_idx][55:48]   <= cpu_wdata[7:0];
                                        4'b0111: data[addr_idx][63:56]   <= cpu_wdata[7:0];
                                        4'b1000: data[addr_idx][71:64]   <= cpu_wdata[7:0];
                                        4'b1001: data[addr_idx][79:72]   <= cpu_wdata[7:0];
                                        4'b1010: data[addr_idx][87:80]   <= cpu_wdata[7:0];
                                        4'b1011: data[addr_idx][95:88]   <= cpu_wdata[7:0];
                                        4'b1100: data[addr_idx][103:96]  <= cpu_wdata[7:0];
                                        4'b1101: data[addr_idx][111:104] <= cpu_wdata[7:0];
                                        4'b1110: data[addr_idx][119:112] <= cpu_wdata[7:0];
                                        4'b1111: data[addr_idx][127:120] <= cpu_wdata[7:0];
                                    endcase
                                end
                                3'b001: begin
                                    case (word_off)
                                        2'b00: data[addr_idx][31:0]   <= {data[addr_idx][31:16], cpu_wdata[15:0]};
                                        2'b01: data[addr_idx][63:32]  <= {data[addr_idx][63:48], cpu_wdata[15:0]};
                                        2'b10: data[addr_idx][95:64]  <= {data[addr_idx][95:80], cpu_wdata[15:0]};
                                        2'b11: data[addr_idx][127:96] <= {data[addr_idx][127:112], cpu_wdata[15:0]};
                                    endcase
                                end
                                3'b010: begin
                                    case (word_off)
                                        2'b00: data[addr_idx][31:0]   <= cpu_wdata;
                                        2'b01: data[addr_idx][63:32]  <= cpu_wdata;
                                        2'b10: data[addr_idx][95:64]  <= cpu_wdata;
                                        2'b11: data[addr_idx][127:96] <= cpu_wdata;
                                    endcase
                                end
                                default: ;
                            endcase
                        end
                        // Write-through: always write to memory
                        stall_reg <= 1'b1;
                        mem_we    <= 1'b1;
                        mem_addr  <= cpu_addr;
                        mem_wdata <= cpu_wdata;
                        case (cpu_funct3)
                            3'b000:  mem_wsize <= 2'b00;
                            3'b001:  mem_wsize <= 2'b01;
                            default: mem_wsize <= 2'b10;
                        endcase
                        state <= S_WRITE;
                    end
                end

                // ------------------------------------------------------------------
                S_MISS: begin
                    // Hold mem_re=1 until memory responds
                    mem_re <= 1'b1;
                    if (mem_ready) begin
                        // Latch the returned data before filling
                        fill_data_latch <= mem_rdata;
                        mem_re <= 1'b0;

                        // Fill cache line
                        if (enable) begin
                            valid[req_addr[6:4]]      <= 1'b1;
                            prefetched[req_addr[6:4]] <= 1'b0;
                            tags[req_addr[6:4]]       <= req_addr[31:7];
                            data[req_addr[6:4]]       <= mem_rdata;
                        end

                        // Compute rdata from returned line immediately
                        miss_rdata <= format_load(
                            req_funct3,
                            req_addr[1:0],
                            sel_word(mem_rdata, req_addr[3:2])
                        );

                        // Go to FILL state: hold stall=1 one more cycle so
                        // the pipeline registers cpu_rdata before advancing
                        state <= S_FILL;
                    end
                end

                // ------------------------------------------------------------------
                S_FILL: begin
                    // stall=1 this cycle; cpu_rdata is already set from S_MISS
                    // Pipeline latches cpu_rdata on this rising edge, then
                    // on the next rising edge stall becomes 0 and it advances.
                    stall_reg <= 1'b0;
                    state     <= S_IDLE;
                end

                // ------------------------------------------------------------------
                S_WRITE: begin
                    mem_we <= 1'b1;
                    if (mem_ready) begin
                        mem_we    <= 1'b0;
                        stall_reg <= 1'b0;
                        state     <= S_IDLE;
                    end
                end

                default: state <= S_IDLE;
            endcase
        end
    end

endmodule
