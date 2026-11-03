// =============================================================================
// trace_pkg.sv — Processor Trace VIP Package and RV32 Disassembler
// =============================================================================
`timescale 1ns/1ps

package trace_pkg;

    typedef struct {
        logic [31:0] pc;
        logic [31:0] insn;
        bit          is_exception;
        logic [4:0]  ecause;
        bit          is_interrupt;
        logic [31:0] tval;
        time         timestamp;
    } trace_event_t;

    // Decode RV32 exception cause code
    function automatic string decode_ecause(logic [4:0] ecause);
        case (ecause)
            5'd0:  return "Instruction address misaligned";
            5'd1:  return "Instruction access fault";
            5'd2:  return "Illegal instruction";
            5'd3:  return "Breakpoint / EBREAK";
            5'd4:  return "Load address misaligned";
            5'd5:  return "Load access fault";
            5'd6:  return "Store/AMO address misaligned";
            5'd7:  return "Store/AMO access fault";
            5'd8:  return "Environment call from U-mode";
            5'd11: return "Environment call from M-mode / ECALL";
            default: return $sformatf("Reserved / Unknown cause (%0d)", ecause);
        endcase
    endfunction

    // Compact RV32 Disassembler Helper
    function automatic string disasm_rv32(logic [31:0] insn);
        logic [6:0] opcode = insn[6:0];
        logic [2:0] funct3 = insn[14:12];
        logic [6:0] funct7 = insn[31:25];
        logic [4:0] rd     = insn[11:7];
        logic [4:0] rs1    = insn[19:15];
        logic [4:0] rs2    = insn[24:20];

        // RVC compressed instruction (ends in 2'b00, 2'b01, 2'b10)
        if (insn[1:0] != 2'b11) begin
            return $sformatf("C.INSN [0x%04h]", insn[15:0]);
        end

        case (opcode)
            7'b0110111: return $sformatf("LUI   x%0d, 0x%05h", rd, insn[31:12]);
            7'b0010111: return $sformatf("AUIPC x%0d, 0x%05h", rd, insn[31:12]);
            7'b1101111: return $sformatf("JAL   x%0d", rd);
            7'b1100111: return $sformatf("JALR  x%0d, x%0d, %0d", rd, rs1, $signed(insn[31:20]));
            7'b1100011: begin // Branch
                case (funct3)
                    3'b000: return $sformatf("BEQ   x%0d, x%0d", rs1, rs2);
                    3'b001: return $sformatf("BNE   x%0d, x%0d", rs1, rs2);
                    3'b100: return $sformatf("BLT   x%0d, x%0d", rs1, rs2);
                    3'b101: return $sformatf("BGE   x%0d, x%0d", rs1, rs2);
                    3'b110: return $sformatf("BLTU  x%0d, x%0d", rs1, rs2);
                    3'b111: return $sformatf("BGEU  x%0d, x%0d", rs1, rs2);
                    default: return "BRANCH";
                endcase
            end
            7'b0000011: begin // Load
                case (funct3)
                    3'b000: return $sformatf("LB    x%0d, %0d(x%0d)", rd, $signed(insn[31:20]), rs1);
                    3'b001: return $sformatf("LH    x%0d, %0d(x%0d)", rd, $signed(insn[31:20]), rs1);
                    3'b010: return $sformatf("LW    x%0d, %0d(x%0d)", rd, $signed(insn[31:20]), rs1);
                    3'b100: return $sformatf("LBU   x%0d, %0d(x%0d)", rd, $signed(insn[31:20]), rs1);
                    3'b101: return $sformatf("LHU   x%0d, %0d(x%0d)", rd, $signed(insn[31:20]), rs1);
                    default: return "LOAD";
                endcase
            end
            7'b0100011: begin // Store
                case (funct3)
                    3'b000: return $sformatf("SB    x%0d, (x%0d)", rs2, rs1);
                    3'b001: return $sformatf("SH    x%0d, (x%0d)", rs2, rs1);
                    3'b010: return $sformatf("SW    x%0d, (x%0d)", rs2, rs1);
                    default: return "STORE";
                endcase
            end
            7'b0010011: begin // OP-IMM
                case (funct3)
                    3'b000: return (rs1 == 0 && insn[31:20] == 0) ? "NOP" : $sformatf("ADDI  x%0d, x%0d, %0d", rd, rs1, $signed(insn[31:20]));
                    3'b010: return $sformatf("SLTI  x%0d, x%0d, %0d", rd, rs1, $signed(insn[31:20]));
                    3'b011: return $sformatf("SLTIU x%0d, x%0d, %0d", rd, rs1, $signed(insn[31:20]));
                    3'b100: return $sformatf("XORI  x%0d, x%0d, 0x%03h", rd, rs1, insn[31:20]);
                    3'b110: return $sformatf("ORI   x%0d, x%0d, 0x%03h", rd, rs1, insn[31:20]);
                    3'b111: return $sformatf("ANDI  x%0d, x%0d, 0x%03h", rd, rs1, insn[31:20]);
                    3'b001: return $sformatf("SLLI  x%0d, x%0d, %0d", rd, rs1, insn[24:20]);
                    3'b101: return (funct7[5]) ? $sformatf("SRAI  x%0d, x%0d, %0d", rd, rs1, insn[24:20]) : $sformatf("SRLI  x%0d, x%0d, %0d", rd, rs1, insn[24:20]);
                    default: return "OP-IMM";
                endcase
            end
            7'b0110011: begin // OP
                if (funct7 == 7'b0000001) return $sformatf("M-EXT x%0d, x%0d, x%0d", rd, rs1, rs2);
                case (funct3)
                    3'b000: return (funct7[5]) ? $sformatf("SUB   x%0d, x%0d, x%0d", rd, rs1, rs2) : $sformatf("ADD   x%0d, x%0d, x%0d", rd, rs1, rs2);
                    3'b001: return $sformatf("SLL   x%0d, x%0d, x%0d", rd, rs1, rs2);
                    3'b010: return $sformatf("SLT   x%0d, x%0d, x%0d", rd, rs1, rs2);
                    3'b011: return $sformatf("SLTU  x%0d, x%0d, x%0d", rd, rs1, rs2);
                    3'b100: return $sformatf("XOR   x%0d, x%0d, x%0d", rd, rs1, rs2);
                    3'b101: return (funct7[5]) ? $sformatf("SRA   x%0d, x%0d, x%0d", rd, rs1, rs2) : $sformatf("SRL   x%0d, x%0d, x%0d", rd, rs1, rs2);
                    3'b110: return $sformatf("OR    x%0d, x%0d, x%0d", rd, rs1, rs2);
                    3'b111: return $sformatf("AND   x%0d, x%0d, x%0d", rd, rs1, rs2);
                    default: return "OP";
                endcase
            end
            7'b1110011: begin // SYSTEM / CSR
                case (funct3)
                    3'b000: return (insn[20]) ? "EBREAK" : "ECALL";
                    3'b001: return $sformatf("CSRRW x%0d, CSR[0x%03h], x%0d", rd, insn[31:20], rs1);
                    3'b010: return $sformatf("CSRRS x%0d, CSR[0x%03h], x%0d", rd, insn[31:20], rs1);
                    3'b011: return $sformatf("CSRRC x%0d, CSR[0x%03h], x%0d", rd, insn[31:20], rs1);
                    default: return "SYSTEM";
                endcase
            end
            default: return $sformatf("RAW[0x%08h]", insn);
        endcase
    endfunction

endpackage: trace_pkg

