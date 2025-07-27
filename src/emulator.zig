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
        self.writeByte(addr + 0, value & 0x00FF);
        self.writeByte(addr + 1, value >> 8);
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

    pub fn resolveAddress(self: *CPU, mode: AddressingMode) AddressResult {
        return switch (mode) {
            .IMP => undefined,
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
    }

    // Reference: http://www.6502.org/users/obelisk/6502/reference.html

    // ------------------------- LDA - Load accumulator -------------------------
    // Function:    A = M
    // Flags:       Z,N

    fn executeLDA(self: *CPU, mode: AddressingMode) u1 {
        const addr_res = self.resolveAddress(mode);
        const value = self.readByte(addr_res.addr);

        self.a = value;
        self.setFlag(.Z, value == 0x00);
        self.setFlag(.N, isBitSet(value, 7));

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

    fn isBitSet(byte: u8, bit: u3) bool {
        return (byte & (@as(u8, 1) << bit)) != 0;
    }

    fn isPageCrossed(base_addr: u16, eff_addr: u16) bool {
        return (base_addr & 0xFF00) != (eff_addr & 0xFF00);
    }
};
