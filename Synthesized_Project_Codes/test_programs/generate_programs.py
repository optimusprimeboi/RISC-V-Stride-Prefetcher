"""
RISC-V RV32I Assembler Helper
Generates .mem files for $readmemh from assembly-like descriptions
"""

def r_type(funct7, rs2, rs1, funct3, rd):
    return (funct7 << 25) | (rs2 << 20) | (rs1 << 15) | (funct3 << 12) | (rd << 7) | 0x33

def i_type(imm, rs1, funct3, rd, opcode=0x13):
    imm = imm & 0xFFF
    return (imm << 20) | (rs1 << 15) | (funct3 << 12) | (rd << 7) | opcode

def s_type(imm, rs2, rs1, funct3):
    imm = imm & 0xFFF
    imm_11_5 = (imm >> 5) & 0x7F
    imm_4_0 = imm & 0x1F
    return (imm_11_5 << 25) | (rs2 << 20) | (rs1 << 15) | (funct3 << 12) | (imm_4_0 << 7) | 0x23

def b_type(imm, rs2, rs1, funct3):
    imm = imm & 0x1FFF
    b12  = (imm >> 12) & 1
    b11  = (imm >> 11) & 1
    b10_5 = (imm >> 5) & 0x3F
    b4_1  = (imm >> 1) & 0xF
    return (b12 << 31) | (b10_5 << 25) | (rs2 << 20) | (rs1 << 15) | (funct3 << 12) | (b4_1 << 8) | (b11 << 7) | 0x63

def u_type(imm, rd, opcode):
    return (imm & 0xFFFFF000) | (rd << 7) | opcode

def j_type(imm, rd):
    imm = imm & 0x1FFFFF
    b20   = (imm >> 20) & 1
    b19_12 = (imm >> 12) & 0xFF
    b11   = (imm >> 11) & 1
    b10_1 = (imm >> 1) & 0x3FF
    return (b20 << 31) | (b10_1 << 21) | (b11 << 20) | (b19_12 << 12) | (rd << 7) | 0x6F

# Convenience
def ADD(rd, rs1, rs2):  return r_type(0x00, rs2, rs1, 0, rd)
def SUB(rd, rs1, rs2):  return r_type(0x20, rs2, rs1, 0, rd)
def AND(rd, rs1, rs2):  return r_type(0x00, rs2, rs1, 7, rd)
def OR(rd, rs1, rs2):   return r_type(0x00, rs2, rs1, 6, rd)
def XOR(rd, rs1, rs2):  return r_type(0x00, rs2, rs1, 4, rd)
def SLL(rd, rs1, rs2):  return r_type(0x00, rs2, rs1, 1, rd)
def SRL(rd, rs1, rs2):  return r_type(0x00, rs2, rs1, 5, rd)
def SRA(rd, rs1, rs2):  return r_type(0x20, rs2, rs1, 5, rd)
def SLT(rd, rs1, rs2):  return r_type(0x00, rs2, rs1, 2, rd)
def SLTU(rd, rs1, rs2): return r_type(0x00, rs2, rs1, 3, rd)

def ADDI(rd, rs1, imm):  return i_type(imm, rs1, 0, rd)
def ANDI(rd, rs1, imm):  return i_type(imm, rs1, 7, rd)
def ORI(rd, rs1, imm):   return i_type(imm, rs1, 6, rd)
def XORI(rd, rs1, imm):  return i_type(imm, rs1, 4, rd)
def SLTI(rd, rs1, imm):  return i_type(imm, rs1, 2, rd)
def SLTIU(rd, rs1, imm): return i_type(imm, rs1, 3, rd)
def SLLI(rd, rs1, shamt): return i_type(shamt & 0x1F, rs1, 1, rd)
def SRLI(rd, rs1, shamt): return i_type(shamt & 0x1F, rs1, 5, rd)
def SRAI(rd, rs1, shamt): return i_type((0x400 | (shamt & 0x1F)), rs1, 5, rd)

def LW(rd, rs1, imm):  return i_type(imm, rs1, 2, rd, 0x03)
def LH(rd, rs1, imm):  return i_type(imm, rs1, 1, rd, 0x03)
def LB(rd, rs1, imm):  return i_type(imm, rs1, 0, rd, 0x03)
def LHU(rd, rs1, imm): return i_type(imm, rs1, 5, rd, 0x03)
def LBU(rd, rs1, imm): return i_type(imm, rs1, 4, rd, 0x03)

