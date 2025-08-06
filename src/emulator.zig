const std = @import("std");

pub const Memory = struct {
    pub const SIZE = 1024 * 64; // 64 KB

    data: [SIZE]u8,

    pub fn init() Memory {
        return Memory {
            .data = [_]u8{0} ** SIZE,
        };
    }

    pub fn read(self: *const Memory, addr: u16) u8 {
        return self.data[addr];
    }

    pub fn write(self: *Memory, addr: u16, value: u8) void {
        self.data[addr] = value;
    }
};

pub const CPU = struct {
    // -----------------------------------------------------------------------------
    //                                  CONSTANTS                                   
    // -----------------------------------------------------------------------------

    pub const RESET_VECTOR: u16   = 0xFFFC;     // Load PC from reset vector
    pub const RESET_SP:     u8    = 0xFD;       // Starts at 0, then gets decremented 3 times
    pub const RESET_REG:    u8    = 0x00;       // Zero all registers
    pub const RESET_STATUS: u8    = 0b100100;   // Set I,U
    pub const RESET_CYCLES: u32   = 7;          // Reset sequence takes 7 cycles
    pub const TABLE_SIZE:   usize = 256;        // Instruction table size (16x16)
    pub const INTER_VECTOR: u16   = 0xFFFE;     // Interrupt vector used by BRK and IRQ
    pub const NMI_VECTOR:   u16   = 0xFFFA;     // Interrupt vector used by NMI

    pub const Flag = enum(u8) {
        C = 1 << 0, // Carry flag
        Z = 1 << 1, // Zero flag
        I = 1 << 2, // Interrupt disable
        D = 1 << 3, // Decimal mode
        B = 1 << 4, // Break command
        U = 1 << 5, // Unused
        V = 1 << 6, // Overflow flag
        N = 1 << 7, // Negative flag
    };

    pub const Opcode = enum(u8) {
        // LDA - Load accumulator
        LDA_IMM = 0xA9, LDA_ZPG = 0xA5, LDA_ZPX = 0xB5, LDA_ABS = 0xAD, LDA_ABX = 0xBD,
        LDA_ABY = 0xB9, LDA_IDX = 0xA1, LDA_IDY = 0xB1,

        // LDX - Load X register
        LDX_IMM = 0xA2, LDX_ZPG = 0xA6, LDX_ZPY = 0xB6, LDX_ABS = 0xAE, LDX_ABY = 0xBE,

        // LDY - Load Y register
        LDY_IMM = 0xA0, LDY_ZPG = 0xA4, LDY_ZPX = 0xB4, LDY_ABS = 0xAC, LDY_ABX = 0xBC,

        // STA - Store accumulator
        STA_ZPG = 0x85, STA_ZPX = 0x95, STA_ABS = 0x8D, STA_ABX = 0x9D, STA_ABY = 0x99,
        STA_IDX = 0x81, STA_IDY = 0x91,

        // STX - Store X register
        STX_ZPG = 0x86, STX_ZPY = 0x96, STX_ABS = 0x8E,

        // STY - Store Y register
        STY_ZPG = 0x84, STY_ZPX = 0x94, STY_ABS = 0x8C,

        // TAX - Transfer accumulator to X
        TAX_IMP = 0xAA,

        // TAY - Transfer accumulator to Y
        TAY_IMP = 0xA8,

        // TXA - Transfer X to accumulator
        TXA_IMP = 0x8A,

        // TYA - Transfer Y to accumulator
        TYA_IMP = 0x98,

        // TSX - Transfer SP to X
        TSX_IMP = 0xBA,

        // TXS - Transfer X to SP
        TXS_IMP = 0x9A,

        // PHA - Push accumulator onto stack
        PHA_IMP = 0x48,

        // PHP - Push processor status onto stack
        PHP_IMP = 0x08,

        // PLA - Pull accumulator from stack
        PLA_IMP = 0x68,

        // PLP - Pull processor status from stack
        PLP_IMP = 0x28,

        // AND - Logical AND
        AND_IMM = 0x29, AND_ZPG = 0x25, AND_ZPX = 0x35, AND_ABS = 0x2D, AND_ABX = 0x3D,
        AND_ABY = 0x39, AND_IDX = 0x21, AND_IDY = 0x31,

        // EOR - Exclusive OR
        EOR_IMM = 0x49, EOR_ZPG = 0x45, EOR_ZPX = 0x55, EOR_ABS = 0x4D, EOR_ABX = 0x5D,
        EOR_ABY = 0x59, EOR_IDX = 0x41, EOR_IDY = 0x51,

        // ORA - Logical OR
        ORA_IMM = 0x09, ORA_ZPG = 0x05, ORA_ZPX = 0x15, ORA_ABS = 0x0D, ORA_ABX = 0x1D,
        ORA_ABY = 0x19, ORA_IDX = 0x01, ORA_IDY = 0x11,

        // BIT - Bit test
        BIT_ZPG = 0x24, BIT_ABS = 0x2C,

        // ADC - Add with carry
        ADC_IMM = 0x69, ADC_ZPG = 0x65, ADC_ZPX = 0x75, ADC_ABS = 0x6D, ADC_ABX = 0x7D,
        ADC_ABY = 0x79, ADC_IDX = 0x61, ADC_IDY = 0x71,

        // SBC - Subtract with carry
        SBC_IMM = 0xE9, SBC_ZPG = 0xE5, SBC_ZPX = 0xF5, SBC_ABS = 0xED, SBC_ABX = 0xFD,
        SBC_ABY = 0xF9, SBC_IDX = 0xE1, SBC_IDY = 0xF1,

        // CMP - Compare accumulator
        CMP_IMM = 0xC9, CMP_ZPG = 0xC5, CMP_ZPX = 0xD5, CMP_ABS = 0xCD, CMP_ABX = 0xDD,
        CMP_ABY = 0xD9, CMP_IDX = 0xC1, CMP_IDY = 0xD1,

        // CPX - Compare X register
        CPX_IMM = 0xE0, CPX_ZPG = 0xE4, CPX_ABS = 0xEC,

        // CPY - Compare Y register
        CPY_IMM = 0xC0, CPY_ZPG = 0xC4, CPY_ABS = 0xCC,

        // INC - Increment memory
        INC_ZPG = 0xE6, INC_ZPX = 0xF6, INC_ABS = 0xEE, INC_ABX = 0xFE,

        // INX - Increment X register
        INX_IMP = 0xE8,

        // INY - Increment Y register
        INY_IMP = 0xC8,

        // DEC - Decrement memory
        DEC_ZPG = 0xC6, DEC_ZPX = 0xD6, DEC_ABS = 0xCE, DEC_ABX = 0xDE,

        // DEX - Decrement X register
        DEX_IMP = 0xCA,

        // DEY - Decrement Y register
        DEY_IMP = 0x88,

        // ASL - Arithmetic shift left
        ASL_IMP = 0x0A, ASL_ZPG = 0x06, ASL_ZPX = 0x16, ASL_ABS = 0x0E, ASL_ABX = 0x1E,

        // LSR - Logical shift right
        LSR_IMP = 0x4A, LSR_ZPG = 0x46, LSR_ZPX = 0x56, LSR_ABS = 0x4E, LSR_ABX = 0x5E,

        // ROL - Rotate left
        ROL_IMP = 0x2A, ROL_ZPG = 0x26, ROL_ZPX = 0x36, ROL_ABS = 0x2E, ROL_ABX = 0x3E,

        // ROR - Rotate right
        ROR_IMP = 0x6A, ROR_ZPG = 0x66, ROR_ZPX = 0x76, ROR_ABS = 0x6E, ROR_ABX = 0x7E,

        // JMP - Jump
        JMP_ABS = 0x4C, JMP_IND = 0x6C,

        // JSR - Jump to subroutine
        JSR_ABS = 0x20,

        // RTS - Return from subroutine
        RTS_IMP = 0x60,

        // BCC - Branch if carry clear
        BCC_REL = 0x90,

        // BCS - Branch if carry set
        BCS_REL = 0xB0,

        // BEQ - Branch if zero set
        BEQ_REL = 0xF0,

        // BMI - Branch if negative set
        BMI_REL = 0x30,

        // BNE - Branch if zero clear
        BNE_REL = 0xD0,

        // BPL - Branch if negative clear
        BPL_REL = 0x10,

        // BVC - Branch if overflow clear
        BVC_REL = 0x50,

        // BVS - Branch if overflow set
        BVS_REL = 0x70,

        // CLC - Clear carry flag
        CLC_IMP = 0x18,

        // CLD - Clear decimal mode
        CLD_IMP = 0xD8,

        // CLI - Clear interrupt disable
        CLI_IMP = 0x58,

        // CLV - Clear overflow flag
        CLV_IMP = 0xB8,

        // SEC - Set carry flag
        SEC_IMP = 0x38,

        // SED - Set decimal mode
        SED_IMP = 0xF8,

        // SEI - Set interrupt disable
        SEI_IMP = 0x78,

        // BRK - Force interrupt
        BRK_IMP = 0x00,

        // NOP - No operation
        NOP_IMP = 0xEA,

        // RTI - Return from interrupt
        RTI_IMP = 0x40,
    };

    pub const AddressingMode = enum {
        IMP,    // Implied
        IMM,    // Immediate
        ZPG,    // Zero Page
        ZPX,    // Zero Page,X
        ZPY,    // Zero Page,Y
        REL,    // Relative
        ABS,    // Absolute
        ABX,    // Absolute,X
        ABY,    // Absolute,Y
        IND,    // Indirect
        IDX,    // (Indirect,X)
        IDY,    // (Indirect),Y
    };

    pub const AddressResult = struct {
        addr: u16,                  // Address fetched
        page_crossed: bool = false,  // Whether a page (0-255) was crossed
    };

    pub const InstructionHandler = *const fn (*CPU, AddressingMode) u2;

    pub const Instruction = struct {
        name: []const u8,               // Pneumonic (TODO: use for disassembly)
        mode: AddressingMode,           // Addressing mode used
        execute: InstructionHandler,    // Function pointer to implementation
        cycles: u32,                    // Number of clock cycles required
    };

    // -----------------------------------------------------------------------------
    //                                   FIELDS                                     
    // -----------------------------------------------------------------------------

    pc: u16,            // Program counter
    sp: u8,             // Stack pointer
    a: u8,              // Accumulator
    x: u8,              // Index register X
    y: u8,              // Index register Y
    status: u8,         // Processor status flags
    memory: *Memory,    // RAM (only device connected to bus)
    cycles: u32,        // Cycles remaining for current instruction
    
    // 16x16 instruction table. Bottom nibble is the column, top nibble is the
    // row, so that instruction opcodes can be used to index the table.
    instruction_table: [TABLE_SIZE]Instruction,

    // -----------------------------------------------------------------------------
    //                                CORE METHODS                                  
    // -----------------------------------------------------------------------------

    pub fn init(memory: *Memory) CPU {
        var cpu: CPU = undefined;

        cpu.memory = memory;
        cpu.buildInstructionTable();
        cpu.reset();

        return cpu;
    }

    pub fn reset(self: *CPU) void {
        self.pc     = self.readWord(RESET_VECTOR);
        self.sp     = RESET_SP;
        self.a      = RESET_REG;
        self.x      = RESET_REG;
        self.y      = RESET_REG;
        self.status = RESET_STATUS;
        self.cycles = RESET_CYCLES;
    }

    pub fn tick(self: *CPU) void {
        if (self.cycles == 0) {
            const fetched = self.fetchByte();
            const maybe_opcode = decodeOpcode(fetched);

            if (maybe_opcode) |opcode| {
                const cycles_required = self.executeInstruction(opcode);
                self.cycles = cycles_required;
            } else {
                std.debug.print("Unknown opcode: '0x{X:0>2}'\n", .{fetched});
                return;
            }
        }

        if (self.cycles > 0) self.cycles -= 1;
    }

    pub fn run(self: *CPU, cycles: u32) void {
        var remaining = cycles;

        while (remaining > 0) : (remaining -= 1) {
            self.tick();
        }
    }

    pub fn irq(self: *CPU) void {
        if (self.getFlag(.I)) return;

        self.stackPushWord(self.pc);
        self.stackPushByte(self.status);
        self.setFlag(.I, true);
        self.pc = self.readWord(INTER_VECTOR);

        self.cycles += 7;
    }

    pub fn nmi(self: *CPU) void {
        self.stackPushWord(self.pc);
        self.stackPushByte(self.status);
        self.pc = self.readWord(NMI_VECTOR);

        self.cycles += 8;
    }

    pub fn readByte(self: *CPU, addr: u16) u8 {
        return self.memory.read(addr);
    }

    pub fn readWord(self: *CPU, addr: u16) u16 {
        const low:  u16 = self.readByte(addr + 0);
        const high: u16 = self.readByte(addr + 1);

        return (high << 8) | low;
    }

    pub fn writeByte(self: *CPU, addr: u16, value: u8) void {
        self.memory.write(addr, value);
    }

    pub fn writeWord(self: *CPU, addr: u16, value: u16) void {
        self.writeByte(addr + 0, @intCast(value & 0x00FF));
        self.writeByte(addr + 1, @intCast(value >> 8));
    }

    pub fn fetchByte(self: *CPU) u8 {
        const byte = self.readByte(self.pc);
        self.pc += 1;

        return byte;
    }

    pub fn fetchWord(self: *CPU) u16 {
        const low:  u16 = self.fetchByte();
        const high: u16 = self.fetchByte();

        return (high << 8) | low;
    }

    pub fn getFlag(self: *CPU, flag: Flag) bool {
        return (self.status & @intFromEnum(flag) > 0);
    }

    pub fn setFlag(self: *CPU, flag: Flag, value: bool) void {
        if (value) self.status |= @intFromEnum(flag)
        else self.status &= ~(@intFromEnum(flag));
    }

    pub fn setFlagsZN(self: *CPU, value: u16) void {
        self.setFlag(.Z, value == 0);
        self.setFlag(.N, isBitSet(value, 7));
    }

    pub fn setFlagsCZN(self: *CPU, value: i16) void {
        self.setFlag(.C, value >= 0);
        self.setFlag(.Z, value == 0);
        self.setFlag(.N, isBitSet(@bitCast(value), 7));
    }

    pub fn getStackAddress(self: *CPU) u16 {
        return 0x0100 | @as(u16, self.sp);
    }

    pub fn stackPushByte(self: *CPU, value: u8) void {
        self.writeByte(self.getStackAddress(), value);
        self.sp -= 1;
    }

    pub fn stackPushWord(self: *CPU, value: u16) void {
        self.stackPushByte(@intCast((value >> 8) & 0x00FF));
        self.stackPushByte(@intCast(value & 0x00FF));
    }

    pub fn stackPullByte(self: *CPU) u8 {
        const value = self.readByte(self.getStackAddress() + 1);
        self.sp += 1;

        return value;
    }

    pub fn stackPullWord(self: *CPU) u16 {
        const low:  u16 = self.stackPullByte();
        const high: u16 = self.stackPullByte();

        return (high << 8) | low;
    }

    pub fn branchIf(self: *CPU, flag: Flag, expected: bool) u2 {
        if (self.getFlag(flag) != expected) return 0;

        const addr_res = self.resolveAddress(.REL);
        self.pc = addr_res.addr;
        
        return 1 + 2 * @as(u2, @intFromBool(addr_res.page_crossed));
    }

    pub fn resolveAddress(self: *CPU, mode: AddressingMode) AddressResult {
        return switch (mode) {
            .IMP => {
                unreachable; // No address resolution needed in Implied mode
            },
            .IMM => {
                const addr = self.pc;
                self.pc += 1;
                return .{ .addr = addr };
            },
            .ZPG => {
                const addr = self.fetchByte();
                return .{ .addr = addr };
            },
            .ZPX => {
                const base_addr = self.fetchByte();
                const addr = base_addr +% self.x;
                return .{ .addr = addr };
            },
            .ZPY => {
                const base_addr = self.fetchByte();
                const addr = base_addr +% self.y;
                return .{ .addr = addr };
            },
            .REL => {
                const unsigned_offset = self.fetchByte();
                const signed_offset: i8 = @bitCast(unsigned_offset);
                const addr: u16 = @intCast(@as(i32, self.pc) + @as(i32, signed_offset));
                return .{ 
                    .addr = addr,
                    .page_crossed = isPageCrossed(addr, self.pc),
                 };
            },
            .ABS => {
                const addr = self.fetchWord();
                return .{ .addr = addr };
            },
            .ABX => {
                const base_addr = self.fetchWord();
                const addr = base_addr + self.x;
                return .{
                    .addr = addr,
                    .page_crossed = isPageCrossed(base_addr, addr),
                };
            },
            .ABY => {
                const base_addr = self.fetchWord();
                const addr = base_addr + self.y;
                return .{
                    .addr = addr,
                    .page_crossed = isPageCrossed(base_addr, addr),
                };
            },
            .IND => {
                const base_addr = self.fetchWord();

                // Implement known 6502 bug
                if (base_addr & 0x00FF == 0xFF) {
                    const page = base_addr & 0xFF00;
                    const low:  u16 = self.readByte(page | 0xFF);
                    const high: u16 = self.readByte(page | 0x00);

                    return .{ .addr = (high << 8) | low };
                }

                const addr = self.readWord(base_addr);
                return .{ .addr = addr };
            },
            .IDX => {
                const base_zpg_addr = self.fetchByte();
                const zpg_addr = base_zpg_addr +% self.x;
                const addr = self.readWord(zpg_addr);
                return .{ .addr = addr };
            },
            .IDY => {
                const zpg_addr = self.fetchByte();
                const base_addr = self.readWord(zpg_addr);
                const addr = base_addr + self.y;
                return .{
                    .addr = addr,
                    .page_crossed = isPageCrossed(base_addr, addr),
                };
            }
        };
    }

    pub fn executeInstruction(self: *CPU, opcode: Opcode) u32 {
        const instruction = self.instruction_table[@intFromEnum(opcode)];
        const extra_cycles = instruction.execute(self, instruction.mode);

        return instruction.cycles + extra_cycles;
    }

    // -----------------------------------------------------------------------------
    //                                INSTRUCTIONS                                  
    // -----------------------------------------------------------------------------

    // Reference: http://www.6502.org/users/obelisk/6502/reference.html

    fn addInstruction(
        self: *CPU,
        opcode: Opcode,
        name: []const u8,
        mode: AddressingMode,
        execute: InstructionHandler,
        cycles: u32
    ) void {
        self.instruction_table[@intFromEnum(opcode)] = Instruction {
            .name = name,
            .mode = mode,
            .execute = execute,
            .cycles = cycles,
        };
    }

    fn buildInstructionTable(self: *CPU) void {
        // Initialize all instructions to default value
        self.instruction_table = [_]Instruction{ .{
            .name = "???",
            .mode = .IMM,
            .execute = &unknownInstruction,
            .cycles = 0,
        } } ** TABLE_SIZE;

        self.addInstruction(.LDA_IMM, "LDA", .IMM, &executeLDA, 2);
        self.addInstruction(.LDA_ZPG, "LDA", .ZPG, &executeLDA, 3);
        self.addInstruction(.LDA_ZPX, "LDA", .ZPX, &executeLDA, 4);
        self.addInstruction(.LDA_ABS, "LDA", .ABS, &executeLDA, 4);
        self.addInstruction(.LDA_ABX, "LDA", .ABX, &executeLDA, 4);
        self.addInstruction(.LDA_ABY, "LDA", .ABY, &executeLDA, 4);
        self.addInstruction(.LDA_IDX, "LDA", .IDX, &executeLDA, 6);
        self.addInstruction(.LDA_IDY, "LDA", .IDY, &executeLDA, 5);

        self.addInstruction(.LDX_IMM, "LDX", .IMM, &executeLDX, 2);
        self.addInstruction(.LDX_ZPG, "LDX", .ZPG, &executeLDX, 3);
        self.addInstruction(.LDX_ZPY, "LDX", .ZPY, &executeLDX, 4);
        self.addInstruction(.LDX_ABS, "LDX", .ABS, &executeLDX, 4);
        self.addInstruction(.LDX_ABY, "LDX", .ABY, &executeLDX, 4);

        self.addInstruction(.LDY_IMM, "LDY", .IMM, &executeLDY, 2);
        self.addInstruction(.LDY_ZPG, "LDY", .ZPG, &executeLDY, 3);
        self.addInstruction(.LDY_ZPX, "LDY", .ZPX, &executeLDY, 4);
        self.addInstruction(.LDY_ABS, "LDY", .ABS, &executeLDY, 4);
        self.addInstruction(.LDY_ABX, "LDY", .ABX, &executeLDY, 4);

        self.addInstruction(.STA_ZPG, "STA", .ZPG, &executeSTA, 3);
        self.addInstruction(.STA_ZPX, "STA", .ZPX, &executeSTA, 4);
        self.addInstruction(.STA_ABS, "STA", .ABS, &executeSTA, 4);
        self.addInstruction(.STA_ABX, "STA", .ABX, &executeSTA, 5);
        self.addInstruction(.STA_ABY, "STA", .ABY, &executeSTA, 5);
        self.addInstruction(.STA_IDX, "STA", .IDX, &executeSTA, 6);
        self.addInstruction(.STA_IDY, "STA", .IDY, &executeSTA, 6);

        self.addInstruction(.STX_ZPG, "STX", .ZPG, &executeSTX, 3);
        self.addInstruction(.STX_ZPY, "STX", .ZPY, &executeSTX, 4);
        self.addInstruction(.STX_ABS, "STX", .ABS, &executeSTX, 4);

        self.addInstruction(.STY_ZPG, "STY", .ZPG, &executeSTY, 3);
        self.addInstruction(.STY_ZPX, "STY", .ZPX, &executeSTY, 4);
        self.addInstruction(.STY_ABS, "STY", .ABS, &executeSTY, 4);

        self.addInstruction(.TAX_IMP, "TAX", .IMP, &executeTAX, 2);
        self.addInstruction(.TAY_IMP, "TAY", .IMP, &executeTAY, 2);
        self.addInstruction(.TXA_IMP, "TXA", .IMP, &executeTXA, 2);
        self.addInstruction(.TYA_IMP, "TYA", .IMP, &executeTYA, 2);
        self.addInstruction(.TSX_IMP, "TSX", .IMP, &executeTSX, 2);
        self.addInstruction(.TXS_IMP, "TXS", .IMP, &executeTXS, 2);

        self.addInstruction(.PHA_IMP, "PHA", .IMP, &executePHA, 3);
        self.addInstruction(.PHP_IMP, "PHP", .IMP, &executePHP, 3);
        self.addInstruction(.PLA_IMP, "PLA", .IMP, &executePLA, 4);
        self.addInstruction(.PLP_IMP, "PLP", .IMP, &executePLP, 4);

        self.addInstruction(.AND_IMM, "AND", .IMM, &executeAND, 2);
        self.addInstruction(.AND_ZPG, "AND", .ZPG, &executeAND, 3);
        self.addInstruction(.AND_ZPX, "AND", .ZPX, &executeAND, 4);
        self.addInstruction(.AND_ABS, "AND", .ABS, &executeAND, 4);
        self.addInstruction(.AND_ABX, "AND", .ABX, &executeAND, 4);
        self.addInstruction(.AND_ABY, "AND", .ABY, &executeAND, 4);
        self.addInstruction(.AND_IDX, "AND", .IDX, &executeAND, 6);
        self.addInstruction(.AND_IDY, "AND", .IDY, &executeAND, 5);

        self.addInstruction(.EOR_IMM, "EOR", .IMM, &executeEOR, 2);
        self.addInstruction(.EOR_ZPG, "EOR", .ZPG, &executeEOR, 3);
        self.addInstruction(.EOR_ZPX, "EOR", .ZPX, &executeEOR, 4);
        self.addInstruction(.EOR_ABS, "EOR", .ABS, &executeEOR, 4);
        self.addInstruction(.EOR_ABX, "EOR", .ABX, &executeEOR, 4);
        self.addInstruction(.EOR_ABY, "EOR", .ABY, &executeEOR, 4);
        self.addInstruction(.EOR_IDX, "EOR", .IDX, &executeEOR, 6);
        self.addInstruction(.EOR_IDY, "EOR", .IDY, &executeEOR, 5);

        self.addInstruction(.ORA_IMM, "ORA", .IMM, &executeORA, 2);
        self.addInstruction(.ORA_ZPG, "ORA", .ZPG, &executeORA, 3);
        self.addInstruction(.ORA_ZPX, "ORA", .ZPX, &executeORA, 4);
        self.addInstruction(.ORA_ABS, "ORA", .ABS, &executeORA, 4);
        self.addInstruction(.ORA_ABX, "ORA", .ABX, &executeORA, 4);
        self.addInstruction(.ORA_ABY, "ORA", .ABY, &executeORA, 4);
        self.addInstruction(.ORA_IDX, "ORA", .IDX, &executeORA, 6);
        self.addInstruction(.ORA_IDY, "ORA", .IDY, &executeORA, 5);

        self.addInstruction(.BIT_ZPG, "BIT", .ZPG, &executeBIT, 3);
        self.addInstruction(.BIT_ABS, "BIT", .ABS, &executeBIT, 4);

        self.addInstruction(.ADC_IMM, "ADC", .IMM, &executeADC, 2);
        self.addInstruction(.ADC_ZPG, "ADC", .ZPG, &executeADC, 3);
        self.addInstruction(.ADC_ZPX, "ADC", .ZPX, &executeADC, 4);
        self.addInstruction(.ADC_ABS, "ADC", .ABS, &executeADC, 4);
        self.addInstruction(.ADC_ABX, "ADC", .ABX, &executeADC, 4);
        self.addInstruction(.ADC_ABY, "ADC", .ABY, &executeADC, 4);
        self.addInstruction(.ADC_IDX, "ADC", .IDX, &executeADC, 6);
        self.addInstruction(.ADC_IDY, "ADC", .IDY, &executeADC, 5);

        self.addInstruction(.SBC_IMM, "SBC", .IMM, &executeSBC, 2);
        self.addInstruction(.SBC_ZPG, "SBC", .ZPG, &executeSBC, 3);
        self.addInstruction(.SBC_ZPX, "SBC", .ZPX, &executeSBC, 4);
        self.addInstruction(.SBC_ABS, "SBC", .ABS, &executeSBC, 4);
        self.addInstruction(.SBC_ABX, "SBC", .ABX, &executeSBC, 4);
        self.addInstruction(.SBC_ABY, "SBC", .ABY, &executeSBC, 4);
        self.addInstruction(.SBC_IDX, "SBC", .IDX, &executeSBC, 6);
        self.addInstruction(.SBC_IDY, "SBC", .IDY, &executeSBC, 5);

        self.addInstruction(.CMP_IMM, "CMP", .IMM, &executeCMP, 2);
        self.addInstruction(.CMP_ZPG, "CMP", .ZPG, &executeCMP, 3);
        self.addInstruction(.CMP_ZPX, "CMP", .ZPX, &executeCMP, 4);
        self.addInstruction(.CMP_ABS, "CMP", .ABS, &executeCMP, 4);
        self.addInstruction(.CMP_ABX, "CMP", .ABX, &executeCMP, 4);
        self.addInstruction(.CMP_ABY, "CMP", .ABY, &executeCMP, 4);
        self.addInstruction(.CMP_IDX, "CMP", .IDX, &executeCMP, 6);
        self.addInstruction(.CMP_IDY, "CMP", .IDY, &executeCMP, 5);

        self.addInstruction(.CPX_IMM, "CPX", .IMM, &executeCPX, 2);
        self.addInstruction(.CPX_ZPG, "CPX", .ZPG, &executeCPX, 3);
        self.addInstruction(.CPX_ABS, "CPX", .ABS, &executeCPX, 4);

        self.addInstruction(.CPY_IMM, "CPY", .IMM, &executeCPY, 2);
        self.addInstruction(.CPY_ZPG, "CPY", .ZPG, &executeCPY, 3);
        self.addInstruction(.CPY_ABS, "CPY", .ABS, &executeCPY, 4);

        self.addInstruction(.INC_ZPG, "INC", .ZPG, &executeINC, 5);
        self.addInstruction(.INC_ZPX, "INC", .ZPX, &executeINC, 6);
        self.addInstruction(.INC_ABS, "INC", .ABS, &executeINC, 6);
        self.addInstruction(.INC_ABX, "INC", .ABX, &executeINC, 7);

        self.addInstruction(.INX_IMP, "INX", .IMP, &executeINX, 2);
        self.addInstruction(.INY_IMP, "INY", .IMP, &executeINY, 2);

        self.addInstruction(.DEC_ZPG, "DEC", .ZPG, &executeDEC, 5);
        self.addInstruction(.DEC_ZPX, "DEC", .ZPX, &executeDEC, 6);
        self.addInstruction(.DEC_ABS, "DEC", .ABS, &executeDEC, 6);
        self.addInstruction(.DEC_ABX, "DEC", .ABX, &executeDEC, 7);

        self.addInstruction(.DEX_IMP, "DEX", .IMP, &executeDEX, 2);
        self.addInstruction(.DEY_IMP, "DEY", .IMP, &executeDEY, 2);

        self.addInstruction(.ASL_IMP, "ASL", .IMP, &executeASL, 2);
        self.addInstruction(.ASL_ZPG, "ASL", .ZPG, &executeASL, 5);
        self.addInstruction(.ASL_ZPX, "ASL", .ZPX, &executeASL, 6);
        self.addInstruction(.ASL_ABS, "ASL", .ABS, &executeASL, 6);
        self.addInstruction(.ASL_ABX, "ASL", .ABX, &executeASL, 7);

        self.addInstruction(.LSR_IMP, "LSR", .IMP, &executeLSR, 2);
        self.addInstruction(.LSR_ZPG, "LSR", .ZPG, &executeLSR, 5);
        self.addInstruction(.LSR_ZPX, "LSR", .ZPX, &executeLSR, 6);
        self.addInstruction(.LSR_ABS, "LSR", .ABS, &executeLSR, 6);
        self.addInstruction(.LSR_ABX, "LSR", .ABX, &executeLSR, 7);

        self.addInstruction(.ROL_IMP, "ROL", .IMP, &executeROL, 2);
        self.addInstruction(.ROL_ZPG, "ROL", .ZPG, &executeROL, 5);
        self.addInstruction(.ROL_ZPX, "ROL", .ZPX, &executeROL, 6);
        self.addInstruction(.ROL_ABS, "ROL", .ABS, &executeROL, 6);
        self.addInstruction(.ROL_ABX, "ROL", .ABX, &executeROL, 7);

        self.addInstruction(.ROR_IMP, "ROR", .IMP, &executeROR, 2);
        self.addInstruction(.ROR_ZPG, "ROR", .ZPG, &executeROR, 5);
        self.addInstruction(.ROR_ZPX, "ROR", .ZPX, &executeROR, 6);
        self.addInstruction(.ROR_ABS, "ROR", .ABS, &executeROR, 6);
        self.addInstruction(.ROR_ABX, "ROR", .ABX, &executeROR, 7);

        self.addInstruction(.JMP_ABS, "JMP", .ABS, &executeJMP, 3);
        self.addInstruction(.JMP_IND, "JMP", .IND, &executeJMP, 5);

        self.addInstruction(.JSR_ABS, "JSR", .ABS, &executeJSR, 6);
        self.addInstruction(.RTS_IMP, "RTS", .IMP, &executeRTS, 6);

        self.addInstruction(.BCC_REL, "BCC", .REL, &executeBCC, 2);
        self.addInstruction(.BCS_REL, "BCS", .REL, &executeBCS, 2);
        self.addInstruction(.BEQ_REL, "BEQ", .REL, &executeBEQ, 2);
        self.addInstruction(.BMI_REL, "BMI", .REL, &executeBMI, 2);
        self.addInstruction(.BNE_REL, "BNE", .REL, &executeBNE, 2);
        self.addInstruction(.BPL_REL, "BPL", .REL, &executeBPL, 2);
        self.addInstruction(.BVC_REL, "BVC", .REL, &executeBVC, 2);
        self.addInstruction(.BVS_REL, "BVS", .REL, &executeBVS, 2);

        self.addInstruction(.CLC_IMP, "CLC", .IMP, &executeCLC, 2);
        self.addInstruction(.CLD_IMP, "CLD", .IMP, &executeCLD, 2);
        self.addInstruction(.CLI_IMP, "CLI", .IMP, &executeCLI, 2);
        self.addInstruction(.CLV_IMP, "CLV", .IMP, &executeCLV, 2);
        self.addInstruction(.SEC_IMP, "SEC", .IMP, &executeSEC, 2);
        self.addInstruction(.SED_IMP, "SED", .IMP, &executeSED, 2);
        self.addInstruction(.SEI_IMP, "SEI", .IMP, &executeSEI, 2);

        self.addInstruction(.BRK_IMP, "BRK", .IMP, &executeBRK, 7);
        self.addInstruction(.NOP_IMP, "NOP", .IMP, &executeNOP, 2);
        self.addInstruction(.RTI_IMP, "RTI", .IMP, &executeRTI, 6);
    }

    // ------------------------- LDA - Load accumulator ----------------------------

    fn executeLDA(self: *CPU, mode: AddressingMode) u2 {
        const addr_res = self.resolveAddress(mode);
        const value = self.readByte(addr_res.addr);

        self.a = value;
        self.setFlagsZN(value);

        return @intFromBool(addr_res.page_crossed);
    }

    // -------------------------- LDX - Load X register ----------------------------

    fn executeLDX(self: *CPU, mode: AddressingMode) u2 {
        const addr_res = self.resolveAddress(mode);
        const value = self.readByte(addr_res.addr);

        self.x = value;
        self.setFlagsZN(value);
        
        return @intFromBool(addr_res.page_crossed);
    }

    // -------------------------- LDY - Load Y register ----------------------------

    fn executeLDY(self: *CPU, mode: AddressingMode) u2 {
        const addr_res = self.resolveAddress(mode);
        const value = self.readByte(addr_res.addr);

        self.y = value;
        self.setFlagsZN(value);
        
        return @intFromBool(addr_res.page_crossed);
    }

    // ------------------------- STA - Store accumulator ---------------------------

    fn executeSTA(self: *CPU, mode: AddressingMode) u2 {
        const addr_res = self.resolveAddress(mode);

        self.writeByte(addr_res.addr, self.a);

        return 0; // No extra cycles
    }

    // ------------------------- STX - Store X register ----------------------------

    fn executeSTX(self: *CPU, mode: AddressingMode) u2 {
        const addr_res = self.resolveAddress(mode);

        self.writeByte(addr_res.addr, self.x);

        return 0; // No extra cycles
    }

    // ------------------------- STY - Store Y register ----------------------------

    fn executeSTY(self: *CPU, mode: AddressingMode) u2 {
        const addr_res = self.resolveAddress(mode);

        self.writeByte(addr_res.addr, self.y);

        return 0; // No extra cycles
    }

    // --------------------- TAX - Transfer accumulator to X -----------------------

    fn executeTAX(self: *CPU, _: AddressingMode) u2 {
        self.x = self.a;
        self.setFlagsZN(self.x);

        return 0; // No extra cycles
    }

    // --------------------- TAY - Transfer accumulator to Y -----------------------

    fn executeTAY(self: *CPU, _: AddressingMode) u2 {
        self.y = self.a;
        self.setFlagsZN(self.y);

        return 0; // No extra cycles
    }

    // --------------------- TXA - Transfer X to accumulator -----------------------

    fn executeTXA(self: *CPU, _: AddressingMode) u2 {
        self.a = self.x;
        self.setFlagsZN(self.a);

        return 0; // No extra cycles
    }

    // --------------------- TYA - Transfer Y to accumulator -----------------------

    fn executeTYA(self: *CPU, _: AddressingMode) u2 {
        self.a = self.y;
        self.setFlagsZN(self.a);

        return 0; // No extra cycles
    }

    // ------------------------- TSX - Transfer SP to X ----------------------------

    fn executeTSX(self: *CPU, _: AddressingMode) u2 {
        self.x = self.sp;
        self.setFlagsZN(self.x);

        return 0; // No extra cycles
    }

    // ------------------------- TXS - Transfer X to SP ----------------------------

    fn executeTXS(self: *CPU, _: AddressingMode) u2 {
        self.sp = self.x;

        return 0; // No extra cycles
    }

    // -------------------- PHA - Push accumulator onto stack ----------------------

    fn executePHA(self: *CPU, _: AddressingMode) u2 {
        self.stackPushByte(self.a);

        return 0; // No extra cycles
    }

    // ----------------- PHP - Push processor status onto stack --------------------

    fn executePHP(self: *CPU, _: AddressingMode) u2 {
        self.stackPushByte(self.status);

        return 0; // No extra cycles
    }

    // -------------------- PLA - Pull accumulator from stack ----------------------

    fn executePLA(self: *CPU, _: AddressingMode) u2 {
        self.a = self.stackPullByte();
        self.setFlagsZN(self.a);

        return 0; // No extra cycles
    }

    // ----------------- PLP - Pull processor status from stack --------------------

    fn executePLP(self: *CPU, _: AddressingMode) u2 {
        self.status = self.stackPullByte();

        return 0; // No extra cycles
    }

    // ---------------------------- AND - Logical AND ------------------------------

    fn executeAND(self: *CPU, mode: AddressingMode) u2 {
        const addr_res = self.resolveAddress(mode);
        const value = self.readByte(addr_res.addr);

        self.a &= value;
        self.setFlagsZN(self.a);

        return @intFromBool(addr_res.page_crossed);
    }

    // --------------------------- EOR - Exclusive OR ------------------------------

    fn executeEOR(self: *CPU, mode: AddressingMode) u2 {
        const addr_res = self.resolveAddress(mode);
        const value = self.readByte(addr_res.addr);

        self.a ^= value;
        self.setFlagsZN(self.a);

        return @intFromBool(addr_res.page_crossed);
    }

    // ---------------------------- ORA - Logical OR -------------------------------

    fn executeORA(self: *CPU, mode: AddressingMode) u2 {
        const addr_res = self.resolveAddress(mode);
        const value = self.readByte(addr_res.addr);

        self.a |= value;
        self.setFlagsZN(self.a);

        return @intFromBool(addr_res.page_crossed);
    }

    // ----------------------------- BIT - Bit test --------------------------------

    fn executeBIT(self: *CPU, mode: AddressingMode) u2 {
        const addr_res = self.resolveAddress(mode);
        const value = self.readByte(addr_res.addr);
        
        self.setFlag(.Z, (self.a & value) == 0x00);
        self.setFlag(.V, isBitSet(value, 6));
        self.setFlag(.N, isBitSet(value, 7));

        return 0; // No extra cycles
    }

    // -------------------------- ADC - Add with carry -----------------------------

    fn executeADC(self: *CPU, mode: AddressingMode) u2 {
        const addr_res = self.resolveAddress(mode);
        const value = self.readByte(addr_res.addr);
        const result_word: u16 = @as(u16, self.a) + @as(u16, value) + @intFromBool(self.getFlag(.C));
        const result_byte: u8 = @intCast(result_word & 0x00FF);

        const same_add_msb = (getBit(self.a, 7) ^ getBit(value, 7)) == 0;
        const diff_acc_msb = getBit(result_byte, 7) != getBit(self.a, 7);

        self.setFlagsZN(result_byte);
        self.setFlag(.C, (result_word & 0xFF00) > 0);
        self.setFlag(.V, same_add_msb and diff_acc_msb);
        self.a = result_byte;

        return @intFromBool(addr_res.page_crossed);
    }

    // ------------------------ SBC - Subtract with carry --------------------------

    fn executeSBC(self: *CPU, mode: AddressingMode) u2 {
        const addr_res = self.resolveAddress(mode);
        const value = self.readByte(addr_res.addr);
        const result_word: u16 = @as(u16, self.a) + @as(u16, ~value) + @intFromBool(self.getFlag(.C));
        const result_byte: u8 = @intCast(result_word & 0x00FF);

        const same_add_msb = (getBit(self.a, 7) ^ getBit(~value, 7)) == 0;
        const diff_acc_msb = getBit(result_byte, 7) != getBit(self.a, 7);

        self.setFlagsZN(result_byte);
        self.setFlag(.C, (result_word & 0xFF00) > 0);
        self.setFlag(.V, same_add_msb and diff_acc_msb);
        self.a = result_byte;

        return @intFromBool(addr_res.page_crossed);
    }

    // ------------------------ CMP - Compare accumulator --------------------------

    fn executeCMP(self: *CPU, mode: AddressingMode) u2 {
        const addr_res = self.resolveAddress(mode);
        const value = self.readByte(addr_res.addr);
        const result: i16 = @as(i16, self.a) - @as(i16, value);
        
        self.setFlagsCZN(result);

        return @intFromBool(addr_res.page_crossed);
    }

    // ------------------------ CPX - Compare X register ---------------------------

    fn executeCPX(self: *CPU, mode: AddressingMode) u2 {
        const addr_res = self.resolveAddress(mode);
        const value = self.readByte(addr_res.addr);
        const result: i16 = @as(i16, self.x) - @as(i16, value);
        
        self.setFlagsCZN(result);

        return 0; // No extra cycles
    }

    // ------------------------ CPY - Compare Y register ---------------------------

    fn executeCPY(self: *CPU, mode: AddressingMode) u2 {
        const addr_res = self.resolveAddress(mode);
        const value = self.readByte(addr_res.addr);
        const result: i16 = @as(i16, self.y) - @as(i16, value);
        
        self.setFlagsCZN(result);

        return 0; // No extra cycles
    }

    // ------------------------- INC - Increment memory ----------------------------

    fn executeINC(self: *CPU, mode: AddressingMode) u2 {
        const addr_res = self.resolveAddress(mode);
        const value = self.readByte(addr_res.addr);
        const result = value +% 1;

        self.writeByte(addr_res.addr, result);
        self.setFlagsZN(result);

        return 0; // No extra cycles
    }

    // ----------------------- INX - Increment X register --------------------------

    fn executeINX(self: *CPU, _: AddressingMode) u2 {
        const result = self.x +% 1;

        self.x = result;
        self.setFlagsZN(result);
        
        return 0; // No extra cycles
    }

    // ----------------------- INY - Increment Y register --------------------------

    fn executeINY(self: *CPU, _: AddressingMode) u2 {
        const result = self.y +% 1;

        self.y = result;
        self.setFlagsZN(result);
        
        return 0; // No extra cycles
    }

    // ------------------------- DEC - Decrement memory ----------------------------

    fn executeDEC(self: *CPU, mode: AddressingMode) u2 {
        const addr_res = self.resolveAddress(mode);
        const value = self.readByte(addr_res.addr);
        const result = value -% 1;

        self.writeByte(addr_res.addr, result);
        self.setFlagsZN(result);

        return 0; // No extra cycles
    }

    // ----------------------- DEX - Decrement X register --------------------------

    fn executeDEX(self: *CPU, _: AddressingMode) u2 {
        const result = self.x -% 1;

        self.x = result;
        self.setFlagsZN(result);
        
        return 0; // No extra cycles
    }

    // ----------------------- DEY - Decrement Y register --------------------------

    fn executeDEY(self: *CPU, _: AddressingMode) u2 {
        const result = self.y -% 1;

        self.y = result;
        self.setFlagsZN(result);
        
        return 0; // No extra cycles
    }

    // ----------------------- ASL - Arithmetic shift left -------------------------

    fn executeASL(self: *CPU, mode: AddressingMode) u2 {
        var result: u16 = undefined;

        if (mode == .IMP) {
            self.setFlag(.C, isBitSet(self.a, 7));

            result = @as(u16, self.a) << 1;
            self.a = @intCast(result & 0x00FF);
        } else {
            const addr_res = self.resolveAddress(mode);
            const value = self.readByte(addr_res.addr);

            self.setFlag(.C, isBitSet(value, 7));

            result = @as(u16, value) << 1;
            self.writeByte(addr_res.addr, @intCast(result & 0x00FF));
        }

        self.setFlagsZN(result);

        return 0; // No extra cycles
    }

    // ------------------------ LSR - Logical shift right --------------------------

    fn executeLSR(self: *CPU, mode: AddressingMode) u2 {
        var result: u8 = undefined;

        if (mode == .IMP) {
            self.setFlag(.C, isBitSet(self.a, 0));

            result = self.a >> 1;
            self.a = result;
        } else {
            const addr_res = self.resolveAddress(mode);
            const value = self.readByte(addr_res.addr);

            self.setFlag(.C, isBitSet(value, 0));

            result = value >> 1;
            self.writeByte(addr_res.addr, result);
        }

        self.setFlagsZN(result);

        return 0; // No extra cycles
    }

    // ---------------------------- ROL - Rotate left ------------------------------

    fn executeROL(self: *CPU, mode: AddressingMode) u2 {
        var result: u16 = undefined;
        const carry = @intFromBool(self.getFlag(.C));

        if (mode == .IMP) {
            self.setFlag(.C, isBitSet(self.a, 7));

            result = (@as(u16, self.a) << 1) | carry;
            self.a = @intCast(result & 0x00FF);
        } else {
            const addr_res = self.resolveAddress(mode);
            const value = self.readByte(addr_res.addr);

            self.setFlag(.C, isBitSet(value, 7));

            result = (@as(u16, value) << 1) | carry;
            self.writeByte(addr_res.addr, @intCast(result & 0x00FF));
        }

        self.setFlagsZN(result);

        return 0; // No extra cycles
    }

    // --------------------------- ROR - Rotate right ------------------------------

    fn executeROR(self: *CPU, mode: AddressingMode) u2 {
        var result: u8 = undefined;
        const carry = @intFromBool(self.getFlag(.C));

        if (mode == .IMP) {
            self.setFlag(.C, isBitSet(self.a, 0));

            result = (self.a >> 1) | (@as(u8, carry) << 7);
            self.a = result;
        } else {
            const addr_res = self.resolveAddress(mode);
            const value = self.readByte(addr_res.addr);

            self.setFlag(.C, isBitSet(value, 0));

            result = (value >> 1) | (@as(u8, carry) << 7);
            self.writeByte(addr_res.addr, result);
        }

        self.setFlagsZN(result);

        return 0; // No extra cycles
    }

    // ------------------------------- JMP - Jump ----------------------------------

    fn executeJMP(self: *CPU, mode: AddressingMode) u2 {
        const addr_res = self.resolveAddress(mode);

        self.pc = addr_res.addr;

        return 0; // No extra cycles
    }

    // ------------------------ JSR - Jump to subroutine ---------------------------

    fn executeJSR(self: *CPU, mode: AddressingMode) u2 {
        const addr_res = self.resolveAddress(mode);
        const ret_addr = self.pc - 1;
        
        self.stackPushWord(ret_addr);
        self.pc = addr_res.addr;
        
        return 0; // No extra cycles
    }

    // ---------------------- RTS - Return from subroutine -------------------------

    fn executeRTS(self: *CPU, _: AddressingMode) u2 {
        self.pc = self.stackPullWord();
        
        return 0; // No extra cycles
    }

    // ----------------------- BCC - Branch if carry clear -------------------------

    fn executeBCC(self: *CPU, _: AddressingMode) u2 {
        return self.branchIf(.C, false);
    }

    // ------------------------ BCS - Branch if carry set --------------------------

    fn executeBCS(self: *CPU, _: AddressingMode) u2 {
        return self.branchIf(.C, true);
    }

    // ------------------------ BEQ - Branch if zero set ---------------------------

    fn executeBEQ(self: *CPU, _: AddressingMode) u2 {
        return self.branchIf(.Z, true);
    }

    // ---------------------- BMI - Branch if negative set -------------------------

    fn executeBMI(self: *CPU, _: AddressingMode) u2 {
        return self.branchIf(.N, true);
    }

    // --------------------- BNE - Branch if negative clear ------------------------

    fn executeBNE(self: *CPU, _: AddressingMode) u2 {
        return self.branchIf(.N, false);
    }

    // --------------------- BPL - Branch if negative clear ------------------------

    fn executeBPL(self: *CPU, _: AddressingMode) u2 {
        return self.branchIf(.N, false);
    }

    // --------------------- BVC - Branch if overflow clear ------------------------

    fn executeBVC(self: *CPU, _: AddressingMode) u2 {
        return self.branchIf(.V, false);
    }

    // ---------------------- BVS - Branch if overflow set -------------------------

    fn executeBVS(self: *CPU, _: AddressingMode) u2 {
        return self.branchIf(.V, true);
    }

    // ------------------------- CLC - Clear carry flag ----------------------------

    fn executeCLC(self: *CPU, _: AddressingMode) u2 {
        self.setFlag(.C, false);

        return 0; // No extra cycles
    }

    // ------------------------ CLD - Clear decimal mode ---------------------------

    fn executeCLD(self: *CPU, _: AddressingMode) u2 {
        self.setFlag(.D, false);
        
        return 0; // No extra cycles
    }

    // ---------------------- CLI - Clear interrupt disable ------------------------

    fn executeCLI(self: *CPU, _: AddressingMode) u2 {
        self.setFlag(.I, false);
        
        return 0; // No extra cycles
    }

    // ------------------------ CLV - Clear overflow flag --------------------------

    fn executeCLV(self: *CPU, _: AddressingMode) u2 {
        self.setFlag(.V, false);
        
        return 0; // No extra cycles
    }

    // -------------------------- SEC - Set carry flag -----------------------------

    fn executeSEC(self: *CPU, _: AddressingMode) u2 {
        self.setFlag(.C, true);
        
        return 0; // No extra cycles
    }

    // ------------------------- SED - Set decimal mode ----------------------------

    fn executeSED(self: *CPU, _: AddressingMode) u2 {
        self.setFlag(.D, true);
        
        return 0; // No extra cycles
    }

    // ----------------------- SEI - Set interrupt disable -------------------------

    fn executeSEI(self: *CPU, _: AddressingMode) u2 {
        self.setFlag(.I, true);
        
        return 0; // No extra cycles
    }

    // -------------------------- BRK - Force interrupt ----------------------------

    fn executeBRK(self: *CPU, _:  AddressingMode) u2 {
        self.stackPushWord(self.pc);
        self.stackPushByte(self.status);
        self.setFlag(.B, true);
        self.pc = self.readWord(INTER_VECTOR);

        return 0; // No extra cycles
    }

    // --------------------------- NOP - No operation ------------------------------

    fn executeNOP(_: *CPU, _:  AddressingMode) u2 {
        return 0; // No extra cycles
    }

    // ----------------------- RTI - Return from interrupt -------------------------

    fn executeRTI(self: *CPU, _:  AddressingMode) u2 {
        self.status = self.stackPullByte();
        self.pc = self.stackPullWord();

        return 0; // No extra cycles
    }

    // ------------------------ ??? - Unknown instruction --------------------------

    fn unknownInstruction(_: *CPU, _:AddressingMode) u2 {
        std.debug.print("Unknown instruction\n", .{});
        return 0;
    }

    // -----------------------------------------------------------------------------
    //                              HELPER FUNCTIONS                                
    // -----------------------------------------------------------------------------

    fn decodeOpcode(byte: u8) ?Opcode {
        return std.meta.intToEnum(Opcode, byte) catch null;
    }

    pub fn getBit(byte: u8, bit: u3) u1 {
        return @intCast((byte >> bit) & 0b1);
    }

    pub fn isBitSet(value: u16, bit: u4) bool {
        return (value & (@as(u16, 1) << bit)) != 0;
    }

    fn isPageCrossed(base_addr: u16, eff_addr: u16) bool {
        return (base_addr & 0xFF00) != (eff_addr & 0xFF00);
    }
};
