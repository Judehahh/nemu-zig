const std = @import("std");
const config = @import("config");
const memory = @import("../memory.zig");
const isa = @import("../isa/common.zig").isa;
const sdb = @import("sdb.zig");
const util = @import("../util.zig");
const disasm = @import("../disasm.zig");
const getopt = @import("../getopt.zig");
const difftest = @import("../difftest.zig");
const device = @import("../device/device.zig");

var log_file: ?[]const u8 = null;
var diff_so_file: ?[]const u8 = null;
var img_file: ?[]const u8 = null;
var difftest_port: c_int = 1234;

pub fn init_monitor() void {
    // Parse arguments.
    parse_args();

    // Open the log file.
    util.init_log(log_file);

    // Initialize memory.
    memory.init_mem();

    // Initialize devices.
    if (config.DEVICE) {
        device.init_device();
    }

    // Perform ISA dependent initialization.
    isa.init_isa();

    // Load the image to memory. This will overwrite the built-in image.
    const img_size = load_img();

    // Initialize differential testing.
    if (config.DIFFTEST) {
        difftest.init_difftest(diff_so_file, img_size, difftest_port);
    }

    // Initialize the simple debugger.
    sdb.init_sdb();

    // Initialize disassembler.
    if (config.ITRACE) {
        disasm.init_disasm(config.ISA ++ "-pc-linux-gnu");
    }

    // Display welcome message.
    welcome();
}

pub fn deinit_monitor() void {
    util.deinit_log();
    sdb.deinit_sdb();
}

fn parse_args() void {
    const usage =
        \\Usage: nemu-zig [options] IMAGE [args]
        \\
        \\Options:
        \\  -l [file]       output log to FILE
        \\  -d [file]       run DiffTest with reference REF_SO
        \\  -p [num]        run DiffTest with port PORT
        \\
    ;

    var opts = getopt.getopt("hl:d:p:");

    while (opts.next()) |maybe_opt| {
        if (maybe_opt) |opt| {
            switch (opt.opt) {
                'l' => {
                    log_file = opt.arg;
                },
                'd' => {
                    diff_so_file = opt.arg;
                },
                'p' => {
                    difftest_port = std.fmt.parseInt(c_int, opt.arg.?, 10) catch {
                        util.panic("invalid port number: {?s}\n", .{opt.arg});
                    };
                },
                'h' => {
                    std.debug.print("{s}", .{usage});
                    std.os.exit(0);
                },
                else => unreachable,
            }
        } else break;
    } else |err| {
        switch (err) {
            getopt.GetoptError.InvalidOption => {
                std.debug.print("{s}: invalid option -- '{c}'\n{s}\n", .{ std.os.argv[0], opts.optopt, usage });
                std.os.exit(0);
            },
            getopt.GetoptError.MissingArgument => {
                std.debug.print("{s}: option requires an argument -- '{c}'\n{s}", .{ std.os.argv[0], opts.optopt, usage });
                std.os.exit(0);
            },
        }
    }

    if (opts.args() != null) {
        img_file = std.mem.span(opts.args().?[0]);
    }
}

fn load_img() usize {
    if (img_file == null) {
        util.log(@src(), "No image is given. Use the default build-in image.\n", .{});
        return 4096; // built-in image size
    }

    const file = std.fs.cwd().openFile(img_file.?, .{ .mode = .read_only }) catch {
        util.panic("Can not open {s}\n", .{img_file.?});
    };
    defer file.close();

    const size = file.getEndPos() catch {
        util.panic("Can not get size of {s}\n", .{img_file.?});
    };
    util.log(@src(), "The image is {s}, size = {d}\n", .{ img_file.?, size });

    _ = file.readAll(memory.pmem[memory.reset_offset..]) catch {
        util.panic("Can not read {s}\n", .{img_file.?});
    };

    return size;
}

fn welcome() void {
    util.log(@src(), "Build time: {s}\n", .{config.build_time});
    std.debug.print("Welcome to {s}-NEMU in Zig!\n", .{util.ansi_fmt(config.ISA, util.AnsiColor.fg_yellow, util.AnsiColor.bg_red)});
    std.debug.print("For help, type \"help\".\n", .{});
}
