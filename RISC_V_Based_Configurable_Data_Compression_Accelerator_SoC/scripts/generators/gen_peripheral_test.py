#!/usr/bin/env python3
"""
gen_peripheral_test.py
Generates machine code for VeeR EL2 Peripheral Integration Test.
"""

# Register mapping
REG = {
    'x0': 0, 'zero': 0,
    'x1': 1, 'ra': 1,
    'x2': 2, 'sp': 2,
    'x3': 3, 'gp': 3,
    'x4': 4, 'tp': 4,
    'x5': 5, 't0': 5,
    'x6': 6, 't1': 6,
    'x7': 7, 't2': 7,
    'x8': 8, 's0': 8, 'fp': 8,
    'x9': 9, 's1': 9,
    'x10': 10, 'a0': 10,
    'x11': 11, 'a1': 11,
    'x12': 12, 'a2': 12,
    'x13': 13, 'a3': 13,
    'x14': 14, 'a4': 14,
    'x15': 15, 'a5': 15,
    'x16': 16, 'a6': 16,
    'x17': 17, 'a7': 17,
    'x18': 18, 's2': 18,
    'x19': 19, 's3': 19,
    'x20': 20, 's4': 20,
    'x21': 21, 's5': 21,
    'x22': 22, 's6': 22,
    'x23': 23, 's7': 23,
    'x24': 24, 's8': 24,
    'x25': 25, 's9': 25,
    'x26': 26, 's10': 26,
    'x27': 27, 's11': 27,
    'x28': 28, 't3': 28,
    'x29': 29, 't4': 29,
    'x30': 30, 't5': 30,
    'x31': 31, 't6': 31,
}

def r_type(funct7, rs2, rs1, funct3, rd, opcode):
    return ((funct7 & 0x7F) << 25) | ((REG[rs2] & 0x1F) << 20) | ((REG[rs1] & 0x1F) << 15) | ((funct3 & 0x7) << 12) | ((REG[rd] & 0x1F) << 7) | (opcode & 0x7F)

def i_type(imm, rs1, funct3, rd, opcode):
    imm12 = imm & 0xFFF
    return (imm12 << 20) | ((REG[rs1] & 0x1F) << 15) | ((funct3 & 0x7) << 12) | ((REG[rd] & 0x1F) << 7) | (opcode & 0x7F)

def s_type(imm, rs2, rs1, funct3, opcode):
    imm12 = imm & 0xFFF
    imm11_5 = (imm12 >> 5) & 0x7F
    imm4_0  = imm12 & 0x1F
    return (imm11_5 << 25) | ((REG[rs2] & 0x1F) << 20) | ((REG[rs1] & 0x1F) << 15) | ((funct3 & 0x7) << 12) | (imm4_0 << 7) | (opcode & 0x7F)

def b_type(imm, rs2, rs1, funct3, opcode):
    imm13 = imm & 0x1FFF
    b12   = (imm13 >> 12) & 1
    b10_5 = (imm13 >> 5) & 0x3F
    b4_1  = (imm13 >> 1) & 0xF
    b11   = (imm13 >> 11) & 1
    return (b12 << 31) | (b10_5 << 25) | ((REG[rs2] & 0x1F) << 20) | ((REG[rs1] & 0x1F) << 15) | ((funct3 & 0x7) << 12) | (b4_1 << 8) | (b11 << 7) | (opcode & 0x7F)

def u_type(imm, rd, opcode):
    imm20 = (imm >> 12) & 0xFFFFF
    return (imm20 << 12) | ((REG[rd] & 0x1F) << 7) | (opcode & 0x7F)

def j_type(imm, rd, opcode):
    imm21 = imm & 0x1FFFFF
    b20   = (imm21 >> 20) & 1
    b10_1 = (imm21 >> 1) & 0x3FF
    b11   = (imm21 >> 11) & 1
    b19_12= (imm21 >> 12) & 0xFF
    return (b20 << 31) | (b10_1 << 21) | (b11 << 20) | (b19_12 << 12) | ((REG[rd] & 0x1F) << 7) | (opcode & 0x7F)

