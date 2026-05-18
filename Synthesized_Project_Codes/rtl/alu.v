//============================================================================
// ALU — Arithmetic Logic Unit for RV32I
// Supports all RV32I base integer ALU operations
//============================================================================
`timescale 1ns / 1ps

module alu (
    input  wire [31:0] a,           // Operand A (rs1)
    input  wire [31:0] b,           // Operand B (rs2 or immediate)
    input  wire [3:0]  alu_ctrl,    // ALU control signal
    output reg  [31:0] result,      // ALU result
    output wire        zero         // Zero flag (result == 0)
);

    // ALU Control Encoding
    localparam ALU_ADD  = 4'b0000;
    localparam ALU_SUB  = 4'b0001;
    localparam ALU_SLL  = 4'b0010;
    localparam ALU_SLT  = 4'b0011;
    localparam ALU_SLTU = 4'b0100;
    localparam ALU_XOR  = 4'b0101;
    localparam ALU_SRL  = 4'b0110;
    localparam ALU_SRA  = 4'b0111;
    localparam ALU_OR   = 4'b1000;
    localparam ALU_AND  = 4'b1001;

    assign zero = (result == 32'b0);

    always @(*) begin
        case (alu_ctrl)
            ALU_ADD:  result = a + b;
            ALU_SUB:  result = a - b;
            ALU_SLL:  result = a << b[4:0];
            ALU_SLT:  result = ($signed(a) < $signed(b)) ? 32'd1 : 32'd0;
            ALU_SLTU: result = (a < b) ? 32'd1 : 32'd0;
            ALU_XOR:  result = a ^ b;
            ALU_SRL:  result = a >> b[4:0];
            ALU_SRA:  result = $signed(a) >>> b[4:0];
            ALU_OR:   result = a | b;
            ALU_AND:  result = a & b;
            default:  result = 32'b0;
        endcase
    end

endmodule
