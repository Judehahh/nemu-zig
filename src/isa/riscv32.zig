const std = @import("std");
const paddr = @import("../memory.zig");
const state = @import("../state.zig");
const util = @import("../util.zig");
const common = @import("../common.zig");
const memory = @import("../memory.zig");

const Decode = @import("../cpu.zig").Decode;
const InstPat = @import("../cpu.zig").InstPat;
const invalid_inst = @import("../cpu.zig").invalid_inst;

const word_t = common.word_t;
const vaddr_t = common.vaddr_t;

// init
const img = [_]u8{
    0x97, 0x02, 0x00, 0x00, // auipc t0,0
    0x23, 0x88, 0x02, 0x00, // sb  zero,16(t0)
    0x03, 0xc5, 0x02, 0x01, // lbu a0,16(t0)
    0x73, 0x00, 0x10, 0x00, // ebreak (used as nemu_trap)
    0xef, 0xbe, 0xad, 0xde, // deadbeef
};

pub var cpu: struct {
    gpr: [32]word_t,
    pc: common.vaddr_t,
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
    @memcpy(paddr.pmem[memory.reset_offset .. memory.reset_offset + img.len], &img);

    // Initialize this virtual computer system.
    restart();
}

// decode & exec
pub const ISADecodeInfo = struct {
    inst: union {
        val: u32,
    },
};

pub const InstType = enum {
    I,
    U,
    S,
    N, // none
};

const RegR = gpr;
inline fn RegW(idx: usize, val: word_t) void {
    cpu.gpr[check_reg_idx(idx)] = val;
}
const MemR = memory.vaddr_read;
const MemW = memory.vaddr_write;
inline fn NEMUTRAP(pc: vaddr_t, halt_ret: u32) void {
    state.set_nemu_state(state.NEMUState.NEMU_END, pc, halt_ret);
}
const INV = invalid_inst;

const InstPats = [_]InstPat{
    .{ .pattern = "??????? ????? ????? ??? ????? 00101 11", .t = .U, .f = f_auipc },
    .{ .pattern = "??????? ????? ????? 100 ????? 00000 11", .t = .I, .f = f_lbu },
    .{ .pattern = "??????? ????? ????? 000 ????? 01000 11", .t = .S, .f = f_sb },
    .{ .pattern = "0000000 00001 00000 000 00000 11100 11", .t = .N, .f = f_ebreak },
    .{ .pattern = "??????? ????? ????? ??? ????? ????? ??", .t = .N, .f = f_inv },
};

pub const f = fn (s: Decode, rd: u5, src1: word_t, src2: word_t, imm: word_t) callconv(.Inline) void;
inline fn f_auipc(s: Decode, rd: u5, src1: word_t, src2: word_t, imm: word_t) void {
    _ = src1;
    _ = src2;
    RegW(rd, s.pc + imm);
}
inline fn f_lbu(s: Decode, rd: u5, src1: word_t, src2: word_t, imm: word_t) void {
    _ = s;
    _ = src2;
    RegW(rd, MemR(src1 + imm, 1));
}
inline fn f_sb(s: Decode, rd: u5, src1: word_t, src2: word_t, imm: word_t) void {
    _ = s;
    _ = rd;
    MemW(src1 + imm, 1, src2);
}
inline fn f_ebreak(s: Decode, rd: u5, src1: word_t, src2: word_t, imm: word_t) void {
    _ = rd;
    _ = src1;
    _ = src2;
    _ = imm;
    NEMUTRAP(s.pc, RegR(10)); // sb, RegR(10) is $a0
}
inline fn f_inv(s: Decode, rd: u5, src1: word_t, src2: word_t, imm: word_t) void {
    _ = rd;
    _ = src1;
    _ = src2;
    _ = imm;
    INV(s.pc);
}

