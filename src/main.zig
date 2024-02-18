const std = @import("std");
const monitor = @import("monitor/monitor.zig");
const sdb = @import("monitor/sdb.zig");
const state = @import("state.zig");

pub fn main() !void {
    monitor.init_monitor();
    defer monitor.deinit_monitor();

    try sdb.sdb_mainloop();

    try state.is_exit_status_bad();
}
