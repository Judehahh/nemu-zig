const std = @import("std");
const config = @import("config");
const util = @import("../util.zig");
const io = @import("io.zig");

const CH_OFFSET = 0;

var serial_base: []u8 = undefined;

pub fn serial_io_handler(offset: u32, len: usize, is_write: bool) void {
    std.debug.assert(len == 1);
    switch (offset) {
        CH_OFFSET => {
            if (is_write)
                std.io.getStdErr().writer().writeByte(serial_base[0]) catch {
                    util.panic("Serial: writeByte failed", .{});
                }
            else
                util.panic("Serial: do not support read", .{});
        },
        else => {
            util.panic("Serial: do not support offset = {d}", .{offset});
        },
    }
}

pub fn init_serial() void {
    serial_base = io.new_space(8);
    io.add_mmio_map("serial", config.SERIAL_MMIO, serial_base, 8, serial_io_handler);
}
