const std = @import("std");
const testing = std.testing;

const emulator = @import("emulator.zig");
const CPU = emulator.CPU;
const Memory = emulator.Memory;
const Opcode = CPU.Opcode;

fn initMemory() Memory {
    var mem = Memory.init();

    // Set starting location
    mem.write(CPU.RESET_VECTOR + 0, 0x00);
    mem.write(CPU.RESET_VECTOR + 1, 0x30);

    return mem;
}

fn initCPU(memory: *Memory) CPU {
    var cpu = CPU.init(memory);

    // Execute startup
    cpu.run(7);

    return cpu;
}

// --------------------------------------------------------------------------
//                               CPU CORE TESTS                              
// --------------------------------------------------------------------------

test "CPU cycles" {
    var mem = Memory.init();
    var cpu = CPU.init(&mem);

    cpu.run(4); // Startup/Reset takes 7 cycles

    try testing.expectEqual(cpu.cycles, 3); // 3 cycles remaining
}

// --------------------------------------------------------------------------
//                              INSTRUCTION TESTS                            
// --------------------------------------------------------------------------

// ------------------------- LDA - Load accumulator -------------------------

test "LDA flags" {
    var mem = initMemory();
    var cpu = initCPU(&mem);

    mem.write(0x3000, @intFromEnum(Opcode.LDA_IMM));
    mem.write(0x3001, 0x80);

    cpu.run(2);

    try testing.expectEqual(cpu.getFlag(.Z), false);
    try testing.expectEqual(cpu.getFlag(.N), true);

    mem.write(0x3002, @intFromEnum(Opcode.LDA_IMM));
    mem.write(0x3003, 0x00);

    cpu.run(2);

    try testing.expectEqual(cpu.getFlag(.Z), true);
    try testing.expectEqual(cpu.getFlag(.N), false);
}

test "LDA Immediate" {
    var mem = initMemory();
    var cpu = initCPU(&mem);

    mem.write(0x3000, @intFromEnum(Opcode.LDA_IMM));
    mem.write(0x3001, 0x27);

    cpu.run(2);

    try testing.expectEqual(cpu.a, 0x27);
    try testing.expectEqual(cpu.cycles, 0);
}

test "LDA Zero page" {
    var mem = initMemory();
    var cpu = initCPU(&mem);

    mem.write(0x3000, @intFromEnum(Opcode.LDA_ZPG));
    mem.write(0x3001, 0x32);
    mem.write(0x0032, 0x33);

    cpu.run(3);

    try testing.expectEqual(cpu.a, 0x33);
    try testing.expectEqual(cpu.cycles, 0);
}

test "LDA Zero page,X" {
    var mem = initMemory();
    var cpu = initCPU(&mem);

    mem.write(0x3000, @intFromEnum(Opcode.LDA_ZPX));
    mem.write(0x3001, 0x44);
    mem.write(0x0045, 0x55);

    cpu.x = 0x01; // No wrap around
    cpu.run(4);

    try testing.expectEqual(cpu.a, 0x55);
    try testing.expectEqual(cpu.cycles, 0);

    mem.write(0x3002, @intFromEnum(Opcode.LDA_ZPX));
    mem.write(0x3003, 0xFF);
    mem.write(0x0001, 0x60);

    cpu.x = 0x02; // Address wraps around
    cpu.run(4);

    try testing.expectEqual(cpu.a, 0x60);
    try testing.expectEqual(cpu.cycles, 0);
}

test "LDA Absolute" {
    var mem = initMemory();
    var cpu = initCPU(&mem);

    mem.write(0x3000, @intFromEnum(Opcode.LDA_ABS));
    mem.write(0x3001, 0x34);
    mem.write(0x3002, 0x12);
    mem.write(0x1234, 0x67);

    cpu.run(4);

    try testing.expectEqual(cpu.a, 0x67);
    try testing.expectEqual(cpu.cycles, 0);
}

test "LDA Absolute,X" {
    var mem = initMemory();
    var cpu = initCPU(&mem);

    mem.write(0x3000, @intFromEnum(Opcode.LDA_ABX));
    mem.write(0x3001, 0x78);
    mem.write(0x3002, 0x56);
    mem.write(0x5679, 0x72);

    cpu.x = 0x01; // No page crossed
    cpu.run(4);

    try testing.expectEqual(cpu.a, 0x72);
    try testing.expectEqual(cpu.cycles, 0);

    mem.write(0x3003, @intFromEnum(Opcode.LDA_ABX));
    mem.write(0x3004, 0x89);
    mem.write(0x3005, 0x67);
    mem.write(0x6800, 0x79);

    cpu.x = 0x77; // Page crossed
    cpu.run(5);

    try testing.expectEqual(cpu.a, 0x79);
    try testing.expectEqual(cpu.cycles, 0);
}

test "LDA Absolute,Y" {
    var mem = initMemory();
    var cpu = initCPU(&mem);

    mem.write(0x3000, @intFromEnum(Opcode.LDA_ABY));
    mem.write(0x3001, 0x78);
    mem.write(0x3002, 0x56);
    mem.write(0x5679, 0x72);

    cpu.y = 0x01; // No page crossed
    cpu.run(4);

    try testing.expectEqual(cpu.a, 0x72);
    try testing.expectEqual(cpu.cycles, 0);

    mem.write(0x3003, @intFromEnum(Opcode.LDA_ABY));
    mem.write(0x3004, 0x89);
    mem.write(0x3005, 0x67);
    mem.write(0x6800, 0x79);

    cpu.y = 0x77; // Page crossed
    cpu.run(5);

    try testing.expectEqual(cpu.a, 0x79);
    try testing.expectEqual(cpu.cycles, 0);
}

test "LDA (Indirect,X)" {
    var mem = initMemory();
    var cpu = initCPU(&mem);

    mem.write(0x3000, @intFromEnum(Opcode.LDA_IDX));
    mem.write(0x3001, 0x84);
    mem.write(0x0085, 0x90);
    mem.write(0x0086, 0x91);
    mem.write(0x9190, 0x95);

    cpu.x = 0x01; // No wrap around
    cpu.run(6);

    try testing.expectEqual(cpu.a, 0x95);
    try testing.expectEqual(cpu.cycles, 0);

    mem.write(0x3002, @intFromEnum(Opcode.LDA_IDX));
    mem.write(0x3003, 0x85);
    mem.write(0x0000, 0x91);
    mem.write(0x0001, 0x92);
    mem.write(0x9291, 0x99);

    cpu.x = 0x7B; // Address wraps around
    cpu.run(6);

    try testing.expectEqual(cpu.a, 0x99);
    try testing.expectEqual(cpu.cycles, 0);
}

test "LDA (Indirect),Y" {
    var mem = initMemory();
    var cpu = initCPU(&mem);

    mem.write(0x3000, @intFromEnum(Opcode.LDA_IDY));
    mem.write(0x3001, 0x84);
    mem.write(0x0084, 0x90);
    mem.write(0x0085, 0x91);
    mem.write(0x9191, 0xA1);

    cpu.y = 0x01; // No page crossed
    cpu.run(5);

    try testing.expectEqual(cpu.a, 0xA1);
    try testing.expectEqual(cpu.cycles, 0);

    mem.write(0x3002, @intFromEnum(Opcode.LDA_IDY));
    mem.write(0x3003, 0x85);
    mem.write(0x0085, 0x91);
    mem.write(0x0086, 0x92);
    mem.write(0x9300, 0xA5);

    cpu.y = 0x6F; // Page crossed
    cpu.run(6);

    try testing.expectEqual(cpu.a, 0xA5);
    try testing.expectEqual(cpu.cycles, 0);
}