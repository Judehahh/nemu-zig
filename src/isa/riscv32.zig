const std = @import("std");
const paddr = @import("../memory.zig");
const state = @import("../state.zig");
const util = @import("../util.zig");
const common = @import("../common.zig");
const memory = @import("../memory.zig");
const cpu = @import("../cpu.zig");
const difftest = @import("../difftest.zig");
const config = @import("config");

const word_t = common.word_t;
const sword_t = common.sword_t;
const double_t = common.double_t;
const sdouble_t = common.sdouble_t;
const vaddr_t = common.vaddr_t;

const isDebug = false;

// init
const img = [_]u8{
    0x97, 0x02, 0x00, 0x00, // auipc t0,0
    0x23, 0x88, 0x02, 0x00, // sb  zero,16(t0)
    0x03, 0xc5, 0x02, 0x01, // lbu a0,16(t0)
    0x73, 0x00, 0x10, 0x00, // ebreak (used as nemu_trap)
    0xef, 0xbe, 0xad, 0xde, // deadbeef
};

pub const CPU_state = struct {
    gpr: [32]word_t,
    pc: common.vaddr_t,
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
    if (isDebug) {
        var i: u32 = 0;
        while (i < @intFromEnum(Instruction._len)) : (i += 1) {
            const inst: Instruction = @enumFromInt(i);
            std.debug.print("{}: {d}\n", .{ inst, InstCount[i] });
        }
    }
    state.set_nemu_state(state.NEMUState.NEMU_END, pc, halt_ret);
}

/// Meet an invalid instruction.
const INV = cpu.invalid_inst;

pub const InstType = enum {
    R,
    I,
    S,
    B,
    U,
    J,
    N, // None

    pub fn decode_operand(self: InstType, s: cpu.Decode, rd: *u5, src1: *word_t, src2: *word_t, imm: *word_t) void {
        const i = s.isa.inst.val;
        const rs1: u5 = @truncate(util.bits(i, 19, 15));
        const rs2: u5 = @truncate(util.bits(i, 24, 20));
        rd.* = @truncate(util.bits(i, 11, 7));

        switch (self) {
            .R => {},
            .I => imm.* = util.sext(util.bits(i, 31, 20), 12),
            .S => imm.* = util.sext(std.math.shl(word_t, util.bits(i, 31, 25), 5) | util.bits(i, 11, 7), 12),
            .B => imm.* = util.sext(
                std.math.shl(word_t, util.bits(i, 31, 31), 12) |
                    std.math.shl(word_t, util.bits(i, 30, 25), 5) |
                    std.math.shl(word_t, util.bits(i, 11, 8), 1) |
                    std.math.shl(word_t, util.bits(i, 7, 7), 11),
                13,
            ),
            .U => imm.* = std.math.shl(word_t, util.sext(util.bits(i, 31, 12), 20), 12),
            .J => imm.* = util.sext(
                std.math.shl(word_t, util.bits(i, 31, 31), 20) |
                    std.math.shl(word_t, util.bits(i, 30, 21), 1) |
                    std.math.shl(word_t, util.bits(i, 20, 20), 11) |
                    std.math.shl(word_t, util.bits(i, 19, 12), 12),
                21,
            ),
            .N => {},
        }
        src1.* = @bitCast(gpr(rs1));
        src2.* = @bitCast(gpr(rs2));
    }
};

var InstCount = std.mem.zeroes([@intFromEnum(Instruction._len)]u32);

