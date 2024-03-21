const std = @import("std");
const util = @import("util.zig");

// Import c for regex.
const c = @cImport({
    @cInclude("llvm_slim.h");
});

var disassembler: ?*anyopaque = null;

pub fn init_disasm(triple: [*c]const u8) void {
    c.LLVMInitializeAllTargetInfos();
    c.LLVMInitializeAllTargetMCs();
    c.LLVMInitializeAllAsmParsers();
    c.LLVMInitializeAllDisassemblers();

    if (std.mem.eql(u8, triple[0..5], "riscv")) {
        disassembler = c.LLVMCreateDisasmCPUFeatures(triple, "", "+m,+a,+c,+f,+d", null, 0, null, null);
        if (disassembler != null) return;
    } else if (std.mem.eql(u8, triple[0..11], "loongarch32")) {
        disassembler = c.LLVMCreateDisasm("loongarch32", null, 0, null, null);
        if (disassembler != null) return;
    }

    disassembler = c.LLVMCreateDisasm(triple, null, 0, null, null);
    if (disassembler == null) {
        util.panic("Can't find disasm target for {s}\n", .{triple});
    }
}

pub fn disassemble(buffer: []u8, pc: u64, inst: u32) void {
    const instBytes: [*c]u8 = @ptrFromInt(@intFromPtr(&inst));
    _ = c.LLVMDisasmInstruction(disassembler.?, instBytes, @sizeOf(u32), pc, &buffer[0], buffer.len);
}
