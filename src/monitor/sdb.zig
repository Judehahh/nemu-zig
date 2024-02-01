const std = @import("std");
const stdin = std.io.getStdIn().reader();
const stdout = std.io.getStdOut().writer();
const cpu = @import("../cpu.zig");
const isa = @import("../isa/riscv32.zig");
const util = @import("../util.zig");
const common = @import("../common.zig");
const memory = @import("../memory.zig");
const expr = @import("expr.zig");

pub fn init_sdb() void {
    expr.init_regex();
}

pub fn deinit_sdb() void {
    expr.deinit_regex();
}

pub fn sdb_mainloop() !void {
    while (true) {
        const max_input = 1024;

        // Prompt.
        try stdout.print("(nemu) ", .{});

        // Read STDIN into buffer.
        var input_buffer: [max_input]u8 = undefined;
        const input_str = (try stdin.readUntilDelimiterOrEof(input_buffer[0..], '\n')) orelse {
            // No input, probably CTRL-d (EOF). Print a newline and exit!
            try stdout.print("\n", .{});
            return;
        };

        // Don't do anything for zero-length input (user just hit Enter).
        if (input_str.len == 0) continue;

        // The command and arguments are null-terminated strings. These arrays are
        // storage for the strings and pointers to those strings.
        var cmd: []const u8 = undefined;

        // Split by space. Turn spaces and the final LF into null bytes.
        var tokens = std.mem.tokenize(u8, input_str, " \t\r\n");

        // All blank or hava a cmd.
        cmd = while (tokens.next()) |token| {
            if (token.len >= 1)
                break token;
        } else continue;

        // Match cmd in cmd_table.
        inline for (cmd_table) |cmds| {
            if (std.mem.eql(u8, cmd, cmds.name)) {
                cmds.handler(&tokens) catch |err| {
                    if (err == error.Exit) return;
                    return err;
                };
                break;
            }
        } else {
            try stdout.print("Unknown command '{s}'.\n", .{cmd});
        }
    }
}

const cmd_table = [_]struct {
    name: []const u8,
    description: []const u8,
    handler: fn (*std.mem.TokenIterator(u8, .any)) anyerror!void,
}{
    .{
        .name = "help",
        .description = "Display information about all supported commands",
        .handler = cmd_help,
    },
    .{
        .name = "info",
        .description = "Showing things about the program being debugged",
        .handler = cmd_info,
    },
    .{
        .name = "si",
        .description = "Step one instruction exactly",
        .handler = cmd_si,
    },
    .{
        .name = "c",
        .description = "Continue the execution of the program",
        .handler = cmd_c,
    },
    .{
        .name = "x",
        .description = "Examine memory",
        .handler = cmd_x,
    },
    .{
        .name = "p",
        .description = "Print value of expression EXP",
        .handler = cmd_p,
    },
    .{
        .name = "q",
        .description = "Exit NEMU",
        .handler = cmd_q,
    },
    // TODO: Add more commands
};

fn cmd_help(tokens: *std.mem.TokenIterator(u8, .any)) anyerror!void {
    const arg = tokens.*.next() orelse null;

    if (arg == null) {
        inline for (cmd_table) |cmd| {
            try stdout.print("{s} -- {s}.\n", .{ cmd.name, cmd.description });
        }
    } else {
        inline for (cmd_table) |cmd| {
            if (std.mem.eql(u8, arg.?, cmd.name)) {
                try stdout.print("{s} -- {s}.\n", .{ cmd.name, cmd.description });
                return;
            }
        }
        try stdout.print("Unknown command '{s}'.\n", .{arg.?});
    }
}

fn cmd_info(tokens: *std.mem.TokenIterator(u8, .any)) anyerror!void {
    const arg1 = tokens.*.next() orelse null;
    const arg2 = tokens.*.next() orelse null;

    if (arg1 == null) {
        try stdout.print("Usage: info SUBCMD.\n", .{});
        return;
    }
    if (std.mem.eql(u8, arg1.?, "r")) {
        isa.isa_reg_display(arg2);
    } else {
        try stdout.print("Undefined info command: {s}.\n", .{arg1.?});
    }
}

fn cmd_si(tokens: *std.mem.TokenIterator(u8, .any)) anyerror!void {
    const arg = tokens.*.next() orelse null;

    if (arg == null) {
        cpu.cpu_exec(1);
    } else {
        const nstep = std.fmt.parseInt(u64, arg.?, 10) catch {
            try stdout.print("Usage: si [N].\n", .{});
            return;
        };
        cpu.cpu_exec(nstep);
    }
}

fn cmd_c(tokens: *std.mem.TokenIterator(u8, .any)) anyerror!void {
    _ = tokens;
    cpu.cpu_exec(std.math.maxInt(u64));
}

fn cmd_x(tokens: *std.mem.TokenIterator(u8, .any)) anyerror!void {
    const arg1 = tokens.*.next() orelse null;
    const arg2 = tokens.*.next() orelse null; // TODO: use expr() to get arg2 from a expression.

    if (arg1 == null or arg2 == null) {
        try stdout.print("Usage: x N ADDRESS.\n", .{});
        return;
    }

    const n = std.fmt.parseInt(u64, arg1.?, 10) catch {
        try stdout.print("Usage: x N ADDRESS.\n", .{});
        return;
    };

    var addr = if (arg2.?[0] == '$') isa.isa_reg_name2val(arg2.?[1..]) catch {
        try stdout.print("Unknown register '{s}'.\n", .{arg2.?[1..]});
        return;
    } else std.fmt.parseInt(common.vaddr_t, arg2.?, 16) catch {
        try stdout.print("Usage: x N ADDRESS.\n", .{});
        return;
    };

    for (0..n) |i| {
        if (i % 4 == 0) {
            try stdout.print(util.ansi_fmt(common.fmt_word, util.AnsiColor.fg_cyan, null) ++ ":\t", .{addr});
        }
        if (!memory.in_pmem(addr)) {
            try stdout.print("Cannot access memory at address " ++ common.fmt_word, .{addr});
            break;
        }
        try stdout.print("0x{x:0>8} ", .{memory.vaddr_read(addr, 4)});
        addr += 4;
        if (i % 4 == 3) {
            try stdout.print("\n", .{});
        }
    }
    try stdout.print("\n", .{});
}

fn cmd_p(tokens: *std.mem.TokenIterator(u8, .any)) anyerror!void {
    var args: [512]u8 = .{0} ** 512;
    var i: usize = 0;

    while (tokens.next()) |token| {
        std.mem.copyForwards(u8, @as([]u8, @ptrCast(args[i..])), token);
        i += token.len + 1;
        args[i - 1] = ' ';
    }

    const r: common.word_t = expr.expr(args[0..]) catch |err| {
        // try stdout.print("Bad expression\n", .{});
        try stdout.print("expr err: {}.\n", .{err});
        return;
    };
    try stdout.print("value of expression: {d}.\n", .{r});
}

fn cmd_q(tokens: *std.mem.TokenIterator(u8, .any)) anyerror!void {
    _ = tokens;
    return error.Exit;
}
