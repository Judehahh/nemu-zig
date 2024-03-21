const std = @import("std");
const config = @import("config");

pub const isa = blk: {
    if (std.mem.eql(u8, config.ISA, "riscv32")) {
        break :blk @import("riscv32.zig");
    } else if (std.mem.eql(u8, config.ISA, "loongarch32r")) {
        break :blk @import("loongarch32r.zig");
    } else {
        @compileError("ISA " ++ config.ISA ++ " is not supported");
    }
};
