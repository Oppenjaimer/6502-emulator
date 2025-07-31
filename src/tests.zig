const std = @import("std");
const testing = std.testing;

const emulator = @import("emulator.zig");
const CPU = emulator.CPU;
const Memory = emulator.Memory;
const Opcode = CPU.Opcode;

// --------------------------------------------------------------------------
//                                  CONSTANTS                                
// --------------------------------------------------------------------------

const START_ADDR: u16 = 0x3000;
const START_HIGH: u8 = START_ADDR >> 8;
const START_LOW:  u8 = START_ADDR & 0xFF;

const LogicalOp = *const fn (u8, u8) u8;

// --------------------------------------------------------------------------
//                              HELPER FUNCTIONS                             
// --------------------------------------------------------------------------

// ----------------------------- Initialization -----------------------------

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

// --------------------------- Logical operations ---------------------------

fn logicalAND(a: u8, b: u8) u8 {
    return a & b;
}

fn logicalOR(a: u8, b: u8) u8 {
    return a | b;
}

fn logicalXOR(a: u8, b: u8) u8 {
    return a ^ b;
}

// ------------------------------ Miscellaneous -----------------------------

fn getInstructionCycles(cpu: *CPU, opcode: Opcode) u32 {
    return cpu.instruction_table[@intFromEnum(opcode)].cycles;
}

// --------------------------------------------------------------------------
//                               TEST FUNCTIONS                              
// --------------------------------------------------------------------------

// ------------------------------ Load register -----------------------------

