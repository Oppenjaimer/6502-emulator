const std = @import("std");
const testing = std.testing;

const emulator = @import("emulator.zig");
const CPU = emulator.CPU;
const Memory = emulator.Memory;
const Opcode = CPU.Opcode;

// -----------------------------------------------------------------------------
//                                  CONSTANTS                                   
// -----------------------------------------------------------------------------

const START_ADDR: u16 = 0x3000;
const START_HIGH: u8 = START_ADDR >> 8;
const START_LOW:  u8 = START_ADDR & 0xFF;

const LogicalOp = *const fn (u8, u8) u8;
const ArithmeticOp = *const fn (u8, u8) u8;

const LoadRegSetupFn = *const fn (*CPU, u8) u1;
const StoreRegSetupFn = *const fn (*CPU) void;
const LogicalOpSetupFn = *const fn (*CPU, u8) u1;
const BitTestSetupFn = *const fn (*CPU, u8) void;

const TestContext = struct {
    mem: Memory,
    cpu: CPU,

    pub fn init() TestContext {
        var mem = initMemory();
        const cpu = initCPU(&mem);

        return TestContext {
            .mem = mem,
            .cpu = cpu,
        };
    }
};

// -----------------------------------------------------------------------------
//                              HELPER FUNCTIONS                                
// -----------------------------------------------------------------------------

// ----------------------------- Initialization --------------------------------

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

// --------------------------- Logical operations ------------------------------

fn logicalAND(a: u8, b: u8) u8 {
    return a & b;
}

fn logicalOR(a: u8, b: u8) u8 {
    return a | b;
}

fn logicalXOR(a: u8, b: u8) u8 {
    return a ^ b;
}

// ------------------------------ Miscellaneous --------------------------------

fn getInstructionCycles(cpu: *CPU, opcode: Opcode) u32 {
    return cpu.instruction_table[@intFromEnum(opcode)].cycles;
}

// -----------------------------------------------------------------------------
//                               TEST FUNCTIONS                                 
// -----------------------------------------------------------------------------

// ------------------------------ Load register --------------------------------

fn testLoadRegister(cpu: *CPU, opcode: Opcode, register: *u8, setup: LoadRegSetupFn) !void {
    const cycles = getInstructionCycles(cpu, opcode);

    cpu.writeByte(START_ADDR, @intFromEnum(opcode));
    const extra_cycle = setup(cpu, 0x80);

    cpu.setFlag(.Z, true);
    cpu.run(cycles + extra_cycle);

    try testing.expectEqual(cpu.getFlag(.Z), false);
    try testing.expectEqual(cpu.getFlag(.N), true);
    try testing.expectEqual(register.*, 0x80);
    try testing.expectEqual(cpu.cycles, 0);
}

fn setupLoadRegisterIMM(cpu: *CPU, value: u8) u1 {
    cpu.writeByte(START_ADDR + 1, value);

    return 0;
}

fn setupLoadRegisterZPG(cpu: *CPU, value: u8) u1 {
    cpu.writeByte(START_ADDR + 1, 0x11);
    cpu.writeByte(0x0011, value);

    return 0;
}

fn setupLoadRegisterZPXNoWrap(cpu: *CPU, value: u8) u1 {
    cpu.writeByte(START_ADDR + 1, 0x11);
    cpu.writeByte(0x0012, value);
    cpu.x = 0x01;

    return 0;
}

fn setupLoadRegisterZPXWrap(cpu: *CPU, value: u8) u1 {
    cpu.writeByte(START_ADDR + 1, 0xFF);
    cpu.writeByte(0x0000, value);
    cpu.x = 0x01;

    return 0;
}

fn setupLoadRegisterZPYNoWrap(cpu: *CPU, value: u8) u1 {
    cpu.writeByte(START_ADDR + 1, 0x11);
    cpu.writeByte(0x0012, value);
    cpu.y = 0x01;

    return 0;
}

fn setupLoadRegisterZPYWrap(cpu: *CPU, value: u8) u1 {
    cpu.writeByte(START_ADDR + 1, 0xFF);
    cpu.writeByte(0x0000, value);
    cpu.y = 0x01;

    return 0;
}

fn setupLoadRegisterABS(cpu: *CPU, value: u8) u1 {
    cpu.writeWord(START_ADDR + 1, 0x1234);
    cpu.writeByte(0x1234, value);

    return 0;
}

fn setupLoadRegisterABXNoCross(cpu: *CPU, value: u8) u1 {
    cpu.writeWord(START_ADDR + 1, 0x1234);
    cpu.writeByte(0x1235, value);
    cpu.x = 0x01;

    return 0;
}

fn setupLoadRegisterABXCross(cpu: *CPU, value: u8) u1 {
    cpu.writeWord(START_ADDR + 1, 0x10FF);
    cpu.writeByte(0x1100, value);
    cpu.x = 0x01;

    return 1;
}

fn setupLoadRegisterABYNoCross(cpu: *CPU, value: u8) u1 {
    cpu.writeWord(START_ADDR + 1, 0x1234);
    cpu.writeByte(0x1235, value);
    cpu.y = 0x01;

    return 0;
}

fn setupLoadRegisterABYCross(cpu: *CPU, value: u8) u1 {
    cpu.writeWord(START_ADDR + 1, 0x10FF);
    cpu.writeByte(0x1100, value);
    cpu.y = 0x01;

    return 1;
}

