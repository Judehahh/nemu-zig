//! Implement for getopt in zig.
//! From https://github.com/dmgk/zig-getopt

const std = @import("std");
const ascii = std.ascii;
const mem = std.mem;
const os = std.os;
const expect = std.testing.expect;

/// Parsed option struct.
pub const Option = struct {
    /// Option character.
    opt: u8,

    /// Option argument, if any.
    arg: ?[]const u8 = null,
};

pub const GetoptError = error{ InvalidOption, MissingArgument };

pub const OptionsIterator = struct {
    argv: [][*:0]const u8,
    opts: []const u8,

    /// Index of the current element of the argv vector.
    optind: usize = 1,

    optpos: usize = 1,

    /// Current option character.
    optopt: u8 = undefined,

    pub fn next(self: *OptionsIterator) GetoptError!?Option {
        if (self.optind == self.argv.len)
            return null;

        const arg = self.argv[self.optind];

        if (mem.eql(u8, mem.span(arg), "--")) {
            self.optind += 1;
            return null;
        }

        if (arg[0] != '-' or !ascii.isAlphanumeric(arg[1]))
            return null;

        self.optopt = arg[self.optpos];

        const maybe_idx = mem.indexOfScalar(u8, self.opts, self.optopt);
        if (maybe_idx) |idx| {
            if (idx < self.opts.len - 1 and self.opts[idx + 1] == ':') {
                if (arg[self.optpos + 1] != 0) {
                    const res = Option{
                        .opt = self.optopt,
                        .arg = mem.span(arg + self.optpos + 1),
                    };
                    self.optind += 1;
                    self.optpos = 1;
                    return res;
                } else if (self.optind + 1 < self.argv.len) {
                    const res = Option{
                        .opt = self.optopt,
                        .arg = mem.span(self.argv[self.optind + 1]),
                    };
                    self.optind += 2;
                    self.optpos = 1;
                    return res;
                } else return GetoptError.MissingArgument;
            } else {
                self.optpos += 1;
                if (arg[self.optpos] == 0) {
                    self.optind += 1;
                    self.optpos = 1;
                }
                return Option{ .opt = self.optopt };
            }
        } else return GetoptError.InvalidOption;
    }

    /// Return remaining arguments, if any.
    pub fn args(self: *OptionsIterator) ?[][*:0]const u8 {
        if (self.optind < self.argv.len)
            return self.argv[self.optind..]
        else
            return null;
    }
};

pub fn getoptArgv(argv: [][*:0]const u8, optstring: []const u8) OptionsIterator {
    return OptionsIterator{
        .argv = argv,
        .opts = optstring,
    };
}

/// Parse os.argv according to the optstring.
pub fn getopt(optstring: []const u8) OptionsIterator {
    // https://github.com/ziglang/zig/issues/8808
    const argv: [][*:0]const u8 = os.argv;
    return getoptArgv(argv, optstring);
}
