const std = @import("std");
const config = @import("config");
const util = @import("../util.zig");
const io = @import("io.zig");

const CH_OFFSET = 0;

var rtc_base: []u8 = undefined;

pub fn rtc_io_handler(offset: u32, len: usize, is_write: bool) void {
    _ = len;
    std.debug.assert(offset == 0 or offset == 4);
    if (!is_write and offset == 4) {
        const us: u64 = util.get_time();
        @as([*]u64, @alignCast(@ptrCast(rtc_base.ptr)))[0] = us;
    }
}

pub fn init_timer() void {
    rtc_base = io.new_space(8);
    io.add_mmio_map("rtc", config.RTC_MMIO, rtc_base, 8, rtc_io_handler);
}
