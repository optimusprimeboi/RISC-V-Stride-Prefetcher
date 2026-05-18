//============================================================================
// RV32I 5-Stage Pipelined Core
// Stages: IF → ID → EX → MEM → WB
// Features: Full forwarding, load-use stall, branch flush
//============================================================================
`timescale 1ns / 1ps

module rv32i_core (
    input  wire        clk,
    input  wire        rst_n,
    // Instruction memory interface
    output wire [31:0] imem_addr,
    input  wire [31:0] imem_rdata,
    // Data memory / cache interface
    output wire [31:0] dmem_addr,
    output wire [31:0] dmem_wdata,
    output wire        dmem_we,
    output wire        dmem_re,
    output wire [2:0]  dmem_funct3,
    output wire [31:0] dmem_pc,       // PC of load/store (for prefetcher)
    input  wire [31:0] dmem_rdata,
    input  wire        dmem_stall,    // Cache miss stall
    // Performance monitoring
    output wire        instr_valid,   // Valid instruction retired
    output wire [31:0] pc_out         // Current PC (debug)
);

    reg [31:0] mem_wb_pc; // Declare here so it is available for pc_out

    // =========================================================================
    // Wires for inter-stage communication
    // =========================================================================
    // Hazard unit signals
    wire [1:0] forward_a, forward_b;
    wire       hz_stall, hz_flush;
    wire       branch_taken;
    wire       pipeline_stall;

    // Combined stall: hazard stall OR cache stall
    assign pipeline_stall = hz_stall || dmem_stall;

    // =========================================================================
    // IF Stage — Instruction Fetch
    // =========================================================================
    reg [31:0] pc;

    wire [31:0] pc_plus4  = pc + 32'd4;
    wire [31:0] pc_next;

    // Branch target from EX stage
    wire [31:0] branch_target;

    assign pc_next = branch_taken ? branch_target : pc_plus4;
    assign imem_addr = pc;
    assign pc_out = mem_wb_pc;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            pc <= 32'h0000_0000;
        else if (!pipeline_stall)
            pc <= pc_next;
    end

    // =========================================================================
    // IF/ID Pipeline Register
    // =========================================================================
    reg [31:0] if_id_pc;
    reg [31:0] if_id_instr;
    reg        if_id_valid;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            if_id_pc    <= 32'd0;
            if_id_instr <= 32'h0000_0013; // NOP (addi x0, x0, 0)
            if_id_valid <= 1'b0;
        end else if (hz_flush) begin
            if_id_pc    <= 32'd0;
            if_id_instr <= 32'h0000_0013;
            if_id_valid <= 1'b0;
        end else if (!pipeline_stall) begin
            if_id_pc    <= pc;
            if_id_instr <= imem_rdata;
            if_id_valid <= 1'b1;
        end
    end

    // =========================================================================
    // ID Stage — Instruction Decode
    // =========================================================================
    wire [6:0] id_opcode = if_id_instr[6:0];
    wire [4:0] id_rd     = if_id_instr[11:7];
    wire [2:0] id_funct3 = if_id_instr[14:12];
    wire [4:0] id_rs1    = if_id_instr[19:15];
    wire [4:0] id_rs2    = if_id_instr[24:20];
    wire [6:0] id_funct7 = if_id_instr[31:25];

    // Control unit
    wire       ctrl_reg_write, ctrl_mem_read, ctrl_mem_write;
    wire       ctrl_alu_src, ctrl_mem_to_reg;
    wire       ctrl_branch, ctrl_jal, ctrl_jalr;
    wire       ctrl_lui, ctrl_auipc;
    wire [3:0] ctrl_alu_ctrl;

    control_unit u_ctrl (
        .opcode    (id_opcode),
        .funct3    (id_funct3),
        .funct7    (id_funct7),
        .reg_write (ctrl_reg_write),
        .mem_read  (ctrl_mem_read),
        .mem_write (ctrl_mem_write),
        .alu_src   (ctrl_alu_src),
        .mem_to_reg(ctrl_mem_to_reg),
        .branch    (ctrl_branch),
        .jal       (ctrl_jal),
        .jalr      (ctrl_jalr),
        .lui       (ctrl_lui),
        .auipc     (ctrl_auipc),
        .alu_ctrl  (ctrl_alu_ctrl)
    );

    // Immediate generator
    wire [31:0] id_imm;
    imm_gen u_immgen (
        .instr(if_id_instr),
        .imm  (id_imm)
    );

    // Register file
    wire [31:0] id_rs1_data, id_rs2_data;
    wire        wb_reg_write;
    wire [4:0]  wb_rd_addr;
    wire [31:0] wb_rd_data;

    reg_file u_regfile (
        .clk      (clk),
        .rst_n    (rst_n),
        .rs1_addr (id_rs1),
        .rs2_addr (id_rs2),
        .rs1_data (id_rs1_data),
        .rs2_data (id_rs2_data),
        .we       (wb_reg_write),
        .rd_addr  (wb_rd_addr),
        .rd_data  (wb_rd_data)
    );

    // =========================================================================
    // ID/EX Pipeline Register
    // =========================================================================
    reg [31:0] id_ex_pc;
    reg [31:0] id_ex_rs1_data, id_ex_rs2_data;
    reg [31:0] id_ex_imm;
    reg [4:0]  id_ex_rd;
    reg [4:0]  id_ex_rs1, id_ex_rs2;
    reg [2:0]  id_ex_funct3;
    reg [3:0]  id_ex_alu_ctrl;
    reg        id_ex_reg_write, id_ex_mem_read, id_ex_mem_write;
    reg        id_ex_alu_src, id_ex_mem_to_reg;
    reg        id_ex_branch, id_ex_jal, id_ex_jalr;
    reg        id_ex_lui, id_ex_auipc;
    reg        id_ex_valid;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            // Async reset
            id_ex_pc        <= 32'd0;
            id_ex_rs1_data  <= 32'd0;
            id_ex_rs2_data  <= 32'd0;
            id_ex_imm       <= 32'd0;
            id_ex_rd        <= 5'd0;
            id_ex_rs1       <= 5'd0;
            id_ex_rs2       <= 5'd0;
            id_ex_funct3    <= 3'd0;
            id_ex_alu_ctrl  <= 4'd0;
            id_ex_reg_write <= 1'b0;
            id_ex_mem_read  <= 1'b0;
            id_ex_mem_write <= 1'b0;
            id_ex_alu_src   <= 1'b0;
            id_ex_mem_to_reg<= 1'b0;
            id_ex_branch    <= 1'b0;
            id_ex_jal       <= 1'b0;
            id_ex_jalr      <= 1'b0;
            id_ex_lui       <= 1'b0;
            id_ex_auipc     <= 1'b0;
            id_ex_valid     <= 1'b0;
        end else if (hz_flush || (hz_stall && !dmem_stall)) begin
            // Sync flush or insert bubble for load-use stall
            // Only clear control signals — data fields are don't-cares
            id_ex_reg_write <= 1'b0;
            id_ex_mem_read  <= 1'b0;
            id_ex_mem_write <= 1'b0;
            id_ex_branch    <= 1'b0;
            id_ex_jal       <= 1'b0;
            id_ex_jalr      <= 1'b0;
            id_ex_valid     <= 1'b0;
        end else if (!dmem_stall) begin
            id_ex_pc        <= if_id_pc;
            id_ex_rs1_data  <= id_rs1_data;
            id_ex_rs2_data  <= id_rs2_data;
            id_ex_imm       <= id_imm;
            id_ex_rd        <= id_rd;
            id_ex_rs1       <= id_rs1;
            id_ex_rs2       <= id_rs2;
            id_ex_funct3    <= id_funct3;
            id_ex_alu_ctrl  <= ctrl_alu_ctrl;
            id_ex_reg_write <= ctrl_reg_write;
            id_ex_mem_read  <= ctrl_mem_read;
            id_ex_mem_write <= ctrl_mem_write;
            id_ex_alu_src   <= ctrl_alu_src;
            id_ex_mem_to_reg<= ctrl_mem_to_reg;
            id_ex_branch    <= ctrl_branch;
            id_ex_jal       <= ctrl_jal;
            id_ex_jalr      <= ctrl_jalr;
            id_ex_lui       <= ctrl_lui;
            id_ex_auipc     <= ctrl_auipc;
            id_ex_valid     <= if_id_valid;
        end
    end

    // =========================================================================
    // EX Stage — Execute
    // =========================================================================

    // Forwarding MUXes
    reg [31:0] ex_alu_a, ex_alu_b_raw;
    wire [31:0] ex_mem_alu_result;
    wire [31:0] wb_result;

    always @(*) begin
        case (forward_a)
            2'b01:   ex_alu_a = ex_mem_alu_result;  // Forward from MEM
            2'b10:   ex_alu_a = wb_rd_data;          // Forward from WB
            default: ex_alu_a = id_ex_rs1_data;      // No forward
        endcase
    end

    always @(*) begin
        case (forward_b)
            2'b01:   ex_alu_b_raw = ex_mem_alu_result;
            2'b10:   ex_alu_b_raw = wb_rd_data;
            default: ex_alu_b_raw = id_ex_rs2_data;
        endcase
    end

    // ALU input B: register or immediate
    wire [31:0] ex_alu_b = id_ex_alu_src ? id_ex_imm : ex_alu_b_raw;

    // ALU input A for special instructions
    wire [31:0] ex_alu_in_a = id_ex_auipc ? id_ex_pc : ex_alu_a;

    // ALU
    wire [31:0] alu_result;
    wire        alu_zero;

    alu u_alu (
        .a       (ex_alu_in_a),
        .b       (ex_alu_b),
        .alu_ctrl(id_ex_alu_ctrl),
        .result  (alu_result),
        .zero    (alu_zero)
    );

    // EX result MUX (LUI passes immediate, JAL/JALR passes PC+4)
    wire [31:0] ex_result = id_ex_lui  ? id_ex_imm :
                            (id_ex_jal || id_ex_jalr) ? (id_ex_pc + 32'd4) :
                            alu_result;

    // Branch target computation
    wire [31:0] branch_pc_target = id_ex_pc + id_ex_imm;
    wire [31:0] jalr_target      = {alu_result[31:1], 1'b0};
    assign branch_target = id_ex_jalr ? jalr_target : branch_pc_target;

    // Branch comparison logic
    reg branch_cond;
    always @(*) begin
        case (id_ex_funct3)
            3'b000:  branch_cond = (ex_alu_a == ex_alu_b_raw);                     // BEQ
            3'b001:  branch_cond = (ex_alu_a != ex_alu_b_raw);                     // BNE
            3'b100:  branch_cond = ($signed(ex_alu_a) < $signed(ex_alu_b_raw));    // BLT
            3'b101:  branch_cond = ($signed(ex_alu_a) >= $signed(ex_alu_b_raw));   // BGE
            3'b110:  branch_cond = (ex_alu_a < ex_alu_b_raw);                      // BLTU
            3'b111:  branch_cond = (ex_alu_a >= ex_alu_b_raw);                     // BGEU
            default: branch_cond = 1'b0;
        endcase
    end

    assign branch_taken = id_ex_valid && (id_ex_jal || id_ex_jalr ||
                          (id_ex_branch && branch_cond));

    // =========================================================================
    // EX/MEM Pipeline Register
    // =========================================================================
    reg [31:0] ex_mem_result;
    reg [31:0] ex_mem_rs2_data;
    reg [4:0]  ex_mem_rd;
    reg [2:0]  ex_mem_funct3;
    reg        ex_mem_reg_write, ex_mem_mem_read, ex_mem_mem_write;
    reg        ex_mem_mem_to_reg;
    reg        ex_mem_valid;
    reg [31:0] ex_mem_pc;

    assign ex_mem_alu_result = ex_mem_result;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ex_mem_result    <= 32'd0;
            ex_mem_rs2_data  <= 32'd0;
            ex_mem_rd        <= 5'd0;
            ex_mem_funct3    <= 3'd0;
            ex_mem_reg_write <= 1'b0;
            ex_mem_mem_read  <= 1'b0;
            ex_mem_mem_write <= 1'b0;
            ex_mem_mem_to_reg<= 1'b0;
            ex_mem_valid     <= 1'b0;
            ex_mem_pc        <= 32'd0;
        end else if (!dmem_stall) begin
            ex_mem_result    <= ex_result;
            ex_mem_rs2_data  <= ex_alu_b_raw; // Store data (not immediate)
            ex_mem_rd        <= id_ex_rd;
            ex_mem_funct3    <= id_ex_funct3;
            ex_mem_reg_write <= id_ex_reg_write;
            ex_mem_mem_read  <= id_ex_mem_read;
            ex_mem_mem_write <= id_ex_mem_write;
            ex_mem_mem_to_reg<= id_ex_mem_to_reg;
            ex_mem_valid     <= id_ex_valid;
            ex_mem_pc        <= id_ex_pc;
        end
    end

    // =========================================================================
    // MEM Stage — Memory Access (connects to L1 cache)
    // =========================================================================
    assign dmem_addr   = ex_mem_result;
    assign dmem_wdata  = ex_mem_rs2_data;
    assign dmem_we     = ex_mem_mem_write && ex_mem_valid;
    assign dmem_re     = ex_mem_mem_read && ex_mem_valid;
    assign dmem_funct3 = ex_mem_funct3;
    assign dmem_pc     = ex_mem_pc;

    // =========================================================================
    // MEM/WB Pipeline Register
    // =========================================================================
    // reg [31:0] mem_wb_pc; // Moved to top for Vivado compliance
    reg [31:0] mem_wb_alu_result;
    reg [31:0] mem_wb_mem_data;
    reg [4:0]  mem_wb_rd;
    reg        mem_wb_reg_write;
    reg        mem_wb_mem_to_reg;
    reg        mem_wb_valid;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            mem_wb_pc         <= 32'd0;
            mem_wb_alu_result <= 32'd0;
            mem_wb_mem_data   <= 32'd0;
            mem_wb_rd         <= 5'd0;
            mem_wb_reg_write  <= 1'b0;
            mem_wb_mem_to_reg <= 1'b0;
            mem_wb_valid      <= 1'b0;
        end else if (!dmem_stall) begin
            mem_wb_pc         <= ex_mem_pc;
            mem_wb_alu_result <= ex_mem_result;
            mem_wb_mem_data   <= dmem_rdata;
            mem_wb_rd         <= ex_mem_rd;
            mem_wb_reg_write  <= ex_mem_reg_write;
            mem_wb_mem_to_reg <= ex_mem_mem_to_reg;
            mem_wb_valid      <= ex_mem_valid;
        end
    end

    // =========================================================================
    // WB Stage — Write Back
    // =========================================================================
    assign wb_rd_data   = mem_wb_mem_to_reg ? mem_wb_mem_data : mem_wb_alu_result;
    assign wb_rd_addr   = mem_wb_rd;
    assign wb_reg_write = mem_wb_reg_write && mem_wb_valid;
    assign wb_result    = wb_rd_data;
    assign instr_valid  = mem_wb_valid && !dmem_stall;

    // =========================================================================
    // Hazard Unit
    // =========================================================================
    hazard_unit u_hazard (
        // Forwarding
        .id_ex_rs1       (id_ex_rs1),
        .id_ex_rs2       (id_ex_rs2),
        .ex_mem_rd       (ex_mem_rd),
        .ex_mem_reg_write(ex_mem_reg_write),
        .mem_wb_rd       (mem_wb_rd),
        .mem_wb_reg_write(mem_wb_reg_write),
        .forward_a       (forward_a),
        .forward_b       (forward_b),
        // Load-use stall
        .if_id_opcode    (id_opcode),
        .if_id_rs1       (id_rs1),
        .if_id_rs2       (id_rs2),
        .id_ex_rd        (id_ex_rd),
        .id_ex_mem_read  (id_ex_mem_read),
        .stall           (hz_stall),
        // Branch flush
        .branch_taken    (branch_taken),
        .flush           (hz_flush)
    );

endmodule
