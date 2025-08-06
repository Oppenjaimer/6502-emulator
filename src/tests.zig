const std = @import("std");
const testing = std.testing;

const emulator = @import("emulator.zig");
const CPU = emulator.CPU;
const Memory = emulator.Memory;
const Opcode = CPU.Opcode;
const Flag = CPU.Flag;

// -----------------------------------------------------------------------------
//                                  CONSTANTS                                   
// -----------------------------------------------------------------------------

const START_ADDR: u16 = 0x3000;
const START_HIGH: u8 = START_ADDR >> 8;
const START_LOW:  u8 = START_ADDR & 0xFF;

const LogicalOp = *const fn (u8, u8) u8;
const ArithmeticOp = *const fn (u8, u8) u16;
const IncDecOp = *const fn (u8) u8;

const ValueSetupFn = *const fn (*CPU, u8) u1;
const NoValueSetupFn = *const fn (*CPU) void;

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

// --------------------- Increment/Decrement operations ------------------------

fn increment(n: u8) u8 {
    return n +% 1;
}

fn decrement(n: u8) u8 {
    return n -% 1;
}

// ------------------------------ Miscellaneous --------------------------------

fn getInstructionCycles(cpu: *CPU, opcode: Opcode) u32 {
    return cpu.instruction_table[@intFromEnum(opcode)].cycles;
}

// -----------------------------------------------------------------------------
//                               SETUP FUNCTIONS                                
// -----------------------------------------------------------------------------

// ------------------------------- With value ----------------------------------

fn setupValueIMM(cpu: *CPU, value: u8) u1 {
    cpu.writeByte(START_ADDR + 1, value);

    return 0;
}

fn setupValueZPG(cpu: *CPU, value: u8) u1 {
    cpu.writeByte(START_ADDR + 1, 0x11);
    cpu.writeByte(0x0011, value);

    return 0;
}

fn setupValueZPXNoWrap(cpu: *CPU, value: u8) u1 {
    cpu.writeByte(START_ADDR + 1, 0x11);
    cpu.writeByte(0x0012, value);
    cpu.x = 0x01;

    return 0;
}

fn setupValueZPXWrap(cpu: *CPU, value: u8) u1 {
    cpu.writeByte(START_ADDR + 1, 0xFF);
    cpu.writeByte(0x0000, value);
    cpu.x = 0x01;

    return 0;
}

fn setupValueZPYNoWrap(cpu: *CPU, value: u8) u1 {
    cpu.writeByte(START_ADDR + 1, 0x11);
    cpu.writeByte(0x0012, value);
    cpu.y = 0x01;

    return 0;
}

fn setupValueZPYWrap(cpu: *CPU, value: u8) u1 {
    cpu.writeByte(START_ADDR + 1, 0xFF);
    cpu.writeByte(0x0000, value);
    cpu.y = 0x01;

    return 0;
}

fn setupValueABS(cpu: *CPU, value: u8) u1 {
    cpu.writeWord(START_ADDR + 1, 0x1234);
    cpu.writeByte(0x1234, value);

    return 0;
}

fn setupValueABXNoCross(cpu: *CPU, value: u8) u1 {
    cpu.writeWord(START_ADDR + 1, 0x1234);
    cpu.writeByte(0x1235, value);
    cpu.x = 0x01;

    return 0;
}

fn setupValueABXCross(cpu: *CPU, value: u8) u1 {
    cpu.writeWord(START_ADDR + 1, 0x10FF);
    cpu.writeByte(0x1100, value);
    cpu.x = 0x01;

    return 1;
}

fn setupValueABYNoCross(cpu: *CPU, value: u8) u1 {
    cpu.writeWord(START_ADDR + 1, 0x1234);
    cpu.writeByte(0x1235, value);
    cpu.y = 0x01;

    return 0;
}

fn setupValueABYCross(cpu: *CPU, value: u8) u1 {
    cpu.writeWord(START_ADDR + 1, 0x10FF);
    cpu.writeByte(0x1100, value);
    cpu.y = 0x01;

    return 1;
}

fn setupValueIDXNoWrap(cpu: *CPU, value: u8) u1 {
    cpu.writeByte(START_ADDR + 1, 0x11);
    cpu.writeWord(0x0012, 0x1234);
    cpu.writeByte(0x1234, value);
    cpu.x = 0x01;

    return 0;
}

fn setupValueIDXWrap(cpu: *CPU, value: u8) u1 {
    cpu.writeByte(START_ADDR + 1, 0xFF);
    cpu.writeWord(0x0000, 0x1234);
    cpu.writeByte(0x1234, value);
    cpu.x = 0x01;

    return 0;
}

fn setupValueIDYNoCross(cpu: *CPU, value: u8) u1 {
    cpu.writeByte(START_ADDR + 1, 0x11);
    cpu.writeWord(0x0011, 0x1234);
    cpu.writeByte(0x1235, value);
    cpu.y = 0x01;

    return 0;
}

fn setupValueIDYCross(cpu: *CPU, value: u8) u1 {
    cpu.writeByte(START_ADDR + 1, 0x11);
    cpu.writeWord(0x0011, 0x10FF);
    cpu.writeByte(0x1100, value);
    cpu.y = 0x01;

    return 1;
}

// ------------------------------ Without value --------------------------------

fn setupNoValueZPG(cpu: *CPU) void {
    cpu.writeByte(START_ADDR + 1, 0x11);
}

fn setupNoValueZPXNoWrap(cpu: *CPU) void {
    cpu.writeByte(START_ADDR + 1, 0x10);
    cpu.x = 0x01;
}

fn setupNoValueZPXWrap(cpu: *CPU) void {
    cpu.writeByte(START_ADDR + 1, 0xFF);
    cpu.x = 0x12;
}

fn setupNoValueZPYNoWrap(cpu: *CPU) void {
    cpu.writeByte(START_ADDR + 1, 0x10);
    cpu.y = 0x01;
}

fn setupNoValueZPYWrap(cpu: *CPU) void {
    cpu.writeByte(START_ADDR + 1, 0xFF);
    cpu.y = 0x12;
}

fn setupNoValueABS(cpu: *CPU) void {
    cpu.writeWord(START_ADDR + 1, 0x0011);
}

fn setupNoValueABX(cpu: *CPU) void {
    cpu.writeWord(START_ADDR + 1, 0x0010);
    cpu.x = 0x01;
}

fn setupNoValueABY(cpu: *CPU) void {
    cpu.writeWord(START_ADDR + 1, 0x0010);
    cpu.y = 0x01;
}

fn setupNoValueIND(cpu: *CPU) void {
    cpu.writeWord(START_ADDR + 1, 0x1234);
    cpu.writeWord(0x1234, 0x0011);
}

fn setupNoValueIDXNoWrap(cpu: *CPU) void {
    cpu.writeByte(START_ADDR + 1, 0x22);
    cpu.writeWord(0x0023, 0x0011);
    cpu.x = 0x01;
}

