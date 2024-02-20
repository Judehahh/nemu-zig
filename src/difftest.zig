const std = @import("std");
const common = @import("common.zig");
const util = @import("util.zig");
const memory = @import("memory.zig");
const cpu = @import("cpu.zig");
const isa = @import("isa/common.zig").isa;
const state = @import("state.zig");

const paddr_t = common.paddr_t;
const vaddr_t = common.vaddr_t;

const DIFFTEST_TO_DUT = false;
const DIFFTEST_TO_REF = true;

var ref_difftest_memcpy: *const fn (paddr_t, *anyopaque, usize, bool) callconv(.C) void = undefined;
var ref_difftest_regcpy: *const fn (*anyopaque, bool) callconv(.C) void = undefined;
var ref_difftest_exec: *const fn (u64) callconv(.C) void = undefined;
var ref_difftest_raise_intr: *const fn (u64) callconv(.C) void = undefined;

/// Init difftest.
pub fn init_difftest(ref_so_file: ?[]const u8, img_size: usize, port: c_int) void {
    std.debug.assert(ref_so_file != null);

    const handler = std.c.dlopen(&(std.os.toPosixPath(ref_so_file.?) catch unreachable), std.c.RTLD.LAZY);
    std.debug.assert(handler != null);

    ref_difftest_memcpy = if (std.c.dlsym(handler, "difftest_memcpy")) |sym| @ptrCast(sym) else {
        util.panic("Can't found symbol: {s}", .{"difftest_memcpy"});
    };

    const ref_difftest_init: *const fn (c_int) callconv(.C) void = if (std.c.dlsym(handler, "difftest_init")) |sym| @ptrCast(sym) else {
        util.panic("Can't found symbol: {s}", .{"difftest_init"});
    };

    ref_difftest_regcpy = if (std.c.dlsym(handler, "difftest_regcpy")) |sym| @ptrCast(sym) else {
        util.panic("Can't found symbol: {s}", .{"difftest_regcpy"});
    };

    ref_difftest_exec = if (std.c.dlsym(handler, "difftest_exec")) |sym| @ptrCast(sym) else {
        util.panic("Can't found symbol: {s}", .{"difftest_exec"});
    };

    ref_difftest_raise_intr = if (std.c.dlsym(handler, "difftest_raise_intr")) |sym| @ptrCast(sym) else {
        util.panic("Can't found symbol: {s}", .{"difftest_raise_intr"});
    };

    util.log(@src(), "Differential testing: {s}\n", .{util.ansi_fmt("ON", util.AnsiColor.fg_green, null)});
    util.log(
        @src(),
        "The result of every instruction will be compared with {?s}. This will help you a lot for debugging, but also significantly reduce the performance. If it is not necessary, you can turn it off by adding -DDIFFTEST=flase when building nemu-zig.\n",
        .{ref_so_file},
    );

    ref_difftest_init(@bitCast(port));
    ref_difftest_memcpy(memory.reset_vector, memory.guest_to_host(memory.reset_vector), img_size, DIFFTEST_TO_REF);
    ref_difftest_regcpy(&cpu.cpu, DIFFTEST_TO_REF);
}

/// Check the difference of registers between dut and ref.
fn checkregs(ref: *cpu.CPU_state, pc: vaddr_t) void {
    if (!isa.isa_difftest_checkregs(ref, pc)) {
        state.nemu_state.state = state.NEMUState.NEMU_ABORT;
        state.nemu_state.halt_pc = pc;
        isa.isa_reg_display(null);
    }
}

/// Make difftest perform one step.
pub fn difftest_step(pc: vaddr_t) void {
    var ref_r: cpu.CPU_state = undefined;

    ref_difftest_exec(1);
    ref_difftest_regcpy(&ref_r, DIFFTEST_TO_DUT);

    checkregs(&ref_r, pc);
}
