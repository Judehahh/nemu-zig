const vaddr_t = @import("types.zig").vaddr_t;

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