pub const Instruction = enum(u32) {
    // RV32I
    LUI = 0,
    AUIPC,
    JAL,
    JALR,
    BEQ,
    BNE,
    BLT,
    BGE,
    BLTU,
    BGEU,
    LB,
    LH,
    LW,
    LBU,
    LHU,
    SB,
    SH,
    SW,
    ADDI,
    SLT,
    SLTI,
    ORI,
    ANDI,
    SLLI,
    SRLI,
    SRAI,
    SLTIU,
    XORI,
    ADD,
    SUB,
    SLL,
    SLTU,
    XOR,
    SRL,
    SRA,
    OR,
    AND,
    EBREAK,

    // RV32M
    MUL,
    MULH,
    MULHU,
    DIV,
    DIVU,
    REM,
    REMU,

    // None
    INV,
    _len,

    pub fn exec(self: Instruction, s: *cpu.Decode, rd: u5, src1: word_t, src2: word_t, imm: word_t) void {
        if (isDebug)
            InstCount[@intFromEnum(self)] += 1;
        switch (self) {
            // RV32I
            .LUI => RegW(rd, imm),
            .AUIPC => RegW(rd, Add(s.pc, imm)),
            .JAL => {
                RegW(rd, Add(s.pc, @as(word_t, 4)));
                s.dnpc = Add(s.pc, imm);
            },
            .JALR => {
                RegW(rd, Add(s.pc, @as(word_t, 4)));
                s.dnpc = Add(src1, imm);
            },
            .BEQ => {
                if (src1 == src2) s.dnpc = Add(s.pc, imm);
            },
            .BNE => {
                if (src1 != src2) s.dnpc = Add(s.pc, imm);
            },
            .BLT => {
                if (@as(sword_t, @bitCast(src1)) < @as(sword_t, @bitCast(src2)))
                    s.dnpc = Add(s.pc, imm);
            },
            .BGE => {
                if (@as(sword_t, @bitCast(src1)) >= @as(sword_t, @bitCast(src2)))
                    s.dnpc = Add(s.pc, imm);
            },
            .BLTU => {
                if (src1 < src2) s.dnpc = Add(s.pc, imm);
            },
            .BGEU => {
                if (src1 >= src2) s.dnpc = Add(s.pc, imm);
            },
            .LB => RegW(rd, util.sext(MemR(Add(src1, imm), 1), 8)),
            .LH => RegW(rd, util.sext(MemR(Add(src1, imm), 2), 16)),
            .LW => RegW(rd, MemR(Add(src1, imm), 4)),
            .LBU => RegW(rd, MemR(Add(src1, imm), 1)),
            .LHU => RegW(rd, MemR(Add(src1, imm), 2)),
            .SB => MemW(Add(src1, imm), 1, src2),
            .SH => MemW(Add(src1, imm), 2, src2),
            .SW => MemW(Add(src1, imm), 4, src2),
            .ADDI => RegW(rd, Add(src1, imm)),
            .SLTI => RegW(rd, @intFromBool(@as(sword_t, @bitCast(src1)) < imm)),
            .ORI => RegW(rd, src1 | imm),
            .ANDI => RegW(rd, src1 & imm),
            .SLLI => RegW(rd, std.math.shl(word_t, src1, imm)),
            .SRLI => RegW(rd, std.math.shr(word_t, src1, imm)),
            .SRAI => RegW(rd, @bitCast(std.math.shr(sword_t, @bitCast(src1), util.bits(imm, 4, 0)))),
            .SLTIU => RegW(rd, @intFromBool(src1 < imm)),
            .XORI => RegW(rd, src1 ^ imm),
            .ADD => RegW(rd, Add(src1, src2)),
            .SUB => RegW(rd, Sub(src1, src2)),
            .SLL => RegW(rd, std.math.shl(word_t, src1, src2 % @typeInfo(word_t).Int.bits)),
            .SLT => RegW(rd, @intFromBool(@as(sword_t, @bitCast(src1)) < @as(sword_t, @bitCast(src2)))),
            .SLTU => RegW(rd, @intFromBool(src1 < src2)),
            .XOR => RegW(rd, src1 ^ src2),
            .SRL => RegW(rd, @bitCast(std.math.shr(word_t, src1, util.bits(src2, 4, 0)))),
            .SRA => RegW(rd, @bitCast(std.math.shr(sword_t, @bitCast(src1), util.bits(src2, 4, 0)))),
            .OR => RegW(rd, src1 | src2),
            .AND => RegW(rd, src1 & src2),
            .EBREAK => {
                if (config.DIFFTEST) difftest.difftest_skip_ref();
                NEMUTRAP(s.pc, RegR(10)); // RegR(10) is $a0
            },

            // RV32M
            .MUL => RegW(rd, @truncate(Mul(sword_t, src1, src2))),
            .MULH => RegW(rd, @truncate(Mul(sword_t, src1, src2) >> @typeInfo(word_t).Int.bits)),
            .MULHU => RegW(rd, @truncate(Mul(word_t, src1, src2) >> @typeInfo(word_t).Int.bits)),
            .DIV => RegW(rd, @bitCast(@divTrunc(@as(sword_t, @bitCast(src1)), @as(sword_t, @bitCast(src2))))),
            .DIVU => RegW(rd, @divTrunc(src1, src2)),
            .REM => RegW(rd, @bitCast(@rem(@as(sword_t, @bitCast(src1)), @as(sword_t, @bitCast(src2))))),
            .REMU => RegW(rd, @rem(src1, src2)),

            // None
            .INV => INV(s.pc),
            ._len => {},
        }
    }
};