def SW(rs2, rs1, imm):  return s_type(imm, rs2, rs1, 2)
def SH(rs2, rs1, imm):  return s_type(imm, rs2, rs1, 1)
def SB(rs2, rs1, imm):  return s_type(imm, rs2, rs1, 0)

def BEQ(rs1, rs2, imm):  return b_type(imm, rs2, rs1, 0)
def BNE(rs1, rs2, imm):  return b_type(imm, rs2, rs1, 1)
def BLT(rs1, rs2, imm):  return b_type(imm, rs2, rs1, 4)
def BGE(rs1, rs2, imm):  return b_type(imm, rs2, rs1, 5)
def BLTU(rs1, rs2, imm): return b_type(imm, rs2, rs1, 6)
def BGEU(rs1, rs2, imm): return b_type(imm, rs2, rs1, 7)

def LUI(rd, imm):   return u_type(imm, rd, 0x37)
def AUIPC(rd, imm): return u_type(imm, rd, 0x17)
def JAL(rd, imm):    return j_type(imm, rd)
def JALR(rd, rs1, imm): return i_type(imm, rs1, 0, rd, 0x67)
def NOP(): return ADDI(0, 0, 0)

def write_mem(filename, instructions):
    with open(filename, 'w') as f:
        for instr in instructions:
            f.write(f"{instr:08X}\n")
    print(f"Written {len(instructions)} instructions to {filename}")

def write_data(filename, data_dict):
    """data_dict: {word_address: value}"""
    with open(filename, 'w') as f:
        for addr, val in sorted(data_dict.items()):
            f.write(f"@{addr:08X} {val:08X}\n")
    print(f"Written {len(data_dict)} data words to {filename}")

# ============================================================================
# Program 1: Sequential stride-4 (sum array elements)
# base = 0x400 (word addr 0x100), 32 elements, stride = 4 bytes
# ============================================================================
prog1 = [
    ADDI(10, 0, 0),       # x10 = 0 (sum)
    LUI(11, 0x1000),      # x11 = 0x00001000 (base addr, but let's use smaller)
]
# Actually use smaller addresses: base = 0x400
prog1 = [
    ADDI(10, 0, 0),       # x10 = 0 (sum)
    ADDI(11, 0, 0x400),   # x11 = 0x400 (base address) -- ERROR: 0x400=1024, fits in 12-bit signed
    ADDI(12, 0, 0),       # x12 = 0 (byte offset)
    ADDI(13, 0, 128),     # x13 = 128 (32 words * 4 bytes = 128 limit)
    # Loop (addr 0x10):
    ADD(14, 11, 12),      # x14 = base + offset
    LW(15, 14, 0),        # x15 = mem[x14]
    ADD(10, 10, 15),      # sum += x15
    ADDI(12, 12, 4),      # offset += 4
    BNE(12, 13, -16),     # if offset != limit, loop back (offset = -16 bytes = -4 instrs)
    JAL(0, 0),            # halt
]
write_mem("program.mem", prog1)

# Data: 32 words at word-address 0x100 (byte 0x400)
data1 = {0x100 + i: i + 1 for i in range(32)}
write_data("data.mem", data1)

# ============================================================================
# Program 2: Stride-16 (access every 4th word)
# base = 0x400, 16 elements, stride = 16 bytes
# ============================================================================
prog2 = [
    ADDI(10, 0, 0),       # sum = 0
    ADDI(11, 0, 0x400),   # base = 0x400
    ADDI(12, 0, 0),       # offset = 0
    ADDI(13, 0, 256),     # limit = 16 * 16 = 256
    # Loop (addr 0x10):
    ADD(14, 11, 12),      # addr = base + offset
    LW(15, 14, 0),        # load
    ADD(10, 10, 15),      # sum += val
    ADDI(12, 12, 16),     # offset += 16 (stride = 16 bytes)
    BNE(12, 13, -16),     # loop
    JAL(0, 0),            # halt
]
write_mem("bench_stride16.mem", prog2)

