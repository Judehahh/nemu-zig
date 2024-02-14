const std = @import("std");
const memory = @import("memory.zig");
const isa = @import("isa/riscv32.zig");
const state = @import("state.zig");
const util = @import("util.zig");
const watchpoint = @import("monitor/watchpoint.zig");
const common = @import("common.zig");

const vaddr_t = @import("common.zig").vaddr_t;

// exec
pub fn cpu_exec(nstep: u64) void {
    switch (state.nemu_state.state) {
        state.NEMUState.NEMU_END, state.NEMUState.NEMU_ABORT => {
            std.debug.print("Program execution has ended. To restart the program, exit NEMU and run again.\n", .{});
            return;
        },
        else => {
            state.nemu_state.state = state.NEMUState.NEMU_RUNNING;
        },
    }
    execute(nstep);
    switch (state.nemu_state.state) {
        state.NEMUState.NEMU_RUNNING => state.nemu_state.state = state.NEMUState.NEMU_STOP,
        state.NEMUState.NEMU_END, state.NEMUState.NEMU_ABORT => {
            util.log(@src(), "nemu: hit at pc = 0x{x:0>8}.\n", .{state.nemu_state.halt_pc});
        },
        else => {},
    }
}

fn execute(nstep: u64) void {
    var s: Decode = undefined;
    for (0..nstep) |i| {
        _ = i;
        exec_once(&s, isa.cpu.pc);
        trace_and_difftest(&s);
        if (state.nemu_state.state != state.NEMUState.NEMU_RUNNING) break;
    }
}

fn exec_once(s: *Decode, pc: vaddr_t) void {
    s.pc = pc;
    s.snpc = pc;
    _ = isa.isa_exec_once(s);
    isa.cpu.pc = s.dnpc;
}

// decode
pub const Decode = struct {
    pc: vaddr_t,
    snpc: vaddr_t, // static next pc
    dnpc: vaddr_t, // dynamic next pc
    isa: isa.ISADecodeInfo,
};

pub const InstPat = struct {
    pattern: []const u8,
    t: isa.InstType,
    f: isa.f,
};

pub fn invalid_inst(thispc: vaddr_t) void {
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
pub fn inst_fetch(snpc: *vaddr_t, len: u32) u32 {
    const inst: u32 = memory.vaddr_ifetch(snpc.*, len);
    snpc.* += len;
    return inst;
}

// trace & difftest
fn trace_and_difftest(_this: *Decode) void {
    watchpoint.check_wp(_this.pc) catch |err| watchpoint.WpErrorHandler(err);
}
