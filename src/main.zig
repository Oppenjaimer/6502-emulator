const std = @import("std");

const emulator = @import("emulator.zig");
const CPU = emulator.CPU;
const Memory = emulator.Memory;
const Opcode = CPU.Opcode;

pub fn main() void {
    var mem = Memory.init();

    mem.write(CPU.RESET_VECTOR + 0, 0x00);
    mem.write(CPU.RESET_VECTOR + 1, 0x30);
    mem.write(0x3000, @intFromEnum(Opcode.LDA_IMM));
    mem.write(0x3001, 0x80);

    var cpu = CPU.init(&mem);

    std.debug.print("A=0x{X:0>2}\n", .{cpu.a});
    cpu.run(8);
    std.debug.print("A=0x{X:0>2}\n", .{cpu.a});
}