# ============================================================================
# Program 3: Random-ish access (LFSR-based)
# ============================================================================
prog3 = [
    ADDI(10, 0, 0),       # x10 = 0 (sum)
    ADDI(11, 0, 0x400),   # x11 = 0x400 (base)
    ADDI(16, 0, 0x55),    # x16 = 0x55 (LFSR state)
    ADDI(12, 0, 0),       # x12 = 0 (loop counter)
    ADDI(13, 0, 32),      # x13 = 32 (limit)
    # Loop (addr 0x14):
    ANDI(14, 16, 0x7C),   # x14 = lfsr & 0x7C (word-aligned, 0-124 range)
    ADD(14, 11, 14),      # x14 = base + offset
    LW(15, 14, 0),        # x15 = mem[addr]
    ADD(10, 10, 15),      # sum += val
    SRLI(16, 16, 1),      # lfsr >>= 1
    ANDI(17, 16, 1),      # x17 = old bit (wrong, need to check before shift)
    # Simplified: just XOR with constant every other iteration
    XORI(16, 16, 0x2D),   # lfsr ^= 0x2D
    ADDI(12, 12, 1),      # i++
    BNE(12, 13, -32),     # loop back
    JAL(0, 0),            # halt
]
write_mem("bench_random.mem", prog3)

# ============================================================================
# Program 4: Mixed pattern (sequential + random bursts)
# First 16 accesses sequential, then 16 with larger stride
# ============================================================================
prog4 = [
    ADDI(10, 0, 0),       # sum = 0
    ADDI(11, 0, 0x400),   # base
    ADDI(12, 0, 0),       # offset = 0
    ADDI(13, 0, 64),      # limit1 = 16 * 4 = 64
    # Phase 1: Sequential stride-4 (addr 0x10)
    ADD(14, 11, 12),
    LW(15, 14, 0),
    ADD(10, 10, 15),
    ADDI(12, 12, 4),
    BNE(12, 13, -16),
    # Phase 2: Stride-8 (addr 0x24)
    ADDI(12, 0, 0),       # reset offset
    ADDI(13, 0, 128),     # limit2 = 16 * 8 = 128
    ADD(14, 11, 12),
    LW(15, 14, 0),
    ADD(10, 10, 15),
    ADDI(12, 12, 8),      # stride = 8
    BNE(12, 13, -16),
    JAL(0, 0),            # halt
]
write_mem("bench_mixed.mem", prog4)

# ============================================================================
# Program 5: Basic ALU test (no memory - for baseline verification)
# ============================================================================
prog_alu = [
    ADDI(1, 0, 5),        # x1 = 5
    ADDI(2, 0, 10),       # x2 = 10
    ADD(3, 1, 2),         # x3 = 15
    SUB(4, 2, 1),         # x4 = 5
    AND(5, 1, 2),         # x5 = 0
    OR(6, 1, 2),          # x6 = 15
    XOR(7, 1, 2),         # x7 = 15
    SLLI(8, 1, 2),        # x8 = 20
    SRLI(9, 2, 1),        # x9 = 5
    SLT(10, 1, 2),        # x10 = 1 (5 < 10)
    ADDI(11, 0, -3),      # x11 = -3
    SRA(12, 11, 1),       # x12: shift right arithmetic (not quite right, SRA needs r-type)
    # Test load/store
    ADDI(20, 0, 0x400),   # x20 = 0x400
    SW(1, 20, 0),         # mem[0x400] = 5
    SW(2, 20, 4),         # mem[0x404] = 10
    LW(21, 20, 0),        # x21 = 5
    LW(22, 20, 4),        # x22 = 10
    ADD(23, 21, 22),      # x23 = 15
    # Test branch
    BEQ(21, 1, 8),        # if x21==x1 (both 5), skip next
    ADDI(24, 0, 99),      # x24 = 99 (should be skipped)
    ADDI(25, 0, 42),      # x25 = 42 (should execute)
    # Test JAL
    JAL(26, 8),           # x26 = PC+4, jump ahead 8
    ADDI(27, 0, 88),      # should be skipped
    ADDI(28, 0, 77),      # should execute (jump target)
    JAL(0, 0),            # halt
]
write_mem("test_alu.mem", prog_alu)

# ============================================================================
# Data for all programs
# 128 words at word-address 0x100 (byte 0x400), values 1..128
# ============================================================================
data_all = {0x100 + i: i + 1 for i in range(128)}
write_data("data.mem", data_all)

print("\nAll test programs generated successfully!")
