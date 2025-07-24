const std = @import("std");

const emulator = @import("emulator.zig");
const CPU = emulator.CPU;
const Memory = emulator.Memory;
const Opcode = CPU.Opcode;

pub fn main() void {
    var mem = emulator.Memory.init();

    mem.write(CPU.RESET_VECTOR + 0, 0x00);
    mem.write(CPU.RESET_VECTOR + 1, 0x30);
    mem.write(0x3000, @intFromEnum(Opcode.LDA_IDY));
    mem.write(0x3001, 0xF0);
    mem.write(0x00F0, 0xFF);
    mem.write(0x00F1, 0x00);
    mem.write(0x0100, 0x44);

    var cpu = emulator.CPU.init(&mem);

    cpu.y = 0x01;

    std.debug.print("A=0x{X:0>2}\n", .{cpu.a});
    cpu.run(13);
    std.debug.print("A=0x{X:0>2}\n", .{cpu.a});
}