fn setupLoadRegisterIDXNoWrap(cpu: *CPU, value: u8) u1 {
    cpu.writeByte(START_ADDR + 1, 0x11);
    cpu.writeWord(0x0012, 0x1234);
    cpu.writeByte(0x1234, value);
    cpu.x = 0x01;

    return 0;
}

fn setupLoadRegisterIDXWrap(cpu: *CPU, value: u8) u1 {
    cpu.writeByte(START_ADDR + 1, 0xFF);
    cpu.writeWord(0x0000, 0x1234);
    cpu.writeByte(0x1234, value);
    cpu.x = 0x01;

    return 0;
}

fn setupLoadRegisterIDYNoCross(cpu: *CPU, value: u8) u1 {
    cpu.writeByte(START_ADDR + 1, 0x11);
    cpu.writeWord(0x0011, 0x1234);
    cpu.writeByte(0x1235, value);
    cpu.y = 0x01;

    return 0;
}

fn setupLoadRegisterIDYCross(cpu: *CPU, value: u8) u1 {
    cpu.writeByte(START_ADDR + 1, 0x11);
    cpu.writeWord(0x0011, 0x10FF);
    cpu.writeByte(0x1100, value);
    cpu.y = 0x01;

    return 1;
}

// ----------------------------- Store register --------------------------------

fn testStoreRegister(cpu: *CPU, opcode: Opcode, register: *u8, setup: StoreRegSetupFn) !void {
    const cycles = getInstructionCycles(cpu, opcode);

    cpu.writeByte(START_ADDR, @intFromEnum(opcode));
    setup(cpu);

    register.* = 0x80;
    cpu.run(cycles);

    try testing.expectEqual(cpu.readByte(0x0011), 0x80);
    try testing.expectEqual(cpu.cycles, 0);
}

fn setupStoreRegisterZPG(cpu: *CPU) void {
    cpu.writeByte(START_ADDR + 1, 0x11);
}

fn setupStoreRegisterZPXNoWrap(cpu: *CPU) void {
    cpu.writeByte(START_ADDR + 1, 0x10);
    cpu.x = 0x01;
}

fn setupStoreRegisterZPXWrap(cpu: *CPU) void {
    cpu.writeByte(START_ADDR + 1, 0xFF);
    cpu.x = 0x12;
}

fn setupStoreRegisterZPYNoWrap(cpu: *CPU) void {
    cpu.writeByte(START_ADDR + 1, 0x10);
    cpu.y = 0x01;
}

fn setupStoreRegisterZPYWrap(cpu: *CPU) void {
    cpu.writeByte(START_ADDR + 1, 0xFF);
    cpu.y = 0x12;
}

fn setupStoreRegisterABS(cpu: *CPU) void {
    cpu.writeWord(START_ADDR + 1, 0x0011);
}

fn setupStoreRegisterABX(cpu: *CPU) void {
    cpu.writeWord(START_ADDR + 1, 0x0010);
    cpu.x = 0x01;
}

fn setupStoreRegisterABY(cpu: *CPU) void {
    cpu.writeWord(START_ADDR + 1, 0x0010);
    cpu.y = 0x01;
}

fn setupStoreRegisterIDXNoWrap(cpu: *CPU) void {
    cpu.writeByte(START_ADDR + 1, 0x22);
    cpu.writeWord(0x0023, 0x0011);
    cpu.x = 0x01;
}

fn setupStoreRegisterIDXWrap(cpu: *CPU) void {
    cpu.writeByte(START_ADDR + 1, 0xFF);
    cpu.writeWord(0x0000, 0x0011);
    cpu.x = 0x01;
}

fn setupStoreRegisterIDY(cpu: *CPU) void {
    cpu.writeByte(START_ADDR + 1, 0x22);
    cpu.writeWord(0x0022, 0x0010);
    cpu.y = 0x01;
}

// ---------------------------- Transfer register ------------------------------

fn testTransferRegister(cpu: *CPU, opcode: Opcode, from: *u8, to: *u8, test_flags: bool) !void {
    const cycles = getInstructionCycles(cpu, opcode);

    cpu.writeByte(START_ADDR, @intFromEnum(opcode));

    if (test_flags) cpu.setFlag(.Z, true);
    from.* = 0x80;
    cpu.run(cycles);

    if (test_flags) {
        try testing.expectEqual(cpu.getFlag(.Z), false);
        try testing.expectEqual(cpu.getFlag(.N), true);
    }

    try testing.expectEqual(to.*, 0x80);
    try testing.expectEqual(cpu.cycles, 0);
}

// ----------------------------- Stack push/pull -------------------------------

fn testStackPush(cpu: *CPU, opcode: Opcode, register: *u8) !void {
    const cycles = getInstructionCycles(cpu, opcode);

    cpu.writeByte(START_ADDR, @intFromEnum(opcode));

    register.* = 0x11;
    cpu.run(cycles);

    try testing.expectEqual(cpu.readByte(cpu.getStackAddress() + 1), 0x11);
    try testing.expectEqual(cpu.sp, CPU.RESET_SP - 1);
    try testing.expectEqual(cpu.cycles, 0);
}

