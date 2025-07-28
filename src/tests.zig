const std = @import("std");
const testing = std.testing;

const emulator = @import("emulator.zig");
const CPU = emulator.CPU;
const Memory = emulator.Memory;
const Opcode = CPU.Opcode;

const START_ADDR: u16 = 0x3000;
const START_HIGH: u8 = START_ADDR >> 8;
const START_LOW:  u8 = START_ADDR & 0xFF;

// --------------------------------------------------------------------------
//                              HELPER FUNCTIONS                             
// --------------------------------------------------------------------------

fn initMemory() Memory {
    var mem = Memory.init();

    // Set starting location
    mem.write(CPU.RESET_VECTOR + 0, START_LOW);
    mem.write(CPU.RESET_VECTOR + 1, START_HIGH);

    return mem;
}

fn initCPU(memory: *Memory) CPU {
    var cpu = CPU.init(memory);

    // Execute startup
    cpu.run(CPU.RESET_CYCLES);

    return cpu;
}

fn getInstructionCycles(cpu: *CPU, opcode: Opcode) u32 {
    return cpu.instruction_table[@intFromEnum(opcode)].cycles;
}

fn testLoadRegisterFlags(cpu: *CPU, opcode: Opcode) !void {
    const cycles = getInstructionCycles(cpu, opcode);

    cpu.writeByte(START_ADDR + 0, @intFromEnum(opcode));
    cpu.writeByte(START_ADDR + 1, 0x80);
    cpu.run(cycles);

    try testing.expectEqual(cpu.getFlag(.Z), false);
    try testing.expectEqual(cpu.getFlag(.N), true);

    cpu.writeByte(START_ADDR + 2, @intFromEnum(opcode));
    cpu.writeByte(START_ADDR + 3, 0x00);
    cpu.run(cycles);

    try testing.expectEqual(cpu.getFlag(.Z), true);
    try testing.expectEqual(cpu.getFlag(.N), false);
}

fn testLoadRegisterIMM(cpu: *CPU, opcode: Opcode, register: *u8) !void {
    const cycles = getInstructionCycles(cpu, opcode);

    cpu.writeByte(START_ADDR + 0, @intFromEnum(opcode));
    cpu.writeByte(START_ADDR + 1, 0x11);
    cpu.run(cycles);

    try testing.expectEqual(register.*, 0x11);
    try testing.expectEqual(cpu.cycles, 0);
}

fn testLoadRegisterZPG(cpu: *CPU, opcode: Opcode, register: *u8) !void {
    const cycles = getInstructionCycles(cpu, opcode);

    cpu.writeByte(START_ADDR + 0, @intFromEnum(opcode));
    cpu.writeByte(START_ADDR + 1, 0x32);
    cpu.writeByte(0x0032, 0x33);
    cpu.run(cycles);

    try testing.expectEqual(register.*, 0x33);
    try testing.expectEqual(cpu.cycles, 0);
}

fn testLoadRegisterZPX(cpu: *CPU, opcode: Opcode, register: *u8) !void {
    const cycles = getInstructionCycles(cpu, opcode);

    cpu.writeByte(START_ADDR + 0, @intFromEnum(opcode));
    cpu.writeByte(START_ADDR + 1, 0x44);
    cpu.writeByte(0x0045, 0x55);
    cpu.x = 0x01; // No wrap around
    cpu.run(cycles);

    try testing.expectEqual(register.*, 0x55);
    try testing.expectEqual(cpu.cycles, 0);

    cpu.writeByte(START_ADDR + 2, @intFromEnum(opcode));
    cpu.writeByte(START_ADDR + 3, 0xFF);
    cpu.writeByte(0x0001, 0x60);
    cpu.x = 0x02; // Address wraps around
    cpu.run(cycles);

    try testing.expectEqual(register.*, 0x60);
    try testing.expectEqual(cpu.cycles, 0);
}

fn testLoadRegisterZPY(cpu: *CPU, opcode: Opcode, register: *u8) !void {
    const cycles = getInstructionCycles(cpu, opcode);

    cpu.writeByte(START_ADDR + 0, @intFromEnum(opcode));
    cpu.writeByte(START_ADDR + 1, 0x44);
    cpu.writeByte(0x0045, 0x55);
    cpu.y = 0x01; // No wrap around
    cpu.run(cycles);

    try testing.expectEqual(register.*, 0x55);
    try testing.expectEqual(cpu.cycles, 0);

    cpu.writeByte(START_ADDR + 2, @intFromEnum(opcode));
    cpu.writeByte(START_ADDR + 3, 0xFF);
    cpu.writeByte(0x0001, 0x60);
    cpu.y = 0x02; // Address wraps around
    cpu.run(cycles);

    try testing.expectEqual(register.*, 0x60);
    try testing.expectEqual(cpu.cycles, 0);
}

