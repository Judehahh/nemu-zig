const paddr = @import("../memory.zig");
const Decode = @import("../cpu.zig").Decode;
const state = @import("../utils/state.zig");

pub const ISADecodeInfo = struct {
    inst: union {
        val: u32,
    },
};

const img = [_]u8{
    0x97, 0x02, 0x00, 0x00, // auipc t0,0
    0x23, 0x88, 0x02, 0x00, // sb  zero,16(t0)
    0x03, 0xc5, 0x02, 0x01, // lbu a0,16(t0)
    0x73, 0x00, 0x10, 0x00, // ebreak (used as nemu_trap)
    0xef, 0xbe, 0xad, 0xde, // deadbeef
};

pub var cpu: struct {
    gpr: [32]u32,
    pc: u32,
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
    @memcpy(paddr.pmem[0..img.len], &img);

    // Initialize this virtual computer system.
    restart();
}

pub fn isa_exec_once(s: *Decode) i32 {
    s.*.isa.inst.val = @import("../cpu.zig").inst_fetch(&s.*.snpc, 4);
    @import("std").debug.print("fetch inst: 0x{x:0>8}\n", .{s.*.isa.inst.val});
    return decode_exec(s);
}

fn decode_exec(s: *Decode) i32 {
    s.*.dnpc = s.*.snpc;
    switch (s.*.isa.inst.val) {
        0x00100073 => {
            state.nemu_state.state = state.NEMUState.NEMU_END;
            state.nemu_state.halt_pc = s.*.pc;
        },
        else => {},
    }
    return 0;
}