fn testStackPull(cpu: *CPU, opcode: Opcode, register: *u8) !void {
    const cycles = getInstructionCycles(cpu, opcode);

    cpu.writeByte(START_ADDR, @intFromEnum(opcode));

    cpu.setFlag(.Z, true);
    cpu.stackPush(0x80);
    cpu.run(cycles);

    try testing.expectEqual(cpu.getFlag(.Z), false);
    try testing.expectEqual(cpu.getFlag(.N), true);
    try testing.expectEqual(register.*, 0x80);
    try testing.expectEqual(cpu.sp, CPU.RESET_SP);
    try testing.expectEqual(cpu.cycles, 0);
}

// --------------------------- Logical operations ------------------------------

fn testLogicalOperation(cpu: *CPU, opcode: Opcode, op: LogicalOp, setup: LogicalOpSetupFn) !void {
    const cycles = getInstructionCycles(cpu, opcode);
    const result = op(0xCC, 0xB1);

    cpu.writeByte(START_ADDR, @intFromEnum(opcode));
    const extra_cycle = setup(cpu, 0xCC);

    cpu.a = 0xB1;
    cpu.run(cycles + extra_cycle);

    try testing.expectEqual(cpu.getFlag(.Z), result == 0x00);
    try testing.expectEqual(cpu.getFlag(.N), CPU.isBitSet(result, 7));
    try testing.expectEqual(cpu.a, result);
    try testing.expectEqual(cpu.cycles, 0);
}

fn setupLogicalOperationIMM(cpu: *CPU, value: u8) u1 {
    cpu.writeByte(START_ADDR + 1, value);

    return 0;
}

fn setupLogicalOperationZPG(cpu: *CPU, value: u8) u1 {
    cpu.writeByte(START_ADDR + 1, 0x11);
    cpu.writeByte(0x0011, value);

    return 0;
}

fn setupLogicalOperationZPXNoWrap(cpu: *CPU, value: u8) u1 {
    cpu.writeByte(START_ADDR + 1, 0x11);
    cpu.writeByte(0x0012, value);
    cpu.x = 0x01;

    return 0;
}

fn setupLogicalOperationZPXWrap(cpu: *CPU, value: u8) u1 {
    cpu.writeByte(START_ADDR + 1, 0xFF);
    cpu.writeByte(0x0000, value);
    cpu.x = 0x01;

    return 0;
}

fn setupLogicalOperationABS(cpu: *CPU, value: u8) u1 {
    cpu.writeWord(START_ADDR + 1, 0x1234);
    cpu.writeByte(0x1234, value);

    return 0;
}

fn setupLogicalOperationABXNoCross(cpu: *CPU, value: u8) u1 {
    cpu.writeWord(START_ADDR + 1, 0x1234);
    cpu.writeByte(0x1235, value);
    cpu.x = 0x01;

    return 0;
}

fn setupLogicalOperationABXCross(cpu: *CPU, value: u8) u1 {
    cpu.writeWord(START_ADDR + 1, 0x10FF);
    cpu.writeByte(0x1100, value);
    cpu.x = 0x01;

    return 1;
}

fn setupLogicalOperationABYNoCross(cpu: *CPU, value: u8) u1 {
    cpu.writeWord(START_ADDR + 1, 0x1234);
    cpu.writeByte(0x1235, value);
    cpu.y = 0x01;

    return 0;
}

fn setupLogicalOperationABYCross(cpu: *CPU, value: u8) u1 {
    cpu.writeWord(START_ADDR + 1, 0x10FF);
    cpu.writeByte(0x1100, value);
    cpu.y = 0x01;

    return 1;
}

fn setupLogicalOperationIDXNoWrap(cpu: *CPU, value: u8) u1 {
    cpu.writeByte(START_ADDR + 1, 0x11);
    cpu.writeWord(0x0012, 0x1234);
    cpu.writeByte(0x1234, value);
    cpu.x = 0x01;

    return 0;
}

fn setupLogicalOperationIDXWrap(cpu: *CPU, value: u8) u1 {
    cpu.writeByte(START_ADDR + 1, 0xFF);
    cpu.writeWord(0x0000, 0x1234);
    cpu.writeByte(0x1234, value);
    cpu.x = 0x01;

    return 0;
}

fn setupLogicalOperationIDYNoCross(cpu: *CPU, value: u8) u1 {
    cpu.writeByte(START_ADDR + 1, 0x11);
    cpu.writeWord(0x0011, 0x1234);
    cpu.writeByte(0x1235, value);
    cpu.y = 0x01;

    return 0;
}

fn setupLogicalOperationIDYCross(cpu: *CPU, value: u8) u1 {
    cpu.writeByte(START_ADDR + 1, 0x11);
    cpu.writeWord(0x0011, 0x10FF);
    cpu.writeByte(0x1100, value);
    cpu.y = 0x01;

    return 1;
}

// -------------------------------- Bit test -----------------------------------

fn testBitTest(cpu: *CPU, opcode: Opcode, setup: BitTestSetupFn) !void {
    const cycles = getInstructionCycles(cpu, opcode);

    cpu.writeByte(START_ADDR, @intFromEnum(opcode));
    setup(cpu, 0x93);

    cpu.setFlag(.Z, true);
    cpu.setFlag(.V, true);
    cpu.a = 0x01;
    cpu.run(cycles);

    try testing.expectEqual(cpu.getFlag(.Z), false);
    try testing.expectEqual(cpu.getFlag(.V), false);
    try testing.expectEqual(cpu.getFlag(.N), true);
    try testing.expectEqual(cpu.cycles, 0);
}

