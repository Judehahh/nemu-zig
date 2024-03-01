const std = @import("std");
const memory = @import("memory.zig");
const isa = @import("isa/common.zig").isa;
const state = @import("state.zig");
const util = @import("util.zig");
const watchpoint = @import("monitor/watchpoint.zig");
const common = @import("common.zig");
const config = @import("config");
const disasm = @import("disasm.zig");
const difftest = @import("difftest.zig");

const vaddr_t = common.vaddr_t;

const max_inst_to_print = 10;
pub var g_print_step: bool = false;

pub const CPU_state = isa.CPU_state;
pub var cpu: CPU_state = undefined;

var g_nr_guest_inst: usize = 0;
var g_timer: u64 = 0; // unit: us

// exec
pub fn cpu_exec(nstep: u64) void {
    g_print_step = (nstep < max_inst_to_print);

    switch (state.nemu_state.state) {
        state.NEMUState.NEMU_END, state.NEMUState.NEMU_ABORT => {
            std.debug.print("Program execution has ended. To restart the program, exit NEMU and run again.\n", .{});
            return;
        },
        else => {
            state.nemu_state.state = state.NEMUState.NEMU_RUNNING;
        },
    }

    const timer_start = util.get_time();

    execute(nstep);

    const timer_end = util.get_time();
    g_timer += timer_end - timer_start;

    switch (state.nemu_state.state) {
        state.NEMUState.NEMU_RUNNING => state.nemu_state.state = state.NEMUState.NEMU_STOP,
        state.NEMUState.NEMU_END, state.NEMUState.NEMU_ABORT => {
            util.log(@src(), "nemu: {s} at pc = " ++ common.fmt_word ++ ".\n", .{
                if (state.nemu_state.state == state.NEMUState.NEMU_ABORT)
                    util.ansi_fmt("ABORT", util.AnsiColor.fg_red, null)
                else if (state.nemu_state.halt_ret == 0)
                    util.ansi_fmt("HIT GOOD TRAP", util.AnsiColor.fg_green, null)
                else
                    util.ansi_fmt("HIT BAD TRAP", util.AnsiColor.fg_red, null),
                state.nemu_state.halt_pc,
            });
            statistic();
        },
        else => {},
    }
}

fn execute(nstep: u64) void {
    var s: Decode = undefined;
    for (0..nstep) |i| {
        _ = i;
        exec_once(&s, cpu.pc);
        g_nr_guest_inst += 1;
        trace_and_difftest(&s);
        if (state.nemu_state.state != state.NEMUState.NEMU_RUNNING) break;
    }
}

fn exec_once(s: *Decode, pc: vaddr_t) void {
    s.pc = pc;
    s.snpc = pc;
    _ = isa.isa_exec_once(s);
    cpu.pc = s.dnpc;

    if (config.ITRACE) {
        var str_len: usize = 0;

        var slice = std.fmt.bufPrint(&s.logbuf, "0x{x:0>8}:", .{s.pc}) catch unreachable;
        str_len += slice.len;

        const ilen: usize = s.snpc - s.pc;
        const inst = @as([*]u8, @ptrCast(@constCast(&[_]u32{s.isa.inst.val})));

        var i: usize = ilen;
        while (i > 0) : (i -= 1) {
            slice = std.fmt.bufPrint(s.logbuf[str_len..], " {x:0>2}", .{inst[i - 1]}) catch unreachable;
            str_len += slice.len;
        }

        const ilen_max: usize = 4;
        const ov = @subWithOverflow(ilen_max, ilen);
        var space_len: usize = if (ov[1] != 0) 0 else ov[0];
        space_len = space_len * 3 + 1;
        @memset(s.logbuf[str_len .. str_len + space_len], ' ');
        str_len += space_len;

        disasm.disassemble(s.logbuf[str_len..], s.pc, s.isa.inst.val);
    }
}

// decode
pub const Decode = struct {
    pc: vaddr_t,
    snpc: vaddr_t, // static next pc
    dnpc: vaddr_t, // dynamic next pc
    isa: isa.ISADecodeInfo,
    logbuf: [128]u8,
};

pub const InstPat = struct {
    t: isa.InstType,
    i: isa.Instruction,
    mask: u32,
    key: u32,
};

pub fn NewInstPat(pattern: []const u8, t: isa.InstType, i: isa.Instruction) InstPat {
    @setEvalBranchQuota(5000);

    var mask: u32 = 0;
    var key: u32 = 0;
    var index: usize = pattern.len;
    var bit: usize = 0;

    while (index > 0) : ({
        index -= 1;
        bit += 1;
    }) {
        switch (pattern[index - 1]) {
            '?' => {},
            '0', '1' => {
                mask |= std.math.shl(u32, 1, bit);
                key |= std.math.shl(u32, pattern[index - 1] - '0', bit);
            },
            ' ' => bit -= 1,
            else => unreachable,
        }
    }

    return .{
        .t = t,
        .i = i,
        .mask = mask,
        .key = key,
    };
}

pub fn invalid_inst(thispc: vaddr_t) void {
    g_print_step = true;

    var temp: [2]u32 = undefined;
    var pc: vaddr_t = thispc;
    temp[0] = inst_fetch(&pc, 4);
    temp[1] = inst_fetch(&pc, 4);

    const p = @as([*]u8, @ptrCast(&temp));
    std.debug.print("invalid opcode(PC = " ++ common.fmt_word ++ "):\n", .{thispc});
    std.debug.print(
        "\t{x:0>2} {x:0>2} {x:0>2} {x:0>2} {x:0>2} {x:0>2} {x:0>2} {x:0>2} ...\n",
        .{ p[0], p[1], p[2], p[3], p[4], p[5], p[6], p[7] },
    );
    std.debug.print("\t{x:0>8} {x:0>8}...\n", .{ temp[0], temp[1] });

    state.set_nemu_state(state.NEMUState.NEMU_ABORT, thispc, 0xffffffff);
}

// ifetch
pub fn inst_fetch(snpc: *vaddr_t, len: usize) u32 {
    const inst: u32 = memory.vaddr_ifetch(snpc.*, len);
    snpc.* += @truncate(len);
    return inst;
}

// trace & difftest
fn trace_and_difftest(_this: *Decode) void {
    if (config.DIFFTEST) {
        difftest.difftest_step(_this.pc);
    }
    if (g_print_step and config.ITRACE) {
        util.log_write("{s}\n", .{std.mem.sliceTo(&_this.logbuf, 0)});
    }
    watchpoint.check_wp(_this.pc) catch |err| watchpoint.WpErrorHandler(err);
}

fn statistic() void {
    util.log(@src(), "host time spent = {d} us\n", .{g_timer});
    util.log(@src(), "total guest instructions = {d}\n", .{g_nr_guest_inst});
    if (g_timer > 0)
        util.log(@src(), "simulation frequency = {d} inst/s\n", .{g_nr_guest_inst * 1000000 / g_timer})
    else
        util.log(@src(), "Finish running in less than 1 us and can not calculate the simulation frequency\n", .{});
}
