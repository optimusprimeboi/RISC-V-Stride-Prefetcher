//============================================================================
// Hazard Unit — Data forwarding, load-use stall, branch flush
//============================================================================
`timescale 1ns / 1ps

module hazard_unit (
    // EX stage source registers
    input  wire [4:0] id_ex_rs1,
    input  wire [4:0] id_ex_rs2,
    // MEM stage destination
    input  wire [4:0] ex_mem_rd,
    input  wire       ex_mem_reg_write,
    // WB stage destination
    input  wire [4:0] mem_wb_rd,
    input  wire       mem_wb_reg_write,
    // Forwarding outputs (to EX stage MUXes)
    output reg  [1:0] forward_a,   // 00: reg, 01: MEM fwd, 10: WB fwd
    output reg  [1:0] forward_b,   // 00: reg, 01: MEM fwd, 10: WB fwd

    // Load-use hazard detection
    input  wire [6:0] if_id_opcode,  // Opcode of instruction in IF/ID stage
    input  wire [4:0] if_id_rs1,
    input  wire [4:0] if_id_rs2,
    input  wire [4:0] id_ex_rd,
    input  wire       id_ex_mem_read,
    output wire       stall,        // Stall IF and ID, insert bubble in EX

    // Branch/jump flush
    input  wire       branch_taken,
    output wire       flush          // Flush IF/ID and ID/EX
);

    // =========================================================================
    // Opcode definitions (to determine which registers an instruction reads)
    // =========================================================================
    localparam OP_RTYPE  = 7'b0110011;  // R-type:  reads rs1, rs2
    localparam OP_ITYPE  = 7'b0010011;  // I-type:  reads rs1
    localparam OP_LOAD   = 7'b0000011;  // Load:    reads rs1
    localparam OP_STORE  = 7'b0100011;  // Store:   reads rs1, rs2
    localparam OP_BRANCH = 7'b1100011;  // Branch:  reads rs1, rs2
    localparam OP_JALR   = 7'b1100111;  // JALR:    reads rs1
    // JAL (1101111), LUI (0110111), AUIPC (0010111) do NOT read rs1/rs2

    // Determine if the instruction in IF/ID actually reads rs1 or rs2
    wire uses_rs1 = (if_id_opcode == OP_RTYPE)  ||
                    (if_id_opcode == OP_ITYPE)  ||
                    (if_id_opcode == OP_LOAD)   ||
                    (if_id_opcode == OP_STORE)  ||
                    (if_id_opcode == OP_BRANCH) ||
                    (if_id_opcode == OP_JALR);

    wire uses_rs2 = (if_id_opcode == OP_RTYPE)  ||
                    (if_id_opcode == OP_STORE)  ||
                    (if_id_opcode == OP_BRANCH);

    // =========================================================================
    // Forwarding logic (EX-EX and MEM-EX forwarding)
    // =========================================================================
    always @(*) begin
        // Forward A (rs1)
        if (ex_mem_reg_write && ex_mem_rd != 5'd0 && ex_mem_rd == id_ex_rs1)
            forward_a = 2'b01;  // Forward from MEM stage (EX-EX)
        else if (mem_wb_reg_write && mem_wb_rd != 5'd0 && mem_wb_rd == id_ex_rs1)
            forward_a = 2'b10;  // Forward from WB stage (MEM-EX)
        else
            forward_a = 2'b00;  // No forwarding

        // Forward B (rs2)
        if (ex_mem_reg_write && ex_mem_rd != 5'd0 && ex_mem_rd == id_ex_rs2)
            forward_b = 2'b01;  // Forward from MEM stage
        else if (mem_wb_reg_write && mem_wb_rd != 5'd0 && mem_wb_rd == id_ex_rs2)
            forward_b = 2'b10;  // Forward from WB stage
        else
            forward_b = 2'b00;  // No forwarding
    end

    // =========================================================================
    // Load-use hazard detection (stall 1 cycle)
    // Only stall if the instruction in IF/ID actually READS the conflicting
    // register. JAL, LUI, AUIPC do not read rs1/rs2, so they must not stall.
    // =========================================================================
    wire rs1_conflict = uses_rs1 && (id_ex_rd == if_id_rs1);
    wire rs2_conflict = uses_rs2 && (id_ex_rd == if_id_rs2);

    assign stall = id_ex_mem_read && (id_ex_rd != 5'd0) &&
                   (rs1_conflict || rs2_conflict);

    // =========================================================================
    // Branch/jump flush (flush 2 instructions in IF and ID)
    // =========================================================================
    assign flush = branch_taken;

endmodule