fn setupBitTestZPG(cpu: *CPU, value: u8) void {
    cpu.writeByte(START_ADDR + 1, 0x11);
    cpu.writeByte(0x0011, value);
}

fn setupBitTestABS(cpu: *CPU, value: u8) void {
    cpu.writeWord(START_ADDR + 1, 0x1234);
    cpu.writeByte(0x1234, value);
}

// -------------------------- Arithmetic operations ----------------------------

fn testArithmeticOperationFlags(cpu: *CPU, opcode: Opcode) !void {
    const cycles = getInstructionCycles(cpu, opcode);

    cpu.writeByte(START_ADDR + 0, @intFromEnum(opcode));
    cpu.writeByte(START_ADDR + 1, 0x00); // Assume immediate mode

    cpu.setFlag(.C, false);
    cpu.a = 0x00;
    cpu.run(cycles);

    try testing.expectEqual(cpu.getFlag(.C), false);
    try testing.expectEqual(cpu.getFlag(.Z), true);
    try testing.expectEqual(cpu.getFlag(.V), false);
    try testing.expectEqual(cpu.getFlag(.N), false);

    cpu.writeByte(START_ADDR + 2, @intFromEnum(opcode));
    cpu.writeByte(START_ADDR + 3, 0x00); // Assume immediate mode

    cpu.setFlag(.C, true);
    cpu.a = 0x00;
    cpu.run(cycles);

    try testing.expectEqual(cpu.getFlag(.C), false);
    try testing.expectEqual(cpu.getFlag(.Z), false);
    try testing.expectEqual(cpu.getFlag(.V), false);
    try testing.expectEqual(cpu.getFlag(.N), false);

    cpu.writeByte(START_ADDR + 4, @intFromEnum(opcode));
    cpu.writeByte(START_ADDR + 5, 0xFF); // Assume immediate mode

    cpu.setFlag(.C, false);
    cpu.a = 0x01;
    cpu.run(cycles);

    try testing.expectEqual(cpu.getFlag(.C), true);
    try testing.expectEqual(cpu.getFlag(.Z), true);
    try testing.expectEqual(cpu.getFlag(.V), false);
    try testing.expectEqual(cpu.getFlag(.N), false);

    cpu.writeByte(START_ADDR + 6, @intFromEnum(opcode));
    cpu.writeByte(START_ADDR + 7, 0xF0); // Assume immediate mode

    cpu.setFlag(.C, false);
    cpu.a = 0xF2;
    cpu.run(cycles);

    try testing.expectEqual(cpu.getFlag(.C), true);
    try testing.expectEqual(cpu.getFlag(.Z), false);
    try testing.expectEqual(cpu.getFlag(.V), false);
    try testing.expectEqual(cpu.getFlag(.N), true);

    cpu.writeByte(START_ADDR + 8, @intFromEnum(opcode));
    cpu.writeByte(START_ADDR + 9, 0x00); // Assume immediate mode

    cpu.setFlag(.C, true);
    cpu.a = 0x7F;
    cpu.run(cycles);

    try testing.expectEqual(cpu.getFlag(.C), false);
    try testing.expectEqual(cpu.getFlag(.Z), false);
    try testing.expectEqual(cpu.getFlag(.V), true);
    try testing.expectEqual(cpu.getFlag(.N), true);
}

fn testArithmeticOperationIMM(cpu: *CPU, opcode: Opcode) !void {
    const cycles = getInstructionCycles(cpu, opcode);

    cpu.writeByte(START_ADDR + 0, @intFromEnum(opcode));
    cpu.writeByte(START_ADDR + 1, 0x32);

    cpu.setFlag(.C, true);
    cpu.a = 0x05;
    cpu.run(cycles);

    try testing.expectEqual(cpu.a, 0x38);
    try testing.expectEqual(cpu.cycles, 0);
}

fn testArithmeticOperationZPG(cpu: *CPU, opcode: Opcode) !void {
    const cycles = getInstructionCycles(cpu, opcode);

    cpu.writeByte(START_ADDR + 0, @intFromEnum(opcode));
    cpu.writeByte(START_ADDR + 1, 0x66);
    cpu.writeByte(0x0066, 0x32);

    cpu.setFlag(.C, true);
    cpu.a = 0x05;
    cpu.run(cycles);

    try testing.expectEqual(cpu.a, 0x38);
    try testing.expectEqual(cpu.cycles, 0);
}

fn testArithmeticOperationZPX(cpu: *CPU, opcode: Opcode) !void {
    const cycles = getInstructionCycles(cpu, opcode);

    cpu.writeByte(START_ADDR + 0, @intFromEnum(opcode));
    cpu.writeByte(START_ADDR + 1, 0x66);
    cpu.writeByte(0x0066, 0x32);

    cpu.setFlag(.C, true);
    cpu.x = 0x01;
    cpu.a = 0x05;
    cpu.run(cycles);

    try testing.expectEqual(cpu.a, 0x38);
    try testing.expectEqual(cpu.cycles, 0);
}

// -----------------------------------------------------------------------------
//                               CPU CORE TESTS                                 
// -----------------------------------------------------------------------------

test "CPU Cycles" {
    var mem = initMemory();
    var cpu = CPU.init(&mem);

    cpu.run(4); // Startup/Reset takes 7 cycles

    try testing.expectEqual(cpu.cycles, 3); // 3 cycles remaining
}