const InstPats = [_]cpu.InstPat{
    cpu.NewInstPat("??????? ????? ????? 000 ????? 00100 11", .I, .ADDI),
    cpu.NewInstPat("0000000 ????? ????? 000 ????? 01100 11", .R, .ADD),
    cpu.NewInstPat("??????? ????? ????? 010 ????? 00000 11", .I, .LW),
    cpu.NewInstPat("0000000 ????? ????? 001 ????? 00100 11", .I, .SLLI),
    cpu.NewInstPat("??????? ????? ????? 010 ????? 01000 11", .S, .SW),
    cpu.NewInstPat("??????? ????? ????? 001 ????? 11000 11", .B, .BNE),
    cpu.NewInstPat("0000001 ????? ????? 000 ????? 01100 11", .R, .MUL),
    cpu.NewInstPat("??????? ????? ????? 000 ????? 11000 11", .B, .BEQ),
    cpu.NewInstPat("??????? ????? ????? 110 ????? 11000 11", .B, .BLTU),
    cpu.NewInstPat("0100000 ????? ????? 101 ????? 00100 11", .I, .SRAI),
    cpu.NewInstPat("??????? ????? ????? 101 ????? 11000 11", .B, .BGE),
    cpu.NewInstPat("0000000 ????? ????? 111 ????? 01100 11", .R, .AND),
    cpu.NewInstPat("0000000 ????? ????? 001 ????? 01100 11", .R, .SLL),
    cpu.NewInstPat("??????? ????? ????? 111 ????? 00100 11", .I, .ANDI),
    cpu.NewInstPat("0000000 ????? ????? 101 ????? 01100 11", .R, .SRL),
    cpu.NewInstPat("??????? ????? ????? ??? ????? 11011 11", .J, .JAL),
    cpu.NewInstPat("0000000 ????? ????? 100 ????? 01100 11", .R, .XOR),
    cpu.NewInstPat("0000000 ????? ????? 110 ????? 01100 11", .R, .OR),
    cpu.NewInstPat("??????? ????? ????? 000 ????? 11001 11", .I, .JALR),
    cpu.NewInstPat("??????? ????? ????? 100 ????? 00100 11", .I, .XORI),
    cpu.NewInstPat("??????? ????? ????? ??? ????? 01101 11", .U, .LUI),
    cpu.NewInstPat("??????? ????? ????? 101 ????? 00000 11", .I, .LHU),
    cpu.NewInstPat("??????? ????? ????? 100 ????? 00000 11", .I, .LBU),
    cpu.NewInstPat("??????? ????? ????? ??? ????? 00101 11", .U, .AUIPC),
    cpu.NewInstPat("0000000 ????? ????? 101 ????? 00100 11", .I, .SRLI),
    cpu.NewInstPat("0100000 ????? ????? 000 ????? 01100 11", .R, .SUB),
    cpu.NewInstPat("??????? ????? ????? 000 ????? 01000 11", .S, .SB),
    cpu.NewInstPat("??????? ????? ????? 100 ????? 11000 11", .B, .BLT),
    cpu.NewInstPat("??????? ????? ????? 000 ????? 00000 11", .I, .LB),
    cpu.NewInstPat("??????? ????? ????? 111 ????? 11000 11", .B, .BGEU),
    cpu.NewInstPat("0000001 ????? ????? 111 ????? 01100 11", .R, .REMU),
    cpu.NewInstPat("??????? ????? ????? 001 ????? 01000 11", .S, .SH),
    cpu.NewInstPat("0000001 ????? ????? 100 ????? 01100 11", .R, .DIV),
    cpu.NewInstPat("0000001 ????? ????? 110 ????? 01100 11", .R, .REM),
    cpu.NewInstPat("??????? ????? ????? 011 ????? 00100 11", .I, .SLTIU),
    cpu.NewInstPat("0000000 ????? ????? 010 ????? 01100 11", .R, .SLT),
    cpu.NewInstPat("0000000 ????? ????? 011 ????? 01100 11", .R, .SLTU),
    cpu.NewInstPat("0000001 ????? ????? 011 ????? 01100 11", .R, .MULHU),
    cpu.NewInstPat("0000001 ????? ????? 101 ????? 01100 11", .R, .DIVU),
    cpu.NewInstPat("??????? ????? ????? 110 ????? 00100 11", .I, .ORI),
    cpu.NewInstPat("0000000 00001 00000 000 00000 11100 11", .N, .EBREAK),
    cpu.NewInstPat("??????? ????? ????? 001 ????? 00000 11", .I, .LH),
    cpu.NewInstPat("??????? ????? ????? 010 ????? 00100 11", .I, .SLTI),
    cpu.NewInstPat("0100000 ????? ????? 101 ????? 01100 11", .R, .SRA),
    cpu.NewInstPat("0000001 ????? ????? 001 ????? 01100 11", .R, .MULH),
    cpu.NewInstPat("??????? ????? ????? ??? ????? ????? ??", .N, .INV),
};