class Assembler:
    def __init__(self, base_pc=0x80000000):
        self.base_pc = base_pc
        self.instructions = [] # tuples of (generator_fn, asm_text, label)
        self.labels = {}

    def label(self, name):
        self.labels[name] = self.base_pc + len(self.instructions) * 4

    def add(self, fn, text):
        self.instructions.append((fn, text))

    def lui(self, rd, imm20):
        self.add(lambda pc: u_type(imm20 << 12, rd, 0x37), f"lui {rd}, 0x{imm20:05x}")

    def addi(self, rd, rs1, imm):
        self.add(lambda pc: i_type(imm, rs1, 0x0, rd, 0x13), f"addi {rd}, {rs1}, {imm}")

    def andi(self, rd, rs1, imm):
        self.add(lambda pc: i_type(imm, rs1, 0x7, rd, 0x13), f"andi {rd}, {rs1}, {imm}")

    def lw(self, rd, rs1, imm):
        self.add(lambda pc: i_type(imm, rs1, 0x2, rd, 0x03), f"lw {rd}, {imm}({rs1})")

    def sw(self, rs2, rs1, imm):
        self.add(lambda pc: s_type(imm, rs2, rs1, 0x2, 0x23), f"sw {rs2}, {imm}({rs1})")

    def beq(self, rs1, rs2, target_label):
        def gen(pc):
            offset = self.labels[target_label] - pc
            return b_type(offset, rs2, rs1, 0x0, 0x63)
        self.add(gen, f"beq {rs1}, {rs2}, {target_label}")

    def bne(self, rs1, rs2, target_label):
        def gen(pc):
            offset = self.labels[target_label] - pc
            return b_type(offset, rs2, rs1, 0x1, 0x63)
        self.add(gen, f"bne {rs1}, {rs2}, {target_label}")

    def beqz(self, rs1, target_label):
        self.bne(rs1, 'zero', target_label) if False else self.beq(rs1, 'zero', target_label)

    def bnez(self, rs1, target_label):
        self.bne(rs1, 'zero', target_label)

    def jal(self, rd, target_label):
        def gen(pc):
            offset = self.labels[target_label] - pc
            return j_type(offset, rd, 0x6F)
        self.add(gen, f"jal {rd}, {target_label}")

    def j(self, target_label):
        self.jal('zero', target_label)

    def csrw(self, csr, rs1):
        self.add(lambda pc: i_type(csr, rs1, 0x1, 'zero', 0x73), f"csrw 0x{csr:03x}, {rs1}")

    def fence(self):
        self.add(lambda pc: 0x0FF0000F, "fence")

    def li(self, rd, val):
        val = val & 0xFFFFFFFF
        if val < 2048 or val >= 0xFFFFF800:
            imm = val if val < 2048 else val - 0x100000000
            self.addi(rd, 'zero', imm)
        else:
            imm12 = val & 0xFFF
            if imm12 >= 2048:
                imm12 -= 4096
                hi = ((val - imm12) >> 12) & 0xFFFFF
            else:
                hi = (val >> 12) & 0xFFFFF
            self.lui(rd, hi)
            if imm12 != 0:
                self.addi(rd, rd, imm12)

    def assemble(self):
        code = []
        for i, (fn, text) in enumerate(self.instructions):
            pc = self.base_pc + i * 4
            word = fn(pc) & 0xFFFFFFFF
            code.append((pc, word, text))
        return code

asm = Assembler(0x80000000)

# ==============================================================================
# VeeR Peripheral Integration Test Program
# ==============================================================================

# 1. Setup MRAC CSR (0x7c0): Region 0 (DMEM) side-effect, Region 1 (MMIO) side-effect
# mrac = 0x0000000A (Region 1 bit 3=1, Region 0 bit 1=1)
asm.li('t0', 0x0000000A)
asm.csrw(0x7C0, 't0')
asm.fence()

# 2. Setup DMEM base address (s0 = 0x00040000)
asm.li('s0', 0x00040000)

# ==============================================================================
# TEST 1: GPIO (Base: 0x10002000)
# ==============================================================================
asm.label("test_gpio")
asm.li('t1', 0x10002000)

# 1.1 DIR register (offset 0x08): write 0x000000FF, read back
asm.li('t2', 0x000000FF)
asm.sw('t2', 't1', 8)
asm.lw('t3', 't1', 8)
asm.bne('t2', 't3', 'fail_gpio_dir')

# 1.2 DATA_OUT register (offset 0x04): write 0x000000A5, read back
asm.li('t2', 0x000000A5)
asm.sw('t2', 't1', 4)
asm.lw('t3', 't1', 4)
asm.bne('t2', 't3', 'fail_gpio_data')

# 1.3 SET_OUT atomic register (offset 0x1C): set bit 4 (0x10) -> 0xA5 | 0x10 = 0xB5
asm.li('t2', 0x00000010)
asm.sw('t2', 't1', 0x1C)
asm.lw('t3', 't1', 4)
asm.li('t4', 0x000000B5)
asm.bne('t3', 't4', 'fail_gpio_set')