// -----------------------------------------------------------------------------
//                              INSTRUCTION TESTS                               
// -----------------------------------------------------------------------------

// ------------------------- LDA - Load accumulator ----------------------------

test "LDA IMM" {
    var ctx = TestContext.init();
    try testLoadRegister(&ctx.cpu, .LDA_IMM, &ctx.cpu.a, &setupLoadRegisterIMM);
}

test "LDA ZPG" {
    var ctx = TestContext.init();
    try testLoadRegister(&ctx.cpu, .LDA_ZPG, &ctx.cpu.a, &setupLoadRegisterZPG);
}

test "LDA ZPX without wrap around" {
    var ctx = TestContext.init();
    try testLoadRegister(&ctx.cpu, .LDA_ZPX, &ctx.cpu.a, &setupLoadRegisterZPXNoWrap);
}

test "LDA ZPX with wrap around" {
    var ctx = TestContext.init();
    try testLoadRegister(&ctx.cpu, .LDA_ZPX, &ctx.cpu.a, &setupLoadRegisterZPXWrap);
}

test "LDA ABS" {
    var ctx = TestContext.init();
    try testLoadRegister(&ctx.cpu, .LDA_ABS, &ctx.cpu.a, &setupLoadRegisterABS);
}

test "LDA ABX without page crossing" {
    var ctx = TestContext.init();
    try testLoadRegister(&ctx.cpu, .LDA_ABX, &ctx.cpu.a,&setupLoadRegisterABXNoCross);
}

test "LDA ABX with page crossing" {
    var ctx = TestContext.init();
    try testLoadRegister(&ctx.cpu, .LDA_ABX, &ctx.cpu.a,&setupLoadRegisterABXCross);
}

test "LDA ABY without page crossing" {
    var ctx = TestContext.init();
    try testLoadRegister(&ctx.cpu, .LDA_ABY, &ctx.cpu.a,&setupLoadRegisterABYNoCross);
}

test "LDA ABY with page crossing" {
    var ctx = TestContext.init();
    try testLoadRegister(&ctx.cpu, .LDA_ABY, &ctx.cpu.a,&setupLoadRegisterABYCross);
}

test "LDA IDX without wrap around" {
    var ctx = TestContext.init();
    try testLoadRegister(&ctx.cpu, .LDA_IDX, &ctx.cpu.a, &setupLoadRegisterIDXNoWrap);
}

test "LDA IDX with wrap around" {
    var ctx = TestContext.init();
    try testLoadRegister(&ctx.cpu, .LDA_IDX, &ctx.cpu.a, &setupLoadRegisterIDXWrap);
}

test "LDA IDY without page crossing" {
    var ctx = TestContext.init();
    try testLoadRegister(&ctx.cpu, .LDA_IDY, &ctx.cpu.a, &setupLoadRegisterIDYNoCross);
}

test "LDA IDY with page crossing" {
    var ctx = TestContext.init();
    try testLoadRegister(&ctx.cpu, .LDA_IDY, &ctx.cpu.a, &setupLoadRegisterIDYCross);
}

// -------------------------- LDX - Load X register ----------------------------

test "LDX IMM" {
    var ctx = TestContext.init();
    try testLoadRegister(&ctx.cpu, .LDX_IMM, &ctx.cpu.x, &setupLoadRegisterIMM);
}

test "LDX ZPG" {
    var ctx = TestContext.init();
    try testLoadRegister(&ctx.cpu, .LDX_ZPG, &ctx.cpu.x, &setupLoadRegisterZPG);
}

test "LDX ZPY with wrap around" {
    var ctx = TestContext.init();
    try testLoadRegister(&ctx.cpu, .LDX_ZPY, &ctx.cpu.x, &setupLoadRegisterZPYNoWrap);
}

test "LDX ZPY without wrap around" {
    var ctx = TestContext.init();
    try testLoadRegister(&ctx.cpu, .LDX_ZPY, &ctx.cpu.x, &setupLoadRegisterZPYWrap);
}

test "LDX ABS" {
    var ctx = TestContext.init();
    try testLoadRegister(&ctx.cpu, .LDX_ABS, &ctx.cpu.x, &setupLoadRegisterABS);
}

test "LDX ABY without page crossing" {
    var ctx = TestContext.init();
    try testLoadRegister(&ctx.cpu, .LDX_ABY, &ctx.cpu.x, &setupLoadRegisterABYNoCross);
}

test "LDX ABY with page crossing" {
    var ctx = TestContext.init();
    try testLoadRegister(&ctx.cpu, .LDX_ABY, &ctx.cpu.x, &setupLoadRegisterABYCross);
}

// -------------------------- LDY - Load Y register ----------------------------

test "LDY IMM" {
    var ctx = TestContext.init();
    try testLoadRegister(&ctx.cpu, .LDY_IMM, &ctx.cpu.y, &setupLoadRegisterIMM);
}

test "LDY ZPG" {
    var ctx = TestContext.init();
    try testLoadRegister(&ctx.cpu, .LDY_ZPG, &ctx.cpu.y, &setupLoadRegisterZPG);
}

test "LDY ZPX without wrap around" {
    var ctx = TestContext.init();
    try testLoadRegister(&ctx.cpu, .LDY_ZPX, &ctx.cpu.y, &setupLoadRegisterZPXNoWrap);
}