fn testLoadRegisterABS(cpu: *CPU, opcode: Opcode, register: *u8) !void {
    const cycles = getInstructionCycles(cpu, opcode);

    cpu.writeByte(START_ADDR + 0, @intFromEnum(opcode));
    cpu.writeWord(START_ADDR + 1, 0x1234);
    cpu.writeByte(0x1234, 0x67);
    cpu.run(cycles);

    try testing.expectEqual(register.*, 0x67);
    try testing.expectEqual(cpu.cycles, 0);
}

fn testLoadRegisterABX(cpu: *CPU, opcode: Opcode, register: *u8) !void {
    const cycles = getInstructionCycles(cpu, opcode);

    cpu.writeByte(START_ADDR + 0, @intFromEnum(opcode));
    cpu.writeWord(START_ADDR + 1, 0x5678);
    cpu.writeByte(0x5679, 0x72);
    cpu.x = 0x01; // No page crossed
    cpu.run(cycles);

    try testing.expectEqual(register.*, 0x72);
    try testing.expectEqual(cpu.cycles, 0);

    cpu.writeByte(START_ADDR + 3, @intFromEnum(opcode));
    cpu.writeWord(START_ADDR + 4, 0x6789);
    cpu.writeByte(0x3005, 0x67);
    cpu.writeByte(0x6800, 0x79);
    cpu.x = 0x77; // Page crossed
    cpu.run(cycles + 1);

    try testing.expectEqual(register.*, 0x79);
    try testing.expectEqual(cpu.cycles, 0);
}

fn testLoadRegisterABY(cpu: *CPU, opcode: Opcode, register: *u8) !void {
    const cycles = getInstructionCycles(cpu, opcode);

    cpu.writeByte(START_ADDR + 0, @intFromEnum(opcode));
    cpu.writeWord(START_ADDR + 1, 0x5678);
    cpu.writeByte(0x5679, 0x72);
    cpu.y = 0x01; // No page crossed
    cpu.run(cycles);

    try testing.expectEqual(register.*, 0x72);
    try testing.expectEqual(cpu.cycles, 0);

    cpu.writeByte(START_ADDR + 3, @intFromEnum(opcode));
    cpu.writeByte(START_ADDR + 4, 0x89);
    cpu.writeByte(0x3005, 0x67);
    cpu.writeByte(0x6800, 0x79);
    cpu.y = 0x77; // Page crossed
    cpu.run(cycles + 1);

    try testing.expectEqual(register.*, 0x79);
    try testing.expectEqual(cpu.cycles, 0);
}

fn testLoadRegisterIDX(cpu: *CPU, opcode: Opcode, register: *u8) !void {
    const cycles = getInstructionCycles(cpu, opcode);

    cpu.writeByte(START_ADDR + 0, @intFromEnum(opcode));
    cpu.writeByte(START_ADDR + 1, 0x84);
    cpu.writeWord(0x0085, 0x9190);
    cpu.writeByte(0x9190, 0x95);
    cpu.x = 0x01; // No wrap around
    cpu.run(cycles);

    try testing.expectEqual(register.*, 0x95);
    try testing.expectEqual(cpu.cycles, 0);

    cpu.writeByte(START_ADDR + 2, @intFromEnum(opcode));
    cpu.writeByte(START_ADDR + 3, 0x85);
    cpu.writeWord(0x0000, 0x9291);
    cpu.writeByte(0x9291, 0x99);
    cpu.x = 0x7B; // Address wraps around
    cpu.run(cycles);

    try testing.expectEqual(register.*, 0x99);
    try testing.expectEqual(cpu.cycles, 0);
}

fn testLoadRegisterIDY(cpu: *CPU, opcode: Opcode, register: *u8) !void {
    const cycles = getInstructionCycles(cpu, opcode);

    cpu.writeByte(START_ADDR + 0, @intFromEnum(opcode));
    cpu.writeByte(START_ADDR + 1, 0x84);
    cpu.writeWord(0x0084, 0x9190);
    cpu.writeByte(0x9191, 0xA1);
    cpu.y = 0x01; // No page crossed
    cpu.run(cycles);

    try testing.expectEqual(register.*, 0xA1);
    try testing.expectEqual(cpu.cycles, 0);

    cpu.writeByte(START_ADDR + 2, @intFromEnum(opcode));
    cpu.writeByte(START_ADDR + 3, 0x85);
    cpu.writeWord(0x0085, 0x9291);
    cpu.writeByte(0x9300, 0xA5);
    cpu.y = 0x6F; // Page crossed
    cpu.run(cycles + 1);

    try testing.expectEqual(register.*, 0xA5);
    try testing.expectEqual(cpu.cycles, 0);
}

