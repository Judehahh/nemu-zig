const std = @import("std");
const stdin = std.io.getStdIn().reader();
const stdout = std.io.getStdOut().writer();
const cpu = @import("../cpu.zig");
const isa = @import("../isa/riscv32.zig");
const util = @import("../util.zig");

pub fn init_sdb() void {}

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

        // match arg0 and cmd in cmd_table
        inline for (cmd_table) |cmds| {
            if (std.mem.eql(u8, cmd, cmds.name)) {
                cmds.handler(&tokens) catch return;
                break;
            }
        } else {
            try stdout.print("Unknown command '{s}.'\n", .{cmd});
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
        .name = "c",
        .description = "Continue the execution of the program",
        .handler = cmd_c,
    },
    .{
        .name = "si",
        .description = "Step one instruction exactly",
        .handler = cmd_si,
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
        try stdout.print("Unknown command {s}.\n", .{arg.?});
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

fn cmd_c(tokens: *std.mem.TokenIterator(u8, .any)) anyerror!void {
    _ = tokens;
    cpu.cpu_exec(std.math.maxInt(u64));
}

fn cmd_si(tokens: *std.mem.TokenIterator(u8, .any)) anyerror!void {
    _ = tokens;
    cpu.cpu_exec(1);
}

fn cmd_q(tokens: *std.mem.TokenIterator(u8, .any)) anyerror!void {
    _ = tokens;
    return error.Exit;
}
