const std = @import("std");
const monitor = @import("monitor/monitor.zig");
const sdb = @import("monitor/sdb.zig");

pub fn main() !void {
    for (std.os.argv) |arg| {
        std.debug.print("{s}\n", .{arg});
    }

    monitor.init_monitor();

    try sdb.sdb_mainloop();
}
