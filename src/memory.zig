const std = @import("std");
const config = @import("config");
const util = @import("util.zig");
const common = @import("common.zig");

const word_t = @import("common.zig").word_t;
const vaddr_t = @import("common.zig").vaddr_t;
const paddr_t = @import("common.zig").paddr_t;

pub const MemError = error{
    NotAlign,
    OutOfBound,
};

pub fn MemErrorHandler(err: anyerror, addr: vaddr_t) void {
    switch (err) {
        MemError.OutOfBound => std.debug.print("Cannot access memory at address " ++ common.fmt_word ++ ".\n", .{addr}),
        MemError.NotAlign => std.debug.print("Address " ++ common.fmt_word ++ " is not aligned to 4 bytes.\n", .{addr}),
        else => std.debug.print("memory err: {}.\n", .{err}),
    }
}

pub const pmem_left = config.MBASE;
pub const pmem_right = config.MBASE + config.MSIZE - 1;
pub const reset_offset = config.PC_RESET_OFFSET;
pub const reset_vector = pmem_left + config.PC_RESET_OFFSET;

// pmem
pub var pmem: [config.MSIZE]u8 = undefined;

pub fn init_mem() void {
    @memset(&pmem, 0);
    util.log(@src(), "physical memory area [ 0x{x:0>8}, 0x{x:0>8} ].\n", .{ pmem_left, pmem_right });
}

pub fn in_pmem(addr: paddr_t) bool {
    return if (addr >= config.MBASE and (addr - config.MBASE) < config.MSIZE) true else false;
}

fn out_of_bound(addr: paddr_t) void {
    util.panic("addr = 0x{x:0>8} is out of pmem [ 0x{x:0>8}, 0x{x:0>8} ] at pc = 0x{x:0>8}.", .{ addr, pmem_left, pmem_right, @import("isa/riscv32.zig").cpu.pc });
}

inline fn pmem_read(addr: paddr_t, len: u32) u32 {
    return host_read(guest_to_host(addr), len);
}

inline fn pmem_write(addr: paddr_t, len: u32, data: word_t) void {
    host_write(guest_to_host(addr), len, data);
}

// paddr
fn paddr_read(addr: paddr_t, len: u32) u32 {
    if (in_pmem(addr)) return pmem_read(addr, len);
    out_of_bound(addr);
    unreachable;
}

fn paddr_write(addr: paddr_t, len: u32, data: word_t) void {
    if (in_pmem(addr)) return pmem_write(addr, len, data);
    out_of_bound(addr);
    unreachable;
}

// vaddr
pub fn vaddr_ifetch(addr: vaddr_t, len: u32) u32 {
    return paddr_read(addr, len);
}

pub fn vaddr_read(addr: vaddr_t, len: u32) u32 {
    return paddr_read(addr, len);
}

pub fn vaddr_write(addr: vaddr_t, len: u32, data: word_t) void {
    paddr_write(addr, len, data);
}

pub fn vaddr_read_safe(addr: vaddr_t, len: u32) !u32 {
    if (addr % 4 != 0) return MemError.NotAlign;
    if (!in_pmem(addr)) return MemError.OutOfBound;
    return paddr_read(addr, len);
}

// host <-> guest
fn guest_to_host(paddr: paddr_t) *u8 {
    return &pmem[paddr - config.MBASE];
}

fn host_to_guest(haddr: *const u8) u32 {
    return haddr - &pmem + config.MBASE;
}

// host
inline fn host_read(addr: *const u8, len: u32) word_t {
    switch (len) {
        1 => return @as(u32, @as(*const u8, @ptrCast(addr)).*),
        2 => return @as(u32, @as(*const u16, @ptrCast(@alignCast(addr))).*),
        4 => return @as(u32, @as(*const u32, @ptrCast(@alignCast(addr))).*),
        else => util.panic("host_read len wrong!", .{}),
    }
}

inline fn host_write(addr: *u8, len: u32, data: word_t) void {
    switch (len) {
        1 => @as(*u8, @ptrCast(addr)).* = @truncate(data),
        2 => @as(*u16, @ptrCast(@alignCast(addr))).* = @truncate(data),
        4 => @as(*u32, @ptrCast(@alignCast(addr))).* = data,
        else => util.panic("host_write len wrong!", .{}),
    }
}