# 1.4 CLR_OUT atomic register (offset 0x20): clear bit 0 (0x01) -> 0xB5 & ~0x01 = 0xB4
asm.li('t2', 0x00000001)
asm.sw('t2', 't1', 0x20)
asm.lw('t3', 't1', 4)
asm.li('t4', 0x000000B4)
asm.bne('t3', 't4', 'fail_gpio_clr')

# GPIO passed -> store signature 0x69100001 to DMEM[1] (0x00040004)
asm.li('t2', 0x69100001)
asm.sw('t2', 's0', 4)

# ==============================================================================
# TEST 2: Timer (Base: 0x10001000)
# ==============================================================================
asm.label("test_timer")
asm.li('t1', 0x10001000)

# 2.1 Set MTIMECMP_LOW (offset 0x08) = 0x00000064 (100)
asm.li('t2', 0x00000064)
asm.sw('t2', 't1', 8)
asm.lw('t3', 't1', 8)
asm.bne('t2', 't3', 'fail_timer_cmp')

# 2.2 Start timer: TIMER_CTRL (offset 0x10) = 1 (EN = 1)
asm.li('t2', 0x00000001)
asm.sw('t2', 't1', 0x10)
asm.lw('t3', 't1', 0x10)
asm.bne('t2', 't3', 'fail_timer_ctrl')

# 2.3 Spin for 25 cycles, then verify MTIME_LOW has incremented (> 0)
asm.li('t4', 25)
asm.label("timer_spin")
asm.addi('t4', 't4', -1)
asm.bnez('t4', 'timer_spin')

asm.lw('t3', 't1', 0)
asm.beqz('t3', 'fail_timer_count')

# Timer passed -> store signature 0x713E0002 to DMEM[2] (0x00040008)
asm.li('t2', 0x713E0002)
asm.sw('t2', 's0', 8)

# ==============================================================================
# TEST 3: UART (Base: 0x10000000)
# ==============================================================================
asm.label("test_uart")
asm.li('t1', 0x10000000)

# 3.1 Write UART_LCR (offset 0x0C) = 0x00000003, read back
asm.li('t2', 0x00000003)
asm.sw('t2', 't1', 0x0C)
asm.lw('t3', 't1', 0x0C)
asm.bne('t2', 't3', 'fail_uart_lcr')

# 3.2 Read UART_LSR (offset 0x14): verify THRE (bit 5) is 1
asm.lw('t3', 't1', 0x14)
asm.andi('t4', 't3', 0x20)
asm.beqz('t4', 'fail_uart_lsr')

# 3.3 Transmit bytes 'H' (0x48) and 'I' (0x49) via UART_THR (offset 0x00)
asm.li('t2', 0x00000048)
asm.sw('t2', 't1', 0)
asm.li('t2', 0x00000049)
asm.sw('t2', 't1', 0)

# UART passed -> store signature 0x0A270003 to DMEM[3] (0x0004000C)
asm.li('t2', 0x0A270003)
asm.sw('t2', 's0', 0x0C)

# ==============================================================================
# TEST 4: CRC-32 (Base: 0x10012000)
# ==============================================================================
asm.label("test_crc")
asm.li('t1', 0x10012000)

# 4.1 Write and read back CRC_INIT (offset 0x10)
asm.li('t2', 0x12345678)
asm.sw('t2', 't1', 0x10)
asm.lw('t3', 't1', 0x10)
asm.bne('t2', 't3', 'fail_crc_init')

# Restore standard initial value (0xFFFFFFFF)
asm.li('t2', 0xFFFFFFFF)
asm.sw('t2', 't1', 0x10)

# 4.2 Reset accumulator: CRC_CTRL (offset 0x08) = 1
asm.li('t2', 1)
asm.sw('t2', 't1', 8)

# 4.3 Feed word 0x34333231 ("1234") into CRC_DATA (offset 0x00)
asm.li('t2', 0x34333231)
asm.sw('t2', 't1', 0)

# 4.4 Check CRC_STATUS (offset 0x0C): byte_count should be 4
asm.lw('t3', 't1', 0x0C)
asm.andi('t4', 't3', 0x00FF)
asm.li('t5', 4)
asm.bne('t4', 't5', 'fail_crc_count')

# 4.5 Check CRC_RESULT (offset 0x04): should be non-zero
asm.lw('t3', 't1', 4)
asm.beqz('t3', 'fail_crc_res')

# CRC passed -> store signature 0xC2C30004 to DMEM[4] (0x00040010)
asm.li('t2', 0xC2C30004)
asm.sw('t2', 's0', 0x10)

# ==============================================================================
# TEST 5: RLE Accelerator (Base: 0x10010000)
# ==============================================================================
asm.label("test_rle")
asm.li('t1', 0x10010000)