fn setupNoValueIDXWrap(cpu: *CPU) void {
    cpu.writeByte(START_ADDR + 1, 0xFF);
    cpu.writeWord(0x0000, 0x0011);
    cpu.x = 0x01;
}

fn setupNoValueIDY(cpu: *CPU) void {
    cpu.writeByte(START_ADDR + 1, 0x22);
    cpu.writeWord(0x0022, 0x0010);
    cpu.y = 0x01;
}

// -----------------------------------------------------------------------------
//                               TEST FUNCTIONS                                 
// -----------------------------------------------------------------------------

// ------------------------------ Load register --------------------------------

fn testLoadRegister(cpu: *CPU, opcode: Opcode, register: *u8, setup: ValueSetupFn) !void {
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

// ----------------------------- Store register --------------------------------

fn testStoreRegister(cpu: *CPU, opcode: Opcode, register: *u8, setup: NoValueSetupFn) !void {
    const cycles = getInstructionCycles(cpu, opcode);

    cpu.writeByte(START_ADDR, @intFromEnum(opcode));
    setup(cpu);

    register.* = 0x80;
    cpu.run(cycles);

    try testing.expectEqual(cpu.readByte(0x0011), 0x80);
    try testing.expectEqual(cpu.cycles, 0);
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
    cpu.stackPushByte(0x80);
    cpu.run(cycles);

    try testing.expectEqual(cpu.getFlag(.Z), false);
    try testing.expectEqual(cpu.getFlag(.N), true);
    try testing.expectEqual(register.*, 0x80);
    try testing.expectEqual(cpu.sp, CPU.RESET_SP);
    try testing.expectEqual(cpu.cycles, 0);
}

// ---------------------- Logical/Arithmetic operations ------------------------

fn testLogicalOperation(cpu: *CPU, opcode: Opcode, op: LogicalOp, setup: ValueSetupFn) !void {
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

fn testArithmeticOperation(cpu: *CPU, opcode: Opcode, setup: ValueSetupFn, params: ArithmeticOpParams) !void {
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

// -------------------------------- Bit test -----------------------------------

fn testBitTest(cpu: *CPU, opcode: Opcode, setup: ValueSetupFn) !void {
    const cycles = getInstructionCycles(cpu, opcode);

    cpu.writeByte(START_ADDR, @intFromEnum(opcode));
    _ = setup(cpu, 0x93);

    cpu.setFlag(.Z, true);
    cpu.setFlag(.V, true);
    cpu.a = 0x01;
    cpu.run(cycles);

    try testing.expectEqual(cpu.getFlag(.Z), false);
    try testing.expectEqual(cpu.getFlag(.V), false);
    try testing.expectEqual(cpu.getFlag(.N), true);
    try testing.expectEqual(cpu.cycles, 0);
}

// ---------------------------- Compare register -------------------------------

fn testCompareRegister(cpu: *CPU, opcode: Opcode, register: *u8, setup: ValueSetupFn) !void {
    const cycles = getInstructionCycles(cpu, opcode);

    cpu.writeByte(START_ADDR, @intFromEnum(opcode));
    const extra_cycle = setup(cpu, 0x02);

    cpu.setFlag(.C, true);
    cpu.setFlag(.Z, true);
    register.* = 0x01;
    cpu.run(cycles + extra_cycle);

    try testing.expectEqual(cpu.getFlag(.C), false);
    try testing.expectEqual(cpu.getFlag(.Z), false);
    try testing.expectEqual(cpu.getFlag(.N), true);
    try testing.expectEqual(cpu.cycles, 0);
}

// -------------------------- Increments/Decrements ----------------------------

fn testIncrementDecrement(cpu: *CPU, opcode: Opcode, op: IncDecOp, setup: NoValueSetupFn) !void {
    const cycles = getInstructionCycles(cpu, opcode);
    const result = op(0x81);
    
    cpu.writeByte(START_ADDR, @intFromEnum(opcode));
    cpu.writeByte(0x0011, 0x81);
    setup(cpu);

    cpu.setFlag(.Z, true);
    cpu.run(cycles);

    try testing.expectEqual(cpu.getFlag(.Z), false);
    try testing.expectEqual(cpu.getFlag(.N), true);
    try testing.expectEqual(cpu.readByte(0x0011), result);
    try testing.expectEqual(cpu.cycles, 0);
}

fn testIncrementDecrementRegister(cpu: *CPU, opcode: Opcode, op: IncDecOp, register: *u8) !void {
    const cycles = getInstructionCycles(cpu, opcode);
    const result = op(0x81);

    cpu.writeByte(START_ADDR, @intFromEnum(opcode));

    cpu.setFlag(.Z, true);
    register.* = 0x81;
    cpu.run(cycles);

    try testing.expectEqual(cpu.getFlag(.Z), false);
    try testing.expectEqual(cpu.getFlag(.N), true);
    try testing.expectEqual(register.*, result);
    try testing.expectEqual(cpu.cycles, 0);
}

// --------------------------------- Shifts ------------------------------------

fn testShiftLeft(cpu: *CPU, opcode: Opcode, acc: bool, rotate: bool, setup: ?NoValueSetupFn) !void {
    const cycles = getInstructionCycles(cpu, opcode);

    cpu.writeByte(START_ADDR, @intFromEnum(opcode));
    if (!acc) setup.?(cpu);
    
    if (acc) cpu.a = 0x40
    else cpu.writeByte(0x0011, 0x40);

    cpu.setFlag(.C, true);
    cpu.setFlag(.Z, true);
    const mask: u8 = if (rotate) @intFromBool(cpu.getFlag(.C)) else 0;
    cpu.run(cycles);

    const src = if (acc) cpu.a else cpu.readByte(0x0011);

    try testing.expectEqual(cpu.getFlag(.C), false);
    try testing.expectEqual(cpu.getFlag(.Z), false);
    try testing.expectEqual(cpu.getFlag(.N), true);
    try testing.expectEqual(src, 0x80 | mask);
    try testing.expectEqual(cpu.cycles, 0);    
}

fn testShiftRight(cpu: *CPU, opcode: Opcode, acc: bool, rotate: bool, setup: ?NoValueSetupFn) !void {
    const cycles = getInstructionCycles(cpu, opcode);

    cpu.writeByte(START_ADDR, @intFromEnum(opcode));
    if (!acc) setup.?(cpu);
    
    if (acc) cpu.a = 0x40
    else cpu.writeByte(0x0011, 0x40);

    cpu.setFlag(.C, true);
    cpu.setFlag(.Z, true);
    const mask: u8 = if (rotate) @as(u8, @intFromBool(cpu.getFlag(.C))) << 7 else 0;
    cpu.run(cycles);

    const src = if (acc) cpu.a else cpu.readByte(0x0011);

    try testing.expectEqual(cpu.getFlag(.C), false);
    try testing.expectEqual(cpu.getFlag(.Z), false);
    try testing.expectEqual(cpu.getFlag(.N), rotate);
    try testing.expectEqual(src, 0x20 | mask);
    try testing.expectEqual(cpu.cycles, 0);    
}

// ---------------------------------- Jump -------------------------------------

fn testJump(cpu: *CPU, opcode: Opcode, setup: NoValueSetupFn) !void {
    const cycles = getInstructionCycles(cpu, opcode);

    cpu.writeByte(START_ADDR, @intFromEnum(opcode));
    setup(cpu);

    cpu.run(cycles);

    try testing.expectEqual(cpu.pc, 0x0011);
    try testing.expectEqual(cpu.cycles, 0);
}

fn testJumpBug(cpu: *CPU, opcode: Opcode) !void {
    const cycles = getInstructionCycles(cpu, opcode);

    cpu.writeByte(START_ADDR + 0, @intFromEnum(opcode));
    cpu.writeWord(START_ADDR + 1, 0x00FF);
    cpu.writeByte(0x00FF, 0x34);
    cpu.writeByte(0x0000, 0x12);

    cpu.run(cycles);

    try testing.expectEqual(cpu.pc, 0x1234);
    try testing.expectEqual(cpu.cycles, 0);
}

fn testJumpSubroutine(cpu: *CPU, opcode: Opcode) !void {
    const cycles = getInstructionCycles(cpu, opcode);

    cpu.writeByte(START_ADDR + 0, @intFromEnum(opcode));
    cpu.writeWord(START_ADDR + 1, 0x1234);

    cpu.run(cycles);

    try testing.expectEqual(cpu.sp, CPU.RESET_SP - 2);
    try testing.expectEqual(cpu.pc, 0x1234);
    try testing.expectEqual(cpu.cycles, 0);
}

fn testJumpReturnSubroutine(cpu: *CPU) !void {
    const cycles_jsr = getInstructionCycles(cpu, .JSR_ABS);
    const cycles_rts = getInstructionCycles(cpu, .RTS_IMP);

    cpu.writeByte(START_ADDR + 0, @intFromEnum(Opcode.JSR_ABS));
    cpu.writeWord(START_ADDR + 1, 0x1234);

    cpu.run(cycles_jsr);

    try testing.expectEqual(cpu.sp, CPU.RESET_SP - 2);
    try testing.expectEqual(cpu.pc, 0x1234);
    try testing.expectEqual(cpu.cycles, 0);

    cpu.writeByte(0x1234, @intFromEnum(Opcode.RTS_IMP));

    cpu.run(cycles_rts);

    try testing.expectEqual(cpu.sp, CPU.RESET_SP);
    try testing.expectEqual(cpu.pc, START_ADDR + 2);
    try testing.expectEqual(cpu.cycles, 0);
}

// -------------------------------- Branching ----------------------------------

fn testBranch(cpu: *CPU, opcode: Opcode, flag: Flag, set: bool) !void {
    const cycles = getInstructionCycles(cpu, opcode);
    const branch_taken = true;
    const page_crossed = true;

    cpu.writeByte(START_ADDR + 0, @intFromEnum(opcode));
    cpu.writeByte(START_ADDR + 1, 0xF6); // offset: -10

    cpu.setFlag(flag, set);
    cpu.run(cycles + @intFromBool(branch_taken) + 2 * @as(u2, @intFromBool(page_crossed)));

    try testing.expectEqual(cpu.pc, START_ADDR - 8);
    try testing.expectEqual(cpu.cycles, 0);
}

// ------------------------------ Change flags ---------------------------------

fn testChangeFlag(cpu: *CPU, opcode: Opcode, flag: Flag, expected: bool) !void {
    const cycles = getInstructionCycles(cpu, opcode);

    cpu.writeByte(START_ADDR, @intFromEnum(opcode));

    cpu.setFlag(flag, !expected);
    cpu.run(cycles);

    try testing.expectEqual(cpu.getFlag(flag), expected);
    try testing.expectEqual(cpu.cycles, 0);
}

// ------------------------------- Interrupts ----------------------------------

fn testInterrupt(cpu: *CPU) !void {
    const cycles_brk = getInstructionCycles(cpu, .BRK_IMP);
    const cycles_rti = getInstructionCycles(cpu, .RTI_IMP);

    cpu.writeByte(START_ADDR, @intFromEnum(Opcode.BRK_IMP));

    cpu.run(cycles_brk);

    try testing.expectEqual(cpu.getFlag(.B), true);
    try testing.expectEqual(cpu.sp, CPU.RESET_SP - 3);
    try testing.expectEqual(cpu.pc, CPU.INTER_VECTOR);
    try testing.expectEqual(cpu.cycles, 0);

    cpu.writeByte(CPU.INTER_VECTOR, @intFromEnum(Opcode.RTI_IMP));

    cpu.run(cycles_rti);

    try testing.expectEqual(cpu.getFlag(.B), false);
    try testing.expectEqual(cpu.sp, CPU.RESET_SP);
    try testing.expectEqual(cpu.pc, START_ADDR + 1);
    try testing.expectEqual(cpu.cycles, 0);
}

// ------------------------------ No operation ---------------------------------

fn testNoOperation(cpu: *CPU, opcode: Opcode) !void {
    const cycles = getInstructionCycles(cpu, opcode);

    cpu.writeByte(START_ADDR, @intFromEnum(opcode));

    cpu.run(cycles);

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
    try testLoadRegister(&ctx.cpu, .LDA_IMM, &ctx.cpu.a, &setupValueIMM);
}

test "LDA ZPG" {
    var ctx = TestContext.init();
    try testLoadRegister(&ctx.cpu, .LDA_ZPG, &ctx.cpu.a, &setupValueZPG);
}

test "LDA ZPX without wrap around" {
    var ctx = TestContext.init();
    try testLoadRegister(&ctx.cpu, .LDA_ZPX, &ctx.cpu.a, &setupValueZPXNoWrap);
}

test "LDA ZPX with wrap around" {
    var ctx = TestContext.init();
    try testLoadRegister(&ctx.cpu, .LDA_ZPX, &ctx.cpu.a, &setupValueZPXWrap);
}

test "LDA ABS" {
    var ctx = TestContext.init();
    try testLoadRegister(&ctx.cpu, .LDA_ABS, &ctx.cpu.a, &setupValueABS);
}

test "LDA ABX without page crossing" {
    var ctx = TestContext.init();
    try testLoadRegister(&ctx.cpu, .LDA_ABX, &ctx.cpu.a,&setupValueABXNoCross);
}

test "LDA ABX with page crossing" {
    var ctx = TestContext.init();
    try testLoadRegister(&ctx.cpu, .LDA_ABX, &ctx.cpu.a,&setupValueABXCross);
}

test "LDA ABY without page crossing" {
    var ctx = TestContext.init();
    try testLoadRegister(&ctx.cpu, .LDA_ABY, &ctx.cpu.a,&setupValueABYNoCross);
}

test "LDA ABY with page crossing" {
    var ctx = TestContext.init();
    try testLoadRegister(&ctx.cpu, .LDA_ABY, &ctx.cpu.a,&setupValueABYCross);
}

test "LDA IDX without wrap around" {
    var ctx = TestContext.init();
    try testLoadRegister(&ctx.cpu, .LDA_IDX, &ctx.cpu.a, &setupValueIDXNoWrap);
}

test "LDA IDX with wrap around" {
    var ctx = TestContext.init();
    try testLoadRegister(&ctx.cpu, .LDA_IDX, &ctx.cpu.a, &setupValueIDXWrap);
}

test "LDA IDY without page crossing" {
    var ctx = TestContext.init();
    try testLoadRegister(&ctx.cpu, .LDA_IDY, &ctx.cpu.a, &setupValueIDYNoCross);
}

test "LDA IDY with page crossing" {
    var ctx = TestContext.init();
    try testLoadRegister(&ctx.cpu, .LDA_IDY, &ctx.cpu.a, &setupValueIDYCross);
}

// -------------------------- LDX - Load X register ----------------------------

test "LDX IMM" {
    var ctx = TestContext.init();
    try testLoadRegister(&ctx.cpu, .LDX_IMM, &ctx.cpu.x, &setupValueIMM);
}

test "LDX ZPG" {
    var ctx = TestContext.init();
    try testLoadRegister(&ctx.cpu, .LDX_ZPG, &ctx.cpu.x, &setupValueZPG);
}

test "LDX ZPY with wrap around" {
    var ctx = TestContext.init();
    try testLoadRegister(&ctx.cpu, .LDX_ZPY, &ctx.cpu.x, &setupValueZPYNoWrap);
}

test "LDX ZPY without wrap around" {
    var ctx = TestContext.init();
    try testLoadRegister(&ctx.cpu, .LDX_ZPY, &ctx.cpu.x, &setupValueZPYWrap);
}

test "LDX ABS" {
    var ctx = TestContext.init();
    try testLoadRegister(&ctx.cpu, .LDX_ABS, &ctx.cpu.x, &setupValueABS);
}

test "LDX ABY without page crossing" {
    var ctx = TestContext.init();
    try testLoadRegister(&ctx.cpu, .LDX_ABY, &ctx.cpu.x, &setupValueABYNoCross);
}

test "LDX ABY with page crossing" {
    var ctx = TestContext.init();
    try testLoadRegister(&ctx.cpu, .LDX_ABY, &ctx.cpu.x, &setupValueABYCross);
}

// -------------------------- LDY - Load Y register ----------------------------

test "LDY IMM" {
    var ctx = TestContext.init();
    try testLoadRegister(&ctx.cpu, .LDY_IMM, &ctx.cpu.y, &setupValueIMM);
}

test "LDY ZPG" {
    var ctx = TestContext.init();
    try testLoadRegister(&ctx.cpu, .LDY_ZPG, &ctx.cpu.y, &setupValueZPG);
}

test "LDY ZPX without wrap around" {
    var ctx = TestContext.init();
    try testLoadRegister(&ctx.cpu, .LDY_ZPX, &ctx.cpu.y, &setupValueZPXNoWrap);
}

test "LDY ZPX with wrap around" {
    var ctx = TestContext.init();
    try testLoadRegister(&ctx.cpu, .LDY_ZPX, &ctx.cpu.y, &setupValueZPXWrap);
}

test "LDY ABS" {
    var ctx = TestContext.init();
    try testLoadRegister(&ctx.cpu, .LDY_ABS, &ctx.cpu.y, &setupValueABS);
}

test "LDY ABX without page crossing" {
    var ctx = TestContext.init();
    try testLoadRegister(&ctx.cpu, .LDY_ABX, &ctx.cpu.y, &setupValueABXNoCross);
}

test "LDY ABX with page crossing" {
    var ctx = TestContext.init();
    try testLoadRegister(&ctx.cpu, .LDY_ABX, &ctx.cpu.y, &setupValueABXCross);
}

// ------------------------- STA - Store accumulator ---------------------------

test "STA ZPG" {
    var ctx = TestContext.init();
    try testStoreRegister(&ctx.cpu, .STA_ZPG, &ctx.cpu.a, &setupNoValueZPG);
}

test "STA ZPX without wrap around" {
    var ctx = TestContext.init();
    try testStoreRegister(&ctx.cpu, .STA_ZPX, &ctx.cpu.a, &setupNoValueZPXNoWrap);
}

test "STA ZPX with wrap around" {
    var ctx = TestContext.init();
    try testStoreRegister(&ctx.cpu, .STA_ZPX, &ctx.cpu.a, &setupNoValueZPXWrap);
}

test "STA ABS" {
    var ctx = TestContext.init();
    try testStoreRegister(&ctx.cpu, .STA_ABS, &ctx.cpu.a, &setupNoValueABS);
}

test "STA ABX" {
    var ctx = TestContext.init();
    try testStoreRegister(&ctx.cpu, .STA_ABX, &ctx.cpu.a, &setupNoValueABX);
}

test "STA ABY" {
    var ctx = TestContext.init();
    try testStoreRegister(&ctx.cpu, .STA_ABY, &ctx.cpu.a, &setupNoValueABY);
}

test "STA IDX without wrap around" {
    var ctx = TestContext.init();
    try testStoreRegister(&ctx.cpu, .STA_IDX, &ctx.cpu.a, &setupNoValueIDXNoWrap);
}

test "STA IDX with wrap around" {
    var ctx = TestContext.init();
    try testStoreRegister(&ctx.cpu, .STA_IDX, &ctx.cpu.a, &setupNoValueIDXWrap);
}

test "STA IDY" {
    var ctx = TestContext.init();
    try testStoreRegister(&ctx.cpu, .STA_IDY, &ctx.cpu.a, &setupNoValueIDY);
}

// ------------------------- STX - Store X register ----------------------------

test "STX ZPG" {
    var ctx = TestContext.init();
    try testStoreRegister(&ctx.cpu, .STX_ZPG, &ctx.cpu.x, &setupNoValueZPG);
}

test "STX ZPY without wrap around" {
    var ctx = TestContext.init();
    try testStoreRegister(&ctx.cpu, .STX_ZPY, &ctx.cpu.x, &setupNoValueZPYNoWrap);
}

test "STX ZPY with wrap around" {
    var ctx = TestContext.init();
    try testStoreRegister(&ctx.cpu, .STX_ZPY, &ctx.cpu.x, &setupNoValueZPYWrap);
}

test "STX ABS" {
    var ctx = TestContext.init();
    try testStoreRegister(&ctx.cpu, .STX_ABS, &ctx.cpu.x, &setupNoValueABS);
}

// ------------------------- STY - Store Y register ----------------------------

test "STY ZPG" {
    var ctx = TestContext.init();
    try testStoreRegister(&ctx.cpu, .STY_ZPG, &ctx.cpu.y, &setupNoValueZPG);
}

test "STY ZPX without wrap around" {
    var ctx = TestContext.init();
    try testStoreRegister(&ctx.cpu, .STY_ZPX, &ctx.cpu.y, &setupNoValueZPXNoWrap);
}

test "STY ZPX with wrap around" {
    var ctx = TestContext.init();
    try testStoreRegister(&ctx.cpu, .STY_ZPX, &ctx.cpu.y, &setupNoValueZPXWrap);
}

test "STY ABS" {
    var ctx = TestContext.init();
    try testStoreRegister(&ctx.cpu, .STY_ABS, &ctx.cpu.y, &setupNoValueABS);
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
    try testLogicalOperation(&ctx.cpu, .AND_IMM, &logicalAND, &setupValueIMM);
}

test "AND ZPG" {
    var ctx = TestContext.init();
    try testLogicalOperation(&ctx.cpu, .AND_ZPG, &logicalAND, &setupValueZPG);
}

test "AND ZPX without wrap around" {
    var ctx = TestContext.init();
    try testLogicalOperation(&ctx.cpu, .AND_ZPX, &logicalAND, &setupValueZPXNoWrap);
}

test "AND ZPX with wrap around" {
    var ctx = TestContext.init();
    try testLogicalOperation(&ctx.cpu, .AND_ZPX, &logicalAND, &setupValueZPXWrap);
}

test "AND ABS" {
    var ctx = TestContext.init();
    try testLogicalOperation(&ctx.cpu, .AND_ABS, &logicalAND, &setupValueABS);
}

test "AND ABX without page crossing" {
    var ctx = TestContext.init();
    try testLogicalOperation(&ctx.cpu, .AND_ABX, &logicalAND, &setupValueABXNoCross);
}

test "AND ABX with page crossing" {
    var ctx = TestContext.init();
    try testLogicalOperation(&ctx.cpu, .AND_ABX, &logicalAND, &setupValueABXCross);
}

test "AND ABY without page crossing" {
    var ctx = TestContext.init();
    try testLogicalOperation(&ctx.cpu, .AND_ABY, &logicalAND, &setupValueABYNoCross);
}

test "AND ABY with page crossing" {
    var ctx = TestContext.init();
    try testLogicalOperation(&ctx.cpu, .AND_ABY, &logicalAND, &setupValueABYCross);
}

test "AND IDX without wrap around" {
    var ctx = TestContext.init();
    try testLogicalOperation(&ctx.cpu, .AND_IDX, &logicalAND, &setupValueIDXNoWrap);
}

test "AND IDX with wrap around" {
    var ctx = TestContext.init();
    try testLogicalOperation(&ctx.cpu, .AND_IDX, &logicalAND, &setupValueIDXWrap);
}

test "AND IDY without page crossing" {
    var ctx = TestContext.init();
    try testLogicalOperation(&ctx.cpu, .AND_IDY, &logicalAND, &setupValueIDYNoCross);
}

test "AND IDY with page crossing" {
    var ctx = TestContext.init();
    try testLogicalOperation(&ctx.cpu, .AND_IDY, &logicalAND, &setupValueIDYCross);
}

// --------------------------- EOR - Exclusive OR ------------------------------

test "EOR IMM" {
    var ctx = TestContext.init();
    try testLogicalOperation(&ctx.cpu, .EOR_IMM, &logicalXOR, &setupValueIMM);
}

test "EOR ZPG" {
    var ctx = TestContext.init();
    try testLogicalOperation(&ctx.cpu, .EOR_ZPG, &logicalXOR, &setupValueZPG);
}

test "EOR ZPX without wrap around" {
    var ctx = TestContext.init();
    try testLogicalOperation(&ctx.cpu, .EOR_ZPX, &logicalXOR, &setupValueZPXNoWrap);
}

test "EOR ZPX with wrap around" {
    var ctx = TestContext.init();
    try testLogicalOperation(&ctx.cpu, .EOR_ZPX, &logicalXOR, &setupValueZPXWrap);
}

test "EOR ABS" {
    var ctx = TestContext.init();
    try testLogicalOperation(&ctx.cpu, .EOR_ABS, &logicalXOR, &setupValueABS);
}

test "EOR ABX without page crossing" {
    var ctx = TestContext.init();
    try testLogicalOperation(&ctx.cpu, .EOR_ABX, &logicalXOR, &setupValueABXNoCross);
}

test "EOR ABX with page crossing" {
    var ctx = TestContext.init();
    try testLogicalOperation(&ctx.cpu, .EOR_ABX, &logicalXOR, &setupValueABXCross);
}

test "EOR ABY without page crossing" {
    var ctx = TestContext.init();
    try testLogicalOperation(&ctx.cpu, .EOR_ABY, &logicalXOR, &setupValueABYNoCross);
}

test "EOR ABY with page crossing" {
    var ctx = TestContext.init();
    try testLogicalOperation(&ctx.cpu, .EOR_ABY, &logicalXOR, &setupValueABYCross);
}

test "EOR IDX without wrap around" {
    var ctx = TestContext.init();
    try testLogicalOperation(&ctx.cpu, .EOR_IDX, &logicalXOR, &setupValueIDXNoWrap);
}

test "EOR IDX with wrap around" {
    var ctx = TestContext.init();
    try testLogicalOperation(&ctx.cpu, .EOR_IDX, &logicalXOR, &setupValueIDXWrap);
}

test "EOR IDY without page crossing" {
    var ctx = TestContext.init();
    try testLogicalOperation(&ctx.cpu, .EOR_IDY, &logicalXOR, &setupValueIDYNoCross);
}

test "EOR IDY with page crossing" {
    var ctx = TestContext.init();
    try testLogicalOperation(&ctx.cpu, .EOR_IDY, &logicalXOR, &setupValueIDYCross);
}

// ---------------------------- ORA - Logical OR -------------------------------

test "ORA IMM" {
    var ctx = TestContext.init();
    try testLogicalOperation(&ctx.cpu, .ORA_IMM, &logicalOR, &setupValueIMM);
}

test "ORA ZPG" {
    var ctx = TestContext.init();
    try testLogicalOperation(&ctx.cpu, .ORA_ZPG, &logicalOR, &setupValueZPG);
}

test "ORA ZPX without wrap around" {
    var ctx = TestContext.init();
    try testLogicalOperation(&ctx.cpu, .ORA_ZPX, &logicalOR, &setupValueZPXNoWrap);
}

test "ORA ZPX with wrap around" {
    var ctx = TestContext.init();
    try testLogicalOperation(&ctx.cpu, .ORA_ZPX, &logicalOR, &setupValueZPXWrap);
}

test "ORA ABS" {
    var ctx = TestContext.init();
    try testLogicalOperation(&ctx.cpu, .ORA_ABS, &logicalOR, &setupValueABS);
}

test "ORA ABX without page crossing" {
    var ctx = TestContext.init();
    try testLogicalOperation(&ctx.cpu, .ORA_ABX, &logicalOR, &setupValueABXNoCross);
}

test "ORA ABX with page crossing" {
    var ctx = TestContext.init();
    try testLogicalOperation(&ctx.cpu, .ORA_ABX, &logicalOR, &setupValueABXCross);
}

test "ORA ABY without page crossing" {
    var ctx = TestContext.init();
    try testLogicalOperation(&ctx.cpu, .ORA_ABY, &logicalOR, &setupValueABYNoCross);
}

test "ORA ABY with page crossing" {
    var ctx = TestContext.init();
    try testLogicalOperation(&ctx.cpu, .ORA_ABY, &logicalOR, &setupValueABYCross);
}

test "ORA IDX without wrap around" {
    var ctx = TestContext.init();
    try testLogicalOperation(&ctx.cpu, .ORA_IDX, &logicalOR, &setupValueIDXNoWrap);
}

test "ORA IDX with wrap around" {
    var ctx = TestContext.init();
    try testLogicalOperation(&ctx.cpu, .ORA_IDX, &logicalOR, &setupValueIDXWrap);
}

test "ORA IDY without page crossing" {
    var ctx = TestContext.init();
    try testLogicalOperation(&ctx.cpu, .ORA_IDY, &logicalOR, &setupValueIDYNoCross);
}

test "ORA IDY with page crossing" {
    var ctx = TestContext.init();
    try testLogicalOperation(&ctx.cpu, .ORA_IDY, &logicalOR, &setupValueIDYCross);
}

// ----------------------------- BIT - Bit test --------------------------------

test "BIT ZPG" {
    var ctx = TestContext.init();
    try testBitTest(&ctx.cpu, .BIT_ZPG, &setupValueZPG);
}

test "BIT ABS" {
    var ctx = TestContext.init();
    try testBitTest(&ctx.cpu, .BIT_ABS, &setupValueABS);
}

// -------------------------- ADC - Add with carry -----------------------------

test "ADC IMM" {
    var ctx = TestContext.init();
    try testArithmeticOperation(&ctx.cpu, .ADC_IMM, &setupValueIMM, .{
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
    try testArithmeticOperation(&ctx.cpu, .ADC_ZPG, &setupValueZPG, .{
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
    try testArithmeticOperation(&ctx.cpu, .ADC_ZPX, &setupValueZPXNoWrap, .{
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
    try testArithmeticOperation(&ctx.cpu, .ADC_ZPX, &setupValueZPXWrap, .{
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
    try testArithmeticOperation(&ctx.cpu, .ADC_ABS, &setupValueABS, .{
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
    try testArithmeticOperation(&ctx.cpu, .ADC_ABX, &setupValueABXNoCross, .{
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
    try testArithmeticOperation(&ctx.cpu, .ADC_ABX, &setupValueABXCross, .{
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
    try testArithmeticOperation(&ctx.cpu, .ADC_ABY, &setupValueABYNoCross, .{
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
    try testArithmeticOperation(&ctx.cpu, .ADC_ABY, &setupValueABYCross, .{
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
    try testArithmeticOperation(&ctx.cpu, .ADC_IDX, &setupValueIDXNoWrap, .{
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
    try testArithmeticOperation(&ctx.cpu, .ADC_IDX, &setupValueIDXWrap, .{
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
    try testArithmeticOperation(&ctx.cpu, .ADC_IDY, &setupValueIDYNoCross, .{
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
    try testArithmeticOperation(&ctx.cpu, .ADC_IDY, &setupValueIDYCross, .{
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
    try testArithmeticOperation(&ctx.cpu, .SBC_IMM, &setupValueIMM, .{
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
    try testArithmeticOperation(&ctx.cpu, .SBC_ZPG, &setupValueZPG, .{
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
    try testArithmeticOperation(&ctx.cpu, .SBC_ZPX, &setupValueZPXNoWrap, .{
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
    try testArithmeticOperation(&ctx.cpu, .SBC_ZPX, &setupValueZPXWrap, .{
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
    try testArithmeticOperation(&ctx.cpu, .SBC_ABS, &setupValueABS, .{
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
    try testArithmeticOperation(&ctx.cpu, .SBC_ABX, &setupValueABXNoCross, .{
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
    try testArithmeticOperation(&ctx.cpu, .SBC_ABX, &setupValueABXCross, .{
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
    try testArithmeticOperation(&ctx.cpu, .SBC_ABY, &setupValueABYNoCross, .{
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
    try testArithmeticOperation(&ctx.cpu, .SBC_ABY, &setupValueABYCross, .{
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
    try testArithmeticOperation(&ctx.cpu, .SBC_IDX, &setupValueIDXNoWrap, .{
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
    try testArithmeticOperation(&ctx.cpu, .SBC_IDX, &setupValueIDXWrap, .{
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
    try testArithmeticOperation(&ctx.cpu, .SBC_IDY, &setupValueIDYNoCross, .{
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
    try testArithmeticOperation(&ctx.cpu, .SBC_IDY, &setupValueIDYCross, .{
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

// ------------------------ CMP - Compare accumulator --------------------------

test "CMP IMM" {
    var ctx = TestContext.init();
    try testCompareRegister(&ctx.cpu, .CMP_IMM, &ctx.cpu.a, &setupValueIMM);
}

test "CMP ZPG" {
    var ctx = TestContext.init();
    try testCompareRegister(&ctx.cpu, .CMP_ZPG, &ctx.cpu.a, &setupValueZPG);
}

test "CMP ZPX without wrap around" {
    var ctx = TestContext.init();
    try testCompareRegister(&ctx.cpu, .CMP_ZPX, &ctx.cpu.a, &setupValueZPXNoWrap);
}

test "CMP ZPX with wrap around" {
    var ctx = TestContext.init();
    try testCompareRegister(&ctx.cpu, .CMP_ZPX, &ctx.cpu.a, &setupValueZPXWrap);
}

test "CMP ABS" {
    var ctx = TestContext.init();
    try testCompareRegister(&ctx.cpu, .CMP_ABS, &ctx.cpu.a, &setupValueABS);
}

test "CMP ABX without page crossing" {
    var ctx = TestContext.init();
    try testCompareRegister(&ctx.cpu, .CMP_ABX, &ctx.cpu.a, &setupValueABXNoCross);
}

test "CMP ABX with page crossing" {
    var ctx = TestContext.init();
    try testCompareRegister(&ctx.cpu, .CMP_ABX, &ctx.cpu.a, &setupValueABXCross);
}

test "CMP ABY without page crossing" {
    var ctx = TestContext.init();
    try testCompareRegister(&ctx.cpu, .CMP_ABY, &ctx.cpu.a, &setupValueABYNoCross);
}

test "CMP ABY with page crossing" {
    var ctx = TestContext.init();
    try testCompareRegister(&ctx.cpu, .CMP_ABY, &ctx.cpu.a, &setupValueABYCross);
}

test "CMP IDX without wrap around" {
    var ctx = TestContext.init();
    try testCompareRegister(&ctx.cpu, .CMP_IDX, &ctx.cpu.a, &setupValueIDXNoWrap);
}

test "CMP IDX with wrap around" {
    var ctx = TestContext.init();
    try testCompareRegister(&ctx.cpu, .CMP_IDX, &ctx.cpu.a, &setupValueIDXWrap);
}

test "CMP IDY without page crossing" {
    var ctx = TestContext.init();
    try testCompareRegister(&ctx.cpu, .CMP_IDY, &ctx.cpu.a, &setupValueIDYNoCross);
}

test "CMP IDY with page crossing" {
    var ctx = TestContext.init();
    try testCompareRegister(&ctx.cpu, .CMP_IDY, &ctx.cpu.a, &setupValueIDYCross);
}

// ------------------------ CPX - Compare X register ---------------------------

test "CPX IMM" {
    var ctx = TestContext.init();
    try testCompareRegister(&ctx.cpu, .CPX_IMM, &ctx.cpu.x, &setupValueIMM);
}

test "CPX ZPG" {
    var ctx = TestContext.init();
    try testCompareRegister(&ctx.cpu, .CPX_ZPG, &ctx.cpu.x, &setupValueZPG);
}

test "CPX ABS" {
    var ctx = TestContext.init();
    try testCompareRegister(&ctx.cpu, .CPX_ABS, &ctx.cpu.x, &setupValueABS);
}

// ------------------------ CPY - Compare Y register ---------------------------

test "CPY IMM" {
    var ctx = TestContext.init();
    try testCompareRegister(&ctx.cpu, .CPY_IMM, &ctx.cpu.y, &setupValueIMM);
}

test "CPY ZPG" {
    var ctx = TestContext.init();
    try testCompareRegister(&ctx.cpu, .CPY_ZPG, &ctx.cpu.y, &setupValueZPG);
}

test "CPY ABS" {
    var ctx = TestContext.init();
    try testCompareRegister(&ctx.cpu, .CPY_ABS, &ctx.cpu.y, &setupValueABS);
}

// ------------------------- INC - Increment memory ----------------------------

test "INC ZPG" {
    var ctx = TestContext.init();
    try testIncrementDecrement(&ctx.cpu, .INC_ZPG, &increment, &setupNoValueZPG);
}

test "INC ZPX without wrap around" {
    var ctx = TestContext.init();
    try testIncrementDecrement(&ctx.cpu, .INC_ZPX, &increment, &setupNoValueZPXNoWrap);
}

test "INC ZPX with wrap around" {
    var ctx = TestContext.init();
    try testIncrementDecrement(&ctx.cpu, .INC_ZPX, &increment, &setupNoValueZPXWrap);
}

test "INC ABS" {
    var ctx = TestContext.init();
    try testIncrementDecrement(&ctx.cpu, .INC_ABS, &increment, &setupNoValueABS);
}

test "INC ABX" {
    var ctx = TestContext.init();
    try testIncrementDecrement(&ctx.cpu, .INC_ABX, &increment, &setupNoValueABX);
}

// ----------------------- INX - Increment X register --------------------------

test "INX IMP" {
    var ctx = TestContext.init();
    try testIncrementDecrementRegister(&ctx.cpu, .INX_IMP, &increment, &ctx.cpu.x);
}

// ----------------------- INY - Increment Y register --------------------------

test "INY IMP" {
    var ctx = TestContext.init();
    try testIncrementDecrementRegister(&ctx.cpu, .INY_IMP, &increment, &ctx.cpu.y);
}

// ------------------------- DEC - Decrement memory ----------------------------

test "DEC ZPG" {
    var ctx = TestContext.init();
    try testIncrementDecrement(&ctx.cpu, .DEC_ZPG, &decrement, &setupNoValueZPG);
}

test "DEC ZPX without wrap around" {
    var ctx = TestContext.init();
    try testIncrementDecrement(&ctx.cpu, .DEC_ZPX, &decrement, &setupNoValueZPXNoWrap);
}

test "DEC ZPX with wrap around" {
    var ctx = TestContext.init();
    try testIncrementDecrement(&ctx.cpu, .DEC_ZPX, &decrement, &setupNoValueZPXWrap);
}

test "DEC ABS" {
    var ctx = TestContext.init();
    try testIncrementDecrement(&ctx.cpu, .DEC_ABS, &decrement, &setupNoValueABS);
}

test "DEC ABX" {
    var ctx = TestContext.init();
    try testIncrementDecrement(&ctx.cpu, .DEC_ABX, &decrement, &setupNoValueABX);
}

// ----------------------- DEX - Decrement X register --------------------------

test "DEX IMP" {
    var ctx = TestContext.init();
    try testIncrementDecrementRegister(&ctx.cpu, .DEX_IMP, &decrement, &ctx.cpu.x);
}

// ----------------------- DEY - Decrement Y register --------------------------

test "DEY IMP" {
    var ctx = TestContext.init();
    try testIncrementDecrementRegister(&ctx.cpu, .DEY_IMP, &decrement, &ctx.cpu.y);
}

// ----------------------- ASL - Arithmetic shift left -------------------------

test "ASL IMP" {
    var ctx = TestContext.init();
    try testShiftLeft(&ctx.cpu, .ASL_IMP, true, false, null);
}

test "ASL ZPG" {
    var ctx = TestContext.init();
    try testShiftLeft(&ctx.cpu, .ASL_ZPG, false, false, &setupNoValueZPG);
}

test "ASL ZPX without wrap around" {
    var ctx = TestContext.init();
    try testShiftLeft(&ctx.cpu, .ASL_ZPX, false, false, &setupNoValueZPXNoWrap);
}

test "ASL ZPX with wrap around" {
    var ctx = TestContext.init();
    try testShiftLeft(&ctx.cpu, .ASL_ZPX, false, false, &setupNoValueZPXWrap);
}

test "ASL ABS" {
    var ctx = TestContext.init();
    try testShiftLeft(&ctx.cpu, .ASL_ABS, false, false, &setupNoValueABS);
}

test "ASL ABX" {
    var ctx = TestContext.init();
    try testShiftLeft(&ctx.cpu, .ASL_ABX, false, false, &setupNoValueABX);
}

// ------------------------ LSR - Logical shift right --------------------------

test "LSR IMP" {
    var ctx = TestContext.init();
    try testShiftRight(&ctx.cpu, .LSR_IMP, true, false, null);
}

test "LSR ZPG" {
    var ctx = TestContext.init();
    try testShiftRight(&ctx.cpu, .LSR_ZPG, false, false, &setupNoValueZPG);
}

test "LSR ZPX without wrap around" {
    var ctx = TestContext.init();
    try testShiftRight(&ctx.cpu, .LSR_ZPX, false, false, &setupNoValueZPXNoWrap);
}

test "LSR ZPX with wrap around" {
    var ctx = TestContext.init();
    try testShiftRight(&ctx.cpu, .LSR_ZPX, false, false, &setupNoValueZPXWrap);
}

test "LSR ABS" {
    var ctx = TestContext.init();
    try testShiftRight(&ctx.cpu, .LSR_ABS, false, false, &setupNoValueABS);
}

test "LSR ABX" {
    var ctx = TestContext.init();
    try testShiftRight(&ctx.cpu, .LSR_ABX, false, false, &setupNoValueABX);
}

// ---------------------------- ROL - Rotate left ------------------------------

test "ROL IMP" {
    var ctx = TestContext.init();
    try testShiftLeft(&ctx.cpu, .ROL_IMP, true, true, null);
}

test "ROL ZPG" {
    var ctx = TestContext.init();
    try testShiftLeft(&ctx.cpu, .ROL_ZPG, false, true, &setupNoValueZPG);
}

test "ROL ZPX without wrap around" {
    var ctx = TestContext.init();
    try testShiftLeft(&ctx.cpu, .ROL_ZPX, false, true, &setupNoValueZPXNoWrap);
}

test "ROL ZPX with wrap around" {
    var ctx = TestContext.init();
    try testShiftLeft(&ctx.cpu, .ROL_ZPX, false, true, &setupNoValueZPXWrap);
}

test "ROL ABS" {
    var ctx = TestContext.init();
    try testShiftLeft(&ctx.cpu, .ROL_ABS, false, true, &setupNoValueABS);
}

test "ROL ABX" {
    var ctx = TestContext.init();
    try testShiftLeft(&ctx.cpu, .ROL_ABX, false, true, &setupNoValueABX);
}

// --------------------------- ROR - Rotate right ------------------------------

test "ROR IMP" {
    var ctx = TestContext.init();
    try testShiftRight(&ctx.cpu, .ROR_IMP, true, true, null);
}

test "ROR ZPG" {
    var ctx = TestContext.init();
    try testShiftRight(&ctx.cpu, .ROR_ZPG, false, true, &setupNoValueZPG);
}

test "ROR ZPX without wrap around" {
    var ctx = TestContext.init();
    try testShiftRight(&ctx.cpu, .ROR_ZPX, false, true, &setupNoValueZPXNoWrap);
}

test "ROR ZPX with wrap around" {
    var ctx = TestContext.init();
    try testShiftRight(&ctx.cpu, .ROR_ZPX, false, true, &setupNoValueZPXWrap);
}

test "ROR ABS" {
    var ctx = TestContext.init();
    try testShiftRight(&ctx.cpu, .ROR_ABS, false, true, &setupNoValueABS);
}

test "ROR ABX" {
    var ctx = TestContext.init();
    try testShiftRight(&ctx.cpu, .ROR_ABX, false, true, &setupNoValueABX);
}

// ------------------------------- JMP - Jump ----------------------------------

test "JMP ABS" {
    var ctx = TestContext.init();
    try testJump(&ctx.cpu, .JMP_ABS, &setupNoValueABS);
}

test "JMP IND no bug" {
    var ctx = TestContext.init();
    try testJump(&ctx.cpu, .JMP_IND, &setupNoValueIND);
}

test "JMP IND bug" {
    var ctx = TestContext.init();
    try testJumpBug(&ctx.cpu, .JMP_IND);
}

// ---------------- JSR/RTS - Jump to/Return from subroutine -------------------

test "JSR ABS / RTS IMP" {
    var ctx = TestContext.init();
    try testJumpReturnSubroutine(&ctx.cpu);
}

// ----------------------- BCC - Branch if carry clear -------------------------

test "BCC REL" {
    var ctx = TestContext.init();
    try testBranch(&ctx.cpu, .BCC_REL, .C, false);
}

// ------------------------ BCS - Branch if carry set --------------------------

test "BCS REL" {
    var ctx = TestContext.init();
    try testBranch(&ctx.cpu, .BCS_REL, .C, true);
}

// ------------------------ BEQ - Branch if zero set ---------------------------

test "BEQ REL" {
    var ctx = TestContext.init();
    try testBranch(&ctx.cpu, .BEQ_REL, .Z, true);
}

// ---------------------- BMI - Branch if negative set -------------------------

test "BMI REL" {
    var ctx = TestContext.init();
    try testBranch(&ctx.cpu, .BMI_REL, .N, true);
}

// --------------------- BNE - Branch if negative clear ------------------------

test "BNE REL" {
    var ctx = TestContext.init();
    try testBranch(&ctx.cpu, .BNE_REL, .Z, false);
}

// --------------------- BPL - Branch if negative clear ------------------------

test "BPL REL" {
    var ctx = TestContext.init();
    try testBranch(&ctx.cpu, .BPL_REL, .N, false);
}

// --------------------- BVC - Branch if overflow clear ------------------------

test "BVC REL" {
    var ctx = TestContext.init();
    try testBranch(&ctx.cpu, .BVC_REL, .V, false);
}

// ---------------------- BVS - Branch if overflow set -------------------------

test "BVS REL" {
    var ctx = TestContext.init();
    try testBranch(&ctx.cpu, .BVS_REL, .V, true);
}

// ------------------------- CLC - Clear carry flag ----------------------------

test "CLC IMP" {
    var ctx = TestContext.init();
    try testChangeFlag(&ctx.cpu, .CLC_IMP, .C, false);
}

test "CLD IMP" {
    var ctx = TestContext.init();
    try testChangeFlag(&ctx.cpu, .CLD_IMP, .D, false);
}

test "CLI IMP" {
    var ctx = TestContext.init();
    try testChangeFlag(&ctx.cpu, .CLI_IMP, .I, false);
}

test "CLV IMP" {
    var ctx = TestContext.init();
    try testChangeFlag(&ctx.cpu, .CLV_IMP, .V, false);
}

test "SEC IMP" {
    var ctx = TestContext.init();
    try testChangeFlag(&ctx.cpu, .SEC_IMP, .C, true);
}

test "SED IMP" {
    var ctx = TestContext.init();
    try testChangeFlag(&ctx.cpu, .SED_IMP, .D, true);
}

test "SEI IMP" {
    var ctx = TestContext.init();
    try testChangeFlag(&ctx.cpu, .SEI_IMP, .I, true);
}

// -------------------------- BRK - Force interrupt ----------------------------
// ----------------------- RTI - Return from interrupt -------------------------

test "BRK IMP / RTI IMP" {
    var ctx = TestContext.init();
    try testInterrupt(&ctx.cpu);
}

// --------------------------- NOP - No operation ------------------------------

test "NOP IMP" {
    var ctx = TestContext.init();
    try testNoOperation(&ctx.cpu, .NOP_IMP);
}