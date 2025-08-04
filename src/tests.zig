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
const ArithmeticOp = *const fn (u8, u8) u16;

const LoadRegSetupFn = *const fn (*CPU, u8) u1;
const StoreRegSetupFn = *const fn (*CPU) void;
const LogicalOpSetupFn = *const fn (*CPU, u8) u1;
const BitTestSetupFn = *const fn (*CPU, u8) void;
const ArithmeticOpSetupFn = *const fn (*CPU, u8) u1;

const ArithmeticOpParams = struct {
    carry: bool, acc: u8, operand: u8, result: u8,
    expected_c: bool, expected_z: bool, expected_v: bool, expected_n: bool,
};

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

// ---------------------- Logical/Arithmetic operations ------------------------

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

fn testArithmeticOperation(cpu: *CPU, opcode: Opcode, setup: ArithmeticOpSetupFn, params: ArithmeticOpParams) !void {
    const cycles = getInstructionCycles(cpu, opcode);

    cpu.writeByte(START_ADDR, @intFromEnum(opcode));
    const extra_cycle = setup(cpu, params.operand);

    cpu.setFlag(.C, params.carry);
    cpu.setFlag(.Z, !params.expected_z);
    cpu.setFlag(.V, !params.expected_v);
    cpu.setFlag(.N, !params.expected_n);
    cpu.a = params.acc;
    cpu.run(cycles + extra_cycle);

    try testing.expectEqual(cpu.getFlag(.C), params.expected_c);
    try testing.expectEqual(cpu.getFlag(.Z), params.expected_z);
    try testing.expectEqual(cpu.getFlag(.V), params.expected_v);
    try testing.expectEqual(cpu.getFlag(.N), params.expected_n);
    try testing.expectEqual(cpu.a, params.result);
    try testing.expectEqual(cpu.cycles, 0);
}

fn setupOperationIMM(cpu: *CPU, value: u8) u1 {
    cpu.writeByte(START_ADDR + 1, value);

    return 0;
}

fn setupOperationZPG(cpu: *CPU, value: u8) u1 {
    cpu.writeByte(START_ADDR + 1, 0x11);
    cpu.writeByte(0x0011, value);

    return 0;
}

fn setupOperationZPXNoWrap(cpu: *CPU, value: u8) u1 {
    cpu.writeByte(START_ADDR + 1, 0x11);
    cpu.writeByte(0x0012, value);
    cpu.x = 0x01;

    return 0;
}

fn setupOperationZPXWrap(cpu: *CPU, value: u8) u1 {
    cpu.writeByte(START_ADDR + 1, 0xFF);
    cpu.writeByte(0x0000, value);
    cpu.x = 0x01;

    return 0;
}

fn setupOperationABS(cpu: *CPU, value: u8) u1 {
    cpu.writeWord(START_ADDR + 1, 0x1234);
    cpu.writeByte(0x1234, value);

    return 0;
}

fn setupOperationABXNoCross(cpu: *CPU, value: u8) u1 {
    cpu.writeWord(START_ADDR + 1, 0x1234);
    cpu.writeByte(0x1235, value);
    cpu.x = 0x01;

    return 0;
}

fn setupOperationABXCross(cpu: *CPU, value: u8) u1 {
    cpu.writeWord(START_ADDR + 1, 0x10FF);
    cpu.writeByte(0x1100, value);
    cpu.x = 0x01;

    return 1;
}

fn setupOperationABYNoCross(cpu: *CPU, value: u8) u1 {
    cpu.writeWord(START_ADDR + 1, 0x1234);
    cpu.writeByte(0x1235, value);
    cpu.y = 0x01;

    return 0;
}

fn setupOperationABYCross(cpu: *CPU, value: u8) u1 {
    cpu.writeWord(START_ADDR + 1, 0x10FF);
    cpu.writeByte(0x1100, value);
    cpu.y = 0x01;

    return 1;
}

fn setupOperationIDXNoWrap(cpu: *CPU, value: u8) u1 {
    cpu.writeByte(START_ADDR + 1, 0x11);
    cpu.writeWord(0x0012, 0x1234);
    cpu.writeByte(0x1234, value);
    cpu.x = 0x01;

    return 0;
}

