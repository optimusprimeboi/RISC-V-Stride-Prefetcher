//============================================================================
// Main Memory — BRAM-based data memory with configurable latency
// Simulates realistic memory access time for cache miss penalty
// Supports full cache-line reads (128-bit) and word writes
//============================================================================
`timescale 1ns / 1ps

module main_memory #(
    parameter DEPTH       = 4096,   // Number of 32-bit words (16KB)
    parameter LATENCY     = 10,     // Access latency in clock cycles
    parameter INIT_FILE   = "data.mem"
)(
    input  wire        clk,
    input  wire        rst_n,
    // Request interface
    input  wire [31:0] addr,
    input  wire        re,          // Read request (cache-line)
    input  wire        we,          // Write request (single word)
    input  wire [31:0] wdata,       // Write data (single word)
    input  wire [1:0]  wsize,       // 00: byte, 01: half, 10: word
    // Response
    output reg [127:0] rdata,       // Read data (4 words = cache line)
    output reg         ready        // Response valid
);

    (* ram_style = "block" *) reg [31:0] mem [0:DEPTH-1];

    // Internal state
    localparam IDLE    = 2'd0;
    localparam READING = 2'd1;
    localparam WRITING = 2'd2;
    localparam DONE    = 2'd3;

    reg [1:0]  state;
    reg [31:0] latency_cnt;
    reg [31:0] pending_addr;

    // Word-aligned base address for cache line fetch
    wire [$clog2(DEPTH)-1:0] word_idx = addr[$clog2(DEPTH)+1:2];
    // Cache-line aligned (4-word boundary): clear bottom 4 bits
    wire [31:0] line_base_addr = {addr[31:4], 4'b0000};
    wire [$clog2(DEPTH)-1:0] line_base_idx = line_base_addr[$clog2(DEPTH)+1:2];

    integer i;
    initial begin
        for (i = 0; i < DEPTH; i = i + 1)
            mem[i] = 32'd0;
        $readmemh(INIT_FILE, mem);
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state       <= IDLE;
            latency_cnt <= 32'd0;
            ready       <= 1'b0;
            rdata       <= 128'd0;
            pending_addr <= 32'd0;
        end else begin
            case (state)
                IDLE: begin
                    ready <= 1'b0;
                    if (re) begin
                        state        <= READING;
                        latency_cnt  <= 32'd1;
                        pending_addr <= addr;
                    end else if (we) begin
                        // Writes: apply immediately with latency
                        state        <= WRITING;
                        latency_cnt  <= 32'd1;
                    end
                end

                READING: begin
                    if (latency_cnt >= LATENCY) begin
                        // Return full cache line (4 words)
                        rdata[31:0]   <= mem[line_base_idx];
                        rdata[63:32]  <= mem[line_base_idx + 1];
                        rdata[95:64]  <= mem[line_base_idx + 2];
                        rdata[127:96] <= mem[line_base_idx + 3];
                        ready         <= 1'b1;
                        state         <= DONE;
                    end else begin
                        latency_cnt <= latency_cnt + 32'd1;
                    end
                end

                WRITING: begin
                    if (latency_cnt >= LATENCY) begin
                        ready <= 1'b1;
                        state <= DONE;
                    end else begin
                        latency_cnt <= latency_cnt + 32'd1;
                    end
                end

                DONE: begin
                    ready <= 1'b0;
                    if (!re && !we) begin
                        state <= IDLE;
                    end
                end

                default: state <= IDLE;
            endcase
        end
    end

    // Memory write port (synchronous, no async reset for BRAM inference)
    always @(posedge clk) begin
        if (state == IDLE && we) begin
            case (wsize)
                2'b10: mem[word_idx] <= wdata;
                2'b01: begin // halfword
                    if (addr[1])
                        mem[word_idx][31:16] <= wdata[15:0];
                    else
                        mem[word_idx][15:0]  <= wdata[15:0];
                end
                2'b00: begin // byte
                    case (addr[1:0])
                        2'b00: mem[word_idx][7:0]   <= wdata[7:0];
                        2'b01: mem[word_idx][15:8]  <= wdata[7:0];
                        2'b10: mem[word_idx][23:16] <= wdata[7:0];
                        2'b11: mem[word_idx][31:24] <= wdata[7:0];
                    endcase
                end
                default: mem[word_idx] <= wdata;
            endcase
        end
    end

endmodule
