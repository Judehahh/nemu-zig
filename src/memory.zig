const std = @import("std");
const config = @import("config");
const util = @import("util.zig");

const word_t = @import("types.zig").word_t;
const vaddr_t = @import("types.zig").vaddr_t;
const paddr_t = @import("types.zig").paddr_t;

pub const pmem_left = config.MBASE;
pub const pmem_right = config.MBASE + config.MSIZE - 1;
pub const reset_vector = pmem_left + config.PC_RESET_OFFSET;

// pmem
pub var pmem: [config.MSIZE]u8 = undefined;

pub fn init_mem() void {
    @memset(&pmem, 0);
    util.log(@src(), "physical memory area [ 0x{x:0>8}, 0x{x:0>8} ].\n", .{ pmem_left, pmem_right });
}

fn in_pmem(addr: paddr_t) bool {
    return addr - config.MBASE < config.MSIZE;
}

fn out_of_bound(addr: paddr_t) void {
    std.debug.panic("addr = 0x{x:0>8} if out of pmem [ 0x{x:0>8}, 0x{x:0>8} ] at pc = 0x{x:0>8}.", .{ addr, pmem_left, pmem_right, @import("isa/riscv32.zig").cpu.pc });
}

fn pmem_read(addr: paddr_t, len: u32) u32 {
    return host_read(guest_to_host(addr), len);
}

fn pmem_write(addr: paddr_t, len: u32, data: word_t) void {
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

// host <-> guest
fn guest_to_host(paddr: paddr_t) *const u8 {
    return @as(*const u8, &pmem[paddr - config.MBASE]);
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
        else => std.debug.panic("host_read len wrong!", .{}),
    }
}

inline fn host_write(addr: *const u8, len: u32, data: word_t) void {
    switch (len) {
        1 => @as(*const u8, @ptrCast(addr)).* = data,
        2 => @as(*const u16, @ptrCast(@alignCast(addr))).* = data,
        4 => @as(*const u32, @ptrCast(@alignCast(addr))).* = data,
        else => std.debug.panic("host_write len wrong!", .{}),
    }
}
