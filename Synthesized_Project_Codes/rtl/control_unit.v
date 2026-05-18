//============================================================================
// Control Unit — Main decoder for RV32I instructions
// Generates all pipeline control signals from opcode, funct3, funct7
//============================================================================
`timescale 1ns / 1ps

module control_unit (
    input  wire [6:0] opcode,
    input  wire [2:0] funct3,
    input  wire [6:0] funct7,
    output reg        reg_write,    // Write to register file
    output reg        mem_read,     // Load from data memory
    output reg        mem_write,    // Store to data memory
    output reg        alu_src,      // 0: rs2, 1: immediate
    output reg        mem_to_reg,   // 0: ALU result, 1: memory data
    output reg        branch,       // Branch instruction
    output reg        jal,          // JAL instruction
    output reg        jalr,         // JALR instruction
    output reg        lui,          // LUI instruction
    output reg        auipc,        // AUIPC instruction
    output reg  [3:0] alu_ctrl      // Direct ALU control
);

    // ALU operation encodings
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

    // Opcode definitions
    localparam OP_RTYPE  = 7'b0110011;
    localparam OP_ITYPE  = 7'b0010011;
    localparam OP_LOAD   = 7'b0000011;
    localparam OP_STORE  = 7'b0100011;
    localparam OP_BRANCH = 7'b1100011;
    localparam OP_JAL    = 7'b1101111;
    localparam OP_JALR   = 7'b1100111;
    localparam OP_LUI    = 7'b0110111;
    localparam OP_AUIPC  = 7'b0010111;

    // ALU control generation for R-type and I-type
    function [3:0] decode_alu;
        input [6:0] op;
        input [2:0] f3;
        input [6:0] f7;
        begin
            case (f3)
                3'b000: begin
                    if (op == OP_RTYPE && f7[5])
                        decode_alu = ALU_SUB;
                    else
                        decode_alu = ALU_ADD;
                end
                3'b001: decode_alu = ALU_SLL;
                3'b010: decode_alu = ALU_SLT;
                3'b011: decode_alu = ALU_SLTU;
                3'b100: decode_alu = ALU_XOR;
                3'b101: begin
                    if (f7[5])
                        decode_alu = ALU_SRA;
                    else
                        decode_alu = ALU_SRL;
                end
                3'b110: decode_alu = ALU_OR;
                3'b111: decode_alu = ALU_AND;
                default: decode_alu = ALU_ADD;
            endcase
        end
    endfunction

    always @(*) begin
        // Defaults
        reg_write  = 1'b0;
        mem_read   = 1'b0;
        mem_write  = 1'b0;
        alu_src    = 1'b0;
        mem_to_reg = 1'b0;
        branch     = 1'b0;
        jal        = 1'b0;
        jalr       = 1'b0;
        lui        = 1'b0;
        auipc      = 1'b0;
        alu_ctrl   = ALU_ADD;

        case (opcode)
            OP_RTYPE: begin
                reg_write = 1'b1;
                alu_ctrl  = decode_alu(opcode, funct3, funct7);
            end

            OP_ITYPE: begin
                reg_write = 1'b1;
                alu_src   = 1'b1;
                alu_ctrl  = decode_alu(opcode, funct3, funct7);
            end

            OP_LOAD: begin
                reg_write  = 1'b1;
                alu_src    = 1'b1;
                mem_read   = 1'b1;
                mem_to_reg = 1'b1;
                alu_ctrl   = ALU_ADD;
            end

            OP_STORE: begin
                alu_src   = 1'b1;
                mem_write = 1'b1;
                alu_ctrl  = ALU_ADD;
            end

            OP_BRANCH: begin
                branch   = 1'b1;
                alu_ctrl = ALU_SUB;
            end

            OP_JAL: begin
                reg_write = 1'b1;
                jal       = 1'b1;
            end

            OP_JALR: begin
                reg_write = 1'b1;
                alu_src   = 1'b1;
                jalr      = 1'b1;
                alu_ctrl  = ALU_ADD;
            end

            OP_LUI: begin
                reg_write = 1'b1;
                lui       = 1'b1;
            end

            OP_AUIPC: begin
                reg_write = 1'b1;
                auipc     = 1'b1;
            end

            default: begin
                // NOP / illegal — all signals stay at defaults
            end
        endcase
    end

endmodule
