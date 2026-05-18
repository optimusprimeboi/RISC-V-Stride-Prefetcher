//============================================================================
// Immediate Generator — Extracts and sign-extends immediates for RV32I
//============================================================================
`timescale 1ns / 1ps

module imm_gen (
    input  wire [31:0] instr,
    output reg  [31:0] imm
);

    // Opcode field
    wire [6:0] opcode = instr[6:0];

    always @(*) begin
        case (opcode)
            // I-type (loads, ALU immediate, JALR)
            7'b0010011, 7'b0000011, 7'b1100111:
                imm = {{20{instr[31]}}, instr[31:20]};

            // S-type (stores)
            7'b0100011:
                imm = {{20{instr[31]}}, instr[31:25], instr[11:7]};

            // B-type (branches)
            7'b1100011:
                imm = {{19{instr[31]}}, instr[31], instr[7], instr[30:25], instr[11:8], 1'b0};

            // U-type (LUI, AUIPC)
            7'b0110111, 7'b0010111:
                imm = {instr[31:12], 12'b0};

            // J-type (JAL)
            7'b1101111:
                imm = {{11{instr[31]}}, instr[31], instr[19:12], instr[20], instr[30:21], 1'b0};

            default:
                imm = 32'd0;
        endcase
    end

endmodule
