const std = @import("std");
const paddr = @import("../memory.zig");
const Decode = @import("../cpu.zig").Decode;
const state = @import("../state.zig");
const util = @import("../util.zig");
const types = @import("../types.zig");

// init
const img = [_]u8{
    0x97, 0x02, 0x00, 0x00, // auipc t0,0
    0x23, 0x88, 0x02, 0x00, // sb  zero,16(t0)
    0x03, 0xc5, 0x02, 0x01, // lbu a0,16(t0)
    0x73, 0x00, 0x10, 0x00, // ebreak (used as nemu_trap)
    0xef, 0xbe, 0xad, 0xde, // deadbeef
};

pub var cpu: struct {
    gpr: [32]types.word_t,
    pc: types.vaddr_t,
} = .{
    .gpr = undefined,
    .pc = undefined,
};

fn restart() void {
    // Set the initial program counter.
    cpu.pc = paddr.reset_vector;

    // The zero register is always 0.
    cpu.gpr[0] = 0;
}

pub fn init_isa() void {
    // Load built-in image.
    @memcpy(paddr.pmem[0..img.len], &img);

    // Initialize this virtual computer system.
    restart();
}

// decode & exec
pub const ISADecodeInfo = struct {
    inst: union {
        val: u32,
    },
};

pub fn isa_exec_once(s: *Decode) i32 {
    s.*.isa.inst.val = @import("../cpu.zig").inst_fetch(&s.*.snpc, 4);
    @import("std").debug.print("fetch inst: 0x{x:0>8}\n", .{s.*.isa.inst.val});
    return decode_exec(s);
}

fn decode_exec(s: *Decode) i32 {
    s.*.dnpc = s.*.snpc;
    switch (s.*.isa.inst.val) {
        0x00100073 => {
            state.nemu_state.state = state.NEMUState.NEMU_END;
            state.nemu_state.halt_pc = s.*.pc;
        },
        else => {},
    }
    return 0;
}

// reg
const regs = [_][]const u8{ "$0", "ra", "sp", "gp", "tp", "t0", "t1", "t2", "s0", "s1", "a0", "a1", "a2", "a3", "a4", "a5", "a6", "a7", "s2", "s3", "s4", "s5", "s6", "s7", "s8", "s9", "s10", "s11", "t3", "t4", "t5", "t6" };

pub fn isa_reg_display(arg: ?[]const u8) void {
    for (regs, 0..) |reg, index| {
        if (arg == null or std.mem.eql(u8, arg.?, reg))
            std.debug.print("{s:4}\t {d}\n", .{ reg, cpu.gpr[index] });
    }
    if (arg == null or std.mem.eql(u8, arg.?, "pc"))
        std.debug.print("{s:4}\t 0x{x:0>8}\n", .{ "pc", cpu.pc });
}