fn testLoadRegisterFlags(cpu: *CPU, opcode: Opcode) !void {
    const cycles = getInstructionCycles(cpu, opcode);

    cpu.writeByte(START_ADDR + 0, @intFromEnum(opcode));
    cpu.writeByte(START_ADDR + 1, 0x80); // Assume immediate mode

    cpu.run(cycles);

    try testing.expectEqual(cpu.getFlag(.Z), false);
    try testing.expectEqual(cpu.getFlag(.N), true);

    cpu.writeByte(START_ADDR + 2, @intFromEnum(opcode));
    cpu.writeByte(START_ADDR + 3, 0x00); // Assume immediate mode

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

// ----------------------------- Store register -----------------------------

fn testStoreRegisterZPG(cpu: *CPU, opcode: Opcode, register: *u8) !void {
    const cycles = getInstructionCycles(cpu, opcode);

    cpu.writeByte(START_ADDR + 0, @intFromEnum(opcode));
    cpu.writeByte(START_ADDR + 1, 0x32);

    register.* = 0xAB;
    cpu.run(cycles);

    try testing.expectEqual(cpu.readByte(0x0032), 0xAB);
    try testing.expectEqual(cpu.cycles, 0);
}

fn testStoreRegisterZPX(cpu: *CPU, opcode: Opcode, register: *u8) !void {
    const cycles = getInstructionCycles(cpu, opcode);

    cpu.writeByte(START_ADDR + 0, @intFromEnum(opcode));
    cpu.writeByte(START_ADDR + 1, 0x44);

    cpu.x = 0x01; // No wrap around
    register.* = 0x55;
    cpu.run(cycles);

    try testing.expectEqual(cpu.readByte(0x0045), 0x55);
    try testing.expectEqual(cpu.cycles, 0);

    cpu.writeByte(START_ADDR + 2, @intFromEnum(opcode));
    cpu.writeByte(START_ADDR + 3, 0xFF);

    cpu.x = 0x02; // Address wraps around
    register.* = 0x60;
    cpu.run(cycles);

    try testing.expectEqual(cpu.readByte(0x0001), 0x60);
    try testing.expectEqual(cpu.cycles, 0);
}

fn testStoreRegisterZPY(cpu: *CPU, opcode: Opcode, register: *u8) !void {
    const cycles = getInstructionCycles(cpu, opcode);

    cpu.writeByte(START_ADDR + 0, @intFromEnum(opcode));
    cpu.writeByte(START_ADDR + 1, 0x44);

    cpu.y = 0x01; // No wrap around
    register.* = 0x55;
    cpu.run(cycles);

    try testing.expectEqual(cpu.readByte(0x0045), 0x55);
    try testing.expectEqual(cpu.cycles, 0);

    cpu.writeByte(START_ADDR + 2, @intFromEnum(opcode));
    cpu.writeByte(START_ADDR + 3, 0xFF);

    cpu.y = 0x02; // Address wraps around
    register.* = 0x60;
    cpu.run(cycles);

    try testing.expectEqual(cpu.readByte(0x0001), 0x60);
    try testing.expectEqual(cpu.cycles, 0);
}

fn testStoreRegisterABS(cpu: *CPU, opcode: Opcode, register: *u8) !void {
    const cycles = getInstructionCycles(cpu, opcode);

    cpu.writeByte(START_ADDR + 0, @intFromEnum(opcode));
    cpu.writeWord(START_ADDR + 1, 0x1234);

    register.* = 0x67;
    cpu.run(cycles);

    try testing.expectEqual(cpu.readByte(0x1234), 0x67);
    try testing.expectEqual(cpu.cycles, 0);
}

fn testStoreRegisterABX(cpu: *CPU, opcode: Opcode, register: *u8) !void {
    const cycles = getInstructionCycles(cpu, opcode);

    cpu.writeByte(START_ADDR + 0, @intFromEnum(opcode));
    cpu.writeWord(START_ADDR + 1, 0x5678);

    cpu.x = 0x01;
    register.* = 0x72;
    cpu.run(cycles);

    try testing.expectEqual(cpu.readByte(0x5679), 0x72);
    try testing.expectEqual(cpu.cycles, 0);
}

fn testStoreRegisterABY(cpu: *CPU, opcode: Opcode, register: *u8) !void {
    const cycles = getInstructionCycles(cpu, opcode);

    cpu.writeByte(START_ADDR + 0, @intFromEnum(opcode));
    cpu.writeWord(START_ADDR + 1, 0x5678);

    cpu.y = 0x01;
    register.* = 0x72;
    cpu.run(cycles);

    try testing.expectEqual(cpu.readByte(0x5679), 0x72);
    try testing.expectEqual(cpu.cycles, 0);
}

fn testStoreRegisterIDX(cpu: *CPU, opcode: Opcode, register: *u8) !void {
    const cycles = getInstructionCycles(cpu, opcode);

    cpu.writeByte(START_ADDR + 0, @intFromEnum(opcode));
    cpu.writeByte(START_ADDR + 1, 0x84);
    cpu.writeWord(0x0085, 0x9190);

    cpu.x = 0x01; // No wrap around
    register.* = 0x95;
    cpu.run(cycles);

    try testing.expectEqual(cpu.readByte(0x9190), 0x95);
    try testing.expectEqual(cpu.cycles, 0);

    cpu.writeByte(START_ADDR + 2, @intFromEnum(opcode));
    cpu.writeByte(START_ADDR + 3, 0x85);
    cpu.writeWord(0x0000, 0x9291);

    cpu.x = 0x7B; // Address wraps around
    register.* = 0x99;
    cpu.run(cycles);

    try testing.expectEqual(cpu.readByte(0x9291), 0x99);
    try testing.expectEqual(cpu.cycles, 0);
}

fn testStoreRegisterIDY(cpu: *CPU, opcode: Opcode, register: *u8) !void {
    const cycles = getInstructionCycles(cpu, opcode);

    cpu.writeByte(START_ADDR + 0, @intFromEnum(opcode));
    cpu.writeByte(START_ADDR + 1, 0x84);
    cpu.writeWord(0x0084, 0x9190);

    cpu.y = 0x01; // No page crossed
    register.* = 0xA1;
    cpu.run(cycles);

    try testing.expectEqual(cpu.readByte(0x9191), 0xA1);
    try testing.expectEqual(cpu.cycles, 0);
}

// ---------------------------- Transfer register ---------------------------

fn testTransferRegisterFlags(cpu: *CPU, opcode: Opcode, from: *u8) !void {
    const cycles = getInstructionCycles(cpu, opcode);

    cpu.writeByte(START_ADDR + 0, @intFromEnum(opcode));

    from.* = 0xBA;
    cpu.run(cycles);

    try testing.expectEqual(cpu.getFlag(.Z), false);
    try testing.expectEqual(cpu.getFlag(.N), true);

    cpu.writeByte(START_ADDR + 1, @intFromEnum(opcode));

    from.* = 0x00;
    cpu.run(cycles);

    try testing.expectEqual(cpu.getFlag(.Z), true);
    try testing.expectEqual(cpu.getFlag(.N), false);
}

fn testTransferRegisterIMM(cpu: *CPU, opcode: Opcode, from: *u8, to: *u8) !void {
    const cycles = getInstructionCycles(cpu, opcode);

    cpu.writeByte(START_ADDR, @intFromEnum(opcode));

    from.* = 0x09;
    cpu.run(cycles);

    try testing.expectEqual(to.*, 0x09);
    try testing.expectEqual(cpu.cycles, 0);
}

// ----------------------------- Stack push/pull ----------------------------

fn testStackPushIMM(cpu: *CPU, opcode: Opcode, register: *u8) !void {
    const cycles = getInstructionCycles(cpu, opcode);

    cpu.writeByte(START_ADDR, @intFromEnum(opcode));

    register.* = 0x25;
    cpu.run(cycles);

    try testing.expectEqual(cpu.readByte(cpu.getStackAddress() + 1), 0x25);
    try testing.expectEqual(cpu.sp, CPU.RESET_SP - 1);
    try testing.expectEqual(cpu.cycles, 0);
}

fn testStackPullFlags(cpu: *CPU, opcode: Opcode) !void {
    const cycles = getInstructionCycles(cpu, opcode);

    cpu.writeByte(START_ADDR + 0, @intFromEnum(opcode));

    cpu.stackPush(0x80);
    cpu.run(cycles);

    try testing.expectEqual(cpu.getFlag(.Z), false);
    try testing.expectEqual(cpu.getFlag(.N), true);

    cpu.writeByte(START_ADDR + 1, @intFromEnum(opcode));

    cpu.stackPush(0x00);
    cpu.run(cycles);

    try testing.expectEqual(cpu.getFlag(.Z), true);
    try testing.expectEqual(cpu.getFlag(.N), false);
}

fn testStackPullIMM(cpu: *CPU, opcode: Opcode, register: *u8) !void {
    const cycles = getInstructionCycles(cpu, opcode);

    cpu.writeByte(START_ADDR, @intFromEnum(opcode));
    
    cpu.stackPush(0x33);
    cpu.run(cycles);

    try testing.expectEqual(register.*, 0x33);
    try testing.expectEqual(cpu.sp, CPU.RESET_SP);
    try testing.expectEqual(cpu.cycles, 0);
}

// --------------------------- Logical operations ---------------------------

fn testLogicalOperationFlags(cpu: *CPU, opcode: Opcode, op: LogicalOp) !void {
    const cycles = getInstructionCycles(cpu, opcode);
    const result = op(0x0F, 0xF0);

    cpu.writeByte(START_ADDR + 0, @intFromEnum(opcode));
    cpu.writeByte(START_ADDR + 1, 0x0F); // Assume immediate mode

    cpu.a = 0xF0;
    cpu.run(cycles);

    try testing.expectEqual(cpu.getFlag(.Z), result == 0x00);
    try testing.expectEqual(cpu.getFlag(.N), CPU.isBitSet(result, 7));
}

fn testLogicalOperationIMM(cpu: *CPU, opcode: Opcode, op: LogicalOp) !void {
    const cycles = getInstructionCycles(cpu, opcode);
    const result = op(0xCC, 0xB1);

    cpu.writeByte(START_ADDR + 0, @intFromEnum(opcode));
    cpu.writeByte(START_ADDR + 1, 0xCC);

    cpu.a = 0xB1;
    cpu.run(cycles);

    try testing.expectEqual(cpu.a, result);
    try testing.expectEqual(cpu.cycles, 0);
}

fn testLogicalOperationZPG(cpu: *CPU, opcode: Opcode, op: LogicalOp) !void {
    const cycles = getInstructionCycles(cpu, opcode);
    const result = op(0xCC, 0xB1);

    cpu.writeByte(START_ADDR + 0, @intFromEnum(opcode));
    cpu.writeByte(START_ADDR + 1, 0x11);
    cpu.writeByte(0x0011, 0xCC);

    cpu.a = 0xB1;
    cpu.run(cycles);

    try testing.expectEqual(cpu.a, result);
    try testing.expectEqual(cpu.cycles, 0);
}

fn testLogicalOperationZPX(cpu: *CPU, opcode: Opcode, op: LogicalOp) !void {
    const cycles = getInstructionCycles(cpu, opcode);
    const result = op(0xCC, 0xB1);

    cpu.writeByte(START_ADDR + 0, @intFromEnum(opcode));
    cpu.writeByte(START_ADDR + 1, 0x11);
    cpu.writeByte(0x0012, 0xCC);

    cpu.x = 0x01; // No wrap around
    cpu.a = 0xB1;
    cpu.run(cycles);

    try testing.expectEqual(cpu.a, result);
    try testing.expectEqual(cpu.cycles, 0);

    cpu.writeByte(START_ADDR + 2, @intFromEnum(opcode));
    cpu.writeByte(START_ADDR + 3, 0x11);
    cpu.writeByte(0x0010, 0xCC);

    cpu.x = 0xFF; // Address wraps around
    cpu.a = 0xB1;
    cpu.run(cycles);

    try testing.expectEqual(cpu.a, result);
    try testing.expectEqual(cpu.cycles, 0);
}

fn testLogicalOperationABS(cpu: *CPU, opcode: Opcode, op: LogicalOp) !void {
    const cycles = getInstructionCycles(cpu, opcode);
    const result = op(0xCC, 0xB1);

    cpu.writeByte(START_ADDR + 0, @intFromEnum(opcode));
    cpu.writeWord(START_ADDR + 1, 0x1234);
    cpu.writeByte(0x1234, 0xCC);

    cpu.a = 0xB1;
    cpu.run(cycles);

    try testing.expectEqual(cpu.a, result);
    try testing.expectEqual(cpu.cycles, 0);
}

fn testLogicalOperationABX(cpu: *CPU, opcode: Opcode, op: LogicalOp) !void {
    const cycles = getInstructionCycles(cpu, opcode);
    const result = op(0xCC, 0xB1);

    cpu.writeByte(START_ADDR + 0, @intFromEnum(opcode));
    cpu.writeWord(START_ADDR + 1, 0x5678);
    cpu.writeByte(0x5679, 0xCC);

    cpu.x = 0x01; // No page crossed
    cpu.a = 0xB1;
    cpu.run(cycles);

    try testing.expectEqual(cpu.a, result);
    try testing.expectEqual(cpu.cycles, 0);

    cpu.writeByte(START_ADDR + 3, @intFromEnum(opcode));
    cpu.writeWord(START_ADDR + 4, 0x6789);
    cpu.writeByte(0x3005, 0x67);
    cpu.writeByte(0x6800, 0xCC);

    cpu.x = 0x77; // Page crossed
    cpu.a = 0xB1;
    cpu.run(cycles + 1);

    try testing.expectEqual(cpu.a, result);
    try testing.expectEqual(cpu.cycles, 0);
}

fn testLogicalOperationABY(cpu: *CPU, opcode: Opcode, op: LogicalOp) !void {
    const cycles = getInstructionCycles(cpu, opcode);
    const result = op(0xCC, 0xB1);

    cpu.writeByte(START_ADDR + 0, @intFromEnum(opcode));
    cpu.writeWord(START_ADDR + 1, 0x5678);
    cpu.writeByte(0x5679, 0xCC);

    cpu.y = 0x01; // No page crossed
    cpu.a = 0xB1;
    cpu.run(cycles);

    try testing.expectEqual(cpu.a, result);
    try testing.expectEqual(cpu.cycles, 0);

    cpu.writeByte(START_ADDR + 3, @intFromEnum(opcode));
    cpu.writeWord(START_ADDR + 4, 0x6789);
    cpu.writeByte(0x3005, 0x67);
    cpu.writeByte(0x6800, 0xCC);

    cpu.y = 0x77; // Page crossed
    cpu.a = 0xB1;
    cpu.run(cycles + 1);

    try testing.expectEqual(cpu.a, result);
    try testing.expectEqual(cpu.cycles, 0);
}

fn testLogicalOperationIDX(cpu: *CPU, opcode: Opcode, op: LogicalOp) !void {
    const cycles = getInstructionCycles(cpu, opcode);
    const result = op(0xCC, 0xB1);

    cpu.writeByte(START_ADDR + 0, @intFromEnum(opcode));
    cpu.writeByte(START_ADDR + 1, 0x84);
    cpu.writeWord(0x0085, 0x9190);
    cpu.writeByte(0x9190, 0xCC);

    cpu.x = 0x01; // No wrap around
    cpu.a = 0xB1;
    cpu.run(cycles);

    try testing.expectEqual(cpu.a, result);
    try testing.expectEqual(cpu.cycles, 0);

    cpu.writeByte(START_ADDR + 2, @intFromEnum(opcode));
    cpu.writeByte(START_ADDR + 3, 0x85);
    cpu.writeWord(0x0000, 0x9291);
    cpu.writeByte(0x9291, 0xCC);

    cpu.x = 0x7B; // Address wraps around
    cpu.a = 0xB1;
    cpu.run(cycles);

    try testing.expectEqual(cpu.a, result);
    try testing.expectEqual(cpu.cycles, 0);
}

fn testLogicalOperationIDY(cpu: *CPU, opcode: Opcode, op: LogicalOp) !void {
    const cycles = getInstructionCycles(cpu, opcode);
    const result = op(0xCC, 0xB1);

    cpu.writeByte(START_ADDR + 0, @intFromEnum(opcode));
    cpu.writeByte(START_ADDR + 1, 0x84);
    cpu.writeWord(0x0084, 0x9190);
    cpu.writeByte(0x9191, 0xCC);

    cpu.y = 0x01; // No page crossed
    cpu.a = 0xB1;
    cpu.run(cycles);

    try testing.expectEqual(cpu.a, result);
    try testing.expectEqual(cpu.cycles, 0);

    cpu.writeByte(START_ADDR + 2, @intFromEnum(opcode));
    cpu.writeByte(START_ADDR + 3, 0x85);
    cpu.writeWord(0x0085, 0x9291);
    cpu.writeByte(0x9300, 0xCC);

    cpu.y = 0x6F; // Page crossed
    cpu.a = 0xB1;
    cpu.run(cycles + 1);

    try testing.expectEqual(cpu.a, result);
    try testing.expectEqual(cpu.cycles, 0);
}

// -------------------------------- Bit test --------------------------------

fn testBitTestZPG(cpu: *CPU, opcode: Opcode) !void {
    const cycles = getInstructionCycles(cpu, opcode);

    cpu.writeByte(START_ADDR + 0, @intFromEnum(opcode));
    cpu.writeByte(START_ADDR + 1, 0x51);
    cpu.writeByte(0x0051, 0x93);

    cpu.a = 0x01;
    cpu.run(cycles);

    try testing.expectEqual(cpu.getFlag(.Z), false);
    try testing.expectEqual(cpu.getFlag(.V), false);
    try testing.expectEqual(cpu.getFlag(.N), true);
    try testing.expectEqual(cpu.cycles, 0);
}

fn testBitTestABS(cpu: *CPU, opcode: Opcode) !void {
    const cycles = getInstructionCycles(cpu, opcode);

    cpu.writeByte(START_ADDR + 0, @intFromEnum(opcode));
    cpu.writeWord(START_ADDR + 1, 0x9876);
    cpu.writeByte(0x9876, 0x44);

    cpu.a = 0x00;
    cpu.run(cycles);

    try testing.expectEqual(cpu.getFlag(.Z), true);
    try testing.expectEqual(cpu.getFlag(.V), true);
    try testing.expectEqual(cpu.getFlag(.N), false);
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

// ------------------------- STA - Store accumulator ------------------------

test "STA ZPG" {
    var mem = initMemory();
    var cpu = initCPU(&mem);

    try testStoreRegisterZPG(&cpu, .STA_ZPG, &cpu.a);
}

test "STA ZPX" {
    var mem = initMemory();
    var cpu = initCPU(&mem);

    try testStoreRegisterZPX(&cpu, .STA_ZPX, &cpu.a);
}

test "STA ABS" {
    var mem = initMemory();
    var cpu = initCPU(&mem);

    try testStoreRegisterABS(&cpu, .STA_ABS, &cpu.a);
}

test "STA ABX" {
    var mem = initMemory();
    var cpu = initCPU(&mem);

    try testStoreRegisterABX(&cpu, .STA_ABX, &cpu.a);
}

test "STA ABY" {
    var mem = initMemory();
    var cpu = initCPU(&mem);

    try testStoreRegisterABY(&cpu, .STA_ABY, &cpu.a);
}

test "STA IDX" {
    var mem = initMemory();
    var cpu = initCPU(&mem);

    try testStoreRegisterIDX(&cpu, .STA_IDX, &cpu.a);
}

test "STA IDY" {
    var mem = initMemory();
    var cpu = initCPU(&mem);

    try testStoreRegisterIDY(&cpu, .STA_IDY, &cpu.a);
}

// ------------------------- STX - Store X register -------------------------

test "STX ZPG" {
    var mem = initMemory();
    var cpu = initCPU(&mem);

    try testStoreRegisterZPG(&cpu, .STX_ZPG, &cpu.x);
}

test "STX ZPY" {
    var mem = initMemory();
    var cpu = initCPU(&mem);

    try testStoreRegisterZPY(&cpu, .STX_ZPY, &cpu.x);
}

test "STX ABS" {
    var mem = initMemory();
    var cpu = initCPU(&mem);

    try testStoreRegisterABS(&cpu, .STX_ABS, &cpu.x);
}

// ------------------------- STY - Store Y register -------------------------

test "STY ZPG" {
    var mem = initMemory();
    var cpu = initCPU(&mem);

    try testStoreRegisterZPG(&cpu, .STY_ZPG, &cpu.y);
}

test "STY ZPX" {
    var mem = initMemory();
    var cpu = initCPU(&mem);

    try testStoreRegisterZPX(&cpu, .STY_ZPX, &cpu.y);
}

test "STY ABS" {
    var mem = initMemory();
    var cpu = initCPU(&mem);

    try testStoreRegisterABS(&cpu, .STY_ABS, &cpu.y);
}

// --------------------- TAX - Transfer accumulator to X --------------------

test "TAX Flags" {
    var mem = initMemory();
    var cpu = initCPU(&mem);

    try testTransferRegisterFlags(&cpu, .TAX_IMP, &cpu.a);
}

test "TAX IMM" {
    var mem = initMemory();
    var cpu = initCPU(&mem);

    try testTransferRegisterIMM(&cpu, .TAX_IMP, &cpu.a, &cpu.x);
}

// --------------------- TAY - Transfer accumulator to Y --------------------

test "TAY Flags" {
    var mem = initMemory();
    var cpu = initCPU(&mem);

    try testTransferRegisterFlags(&cpu, .TAY_IMP, &cpu.a);
}

test "TAY IMM" {
    var mem = initMemory();
    var cpu = initCPU(&mem);

    try testTransferRegisterIMM(&cpu, .TAY_IMP, &cpu.a, &cpu.y);
}

// --------------------- TXA - Transfer X to accumulator --------------------

test "TXA Flags" {
    var mem = initMemory();
    var cpu = initCPU(&mem);

    try testTransferRegisterFlags(&cpu, .TXA_IMP, &cpu.x);
}

test "TXA IMM" {
    var mem = initMemory();
    var cpu = initCPU(&mem);

    try testTransferRegisterIMM(&cpu, .TXA_IMP, &cpu.x, &cpu.a);
}

// --------------------- TYA - Transfer Y to accumulator --------------------

test "TYA Flags" {
    var mem = initMemory();
    var cpu = initCPU(&mem);

    try testTransferRegisterFlags(&cpu, .TYA_IMP, &cpu.y);
}

test "TYA IMM" {
    var mem = initMemory();
    var cpu = initCPU(&mem);

    try testTransferRegisterIMM(&cpu, .TYA_IMP, &cpu.y, &cpu.a);
}

// ------------------------- TSX - Transfer SP to X -------------------------

test "TSX Flags" {
    var mem = initMemory();
    var cpu = initCPU(&mem);

    try testTransferRegisterFlags(&cpu, .TSX_IMP, &cpu.sp);
}

test "TSX IMM" {
    var mem = initMemory();
    var cpu = initCPU(&mem);

    try testTransferRegisterIMM(&cpu, .TSX_IMP, &cpu.sp, &cpu.x);
}

// ------------------------- TXS - Transfer X to SP -------------------------

test "TXS IMM" {
    var mem = initMemory();
    var cpu = initCPU(&mem);

    try testTransferRegisterIMM(&cpu, .TXS_IMP, &cpu.x, &cpu.sp);
}

// -------------------- PHA - Push accumulator onto stack -------------------

test "PHA IMM" {
    var mem = initMemory();
    var cpu = initCPU(&mem);

    try testStackPushIMM(&cpu, .PHA_IMP, &cpu.a);
}

// ----------------- PHP - Push processor status onto stack -----------------

test "PHP IMM" {
    var mem = initMemory();
    var cpu = initCPU(&mem);

    try testStackPushIMM(&cpu, .PHP_IMP, &cpu.status);
}

// -------------------- PLA - Pull accumulator from stack -------------------

test "PLA Flags" {
    var mem = initMemory();
    var cpu = initCPU(&mem);

    try testStackPullFlags(&cpu, .PLA_IMP);
}

test "PLA IMM" {
    var mem = initMemory();
    var cpu = initCPU(&mem);

    try testStackPullIMM(&cpu, .PLA_IMP, &cpu.a);
}

// ----------------- PLP - Pull processor status from stack -----------------

test "PLP IMM" {
    var mem = initMemory();
    var cpu = initCPU(&mem);

    try testStackPullIMM(&cpu, .PLP_IMP, &cpu.status);
}

// ---------------------------- AND - Logical AND ---------------------------

test "AND Flags" {
    var mem = initMemory();
    var cpu = initCPU(&mem);

    try testLogicalOperationFlags(&cpu, .AND_IMM, &logicalAND);
}

test "AND IMM" {
    var mem = initMemory();
    var cpu = initCPU(&mem);

    try testLogicalOperationIMM(&cpu, .AND_IMM, &logicalAND);
}

test "AND ZPG" {
    var mem = initMemory();
    var cpu = initCPU(&mem);

    try testLogicalOperationZPG(&cpu, .AND_ZPG, &logicalAND);
}

test "AND ZPX" {
    var mem = initMemory();
    var cpu = initCPU(&mem);

    try testLogicalOperationZPX(&cpu, .AND_ZPX, &logicalAND);
}

test "AND ABS" {
    var mem = initMemory();
    var cpu = initCPU(&mem);

    try testLogicalOperationABS(&cpu, .AND_ABS, &logicalAND);
}

test "AND ABX" {
    var mem = initMemory();
    var cpu = initCPU(&mem);

    try testLogicalOperationABX(&cpu, .AND_ABX, &logicalAND);
}

test "AND ABY" {
    var mem = initMemory();
    var cpu = initCPU(&mem);

    try testLogicalOperationABY(&cpu, .AND_ABY, &logicalAND);
}

test "AND IDX" {
    var mem = initMemory();
    var cpu = initCPU(&mem);

    try testLogicalOperationIDX(&cpu, .AND_IDX, &logicalAND);
}

test "AND IDY" {
    var mem = initMemory();
    var cpu = initCPU(&mem);

    try testLogicalOperationIDY(&cpu, .AND_IDY, &logicalAND);
}

// --------------------------- EOR - Exclusive OR ---------------------------

test "EOR Flags" {
    var mem = initMemory();
    var cpu = initCPU(&mem);

    try testLogicalOperationFlags(&cpu, .EOR_IMM, &logicalXOR);
}

test "EOR IMM" {
    var mem = initMemory();
    var cpu = initCPU(&mem);

    try testLogicalOperationIMM(&cpu, .EOR_IMM, &logicalXOR);
}

test "EOR ZPG" {
    var mem = initMemory();
    var cpu = initCPU(&mem);

    try testLogicalOperationZPG(&cpu, .EOR_ZPG, &logicalXOR);
}

test "EOR ZPX" {
    var mem = initMemory();
    var cpu = initCPU(&mem);

    try testLogicalOperationZPX(&cpu, .EOR_ZPX, &logicalXOR);
}

test "EOR ABS" {
    var mem = initMemory();
    var cpu = initCPU(&mem);

    try testLogicalOperationABS(&cpu, .EOR_ABS, &logicalXOR);
}

test "EOR ABX" {
    var mem = initMemory();
    var cpu = initCPU(&mem);

    try testLogicalOperationABX(&cpu, .EOR_ABX, &logicalXOR);
}

test "EOR ABY" {
    var mem = initMemory();
    var cpu = initCPU(&mem);

    try testLogicalOperationABY(&cpu, .EOR_ABY, &logicalXOR);
}

test "EOR IDX" {
    var mem = initMemory();
    var cpu = initCPU(&mem);

    try testLogicalOperationIDX(&cpu, .EOR_IDX, &logicalXOR);
}

test "EOR IDY" {
    var mem = initMemory();
    var cpu = initCPU(&mem);

    try testLogicalOperationIDY(&cpu, .EOR_IDY, &logicalXOR);
}

// ---------------------------- ORA - Logical OR ----------------------------

test "ORA Flags" {
    var mem = initMemory();
    var cpu = initCPU(&mem);

    try testLogicalOperationFlags(&cpu, .ORA_IMM, &logicalOR);
}

test "ORA IMM" {
    var mem = initMemory();
    var cpu = initCPU(&mem);

    try testLogicalOperationIMM(&cpu, .ORA_IMM, &logicalOR);
}

test "ORA ZPG" {
    var mem = initMemory();
    var cpu = initCPU(&mem);

    try testLogicalOperationZPG(&cpu, .ORA_ZPG, &logicalOR);
}

test "ORA ZPX" {
    var mem = initMemory();
    var cpu = initCPU(&mem);

    try testLogicalOperationZPX(&cpu, .ORA_ZPX, &logicalOR);
}

test "ORA ABS" {
    var mem = initMemory();
    var cpu = initCPU(&mem);

    try testLogicalOperationABS(&cpu, .ORA_ABS, &logicalOR);
}

test "ORA ABX" {
    var mem = initMemory();
    var cpu = initCPU(&mem);

    try testLogicalOperationABX(&cpu, .ORA_ABX, &logicalOR);
}

test "ORA ABY" {
    var mem = initMemory();
    var cpu = initCPU(&mem);

    try testLogicalOperationABY(&cpu, .ORA_ABY, &logicalOR);
}

test "ORA IDX" {
    var mem = initMemory();
    var cpu = initCPU(&mem);

    try testLogicalOperationIDX(&cpu, .ORA_IDX, &logicalOR);
}

test "ORA IDY" {
    var mem = initMemory();
    var cpu = initCPU(&mem);

    try testLogicalOperationIDY(&cpu, .ORA_IDY, &logicalOR);
}

// ----------------------------- BIT - Bit test -----------------------------

test "BIT ZPG" {
    var mem = initMemory();
    var cpu = initCPU(&mem);

    try testBitTestZPG(&cpu, .BIT_ZPG);
}

test "BIT ABS" {
    var mem = initMemory();
    var cpu = initCPU(&mem);

    try testBitTestABS(&cpu, .BIT_ABS);
}