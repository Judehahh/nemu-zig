const std = @import("std");
const config = @import("config");
const memory = @import("../memory.zig");
const isa = @import("../isa/riscv32.zig");
const sdb = @import("sdb.zig");
const util = @import("../util.zig");

pub fn init_monitor() void {
    memory.init_mem();
    isa.init_isa();
    sdb.init_sdb();
    welcome();
}

fn welcome() void {
    std.debug.print("Welcome to {s}-NEMU in Zig!\n", .{util.ansi_fmt(config.ISA, util.ansi_color.fg_yellow, util.ansi_color.bg_red)});
    std.debug.print("For help, type \"help\".\n", .{});
}
