const emulator = @import("emulator.zig");
const std = @import("std");

pub fn main() void {
    var mem = emulator.Memory.init();
    var cpu = emulator.CPU.init(&mem);

    std.debug.print("SP=0x{X}\n", .{cpu.sp});

    cpu.run(7);
}
