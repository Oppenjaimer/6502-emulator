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
    // -------------------------------- CONSTANTS -------------------------------

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
        LDA_IMM = 0xA9, LDA_ZPG = 0xA5, LDA_ZPX = 0xB5, LDA_ABS = 0xAD, LDA_ABX = 0xBD,
        LDA_ABY = 0xB9, LDA_IDX = 0xA1, LDA_IDY = 0xB1,
    };

    // --------------------------------- FIELDS ---------------------------------

    pc: u16,            // Program counter
    sp: u8,             // Stack pointer
    a: u8,              // Accumulator
    x: u8,              // Index register X
    y: u8,              // Index register Y
    status: u8,         // Processor status flags
    memory: *Memory,    // RAM (only device connected to bus)
    cycles: u32,        // Cycles remaining for current instruction

    // ------------------------------ CORE METHODS ------------------------------

    pub fn init(memory: *Memory) CPU {
        var cpu: CPU = undefined;

        cpu.memory = memory;
        cpu.reset();

        return cpu;
    }

    pub fn reset(self: *CPU) void {
        // Fetch PC from reset vector
        const low: u16  = self.memory.read(0xFFFC);
        const high: u16 = self.memory.read(0xFFFD);
        self.pc = (high << 8) | low;

        self.sp = 0xFD;         // Starts at 0, then gets decremented 3 times
        self.a = 0;
        self.x = 0;
        self.y = 0;
        self.status = 0b100100; // Set I, U
        self.cycles = 7;        // Reset sequence takes 7 cycles
    }

    pub fn tick(self: *CPU) void {
        if (self.cycles == 0) {
            const fetched = self.fetch();
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

    pub fn fetch(self: *CPU) u8 {
        const byte = self.memory.read(self.pc);
        self.pc += 1;

        return byte;
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
            .LDA_IMM => self.lda_imm(),
            else => {
                std.debug.print("Unimplemented opcode: '0x{X:0>2}'\n", .{@intFromEnum(opcode)});
                return 0;
            }
        };
    }

    // ------------------------------ INSTRUCTIONS ------------------------------
    // Reference: http://www.6502.org/users/obelisk/6502/reference.html



    // ---------------------------- HELPER FUNCTIONS ----------------------------

    fn decodeOpcode(byte: u8) ?Opcode {
        return std.meta.intToEnum(Opcode, byte) catch null;
    }

    fn isBitSet(byte: u8, bit: u3) bool {
        return (byte & (@as(u8, 1) << bit)) != 0;
    }
};