test "LDY ZPX with wrap around" {
    var ctx = TestContext.init();
    try testLoadRegister(&ctx.cpu, .LDY_ZPX, &ctx.cpu.y, &setupLoadRegisterZPXWrap);
}

test "LDY ABS" {
    var ctx = TestContext.init();
    try testLoadRegister(&ctx.cpu, .LDY_ABS, &ctx.cpu.y, &setupLoadRegisterABS);
}

test "LDY ABX without page crossing" {
    var ctx = TestContext.init();
    try testLoadRegister(&ctx.cpu, .LDY_ABX, &ctx.cpu.y, &setupLoadRegisterABXNoCross);
}

test "LDY ABX with page crossing" {
    var ctx = TestContext.init();
    try testLoadRegister(&ctx.cpu, .LDY_ABX, &ctx.cpu.y, &setupLoadRegisterABXCross);
}

// ------------------------- STA - Store accumulator ---------------------------

test "STA ZPG" {
    var ctx = TestContext.init();
    try testStoreRegister(&ctx.cpu, .STA_ZPG, &ctx.cpu.a, &setupStoreRegisterZPG);
}

test "STA ZPX without wrap around" {
    var ctx = TestContext.init();
    try testStoreRegister(&ctx.cpu, .STA_ZPX, &ctx.cpu.a, &setupStoreRegisterZPXNoWrap);
}

test "STA ZPX with wrap around" {
    var ctx = TestContext.init();
    try testStoreRegister(&ctx.cpu, .STA_ZPX, &ctx.cpu.a, &setupStoreRegisterZPXWrap);
}

test "STA ABS" {
    var ctx = TestContext.init();
    try testStoreRegister(&ctx.cpu, .STA_ABS, &ctx.cpu.a, &setupStoreRegisterABS);
}

test "STA ABX" {
    var ctx = TestContext.init();
    try testStoreRegister(&ctx.cpu, .STA_ABX, &ctx.cpu.a, &setupStoreRegisterABX);
}

test "STA ABY" {
    var ctx = TestContext.init();
    try testStoreRegister(&ctx.cpu, .STA_ABY, &ctx.cpu.a, &setupStoreRegisterABY);
}

test "STA IDX without wrap around" {
    var ctx = TestContext.init();
    try testStoreRegister(&ctx.cpu, .STA_IDX, &ctx.cpu.a, &setupStoreRegisterIDXNoWrap);
}

test "STA IDX with wrap around" {
    var ctx = TestContext.init();
    try testStoreRegister(&ctx.cpu, .STA_IDX, &ctx.cpu.a, &setupStoreRegisterIDXWrap);
}

test "STA IDY" {
    var ctx = TestContext.init();
    try testStoreRegister(&ctx.cpu, .STA_IDY, &ctx.cpu.a, &setupStoreRegisterIDY);
}

// ------------------------- STX - Store X register ----------------------------

test "STX ZPG" {
    var ctx = TestContext.init();
    try testStoreRegister(&ctx.cpu, .STX_ZPG, &ctx.cpu.x, &setupStoreRegisterZPG);
}

test "STX ZPY without wrap around" {
    var ctx = TestContext.init();
    try testStoreRegister(&ctx.cpu, .STX_ZPY, &ctx.cpu.x, &setupStoreRegisterZPYNoWrap);
}

test "STX ZPY with wrap around" {
    var ctx = TestContext.init();
    try testStoreRegister(&ctx.cpu, .STX_ZPY, &ctx.cpu.x, &setupStoreRegisterZPYWrap);
}

test "STX ABS" {
    var ctx = TestContext.init();
    try testStoreRegister(&ctx.cpu, .STX_ABS, &ctx.cpu.x, &setupStoreRegisterABS);
}

// ------------------------- STY - Store Y register ----------------------------

test "STY ZPG" {
    var ctx = TestContext.init();
    try testStoreRegister(&ctx.cpu, .STY_ZPG, &ctx.cpu.y, &setupStoreRegisterZPG);
}

test "STY ZPX without wrap around" {
    var ctx = TestContext.init();
    try testStoreRegister(&ctx.cpu, .STY_ZPX, &ctx.cpu.y, &setupStoreRegisterZPXNoWrap);
}

test "STY ZPX with wrap around" {
    var ctx = TestContext.init();
    try testStoreRegister(&ctx.cpu, .STY_ZPX, &ctx.cpu.y, &setupStoreRegisterZPXWrap);
}

test "STY ABS" {
    var ctx = TestContext.init();
    try testStoreRegister(&ctx.cpu, .STY_ABS, &ctx.cpu.y, &setupStoreRegisterABS);
}

// --------------------- TAX - Transfer accumulator to X -----------------------

test "TAX IMP" {
    var ctx = TestContext.init();
    try testTransferRegister(&ctx.cpu, .TAX_IMP, &ctx.cpu.a, &ctx.cpu.x, true);
}

// --------------------- TAY - Transfer accumulator to Y -----------------------

test "TAY IMP" {
    var ctx = TestContext.init();
    try testTransferRegister(&ctx.cpu, .TAY_IMP, &ctx.cpu.a, &ctx.cpu.y, true);
}

// --------------------- TXA - Transfer X to accumulator -----------------------