// ISA decode.
pub fn isa_exec_once(s: *cpu.Decode) i32 {
    s.isa.inst.val = @import("../cpu.zig").inst_fetch(&s.snpc, 4);
    // std.debug.print("fetch inst: 0x{x:0>8}\n", .{s.isa.inst.val});
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

    RegW(0, 0); // reset $zero to 0

    return 0;
}

// reg
const regs = [_][]const u8{ "$0", "ra", "sp", "gp", "tp", "t0", "t1", "t2", "s0", "s1", "a0", "a1", "a2", "a3", "a4", "a5", "a6", "a7", "s2", "s3", "s4", "s5", "s6", "s7", "s8", "s9", "s10", "s11", "t3", "t4", "t5", "t6" };

inline fn check_reg_idx(idx: usize) usize {
    std.debug.assert(idx >= 0 and idx < 32);
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
            std.debug.print("{s:4}\t0x{x}\n", .{ reg, gpr(index) });
        }
        std.debug.print("{s:4}\t0x{x:0>8}\n", .{ "pc", cpu.cpu.pc });
    } else {
        inline for (regs, 0..) |reg, index| {
            if (std.mem.eql(u8, arg.?, reg)) {
                std.debug.print("{s:4}\t0x{x}\n", .{ reg, gpr(index) });
                return;
            }
        }
        if (std.mem.eql(u8, arg.?, "pc")) {
            std.debug.print("{s:4}\t0x{x:0>8}\n", .{ "pc", cpu.cpu.pc });
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

// difftest
pub fn isa_difftest_checkregs(ref_r: *CPU_state, pc: vaddr_t) bool {
    var i: usize = 0;
    while (i < 32) : (i += 1) {
        if (ref_r.gpr[i] != cpu.cpu.gpr[i]) {
            util.log(
                @src(),
                "Register {s} is different at pc = " ++ common.fmt_word ++ "\nref = 0x{x:0>8}\tnemu = 0x{x:0>8}\n",
                .{ regs[i], pc, ref_r.gpr[i], cpu.cpu.gpr[i] },
            );
            return false;
        }
    }

    if (ref_r.pc != cpu.cpu.pc) {
        util.log(
            @src(),
            "Register pc is different at pc = " ++ common.fmt_word ++ "\nref = 0x{x:0>8}\tnemu = 0x{x:0>8}\n",
            .{ pc, ref_r.pc, cpu.cpu.pc },
        );
        return false;
    }

    return true;
}
