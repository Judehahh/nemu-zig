const std = @import("std");

pub fn main() !void {
    for (std.os.argv) |arg| {
        std.debug.print("{s}\n", .{arg});
    }

    const monitor = @import("./monitor/monitor.zig");
    monitor.init_monitor();

    const sdb = @import("./monitor/sdb/sdb.zig");
    try sdb.sdb_mainloop();
}
