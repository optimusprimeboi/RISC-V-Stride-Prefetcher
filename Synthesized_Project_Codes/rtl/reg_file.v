//============================================================================
// Register File — 32 x 32-bit registers (x0 hardwired to 0)
// Optimized for LUTRAM inference: pure synchronous write, async read
// Forwarding logic moved OUTSIDE to allow Vivado to infer RAM32M
//============================================================================
`timescale 1ns / 1ps

module reg_file (
    input  wire        clk,
    input  wire        rst_n,
    // Read ports
    input  wire [4:0]  rs1_addr,
    input  wire [4:0]  rs2_addr,
    output wire [31:0] rs1_data,
    output wire [31:0] rs2_data,
    // Write port
    input  wire        we,
    input  wire [4:0]  rd_addr,
    input  wire [31:0] rd_data
);

    (* ram_style = "distributed" *) reg [31:0] regs [0:31];

    // Pure async read — Vivado can infer RAM32M (6-LUT distributed RAM)
    wire [31:0] rs1_raw = (rs1_addr == 5'd0) ? 32'd0 : regs[rs1_addr];
    wire [31:0] rs2_raw = (rs2_addr == 5'd0) ? 32'd0 : regs[rs2_addr];

    // Write-through forwarding (bypass on same-cycle write)
    assign rs1_data = (we && rd_addr != 5'd0 && rd_addr == rs1_addr) ? rd_data : rs1_raw;
    assign rs2_data = (we && rd_addr != 5'd0 && rd_addr == rs2_addr) ? rd_data : rs2_raw;

    // Synchronous write — clean single-write port for LUTRAM inference
    always @(posedge clk) begin
        if (we && rd_addr != 5'd0) begin
            regs[rd_addr] <= rd_data;
        end
    end

endmodule
