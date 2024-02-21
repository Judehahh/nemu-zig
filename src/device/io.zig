const std = @import("std");
const common = @import("../common.zig");
const memory = @import("../memory.zig");
const difftest = @import("../difftest.zig");
const util = @import("../util.zig");
const cpu = @import("../cpu.zig");

const word_t = common.word_t;
const paddr_t = common.paddr_t;

const io_callback_t = *const fn (u32, usize, bool) void;

const IOError = error{
    MapNotFound,
};

const IOMap = struct {
    name: []const u8,
    low: paddr_t,
    high: paddr_t,
    space: []u8, // slice of space
    callback: ?io_callback_t, // callback function, can be null
};

// map start
const page_shift = 12;
const page_size = 1 << page_shift;
const page_mask: usize = (page_size - 1);

const max_io_space = 2 * 1024 * 1024;
var io_space: [max_io_space]u8 = undefined;
var io_space_top: usize = 0;

inline fn map_insice(map: IOMap, addr: paddr_t) bool {
    return (addr >= map.low and addr <= map.high);
}

inline fn find_mapid_by_addr(size: usize, addr: paddr_t) IOError!usize {
    var i: usize = 0;
    while (i < size) : (i += 1) {
        if (map_insice(maps[i], addr)) {
            difftest.difftest_skip_ref();
            return i;
        }
    }
    return IOError.MapNotFound;
}

pub fn init_map() void {}

pub fn in_mmio(addr: paddr_t) bool {
    _ = find_mapid_by_addr(nr_map, addr) catch return false;
    return true;
}

pub fn new_space(size: usize) []u8 {
    const top_save = io_space_top;
    const aligned_size = (size + (page_size - 1)) & ~page_mask; // page aligned
    io_space_top += aligned_size;
    std.debug.assert(io_space_top < max_io_space);
    return io_space[top_save..io_space_top];
}

fn check_bound(map: IOMap, addr: paddr_t) void {
    if (addr <= map.high and addr >= map.high) {
        util.panic(
            "address" ++
                common.fmt_word ++
                ") is out of bound {s} [" ++
                common.fmt_word ++ ", " ++ common.fmt_word ++
                "] at pc = " ++ common.fmt_word,
            .{ addr, map.name, map.low, map.high, cpu.cpu.pc },
        );
    }
}

fn invoke_callback(callback: ?io_callback_t, offset: paddr_t, len: usize, is_write: bool) void {
    if (callback != null) {
        callback.?(offset, len, is_write);
    }
}

fn map_read(addr: paddr_t, len: usize, map: IOMap) word_t {
    std.debug.assert(len >= 1 and len <= 8);
    check_bound(map, addr);
    const offset: paddr_t = addr - map.low;
    invoke_callback(map.callback, offset, len, false); // prepare data to read
    const ret: word_t = memory.host_read(&map.space[offset], len);
    return ret;
}

fn map_write(addr: paddr_t, len: usize, data: word_t, map: IOMap) void {
    std.debug.assert(len >= 1 and len <= 8);
    check_bound(map, addr);
    const offset: paddr_t = addr - map.low;
    memory.host_write(&map.space[offset], len, data);
    invoke_callback(map.callback, offset, len, true);
}
// map end

// mmio start
const max_maps = 16;
var maps: [max_maps]IOMap = undefined;
var nr_map: usize = 0;

fn fetch_mmio_map(addr: paddr_t) IOMap {
    const mapid = find_mapid_by_addr(nr_map, addr) catch {
        util.panic(
            "find mapid for address (" ++ common.fmt_word ++ ") failed at pc = " ++ common.fmt_word,
            .{ addr, cpu.cpu.pc },
        );
    };
    return maps[mapid];
}

fn report_mmio_overlap(name1: []const u8, l1: paddr_t, r1: paddr_t, name2: []const u8, l2: paddr_t, r2: paddr_t) void {
    util.panic(
        "MMIO region {s}@[" ++ common.fmt_word ++ ", " ++ common.fmt_word ++ "] is overlapped " ++
            "with {s}@[" ++ common.fmt_word ++ ", " ++ common.fmt_word ++ "]",
        .{ name1, l1, r1, name2, l2, r2 },
    );
}

// device interface
pub fn add_mmio_map(name: []const u8, addr: paddr_t, space: []u8, len: usize, callback: io_callback_t) void {
    std.debug.assert(nr_map < max_maps);
    const left: paddr_t = addr;
    const right: paddr_t = addr + @as(paddr_t, @truncate(len)) - 1;
    if (memory.in_pmem(left) or memory.in_pmem(right)) {
        report_mmio_overlap(name, left, right, "pmem", memory.pmem_left, memory.pmem_right);
    }
    for (0..nr_map) |i| {
        if (left <= maps[i].high and right >= maps[i].low) {
            report_mmio_overlap(name, left, right, maps[i].name, maps[i].low, maps[i].high);
        }
    }

    maps[nr_map] = .{
        .name = name,
        .low = left,
        .high = right,
        .space = space,
        .callback = callback,
    };
    util.log(
        @src(),
        "Add mmio map {s} at [" ++
            common.fmt_word ++ ", " ++ common.fmt_word ++ "]\n",
        .{ maps[nr_map].name, maps[nr_map].low, maps[nr_map].high },
    );

    nr_map += 1;
}

// bus interface
pub fn mmio_read(addr: paddr_t, len: usize) word_t {
    return map_read(addr, len, fetch_mmio_map(addr));
}

pub fn mmio_write(addr: paddr_t, len: usize, data: word_t) void {
    return map_write(addr, len, data, fetch_mmio_map(addr));
}
// mmio end
