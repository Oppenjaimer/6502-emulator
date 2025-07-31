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
    // --------------------------------------------------------------------------
    //                                  CONSTANTS                                
    // --------------------------------------------------------------------------

    pub const RESET_VECTOR: u16   = 0xFFFC;     // Load PC from reset vector
    pub const RESET_SP:     u8    = 0xFD;       // Starts at 0, then gets decremented 3 times
    pub const RESET_REG:    u8    = 0x00;       // Zero all registers
    pub const RESET_STATUS: u8    = 0b100100;   // Set I,U
    pub const RESET_CYCLES: u32   = 7;          // Reset sequence takes 7 cycles
    pub const TABLE_SIZE:   usize = 256;        // Instruction table size (16x16)

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
        pageCrossed: bool = false,  // Whether a page (0-255) was crossed
    };

    pub const InstructionHandler = *const fn (*CPU, AddressingMode) u1;

    pub const Instruction = struct {
        name: []const u8,               // Pneumonic (TODO: use for disassembly)
        mode: AddressingMode,           // Addressing mode used
        execute: InstructionHandler,    // Function pointer to implementation
        cycles: u32,                    // Number of clock cycles required
    };

    // --------------------------------------------------------------------------
    //                                   FIELDS                                  
    // --------------------------------------------------------------------------

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

    // --------------------------------------------------------------------------
    //                                CORE METHODS                               
    // --------------------------------------------------------------------------

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
        self.writeByte(addr + 0, @intCast(value & 0xFF));
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

    pub fn setFlagsZN(self: *CPU, value: u8) void {
        self.setFlag(.Z, value == 0x00);
        self.setFlag(.N, isBitSet(value, 7));
    }

    pub fn getStackAddress(self: *CPU) u16 {
        return 0x0100 | @as(u16, self.sp);
    }

    pub fn stackPush(self: *CPU, value: u8) void {
        self.writeByte(self.getStackAddress(), value);
        self.sp -= 1;
    }

    pub fn stackPull(self: *CPU) u8 {
        const value = self.readByte(self.getStackAddress() + 1);
        self.sp += 1;

        return value;
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
            .REL => undefined,
            .ABS => {
                const addr = self.fetchWord();
                return .{ .addr = addr };
            },
            .ABX => {
                const base_addr = self.fetchWord();
                const addr = base_addr + self.x;
                return .{
                    .addr = addr,
                    .pageCrossed = isPageCrossed(base_addr, addr)
                };
            },
            .ABY => {
                const base_addr = self.fetchWord();
                const addr = base_addr + self.y;
                return .{
                    .addr = addr,
                    .pageCrossed = isPageCrossed(base_addr, addr),
                };
            },
            .IND => undefined,
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
                    .pageCrossed = isPageCrossed(base_addr, addr),
                };
            }
        };
    }

    pub fn executeInstruction(self: *CPU, opcode: Opcode) u32 {
        const instruction = self.instruction_table[@intFromEnum(opcode)];
        const extra_cycle = instruction.execute(self, instruction.mode);

        return instruction.cycles + extra_cycle;
    }

    // --------------------------------------------------------------------------
    //                                INSTRUCTIONS                               
    // --------------------------------------------------------------------------

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
    }

    // ------------------------- LDA - Load accumulator -------------------------
    // Function:    A = M
    // Flags:       Z,N

    fn executeLDA(self: *CPU, mode: AddressingMode) u1 {
        const addr_res = self.resolveAddress(mode);
        const value = self.readByte(addr_res.addr);

        self.a = value;
        self.setFlagsZN(value);

        return @intFromBool(addr_res.pageCrossed);
    }

    // -------------------------- LDX - Load X register -------------------------
    // Function:    X = M
    // Flags:       Z,N

    fn executeLDX(self: *CPU, mode: AddressingMode) u1 {
        const addr_res = self.resolveAddress(mode);
        const value = self.readByte(addr_res.addr);

        self.x = value;
        self.setFlagsZN(value);
        
        return @intFromBool(addr_res.pageCrossed);
    }

    // -------------------------- LDY - Load Y register -------------------------
    // Function:    Y = M
    // Flags:       Z,N

    fn executeLDY(self: *CPU, mode: AddressingMode) u1 {
        const addr_res = self.resolveAddress(mode);
        const value = self.readByte(addr_res.addr);

        self.y = value;
        self.setFlagsZN(value);
        
        return @intFromBool(addr_res.pageCrossed);
    }

    // ------------------------- STA - Store accumulator ------------------------
    // Function:    M = A
    // Flags:       none

    fn executeSTA(self: *CPU, mode: AddressingMode) u1 {
        const addr_res = self.resolveAddress(mode);

        self.writeByte(addr_res.addr, self.a);

        return 0; // No extra cycles
    }

    // ------------------------- STX - Store X register -------------------------
    // Function:    M = X
    // Flags:       none

    fn executeSTX(self: *CPU, mode: AddressingMode) u1 {
        const addr_res = self.resolveAddress(mode);

        self.writeByte(addr_res.addr, self.x);

        return 0; // No extra cycles
    }

    // ------------------------- STY - Store Y register -------------------------
    // Function:    M = Y
    // Flags:       none

    fn executeSTY(self: *CPU, mode: AddressingMode) u1 {
        const addr_res = self.resolveAddress(mode);

        self.writeByte(addr_res.addr, self.y);

        return 0; // No extra cycles
    }

    // --------------------- TAX - Transfer accumulator to X --------------------
    // Function:    X = A
    // Flags:       Z,N

    fn executeTAX(self: *CPU, _: AddressingMode) u1 {
        self.x = self.a;
        self.setFlagsZN(self.x);

        return 0; // No extra cycles
    }

    // --------------------- TAY - Transfer accumulator to Y --------------------
    // Function:    Y = A
    // Flags:       Z,N

    fn executeTAY(self: *CPU, _: AddressingMode) u1 {
        self.y = self.a;
        self.setFlagsZN(self.y);

        return 0; // No extra cycles
    }

    // --------------------- TXA - Transfer X to accumulator --------------------
    // Function:    A = X
    // Flags:       Z,N

    fn executeTXA(self: *CPU, _: AddressingMode) u1 {
        self.a = self.x;
        self.setFlagsZN(self.a);

        return 0; // No extra cycles
    }

    // --------------------- TYA - Transfer Y to accumulator --------------------
    // Function:    A = Y
    // Flags:       Z,N

    fn executeTYA(self: *CPU, _: AddressingMode) u1 {
        self.a = self.y;
        self.setFlagsZN(self.a);

        return 0; // No extra cycles
    }

    // ------------------------- TSX - Transfer SP to X -------------------------
    // Function:    X = SP
    // Flags:       Z,N

    fn executeTSX(self: *CPU, _: AddressingMode) u1 {
        self.x = self.sp;
        self.setFlagsZN(self.x);

        return 0; // No extra cycles
    }

    // ------------------------- TXS - Transfer X to SP -------------------------
    // Function:    SP = X
    // Flags:       none

    fn executeTXS(self: *CPU, _: AddressingMode) u1 {
        self.sp = self.x;

        return 0; // No extra cycles
    }

    // -------------------- PHA - Push accumulator onto stack -------------------
    // Function:    *SP = A; SP--
    // Flags:       none

    fn executePHA(self: *CPU, _: AddressingMode) u1 {
        self.stackPush(self.a);

        return 0; // No extra cycles
    }

    // ----------------- PHP - Push processor status onto stack -----------------
    // Function:    *SP = status; SP--
    // Flags:       none

    fn executePHP(self: *CPU, _: AddressingMode) u1 {
        self.stackPush(self.status);

        return 0; // No extra cycles
    }

    // -------------------- PLA - Pull accumulator from stack -------------------
    // Function:    A = *SP; SP++
    // Flags:       Z,N

    fn executePLA(self: *CPU, _: AddressingMode) u1 {
        self.a = self.stackPull();
        self.setFlagsZN(self.a);

        return 0; // No extra cycles
    }

    // ----------------- PLP - Pull processor status from stack -----------------
    // Function:    status = *SP; SP++
    // Flags:       all

    fn executePLP(self: *CPU, _: AddressingMode) u1 {
        self.status = self.stackPull();

        return 0; // No extra cycles
    }

    // ---------------------------- AND - Logical AND ---------------------------
    // Function:    A = A & M
    // Flags:       Z,N

    fn executeAND(self: *CPU, mode: AddressingMode) u1 {
        const addr_res = self.resolveAddress(mode);
        const value = self.readByte(addr_res.addr);

        self.a &= value;
        self.setFlagsZN(self.a);

        return @intFromBool(addr_res.pageCrossed);
    }

    // --------------------------- EOR - Exclusive OR ---------------------------
    // Function:    A = A ^ M
    // Flags:       Z,N

    fn executeEOR(self: *CPU, mode: AddressingMode) u1 {
        const addr_res = self.resolveAddress(mode);
        const value = self.readByte(addr_res.addr);

        self.a ^= value;
        self.setFlagsZN(self.a);

        return @intFromBool(addr_res.pageCrossed);
    }

    // ---------------------------- ORA - Logical OR ----------------------------
    // Function:    A = A | M
    // Flags:       Z,N

    fn executeORA(self: *CPU, mode: AddressingMode) u1 {
        const addr_res = self.resolveAddress(mode);
        const value = self.readByte(addr_res.addr);

        self.a |= value;
        self.setFlagsZN(self.a);

        return @intFromBool(addr_res.pageCrossed);
    }

    // ------------------------ ??? - Unknown instruction -----------------------

    fn unknownInstruction(_: *CPU, _:AddressingMode) u1 {
        std.debug.print("Unknown instruction\n", .{});
        return 0;
    }

    // --------------------------------------------------------------------------
    //                              HELPER FUNCTIONS                             
    // --------------------------------------------------------------------------

    fn decodeOpcode(byte: u8) ?Opcode {
        return std.meta.intToEnum(Opcode, byte) catch null;
    }

    pub fn isBitSet(byte: u8, bit: u3) bool {
        return (byte & (@as(u8, 1) << bit)) != 0;
    }

    fn isPageCrossed(base_addr: u16, eff_addr: u16) bool {
        return (base_addr & 0xFF00) != (eff_addr & 0xFF00);
    }
};
