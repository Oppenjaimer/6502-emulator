pub const Memory = struct {
    pub const SIZE = 1024 * 64; // 64 KB

    data: [SIZE]u8,

    pub fn init() Memory {
        return Memory {
            .data = [_]u8{0} ** SIZE,
        };
    }
};

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

pub const CPU = struct {
    pc: u16,            // Program counter
    sp: u8,             // Stack pointer
    a: u8,              // Accumulator
    x: u8,              // Index register X
    y: u8,              // Index register Y
    status: u8,         // Processor status flags
    memory: *Memory,    // RAM (only device connected to bus)
    cycles: u32,        // Cycles remaining for current instruction

    pub fn init(memory: *Memory) CPU {
        var cpu: CPU = undefined;

        cpu.memory = memory;
        cpu.reset();

        return cpu;
    }

    pub fn reset(self: *CPU) void {
        self.pc = 0;            // TODO: Fetch from reset vector (0xFFFC/0xFFFD)
        self.sp = 0xFD;         // Starts at 0, then gets decremented 3 times
        self.a = 0;
        self.x = 0;
        self.y = 0;
        self.status = 0b100100; // Set I, U
        self.cycles = 7;        // Reset sequence takes 7 cycles
    }

    pub fn tick(self: *CPU) void {
        if (self.cycles == 0) {
            // TODO: Fetch and execute instruction
            // TODO: Set remaining cycles to instruction return value
        }

        self.cycles -= 1;
    }

    pub fn run(self: *CPU, cycles: u32) void {
        var remaining = cycles;

        while (remaining > 0) : (remaining -= 1) {
            self.tick();
        }
    }
};
