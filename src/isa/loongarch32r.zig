const std = @import("std");
const paddr = @import("../memory.zig");
const state = @import("../state.zig");
const util = @import("../util.zig");
const common = @import("../common.zig");
const memory = @import("../memory.zig");
const cpu = @import("../cpu.zig");
const config = @import("config");

const word_t = common.word_t;
const sword_t = common.sword_t;
const double_t = common.double_t;
const sdouble_t = common.sdouble_t;
const vaddr_t = common.vaddr_t;

// init
const img = [_]u8{
    0x0c, 0x00, 0x00, 0x1c, // pcaddu12i $t0,0
    0x80, 0x41, 0x80, 0x29, // st.w $zero,$t0,16
    0x84, 0x41, 0x80, 0x28, // ld.w $a0,$t0,16
    0x00, 0x00, 0x2a, 0x00, // break 0 (used as nemu_trap)
    0xef, 0xbe, 0xad, 0xde, // some data
};

fn restart() void {
    // Set the initial program counter.
    cpu.cpu.pc = paddr.reset_vector;

    // The zero register is always 0.
    cpu.cpu.gpr[0] = 0;
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

/// Read data from register.
const RegR = gpr;

/// Write data to register.
inline fn RegW(idx: usize, val: word_t) void {
    cpu.cpu.gpr[check_reg_idx(idx)] = val;
}

// Read data from memory.
const MemR = memory.vaddr_read;

/// Write data to memory.
const MemW = memory.vaddr_write;

/// Add two number and ignore the overflow.
inline fn Add(a: word_t, b: word_t) word_t {
    return @addWithOverflow(a, b)[0];
}

/// Sub two number and ignore the overflow.
inline fn Sub(a: word_t, b: word_t) word_t {
    return @subWithOverflow(a, b)[0];
}

/// Mul two word number and return double.
inline fn Mul(T: type, a: word_t, b: word_t) double_t {
    return @bitCast(std.math.mulWide(T, @bitCast(a), @bitCast(b)));
}

/// NEMU go into END.
inline fn NEMUTRAP(pc: vaddr_t, halt_ret: u32) void {
    state.set_nemu_state(state.NEMUState.NEMU_END, pc, halt_ret);
}

/// Meet an invalid instruction.
const INV = cpu.invalid_inst;

pub const InstType = enum {
    _2R,
    _3R,
    _4R,
    _2RI8,
    _2RI12,
    _2RI14,
    _2RI16,
    _1RI20,
    _1RI21,
    N, // None

    pub fn decode_operand(self: InstType, s: cpu.Decode, rd: *u5, src1: *word_t, src2: *word_t, imm: *word_t) void {
        const i = s.isa.inst.val;
        const rs1: u5 = @truncate(util.bits(i, 9, 5));
        const rs2: u5 = @truncate(util.bits(i, 14, 10));
        rd.* = @truncate(util.bits(i, 4, 0));

        switch (self) {
            ._2R => {
                src1.* = @bitCast(gpr(rs1));
                src2.* = @bitCast(gpr(rs2));
            },
            ._2RI12 => {
                src1.* = @bitCast(gpr(rs1));
                imm.* = util.sext(util.bits(i, 21, 10), 12);
            },
            ._1RI20 => {
                imm.* = util.sext(util.bits(i, 24, 5), 20);
            },
            .N => {},
            else => util.panic("Inst type {s} is not supported for now\n", .{@tagName(self)}),
        }
    }
};

pub const Instruction = enum {
    // 3R
    ADD_W,

    // 2RI12
    ADDI_W,
    ST_W,
    LD_W,

    // 1RI20
    PCADDU12I,

    // N
    BREAK,
    INV,

    pub fn exec(self: Instruction, s: *cpu.Decode, rd: u5, src1: word_t, src2: word_t, imm: word_t) void {
        switch (self) {
            // 3R
            .ADD_W => RegW(rd, Add(src1, src2)),

            // 2RI12
            .ADDI_W => RegW(rd, Add(src1, imm)),
            .ST_W => MemW(Add(src1, imm), 4, RegR(rd)),
            .LD_W => RegW(rd, MemR(Add(src1, imm), 4)),

            // 1RI20
            .PCADDU12I => RegW(rd, Add(s.pc, imm)),

            // N
            .BREAK => NEMUTRAP(s.pc, 0),
            .INV => INV(s.pc),
        }
    }
};

const InstPats = [_]cpu.InstPat{
    // 3R
    cpu.NewInstPat("00000 00000 0100000 ????? ????? ?????", ._3R, .ADD_W),

    // 2RI12
    cpu.NewInstPat("00000 01010 ???????????? ????? ?????", ._2RI12, .ADDI_W),
    cpu.NewInstPat("00101 00110 ???????????? ????? ?????", ._2RI12, .ST_W),
    cpu.NewInstPat("00101 00010 ???????????? ????? ?????", ._2RI12, .LD_W),

    // 1RI20
    cpu.NewInstPat("0001110 ???????????????????? ?????", ._1RI20, .PCADDU12I),

    // N
    cpu.NewInstPat("00000000001010100 ???????????????", .N, .BREAK),
    cpu.NewInstPat("????????????????? ???????????????", .N, .INV),
};

// ISA decode.
pub fn isa_exec_once(s: *cpu.Decode) i32 {
    s.isa.inst.val = @import("../cpu.zig").inst_fetch(&s.snpc, 4);
    return decode_exec(s);
}

fn decode_exec(s: *cpu.Decode) i32 {
    var rd: u5 = 0;
    var src1: word_t = 0;
    var src2: word_t = 0;
    var imm: word_t = 0;
    s.dnpc = s.snpc;

    inline for (InstPats) |ip| {
        if ((s.isa.inst.val & ip.mask) == ip.key) {
            ip.t.decode_operand(s.*, &rd, &src1, &src2, &imm);
            ip.i.exec(s, rd, src1, src2, imm);
            break;
        }
    }

    return 0;
}

// reg
pub const CPU_state = struct {
    gpr: [regs.len]word_t,
    pc: vaddr_t,
};

const regs = [_][]const u8{ "$0", "ra", "tp", "sp", "a0", "a1", "a2", "a3", "a4", "a5", "a6", "a7", "t0", "t1", "t2", "t3", "t4", "t5", "t6", "t7", "t8", "rs", "fp", "s0", "s1", "s2", "s3", "s4", "s5", "s6", "s7", "s8" };

inline fn check_reg_idx(idx: usize) usize {
    std.debug.assert(idx >= 0 and idx < regs.len);
    return idx;
}

inline fn gpr(idx: usize) word_t {
    return cpu.cpu.gpr[check_reg_idx(idx)];
}

inline fn reg_name(idx: usize) []const usize {
    return regs[check_reg_idx(idx)];
}

pub fn isa_reg_display(arg: ?[]const u8) void {
    if (arg == null) {
        inline for (regs, 0..) |reg, index| {
            std.debug.print("{s:10}\t0x{x}\n", .{ reg, gpr(index) });
        }
        std.debug.print("{s:10}\t0x{x:0>8}\n", .{ "pc", cpu.cpu.pc });
    } else {
        inline for (regs, 0..) |reg, index| {
            if (std.mem.eql(u8, arg.?, reg)) {
                std.debug.print("{s:10}\t0x{x}\n", .{ reg, gpr(index) });
                return;
            }
        }
        if (std.mem.eql(u8, arg.?, "pc")) {
            std.debug.print("{s:10}\t0x{x:0>8}\n", .{ "pc", cpu.cpu.pc });
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
        return cpu.cpu.pc;
    }
    return error.RegNotFound;
}
