const vaddr_t = @import("common.zig").vaddr_t;

pub const NEMUState = enum {
    NEMU_RUNNING,
    NEMU_STOP,
    NEMU_END,
    NEMU_ABORT,
    NEMU_QUIT,
};

pub var nemu_state: struct {
    state: NEMUState,
    halt_pc: vaddr_t = undefined,
    halt_ret: u32 = undefined,
} = .{
    .state = .NEMU_STOP,
};

pub fn set_nemu_state(state: NEMUState, pc: vaddr_t, halt_ret: u32) void {
    nemu_state.state = state;
    nemu_state.halt_pc = pc;
    nemu_state.halt_ret = halt_ret;
}
