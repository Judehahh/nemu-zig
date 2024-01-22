const std = @import("std");
const stdin = std.io.getStdIn().reader();
const stdout = std.io.getStdOut().writer();
const cpu = @import("../../cpu.zig");

pub fn init_sdb() void {}

// Reference: https://github.com/ratfactor/zigish
pub fn sdb_mainloop() !void {
    while (true) {
        const max_input = 1024;

        // Prompt
        try stdout.print("(nemu) ", .{});

        // Read STDIN into buffer
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
        var cmd: []u8 = undefined;

        // Split by space. Turn spaces and the final LF into null bytes
        var i: usize = 0;
        var ofs: usize = 0;
        while (i <= input_str.len) : (i += 1) {
            if ((input_buffer[i] == ' ' or input_buffer[i] == '\n' or input_buffer[i] == '\t')) {
                if (i != ofs) {
                    input_buffer[i] = 0; // turn space or line feed into null byte as sentinel
                    cmd = input_buffer[ofs..i :0];
                    break;
                }
                ofs = i + 1;
            }
        }

        // All blank
        if (i > input_str.len) continue;

        const args = input_buffer[i..];

        // match arg0 and cmd in cmd_table
        inline for (cmd_table) |cmds| {
            if (std.mem.eql(u8, cmd, cmds.name)) {
                cmds.handler(args) catch return;
                break;
            }
        } else {
            try stdout.print("Unknown command '{s}'\n", .{cmd});
        }
    }
}

const cmd_table = [_]struct {
    name: []const u8,
    description: []const u8,
    handler: fn ([]const u8) anyerror!void,
}{
    .{
        .name = "help",
        .description = "Display information about all supported commands",
        .handler = cmd_help,
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
};

fn cmd_help(args: []const u8) anyerror!void {
    _ = args;
    inline for (cmd_table) |cmd| {
        try stdout.print("{s} - {s}\n", .{ cmd.name, cmd.description });
    }
}

fn cmd_c(args: []const u8) anyerror!void {
    _ = args;
    cpu.cpu_exec(std.math.maxInt(u64));
}

fn cmd_si(args: []const u8) anyerror!void {
    _ = args;
    cpu.cpu_exec(1);
}

fn cmd_q(args: []const u8) anyerror!void {
    _ = args;
    return error.Exit;
}
