const std = @import("std");
const config = @import("config");
const memory = @import("../memory.zig");
const isa = @import("../isa/riscv32.zig");
const sdb = @import("./sdb/sdb.zig");

pub fn init_monitor() void {
    memory.init_mem();
    isa.init_isa();
    sdb.init_sdb();
    welcome();
}

fn welcome() void {
    std.debug.print("Welcome to {s}-NEMU in Zig!\n", .{config.ISA});
    std.debug.print("For help, type \"help\"\n", .{});
}