fn setupOperationIDXWrap(cpu: *CPU, value: u8) u1 {
    cpu.writeByte(START_ADDR + 1, 0xFF);
    cpu.writeWord(0x0000, 0x1234);
    cpu.writeByte(0x1234, value);
    cpu.x = 0x01;

    return 0;
}

fn setupOperationIDYNoCross(cpu: *CPU, value: u8) u1 {
    cpu.writeByte(START_ADDR + 1, 0x11);
    cpu.writeWord(0x0011, 0x1234);
    cpu.writeByte(0x1235, value);
    cpu.y = 0x01;

    return 0;
}

fn setupOperationIDYCross(cpu: *CPU, value: u8) u1 {
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
    try testLogicalOperation(&ctx.cpu, .AND_IMM, &logicalAND, &setupOperationIMM);
}

test "AND ZPG" {
    var ctx = TestContext.init();
    try testLogicalOperation(&ctx.cpu, .AND_ZPG, &logicalAND, &setupOperationZPG);
}

test "AND ZPX without wrap around" {
    var ctx = TestContext.init();
    try testLogicalOperation(&ctx.cpu, .AND_ZPX, &logicalAND, &setupOperationZPXNoWrap);
}

test "AND ZPX with wrap around" {
    var ctx = TestContext.init();
    try testLogicalOperation(&ctx.cpu, .AND_ZPX, &logicalAND, &setupOperationZPXWrap);
}

test "AND ABS" {
    var ctx = TestContext.init();
    try testLogicalOperation(&ctx.cpu, .AND_ABS, &logicalAND, &setupOperationABS);
}

test "AND ABX without page crossing" {
    var ctx = TestContext.init();
    try testLogicalOperation(&ctx.cpu, .AND_ABX, &logicalAND, &setupOperationABXNoCross);
}

test "AND ABX with page crossing" {
    var ctx = TestContext.init();
    try testLogicalOperation(&ctx.cpu, .AND_ABX, &logicalAND, &setupOperationABXCross);
}

test "AND ABY without page crossing" {
    var ctx = TestContext.init();
    try testLogicalOperation(&ctx.cpu, .AND_ABY, &logicalAND, &setupOperationABYNoCross);
}

test "AND ABY with page crossing" {
    var ctx = TestContext.init();
    try testLogicalOperation(&ctx.cpu, .AND_ABY, &logicalAND, &setupOperationABYCross);
}

test "AND IDX without wrap around" {
    var ctx = TestContext.init();
    try testLogicalOperation(&ctx.cpu, .AND_IDX, &logicalAND, &setupOperationIDXNoWrap);
}

test "AND IDX with wrap around" {
    var ctx = TestContext.init();
    try testLogicalOperation(&ctx.cpu, .AND_IDX, &logicalAND, &setupOperationIDXWrap);
}

test "AND IDY without page crossing" {
    var ctx = TestContext.init();
    try testLogicalOperation(&ctx.cpu, .AND_IDY, &logicalAND, &setupOperationIDYNoCross);
}

test "AND IDY with page crossing" {
    var ctx = TestContext.init();
    try testLogicalOperation(&ctx.cpu, .AND_IDY, &logicalAND, &setupOperationIDYCross);
}

// --------------------------- EOR - Exclusive OR ------------------------------

test "EOR IMM" {
    var ctx = TestContext.init();
    try testLogicalOperation(&ctx.cpu, .EOR_IMM, &logicalXOR, &setupOperationIMM);
}

test "EOR ZPG" {
    var ctx = TestContext.init();
    try testLogicalOperation(&ctx.cpu, .EOR_ZPG, &logicalXOR, &setupOperationZPG);
}

test "EOR ZPX without wrap around" {
    var ctx = TestContext.init();
    try testLogicalOperation(&ctx.cpu, .EOR_ZPX, &logicalXOR, &setupOperationZPXNoWrap);
}

test "EOR ZPX with wrap around" {
    var ctx = TestContext.init();
    try testLogicalOperation(&ctx.cpu, .EOR_ZPX, &logicalXOR, &setupOperationZPXWrap);
}