# 5.1 Set REG_INPUT_LENGTH (offset 0x08) = 8
asm.li('t2', 8)
asm.sw('t2', 't1', 8)
asm.lw('t3', 't1', 8)
asm.bne('t2', 't3', 'fail_rle_len')

# 5.2 Set mode: REG_CONTROL (offset 0x00) bit 1 = 1 (decode mode)
asm.li('t2', 2)
asm.sw('t2', 't1', 0)
asm.lw('t3', 't1', 0)
asm.andi('t4', 't3', 2)
asm.beqz('t4', 'fail_rle_ctrl')

# Reset to encode mode (0)
asm.sw('zero', 't1', 0)

# 5.3 Read REG_STATUS (offset 0x04): busy (bit 0) should be 0
asm.lw('t3', 't1', 4)
asm.andi('t4', 't3', 1)
asm.bnez('t4', 'fail_rle_status')

# RLE passed -> store signature 0x21E00005 to DMEM[5] (0x00040014)
asm.li('t2', 0x21E00005)
asm.sw('t2', 's0', 0x14)

# ==============================================================================
# OVERALL SUCCESS
# ==============================================================================
asm.label("all_pass")
asm.li('t2', 0xCAFEF00D)
asm.sw('t2', 's0', 0)     # DMEM[0] = 0xCAFEF00D

asm.label("loop_success")
asm.j('loop_success')

# ==============================================================================
# FAILURE HANDLERS (Write unique error code to DMEM[0])
# ==============================================================================
asm.label("fail_gpio_dir")
asm.li('t2', 0xDEAD0011); asm.sw('t2', 's0', 0); asm.j('hang')

asm.label("fail_gpio_data")
asm.li('t2', 0xDEAD0012); asm.sw('t2', 's0', 0); asm.j('hang')

asm.label("fail_gpio_set")
asm.li('t2', 0xDEAD0013); asm.sw('t2', 's0', 0); asm.j('hang')

asm.label("fail_gpio_clr")
asm.li('t2', 0xDEAD0014); asm.sw('t2', 's0', 0); asm.j('hang')

asm.label("fail_timer_cmp")
asm.li('t2', 0xDEAD0021); asm.sw('t2', 's0', 0); asm.j('hang')

asm.label("fail_timer_ctrl")
asm.li('t2', 0xDEAD0022); asm.sw('t2', 's0', 0); asm.j('hang')

asm.label("fail_timer_count")
asm.li('t2', 0xDEAD0023); asm.sw('t2', 's0', 0); asm.j('hang')

asm.label("fail_uart_lcr")
asm.li('t2', 0xDEAD0031); asm.sw('t2', 's0', 0); asm.j('hang')

asm.label("fail_uart_lsr")
asm.li('t2', 0xDEAD0032); asm.sw('t2', 's0', 0); asm.j('hang')

asm.label("fail_crc_init")
asm.li('t2', 0xDEAD0041); asm.sw('t2', 's0', 0); asm.j('hang')

asm.label("fail_crc_count")
asm.li('t2', 0xDEAD0042); asm.sw('t2', 's0', 0); asm.j('hang')

asm.label("fail_crc_res")
asm.li('t2', 0xDEAD0043); asm.sw('t2', 's0', 0); asm.j('hang')

asm.label("fail_rle_len")
asm.li('t2', 0xDEAD0051); asm.sw('t2', 's0', 0); asm.j('hang')

asm.label("fail_rle_ctrl")
asm.li('t2', 0xDEAD0052); asm.sw('t2', 's0', 0); asm.j('hang')

asm.label("fail_rle_status")
asm.li('t2', 0xDEAD0053); asm.sw('t2', 's0', 0); asm.j('hang')

asm.label("hang")
asm.j('hang')

# Assemble
assembled = asm.assemble()
print(f"Total instructions: {len(assembled)}")

script_dir = os.path.dirname(os.path.abspath(__file__))
repo_root = os.path.abspath(os.path.join(script_dir, "..", ".."))
images_dir = os.path.join(repo_root, "firmware", "images")
os.makedirs(images_dir, exist_ok=True)

vh_path = os.path.join(images_dir, "peripheral_prog.vh")
hex_path = os.path.join(images_dir, "peripheral_prog.hex")

# Output Verilog initial block snippet
with open(vh_path, "w") as f:
    f.write("// Auto-generated peripheral test program\n")
    for i, (pc, word, text) in enumerate(assembled):
        f.write(f"u_dut.u_soc.u_imem.mem[{i}] = 32'h{word:08x}; // [0x{pc:08x}] {text}\n")

# Output hex file
with open(hex_path, "w") as f:
    for pc, word, text in assembled:
        f.write(f"{word:08x}\n")

print(f"Generated {vh_path} and {hex_path} successfully.")
