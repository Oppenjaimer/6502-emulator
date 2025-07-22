const emulator = @import("emulator.zig");
const std = @import("std");

pub fn main() void {
    var mem = emulator.Memory.init();

    mem.write(0xFFFC, 0x00);
    mem.write(0xFFFD, 0x30);
    mem.write(0x3000, 0xA1);

    var cpu = emulator.CPU.init(&mem);

    std.debug.print("PC=0x{X}, SP=0x{X}\n", .{cpu.pc, cpu.sp});

    cpu.run(11);
}