test "TXA IMP" {
    var ctx = TestContext.init();
    try testTransferRegister(&ctx.cpu, .TXA_IMP, &ctx.cpu.x, &ctx.cpu.a, true);
}

// --------------------- TYA - Transfer Y to accumulator -----------------------

test "TYA IMP" {
    var ctx = TestContext.init();
    try testTransferRegister(&ctx.cpu, .TYA_IMP, &ctx.cpu.y, &ctx.cpu.a, true);
}

// ------------------------- TSX - Transfer SP to X ----------------------------

test "TSX IMP" {
    var ctx = TestContext.init();
    try testTransferRegister(&ctx.cpu, .TSX_IMP, &ctx.cpu.sp, &ctx.cpu.x, true);
}

// ------------------------- TXS - Transfer X to SP ----------------------------

test "TXS IMP" {
    var ctx = TestContext.init();
    try testTransferRegister(&ctx.cpu, .TXS_IMP, &ctx.cpu.x, &ctx.cpu.sp, false);
}

// -------------------- PHA - Push accumulator onto stack ----------------------

test "PHA IMP" {
    var ctx = TestContext.init();
    try testStackPush(&ctx.cpu, .PHA_IMP, &ctx.cpu.a);
}

// ----------------- PHP - Push processor status onto stack --------------------

test "PHP IMP" {
    var ctx = TestContext.init();
    try testStackPush(&ctx.cpu, .PHP_IMP, &ctx.cpu.status);
}

// -------------------- PLA - Pull accumulator from stack ----------------------

test "PLA IMP" {
    var ctx = TestContext.init();
    try testStackPull(&ctx.cpu, .PLA_IMP, &ctx.cpu.a);
}

// ----------------- PLP - Pull processor status from stack --------------------

test "PLP IMP" {
    var ctx = TestContext.init();
    try testStackPull(&ctx.cpu, .PLP_IMP, &ctx.cpu.status);
}

// ---------------------------- AND - Logical AND ------------------------------

test "AND IMM" {
    var ctx = TestContext.init();
    try testLogicalOperation(&ctx.cpu, .AND_IMM, &logicalAND, &setupLogicalOperationIMM);
}

test "AND ZPG" {
    var ctx = TestContext.init();
    try testLogicalOperation(&ctx.cpu, .AND_ZPG, &logicalAND, &setupLogicalOperationZPG);
}

test "AND ZPX without wrap around" {
    var ctx = TestContext.init();
    try testLogicalOperation(&ctx.cpu, .AND_ZPX, &logicalAND, &setupLogicalOperationZPXNoWrap);
}

test "AND ZPX with wrap around" {
    var ctx = TestContext.init();
    try testLogicalOperation(&ctx.cpu, .AND_ZPX, &logicalAND, &setupLogicalOperationZPXWrap);
}

test "AND ABS" {
    var ctx = TestContext.init();
    try testLogicalOperation(&ctx.cpu, .AND_ABS, &logicalAND, &setupLogicalOperationABS);
}

test "AND ABX without page crossing" {
    var ctx = TestContext.init();
    try testLogicalOperation(&ctx.cpu, .AND_ABX, &logicalAND, &setupLogicalOperationABXNoCross);
}

test "AND ABX with page crossing" {
    var ctx = TestContext.init();
    try testLogicalOperation(&ctx.cpu, .AND_ABX, &logicalAND, &setupLogicalOperationABXCross);
}

test "AND ABY without page crossing" {
    var ctx = TestContext.init();
    try testLogicalOperation(&ctx.cpu, .AND_ABY, &logicalAND, &setupLogicalOperationABYNoCross);
}

test "AND ABY with page crossing" {
    var ctx = TestContext.init();
    try testLogicalOperation(&ctx.cpu, .AND_ABY, &logicalAND, &setupLogicalOperationABYCross);
}

test "AND IDX without wrap around" {
    var ctx = TestContext.init();
    try testLogicalOperation(&ctx.cpu, .AND_IDX, &logicalAND, &setupLogicalOperationIDXNoWrap);
}

test "AND IDX with wrap around" {
    var ctx = TestContext.init();
    try testLogicalOperation(&ctx.cpu, .AND_IDX, &logicalAND, &setupLogicalOperationIDXWrap);
}

test "AND IDY without page crossing" {
    var ctx = TestContext.init();
    try testLogicalOperation(&ctx.cpu, .AND_IDY, &logicalAND, &setupLogicalOperationIDYNoCross);
}

test "AND IDY with page crossing" {
    var ctx = TestContext.init();
    try testLogicalOperation(&ctx.cpu, .AND_IDY, &logicalAND, &setupLogicalOperationIDYCross);
}

// --------------------------- EOR - Exclusive OR ------------------------------

test "EOR IMM" {
    var ctx = TestContext.init();
    try testLogicalOperation(&ctx.cpu, .EOR_IMM, &logicalXOR, &setupLogicalOperationIMM);
}

test "EOR ZPG" {
    var ctx = TestContext.init();
    try testLogicalOperation(&ctx.cpu, .EOR_ZPG, &logicalXOR, &setupLogicalOperationZPG);
}

test "EOR ZPX without wrap around" {
    var ctx = TestContext.init();
    try testLogicalOperation(&ctx.cpu, .EOR_ZPX, &logicalXOR, &setupLogicalOperationZPXNoWrap);
}

