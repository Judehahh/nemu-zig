const std = @import("std");
const config = @import("config");
const io = @import("io.zig");
const serial = @import("serial.zig");

pub fn init_device() void {
    io.init_map();

    if (config.HAS_SERIAL) serial.init_serial();
}
