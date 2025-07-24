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

    pub const RESET_VECTOR: u16 = 0xFFFC;   // Load PC from reset vector
    pub const RESET_SP:     u8  = 0xFD;     // Starts at 0, then gets decremented 3 times
    pub const RESET_REG:    u8  = 0x00;     // Zero all registers
    pub const RESET_STATUS: u8  = 0b100100; // Set I,U
    pub const RESET_CYCLES: u32 = 7;        // Reset sequence takes 7 cycles

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

    // --------------------------------------------------------------------------
    //                                CORE METHODS                               
    // --------------------------------------------------------------------------

    pub fn init(memory: *Memory) CPU {
        var cpu: CPU = undefined;

        cpu.memory = memory;
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
                const cycles_required = self.execute(opcode);
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
        self.pc += 2;

        return (high << 8) | low;
    }

    pub fn getFlag(self: *CPU, flag: Flag) bool {
        return (self.status & @intFromEnum(flag) > 0);
    }

    pub fn setFlag(self: *CPU, flag: Flag, value: bool) void {
        if (value) self.status |= @intFromEnum(flag)
        else self.status &= ~(@intFromEnum(flag));
    }

    pub fn execute(self: *CPU, opcode: Opcode) u32 {
        return switch (opcode) {
            .LDA_IMM => self.ldaImm(),
            .LDA_ZPG => self.ldaZpg(),
            .LDA_ZPX => self.ldaZpx(),
            .LDA_ABS => self.ldaAbs(),
            .LDA_ABX => self.ldaAbx(),
            .LDA_ABY => self.ldaAby(),
            .LDA_IDX => self.ldaIdx(),
            .LDA_IDY => self.ldaIdy(),
        };
    }

    // --------------------------------------------------------------------------
    //                                INSTRUCTIONS                               
    // --------------------------------------------------------------------------

    // Reference: http://www.6502.org/users/obelisk/6502/reference.html

    // ------------------------- LDA - Load accumulator -------------------------
    // Function:    A = M
    // Flags:       Z,N

    fn lda(self: *CPU, m: u8) void {
        self.a = m;
        self.setFlag(.Z, m == 0x00);
        self.setFlag(.N, isBitSet(m, 7));
    }

    // Immediate
    fn ldaImm(self: *CPU) u32 {
        const m = self.fetchByte();

        self.lda(m);
        return 2;
    }

    // Zero page
    fn ldaZpg(self: *CPU) u32 {
        const addr = self.fetchByte();
        const m = self.readByte(addr);

        self.lda(m);
        return 3; 
    }

    // Zero page,X
    fn ldaZpx(self: *CPU) u32 {
        const base_addr = self.fetchByte();
        const addr = base_addr +% self.x;
        const m = self.readByte(addr);

        self.lda(m);
        return 4;
    }

    // Absolute
    fn ldaAbs(self: *CPU) u32 {
        const addr = self.fetchWord();
        const m = self.readByte(addr);

        self.lda(m);
        return 4;
    }

    // Absolute,X
    fn ldaAbx(self: *CPU) u32 {
        const base_addr = self.fetchWord();
        const addr = base_addr + self.x;
        const m = self.readByte(addr);

        self.lda(m);
        return if (isPageCrossed(base_addr, addr)) 5 else 4;
    }

    // Absolute,Y
    fn ldaAby(self: *CPU) u32 {
        const base_addr = self.fetchWord();
        const addr = base_addr + self.y;
        const m = self.readByte(addr);

        self.lda(m);
        return if (isPageCrossed(base_addr, addr)) 5 else 4;
    }

    // (Indirect,X)
    fn ldaIdx(self: *CPU) u32 {
        const base_zpg_addr = self.fetchByte();
        const zpg_addr = base_zpg_addr +% self.x;
        const addr = self.readWord(zpg_addr);
        const m = self.readByte(addr);

        self.lda(m);
        return 6;
    }

    // (Indirect),Y
    fn ldaIdy(self: *CPU) u32 {
        const zpg_addr = self.fetchByte();
        const base_addr = self.readWord(zpg_addr);
        const addr = base_addr + self.y;
        const m = self.readByte(addr);

        self.lda(m);
        return if (isPageCrossed(base_addr, addr)) 6 else 5;
    }

    // ---------------------------- HELPER FUNCTIONS ----------------------------

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