test "EOR ZPX with wrap around" {
    var ctx = TestContext.init();
    try testLogicalOperation(&ctx.cpu, .EOR_ZPX, &logicalXOR, &setupLogicalOperationZPXWrap);
}

test "EOR ABS" {
    var ctx = TestContext.init();
    try testLogicalOperation(&ctx.cpu, .EOR_ABS, &logicalXOR, &setupLogicalOperationABS);
}

test "EOR ABX without page crossing" {
    var ctx = TestContext.init();
    try testLogicalOperation(&ctx.cpu, .EOR_ABX, &logicalXOR, &setupLogicalOperationABXNoCross);
}

test "EOR ABX with page crossing" {
    var ctx = TestContext.init();
    try testLogicalOperation(&ctx.cpu, .EOR_ABX, &logicalXOR, &setupLogicalOperationABXCross);
}

test "EOR ABY without page crossing" {
    var ctx = TestContext.init();
    try testLogicalOperation(&ctx.cpu, .EOR_ABY, &logicalXOR, &setupLogicalOperationABYNoCross);
}

test "EOR ABY with page crossing" {
    var ctx = TestContext.init();
    try testLogicalOperation(&ctx.cpu, .EOR_ABY, &logicalXOR, &setupLogicalOperationABYCross);
}

test "EOR IDX without wrap around" {
    var ctx = TestContext.init();
    try testLogicalOperation(&ctx.cpu, .EOR_IDX, &logicalXOR, &setupLogicalOperationIDXNoWrap);
}

test "EOR IDX with wrap around" {
    var ctx = TestContext.init();
    try testLogicalOperation(&ctx.cpu, .EOR_IDX, &logicalXOR, &setupLogicalOperationIDXWrap);
}

test "EOR IDY without page crossing" {
    var ctx = TestContext.init();
    try testLogicalOperation(&ctx.cpu, .EOR_IDY, &logicalXOR, &setupLogicalOperationIDYNoCross);
}

test "EOR IDY with page crossing" {
    var ctx = TestContext.init();
    try testLogicalOperation(&ctx.cpu, .EOR_IDY, &logicalXOR, &setupLogicalOperationIDYCross);
}

// ---------------------------- ORA - Logical OR -------------------------------

test "ORA IMM" {
    var ctx = TestContext.init();
    try testLogicalOperation(&ctx.cpu, .ORA_IMM, &logicalOR, &setupLogicalOperationIMM);
}

test "ORA ZPG" {
    var ctx = TestContext.init();
    try testLogicalOperation(&ctx.cpu, .ORA_ZPG, &logicalOR, &setupLogicalOperationZPG);
}

test "ORA ZPX without wrap around" {
    var ctx = TestContext.init();
    try testLogicalOperation(&ctx.cpu, .ORA_ZPX, &logicalOR, &setupLogicalOperationZPXNoWrap);
}

test "ORA ZPX with wrap around" {
    var ctx = TestContext.init();
    try testLogicalOperation(&ctx.cpu, .ORA_ZPX, &logicalOR, &setupLogicalOperationZPXWrap);
}

test "ORA ABS" {
    var ctx = TestContext.init();
    try testLogicalOperation(&ctx.cpu, .ORA_ABS, &logicalOR, &setupLogicalOperationABS);
}

test "ORA ABX without page crossing" {
    var ctx = TestContext.init();
    try testLogicalOperation(&ctx.cpu, .ORA_ABX, &logicalOR, &setupLogicalOperationABXNoCross);
}

test "ORA ABX with page crossing" {
    var ctx = TestContext.init();
    try testLogicalOperation(&ctx.cpu, .ORA_ABX, &logicalOR, &setupLogicalOperationABXCross);
}

test "ORA ABY without page crossing" {
    var ctx = TestContext.init();
    try testLogicalOperation(&ctx.cpu, .ORA_ABY, &logicalOR, &setupLogicalOperationABYNoCross);
}

test "ORA ABY with page crossing" {
    var ctx = TestContext.init();
    try testLogicalOperation(&ctx.cpu, .ORA_ABY, &logicalOR, &setupLogicalOperationABYCross);
}

test "ORA IDX without wrap around" {
    var ctx = TestContext.init();
    try testLogicalOperation(&ctx.cpu, .ORA_IDX, &logicalOR, &setupLogicalOperationIDXNoWrap);
}

test "ORA IDX with wrap around" {
    var ctx = TestContext.init();
    try testLogicalOperation(&ctx.cpu, .ORA_IDX, &logicalOR, &setupLogicalOperationIDXWrap);
}

test "ORA IDY without page crossing" {
    var ctx = TestContext.init();
    try testLogicalOperation(&ctx.cpu, .ORA_IDY, &logicalOR, &setupLogicalOperationIDYNoCross);
}

test "ORA IDY with page crossing" {
    var ctx = TestContext.init();
    try testLogicalOperation(&ctx.cpu, .ORA_IDY, &logicalOR, &setupLogicalOperationIDYCross);
}

// ----------------------------- BIT - Bit test --------------------------------

test "BIT ZPG" {
    var ctx = TestContext.init();
    try testBitTest(&ctx.cpu, .BIT_ZPG, &setupBitTestZPG);
}

test "BIT ABS" {
    var ctx = TestContext.init();
    try testBitTest(&ctx.cpu, .BIT_ABS, &setupBitTestABS);
}