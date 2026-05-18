//============================================================================
// Instruction Memory — Single-port BRAM, word-addressed
// Loaded from hex file via $readmemh
// Rev 2 — forces xsim re-elaboration so updated .mem files are loaded
//============================================================================
`timescale 1ns / 1ps

module instruction_memory #(
    parameter DEPTH     = 1024,       // Number of 32-bit words
    parameter INIT_FILE = "program.mem"
)(
    input  wire [31:0] addr,
    output wire [31:0] rdata
);

    localparam ADDR_BITS = $clog2(DEPTH);

    (* ram_style = "block" *) reg [31:0] mem [0:DEPTH-1];

    // Word-addressed: use bounded slice to stay within declared depth
    wire [ADDR_BITS-1:0] word_addr = addr[ADDR_BITS+1:2];

    assign rdata = mem[word_addr];

    initial begin
        $readmemh(INIT_FILE, mem);
    end

endmodule
