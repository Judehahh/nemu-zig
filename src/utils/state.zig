pub const NEMUState = enum {
    NEMU_RUNNING,
    NEMU_STOP,
    NEMU_END,
    NEMU_ABORT,
    NEMU_QUIT,
};

pub var nemu_state: struct {
    state: NEMUState,
    halt_pc: u32 = undefined,
    halt_ret: u32 = undefined,
} = .{
    .state = .NEMU_STOP,
};