pub fn isa_exec_once(s: *Decode) i32 {
    s.isa.inst.val = @import("../cpu.zig").inst_fetch(&s.snpc, 4);
    @import("std").debug.print("fetch inst: 0x{x:0>8}\n", .{s.isa.inst.val});
    return decode_exec(s);
}

fn decode_exec(s: *Decode) i32 {
    var rd: u5 = 0;
    var src1: word_t = 0;
    var src2: word_t = 0;
    var imm: word_t = 0;
    s.dnpc = s.snpc;

    var instBuf: [32]u8 = undefined;
    _ = std.fmt.formatIntBuf(instBuf[0..], s.isa.inst.val, 2, .lower, .{ .fill = '0', .width = 32 });

    INSTPAT_END: inline for (InstPats) |ip| {
        var i: usize = 0;
        for (ip.pattern) |c| {
            switch (c) {
                '?' => i += 1,
                '1', '0' => i = if (instBuf[i] == c) i + 1 else break,
                ' ' => {},
                else => unreachable,
            }
        } else {
            decode_operand(s.*, &rd, &src1, &src2, &imm, ip.t);
            ip.f(s.*, rd, src1, src2, imm);
            break :INSTPAT_END;
        }
    }

    RegW(0, 0); // reset $zero to 0

    return 0;
}

fn decode_operand(s: Decode, rd: *u5, src1: *word_t, src2: *word_t, imm: *word_t, t: InstType) void {
    const i = s.isa.inst.val;
    const rs1: u5 = @intCast((i >> 15) & 0b11111);
    const rs2: u5 = @intCast((i >> 20) & 0b11111);
    rd.* = @intCast((i >> 7) & 0b11111);

    switch (t) {
        .I => imm.* = @as(u12, @truncate(i >> 20)),
        .U => imm.* = @as(u20, @truncate(i >> 12)) << 12,
        .S => imm.* = @as(u7, @truncate(i >> 25)) << 5 | @as(u5, @truncate((i >> 7))),
        .N => {},
    }
    src1.* = gpr(rs1);
    src2.* = gpr(rs2);
}

// reg
const regs = [_][]const u8{ "$0", "ra", "sp", "gp", "tp", "t0", "t1", "t2", "s0", "s1", "a0", "a1", "a2", "a3", "a4", "a5", "a6", "a7", "s2", "s3", "s4", "s5", "s6", "s7", "s8", "s9", "s10", "s11", "t3", "t4", "t5", "t6" };

inline fn check_reg_idx(idx: usize) usize {
    std.debug.assert(idx >= 0 and idx < 32);
    return idx;
}

inline fn gpr(idx: usize) word_t {
    return cpu.gpr[check_reg_idx(idx)];
}

inline fn reg_name(idx: usize) []const usize {
    return regs[check_reg_idx(idx)];
}

pub fn isa_reg_display(arg: ?[]const u8) void {
    if (arg == null) {
        inline for (regs, 0..) |reg, index| {
            std.debug.print("{s:4}\t0x{x}\n", .{ reg, gpr(index) });
        }
        std.debug.print("{s:4}\t0x{x:0>8}\n", .{ "pc", cpu.pc });
    } else {
        inline for (regs, 0..) |reg, index| {
            if (std.mem.eql(u8, arg.?, reg)) {
                std.debug.print("{s:4}\t0x{x}\n", .{ reg, gpr(index) });
                return;
            }
        }
        if (std.mem.eql(u8, arg.?, "pc")) {
            std.debug.print("{s:4}\t0x{x:0>8}\n", .{ "pc", cpu.pc });
            return;
        }
        std.debug.print("Unknown register '{s}'.\n", .{arg.?});
    }
}

pub fn isa_reg_name2val(name: []const u8) anyerror!word_t {
    inline for (regs, 0..) |reg, index| {
        if (std.mem.eql(u8, name, reg)) {
            return gpr(index);
        }
    }
    if (std.mem.eql(u8, name, "pc")) {
        return cpu.pc;
    }
    return error.RegNotFound;
}