test "EOR ABS" {
    var ctx = TestContext.init();
    try testLogicalOperation(&ctx.cpu, .EOR_ABS, &logicalXOR, &setupOperationABS);
}

test "EOR ABX without page crossing" {
    var ctx = TestContext.init();
    try testLogicalOperation(&ctx.cpu, .EOR_ABX, &logicalXOR, &setupOperationABXNoCross);
}

test "EOR ABX with page crossing" {
    var ctx = TestContext.init();
    try testLogicalOperation(&ctx.cpu, .EOR_ABX, &logicalXOR, &setupOperationABXCross);
}

test "EOR ABY without page crossing" {
    var ctx = TestContext.init();
    try testLogicalOperation(&ctx.cpu, .EOR_ABY, &logicalXOR, &setupOperationABYNoCross);
}

test "EOR ABY with page crossing" {
    var ctx = TestContext.init();
    try testLogicalOperation(&ctx.cpu, .EOR_ABY, &logicalXOR, &setupOperationABYCross);
}

test "EOR IDX without wrap around" {
    var ctx = TestContext.init();
    try testLogicalOperation(&ctx.cpu, .EOR_IDX, &logicalXOR, &setupOperationIDXNoWrap);
}

test "EOR IDX with wrap around" {
    var ctx = TestContext.init();
    try testLogicalOperation(&ctx.cpu, .EOR_IDX, &logicalXOR, &setupOperationIDXWrap);
}

test "EOR IDY without page crossing" {
    var ctx = TestContext.init();
    try testLogicalOperation(&ctx.cpu, .EOR_IDY, &logicalXOR, &setupOperationIDYNoCross);
}

test "EOR IDY with page crossing" {
    var ctx = TestContext.init();
    try testLogicalOperation(&ctx.cpu, .EOR_IDY, &logicalXOR, &setupOperationIDYCross);
}

// ---------------------------- ORA - Logical OR -------------------------------

test "ORA IMM" {
    var ctx = TestContext.init();
    try testLogicalOperation(&ctx.cpu, .ORA_IMM, &logicalOR, &setupOperationIMM);
}

test "ORA ZPG" {
    var ctx = TestContext.init();
    try testLogicalOperation(&ctx.cpu, .ORA_ZPG, &logicalOR, &setupOperationZPG);
}

test "ORA ZPX without wrap around" {
    var ctx = TestContext.init();
    try testLogicalOperation(&ctx.cpu, .ORA_ZPX, &logicalOR, &setupOperationZPXNoWrap);
}

test "ORA ZPX with wrap around" {
    var ctx = TestContext.init();
    try testLogicalOperation(&ctx.cpu, .ORA_ZPX, &logicalOR, &setupOperationZPXWrap);
}

test "ORA ABS" {
    var ctx = TestContext.init();
    try testLogicalOperation(&ctx.cpu, .ORA_ABS, &logicalOR, &setupOperationABS);
}

test "ORA ABX without page crossing" {
    var ctx = TestContext.init();
    try testLogicalOperation(&ctx.cpu, .ORA_ABX, &logicalOR, &setupOperationABXNoCross);
}

test "ORA ABX with page crossing" {
    var ctx = TestContext.init();
    try testLogicalOperation(&ctx.cpu, .ORA_ABX, &logicalOR, &setupOperationABXCross);
}

test "ORA ABY without page crossing" {
    var ctx = TestContext.init();
    try testLogicalOperation(&ctx.cpu, .ORA_ABY, &logicalOR, &setupOperationABYNoCross);
}

test "ORA ABY with page crossing" {
    var ctx = TestContext.init();
    try testLogicalOperation(&ctx.cpu, .ORA_ABY, &logicalOR, &setupOperationABYCross);
}

test "ORA IDX without wrap around" {
    var ctx = TestContext.init();
    try testLogicalOperation(&ctx.cpu, .ORA_IDX, &logicalOR, &setupOperationIDXNoWrap);
}

test "ORA IDX with wrap around" {
    var ctx = TestContext.init();
    try testLogicalOperation(&ctx.cpu, .ORA_IDX, &logicalOR, &setupOperationIDXWrap);
}