// --------------------------------------------------------------------------
//                               CPU CORE TESTS                              
// --------------------------------------------------------------------------

test "CPU Cycles" {
    var mem = Memory.init();
    var cpu = CPU.init(&mem);

    cpu.run(4); // Startup/Reset takes 7 cycles

    try testing.expectEqual(cpu.cycles, 3); // 3 cycles remaining
}

// --------------------------------------------------------------------------
//                              INSTRUCTION TESTS                            
// --------------------------------------------------------------------------

// ------------------------- LDA - Load accumulator -------------------------

test "LDA Flags" {
    var mem = initMemory();
    var cpu = initCPU(&mem);
    
    try testLoadRegisterFlags(&cpu, .LDA_IMM);
}

test "LDA IMM" {
    var mem = initMemory();
    var cpu = initCPU(&mem);

    try testLoadRegisterIMM(&cpu, .LDA_IMM, &cpu.a);
}

test "LDA ZPG" {
    var mem = initMemory();
    var cpu = initCPU(&mem);

    try testLoadRegisterZPG(&cpu, .LDA_ZPG, &cpu.a);
}

test "LDA ZPX" {
    var mem = initMemory();
    var cpu = initCPU(&mem);

    try testLoadRegisterZPX(&cpu, .LDA_ZPX, &cpu.a);
}

test "LDA ABS" {
    var mem = initMemory();
    var cpu = initCPU(&mem);

    try testLoadRegisterABS(&cpu, .LDA_ABS, &cpu.a);
}

test "LDA ABX" {
    var mem = initMemory();
    var cpu = initCPU(&mem);

    try testLoadRegisterABX(&cpu, .LDA_ABX, &cpu.a);
}

test "LDA ABY" {
    var mem = initMemory();
    var cpu = initCPU(&mem);

    try testLoadRegisterABY(&cpu, .LDA_ABY, &cpu.a);
}

test "LDA IDX" {
    var mem = initMemory();
    var cpu = initCPU(&mem);

    try testLoadRegisterIDX(&cpu, .LDA_IDX, &cpu.a);
}

test "LDA IDY" {
    var mem = initMemory();
    var cpu = initCPU(&mem);

    try testLoadRegisterIDY(&cpu, .LDA_IDY, &cpu.a);
}

// -------------------------- LDX - Load X register -------------------------

test "LDX Flags" {
    var mem = initMemory();
    var cpu = initCPU(&mem);
    
    try testLoadRegisterFlags(&cpu, .LDX_IMM);
}

test "LDX IMM" {
    var mem = initMemory();
    var cpu = initCPU(&mem);

    try testLoadRegisterIMM(&cpu, .LDX_IMM, &cpu.x);
}

test "LDX ZPG" {
    var mem = initMemory();
    var cpu = initCPU(&mem);

    try testLoadRegisterZPG(&cpu, .LDX_ZPG, &cpu.x);
}

test "LDX ZPY" {
    var mem = initMemory();
    var cpu = initCPU(&mem);

    try testLoadRegisterZPY(&cpu, .LDX_ZPY, &cpu.x);
}

test "LDX ABS" {
    var mem = initMemory();
    var cpu = initCPU(&mem);

    try testLoadRegisterABS(&cpu, .LDX_ABS, &cpu.x);
}

test "LDX ABY" {
    var mem = initMemory();
    var cpu = initCPU(&mem);

    try testLoadRegisterABY(&cpu, .LDX_ABY, &cpu.x);
}

// -------------------------- LDY - Load Y register -------------------------

test "LDY Flags" {
    var mem = initMemory();
    var cpu = initCPU(&mem);
    
    try testLoadRegisterFlags(&cpu, .LDY_IMM);
}

test "LDY IMM" {
    var mem = initMemory();
    var cpu = initCPU(&mem);

    try testLoadRegisterIMM(&cpu, .LDY_IMM, &cpu.y);
}

test "LDY ZPG" {
    var mem = initMemory();
    var cpu = initCPU(&mem);

    try testLoadRegisterZPG(&cpu, .LDY_ZPG, &cpu.y);
}

test "LDY ZPX" {
    var mem = initMemory();
    var cpu = initCPU(&mem);

    try testLoadRegisterZPX(&cpu, .LDY_ZPX, &cpu.y);
}

test "LDY ABS" {
    var mem = initMemory();
    var cpu = initCPU(&mem);

    try testLoadRegisterABS(&cpu, .LDY_ABS, &cpu.y);
}

test "LDY ABX" {
    var mem = initMemory();
    var cpu = initCPU(&mem);

    try testLoadRegisterABX(&cpu, .LDY_ABX, &cpu.y);
}