const std = @import("std");
const memory = @import("memory.zig");
const isa = @import("isa/riscv32.zig");
const state = @import("utils/state.zig");

// cpu-exec
pub fn cpu_exec(nstep: u64) void {
    switch (state.nemu_state.state) {
        state.NEMUState.NEMU_END, state.NEMUState.NEMU_ABORT => {
            std.debug.print("Program execution has ended. To restart the program, exit NEMU and run again.\n", .{});
            return;
        },
        else => {
            state.nemu_state.state = state.NEMUState.NEMU_RUNNING;
            std.debug.print("Update nemu_state.\n", .{});
        },
    }
    execute(nstep);
    switch (state.nemu_state.state) {
        state.NEMUState.NEMU_RUNNING => state.nemu_state.state = state.NEMUState.NEMU_STOP,
        state.NEMUState.NEMU_END, state.NEMUState.NEMU_ABORT => {
            std.log.info("nemu: hit at pc = 0x{x:0>8}", .{state.nemu_state.halt_pc});
        },
        else => {},
    }
}

fn execute(nstep: u64) void {
    var s: Decode = undefined;
    for (0..nstep) |i| {
        _ = i;
        exec_once(&s, isa.cpu.pc);
        if (state.nemu_state.state != state.NEMUState.NEMU_RUNNING) break;
    }
}

fn exec_once(s: *Decode, pc: u32) void {
    s.*.pc = pc;
    s.*.snpc = pc;
    _ = isa.isa_exec_once(s);
    isa.cpu.pc = s.*.dnpc;
}

// decode
pub const Decode = struct {
    pc: u32,
    snpc: u32, // static next pc
    dnpc: u32, // dynamic next pc
    isa: isa.ISADecodeInfo,
};

// ifetch
pub fn inst_fetch(snpc: *u32, len: u8) u32 {
    const inst: u32 = memory.vaddr_ifetch(snpc.*, len);
    snpc.* += len;
    return inst;
}