test "ORA IDY without page crossing" {
    var ctx = TestContext.init();
    try testLogicalOperation(&ctx.cpu, .ORA_IDY, &logicalOR, &setupOperationIDYNoCross);
}

test "ORA IDY with page crossing" {
    var ctx = TestContext.init();
    try testLogicalOperation(&ctx.cpu, .ORA_IDY, &logicalOR, &setupOperationIDYCross);
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

// -------------------------- ADC - Add with carry -----------------------------

test "ADC IMM" {
    var ctx = TestContext.init();
    try testArithmeticOperation(&ctx.cpu, .ADC_IMM, &setupOperationIMM, .{
        .carry = false,
        .acc = 0x00,
        .operand = 0x00,
        .result = 0x00,
        .expected_c = false,
        .expected_z = true,
        .expected_v = false,
        .expected_n = false,
    }); // 0 + 0 + 0 = 0
}

test "ADC ZPG" {
    var ctx = TestContext.init();
    try testArithmeticOperation(&ctx.cpu, .ADC_ZPG, &setupOperationZPG, .{
        .carry = true,
        .acc = 0x00,
        .operand = 0x00,
        .result = 0x01,
        .expected_c = false,
        .expected_z = false,
        .expected_v = false,
        .expected_n = false,
    }); // 1 + 0 + 0 = 1
}

test "ADC ZPX without wrap around" {
    var ctx = TestContext.init();
    try testArithmeticOperation(&ctx.cpu, .ADC_ZPX, &setupOperationZPXNoWrap, .{
        .carry = false,
        .acc = 0x50,
        .operand = 0x30,
        .result = 0x80,
        .expected_c = false,
        .expected_z = false,
        .expected_v = true,
        .expected_n = true,
    }); // 0 + 80 + 48 = -128
}

test "ADC ZPX with wrap around" {
    var ctx = TestContext.init();
    try testArithmeticOperation(&ctx.cpu, .ADC_ZPX, &setupOperationZPXWrap, .{
        .carry = true,
        .acc = 0x50,
        .operand = 0x30,
        .result = 0x81,
        .expected_c = false,
        .expected_z = false,
        .expected_v = true,
        .expected_n = true,
    }); // 1 + 80 + 48 = -127
}

test "ADC ABS" {
    var ctx = TestContext.init();
    try testArithmeticOperation(&ctx.cpu, .ADC_ABS, &setupOperationABS, .{
        .carry = false,
        .acc = 0xFF,
        .operand = 0x01,
        .result = 0x00,
        .expected_c = true,
        .expected_z = true,
        .expected_v = false,
        .expected_n = false,
    }); // 0 + (-1) + 1 = 0
}

test "ADC ABX without page crossing" {
    var ctx = TestContext.init();
    try testArithmeticOperation(&ctx.cpu, .ADC_ABX, &setupOperationABXNoCross, .{
        .carry = true,
        .acc = 0xF0,
        .operand = 0xF2,
        .result = 0xE3,
        .expected_c = true,
        .expected_z = false,
        .expected_v = false,
        .expected_n = true,
    }); // 1 + (-16) + (-14) = -29
}

test "ADC ABX with page crossing" {
    var ctx = TestContext.init();
    try testArithmeticOperation(&ctx.cpu, .ADC_ABX, &setupOperationABXCross, .{
        .carry = false,
        .acc = 0xF0,
        .operand = 0xF2,
        .result = 0xE2,
        .expected_c = true,
        .expected_z = false,
        .expected_v = false,
        .expected_n = true,
    }); // 0 + (-16) + (-14) = -30
}

test "ADC ABY without page crossing" {
    var ctx = TestContext.init();
    try testArithmeticOperation(&ctx.cpu, .ADC_ABY, &setupOperationABYNoCross, .{
        .carry = false,
        .acc = 0x01,
        .operand = 0x7F,
        .result = 0x80,
        .expected_c = false,
        .expected_z = false,
        .expected_v = true,
        .expected_n = true,
    }); // 0 + 1 + 127 = -128
}

test "ADC ABY with page crossing" {
    var ctx = TestContext.init();
    try testArithmeticOperation(&ctx.cpu, .ADC_ABY, &setupOperationABYCross, .{
        .carry = true,
        .acc = 0x01,
        .operand = 0x7F,
        .result = 0x81,
        .expected_c = false,
        .expected_z = false,
        .expected_v = true,
        .expected_n = true,
    }); // 1 + 1 + 127 = -127
}

test "ADC IDX without wrap around" {
    var ctx = TestContext.init();
    try testArithmeticOperation(&ctx.cpu, .ADC_IDX, &setupOperationIDXNoWrap, .{
        .carry = false,
        .acc = 0x64,
        .operand = 0x64,
        .result = 0xC8,
        .expected_c = false,
        .expected_z = false,
        .expected_v = true,
        .expected_n = true,
    }); // 0 + 100 + 100 = -56
}

test "ADC IDX with wrap around" {
    var ctx = TestContext.init();
    try testArithmeticOperation(&ctx.cpu, .ADC_IDX, &setupOperationIDXWrap, .{
        .carry = true,
        .acc = 0x64,
        .operand = 0x64,
        .result = 0xC9,
        .expected_c = false,
        .expected_z = false,
        .expected_v = true,
        .expected_n = true,
    }); // 1 + 100 + 100 = -55
}

test "ADC IDY without page crossing" {
    var ctx = TestContext.init();
    try testArithmeticOperation(&ctx.cpu, .ADC_IDY, &setupOperationIDYNoCross, .{
        .carry = false,
        .acc = 0xA1,
        .operand = 0x90,
        .result = 0x31,
        .expected_c = true,
        .expected_z = false,
        .expected_v = true,
        .expected_n = false,
    }); // 0 + (-95) + (-110) = 31
}

test "ADC IDY with page crossing" {
    var ctx = TestContext.init();
    try testArithmeticOperation(&ctx.cpu, .ADC_IDY, &setupOperationIDYCross, .{
        .carry = true,
        .acc = 0xA1,
        .operand = 0x90,
        .result = 0x32,
        .expected_c = true,
        .expected_z = false,
        .expected_v = true,
        .expected_n = false,
    }); // 1 + (-95) + (-110) = 32
}

// ------------------------ SBC - Subtract with carry --------------------------

test "SBC IMM" {
    var ctx = TestContext.init();
    try testArithmeticOperation(&ctx.cpu, .SBC_IMM, &setupOperationIMM, .{
        .carry = true,
        .acc = 0x00,
        .operand = 0x00,
        .result = 0x00,
        .expected_c = true,
        .expected_z = true,
        .expected_v = false,
        .expected_n = false,
    }); // 0 - 0 - (1 - 1) = 0
}

test "SBC ZPG" {
    var ctx = TestContext.init();
    try testArithmeticOperation(&ctx.cpu, .SBC_ZPG, &setupOperationZPG, .{
        .carry = true,
        .acc = 0x01,
        .operand = 0x00,
        .result = 0x01,
        .expected_c = true,
        .expected_z = false,
        .expected_v = false,
        .expected_n = false,
    }); // 1 - 0 - (1 - 1) = 1
}

test "SBC ZPX without wrap around" {
    var ctx = TestContext.init();
    try testArithmeticOperation(&ctx.cpu, .SBC_ZPX, &setupOperationZPXNoWrap, .{
        .carry = true,
        .acc = 0x00,
        .operand = 0x01,
        .result = 0xFF,
        .expected_c = false,
        .expected_z = false,
        .expected_v = false,
        .expected_n = true,
    }); // 0 - 1 - (1 - 1) = -1
}

test "SBC ZPX with wrap around" {
    var ctx = TestContext.init();
    try testArithmeticOperation(&ctx.cpu, .SBC_ZPX, &setupOperationZPXWrap, .{
        .carry = false,
        .acc = 0x00,
        .operand = 0x01,
        .result = 0xFE,
        .expected_c = false,
        .expected_z = false,
        .expected_v = false,
        .expected_n = true,
    }); // 0 - 1 - (1 - 0) = -2
}

test "SBC ABS" {
    var ctx = TestContext.init();
    try testArithmeticOperation(&ctx.cpu, .SBC_ABS, &setupOperationABS, .{
        .carry = true,
        .acc = 0x01,
        .operand = 0x01,
        .result = 0x00,
        .expected_c = true,
        .expected_z = true,
        .expected_v = false,
        .expected_n = false,
    }); // 1 - 1 - (1 - 1) = 0
}

test "SBC ABX without page crossing" {
    var ctx = TestContext.init();
    try testArithmeticOperation(&ctx.cpu, .SBC_ABX, &setupOperationABXNoCross, .{
        .carry = true,
        .acc = 0xF0,
        .operand = 0xF2,
        .result = 0xFE,
        .expected_c = false,
        .expected_z = false,
        .expected_v = false,
        .expected_n = true,
    }); // -16 - (-14) - (1 - 1) = -2
}

test "SBC ABX with page crossing" {
    var ctx = TestContext.init();
    try testArithmeticOperation(&ctx.cpu, .SBC_ABX, &setupOperationABXCross, .{
        .carry = false,
        .acc = 0xF0,
        .operand = 0xF2,
        .result = 0xFD,
        .expected_c = false,
        .expected_z = false,
        .expected_v = false,
        .expected_n = true,
    }); // -16 - (-14) - (1 - 0) = -3
}

test "SBC ABY without page crossing" {
    var ctx = TestContext.init();
    try testArithmeticOperation(&ctx.cpu, .SBC_ABY, &setupOperationABYNoCross, .{
        .carry = true,
        .acc = 0x80,
        .operand = 0x01,
        .result = 0x7F,
        .expected_c = true,
        .expected_z = false,
        .expected_v = true,
        .expected_n = false,
    }); // -128 - 1 - (1 - 1) = 127
}

test "SBC ABY with page crossing" {
    var ctx = TestContext.init();
    try testArithmeticOperation(&ctx.cpu, .SBC_ABY, &setupOperationABYCross, .{
        .carry = false,
        .acc = 0x80,
        .operand = 0x01,
        .result = 0x7E,
        .expected_c = true,
        .expected_z = false,
        .expected_v = true,
        .expected_n = false,
    }); // -128 - 1 - (1 - 0) = 126
}

test "SBC IDX without wrap around" {
    var ctx = TestContext.init();
    try testArithmeticOperation(&ctx.cpu, .SBC_IDX, &setupOperationIDXNoWrap, .{
        .carry = true,
        .acc = 0x7F,
        .operand = 0xFF,
        .result = 0x80,
        .expected_c = false,
        .expected_z = false,
        .expected_v = true,
        .expected_n = true,
    }); // 127 - (-1) - (1 - 1) = -128
}

test "SBC IDX with wrap around" {
    var ctx = TestContext.init();
    try testArithmeticOperation(&ctx.cpu, .SBC_IDX, &setupOperationIDXWrap, .{
        .carry = false,
        .acc = 0x7F,
        .operand = 0xFF,
        .result = 0x7F,
        .expected_c = false,
        .expected_z = false,
        .expected_v = false,
        .expected_n = false,
    }); // 127 - (-1) - (1 - 0) = 127
}

test "SBC IDY without page crossing" {
    var ctx = TestContext.init();
    try testArithmeticOperation(&ctx.cpu, .SBC_IDY, &setupOperationIDYNoCross, .{
        .carry = false,
        .acc = 0x00,
        .operand = 0x00,
        .result = 0xFF,
        .expected_c = false,
        .expected_z = false,
        .expected_v = false,
        .expected_n = true,
    }); // 0 - 0 - (1 - 0) = -1
}

test "SBC IDY with page crossing" {
    var ctx = TestContext.init();
    try testArithmeticOperation(&ctx.cpu, .SBC_IDY, &setupOperationIDYCross, .{
        .carry = true,
        .acc = 0x14,
        .operand = 0x11,
        .result = 0x03,
        .expected_c = true,
        .expected_z = false,
        .expected_v = false,
        .expected_n = false,
    }); // 20 - 17 - (1 - 1) = 3
}