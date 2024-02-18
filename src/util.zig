const std = @import("std");
const config = @import("config");
const common = @import("common.zig");

const word_t = common.word_t;
const sword_t = common.sword_t;

// log
pub const AnsiColor = enum {
    fg_black,
    fg_red,
    fg_green,
    fg_yellow,
    fg_blue,
    fg_magenta,
    fg_cyan,
    fg_white,
    bg_black,
    bg_red,
    bg_green,
    bg_yellow,
    bg_blue,
    bg_magenta,
    bg_cyan,
    bg_white,
    reset,
    none,

    inline fn code(self: AnsiColor) []const u8 {
        return switch (self) {
            .fg_black => "\x1B[1;30m",
            .fg_red => "\x1B[1;31m",
            .fg_green => "\x1B[1;32m",
            .fg_yellow => "\x1B[1;33m",
            .fg_blue => "\x1B[1;34m",
            .fg_magenta => "\x1B[1;35m",
            .fg_cyan => "\x1B[1;36m",
            .fg_white => "\x1B[1;37m",
            .bg_black => "\x1B[1;40m",
            .bg_red => "\x1B[1;41m",
            .bg_green => "\x1B[1;42m",
            .bg_yellow => "\x1B[1;43m",
            .bg_blue => "\x1B[1;44m",
            .bg_magenta => "\x1B[1;45m",
            .bg_cyan => "\x1B[1;46m",
            .bg_white => "\x1B[1;47m",
            .reset => "\x1B[0m",
            .none => "",
        };
    }
};

pub inline fn ansi_fmt(comptime fmt: []const u8, comptime fg: AnsiColor, comptime bg: ?AnsiColor) []const u8 {
    return fg.code() ++ (bg orelse AnsiColor.none).code() ++ fmt ++ AnsiColor.reset.code();
}

pub inline fn log(comptime src: std.builtin.SourceLocation, comptime fmt: []const u8, args: anytype) void {
    std.debug.print(ansi_fmt("[{s}:{d} {s}] ", AnsiColor.fg_blue, null), .{ src.file, src.line, src.fn_name });
    std.debug.print(ansi_fmt(fmt, AnsiColor.fg_blue, null), args);
}

pub inline fn panic(comptime fmt: []const u8, args: anytype) void {
    std.debug.panic(ansi_fmt(fmt, AnsiColor.fg_red, null), args);
}

// tokens
// pub inline fn print_tokens(tokens: std.mem.TokenIterator(u8, .any)) void {
//     var tks = tokens;
//     while (tks.next()) |tk| {
//         std.debug.print("{s}", .{tk});
//     }
// }

// bits
inline fn bitmask(bit: usize) word_t {
    return (1 << bit) - 1;
}

pub inline fn bits(x: word_t, hi: usize, lo: usize) word_t {
    return (x >> lo) & bitmask(hi - lo + 1);
}

pub inline fn sext(x: word_t, len: usize) word_t {
    const shift = if (config.ISA64) 64 else 32 - len;
    return @bitCast(std.math.shr(sword_t, @as(sword_t, @bitCast(std.math.shl(word_t, x, shift))), shift));
}
