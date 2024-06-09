const std = @import("std");
const builtin = @import("builtin");

// Although this function looks imperative, note that its job is to
// declaratively construct a build graph that will be executed by an external
// runner.
pub fn build(b: *std.Build) void {
    // Build Configs.
    const ISA = b.option([]const u8, "ISA", "ISA running in NEMU") orelse "riscv32";
    const ISA64 = b.option(bool, "ISA64", "Whether it is a 64-bit architecture(true or flase)") orelse false;
    const MBASE = b.option(u32, "MBASE", "Memory base") orelse 0x80000000;
    const MSIZE = b.option(u32, "MSIZE", "Memory size") orelse 0x8000000;
    const PC_RESET_OFFSET = b.option(u32, "PC_RESET_OFFSET", "PC reset offset") orelse 0;
    const ITRACE = b.option(bool, "ITRACE", "Enable instruction tracer") orelse false;
    const DIFFTEST = b.option(bool, "DIFFTEST", "Enable differential testing") orelse false;

    const DEVICE = b.option(bool, "DEVICE", "Enable devices") orelse true;
    const HAS_SERIAL = if (DEVICE) b.option(bool, "HAS_SERIAL", "Enable serial device") orelse true else false;
    const SERIAL_MMIO = b.option(u32, "SERIAL_MMIO", "Serial mmio base") orelse 0xa00003f8;
    const HAS_RTC = if (DEVICE) b.option(bool, "HAS_RTC", "Enable rtc device") orelse true else false;
    const RTC_MMIO = b.option(u32, "RTC_MMIO", "RTC mmio base") orelse 0xa0000048;

    const options = b.addOptions();
    options.addOption([]const u8, "ISA", ISA);
    options.addOption(bool, "ISA64", ISA64);
    options.addOption(u32, "MBASE", MBASE);
    options.addOption(u32, "MSIZE", MSIZE);
    options.addOption(u32, "PC_RESET_OFFSET", PC_RESET_OFFSET);
    options.addOption(bool, "ITRACE", ITRACE);
    options.addOption(bool, "DIFFTEST", DIFFTEST);

    options.addOption(bool, "DEVICE", DEVICE);
    if (DEVICE) options.addOption(bool, "HAS_SERIAL", HAS_SERIAL);
    if (HAS_SERIAL) options.addOption(u32, "SERIAL_MMIO", SERIAL_MMIO);
    if (DEVICE) options.addOption(bool, "HAS_RTC", HAS_RTC);
    if (HAS_RTC) options.addOption(u32, "RTC_MMIO", RTC_MMIO);

    // build time
    {
        var build_time: [32]u8 = undefined;
        const n = std.time.timestamp();
        const es = std.time.epoch.EpochSeconds{ .secs = @as(u64, @intCast(n)) };
        const ds = es.getDaySeconds();
        const ed = es.getEpochDay();
        const yd = ed.calculateYearDay();
        const md = yd.calculateMonthDay();

        _ = std.fmt.bufPrint(&build_time, "{}-{:0>2}-{:0>2} {:0>2}:{:0>2}:{:0>2}", .{
            yd.year,
            md.month.numeric(),
            md.day_index + 1,
            @mod(ds.getHoursIntoDay() + 8, 24), // Shanghai
            ds.getMinutesIntoHour(),
            ds.getSecondsIntoMinute(),
        }) catch @panic("bufPrint build_time failed");

        options.addOption([]const u8, "build_time", std.mem.sliceTo(&build_time, 0));
    }

    const target = b.standardTargetOptions(.{});

    const optimize = b.standardOptimizeOption(.{});

    const exe = b.addExecutable(.{
        .name = "nemu-zig",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    // For expr.
    const regex_lib = b.addStaticLibrary(.{
        .name = "regex_slim",
        .target = target,
        .optimize = optimize,
    });
    regex_lib.addIncludePath(b.path("lib"));
    regex_lib.addCSourceFile(.{
        .file = b.path("lib/regex_slim.c"),
        .flags = &.{"-std=c99"},
    });
    regex_lib.linkLibC();
    exe.linkLibrary(regex_lib);

    // For itrace.
    if (ITRACE) {
        const llvm_lib = b.addStaticLibrary(.{
            .name = "llvm_slim",
            .target = target,
            .optimize = optimize,
        });
        llvm_lib.addIncludePath(b.path("lib"));
        llvm_lib.addCSourceFile(.{
            .file = b.path("lib/llvm_slim.c"),
            .flags = &.{"-std=c99"},
        });
        llvm_lib.linkLibC();
        exe.linkLibrary(llvm_lib);
        exe.linkSystemLibrary("LLVM");
    }

    exe.addIncludePath(b.path("lib"));
    exe.linkLibC();
    exe.root_module.addOptions("config", options);

    b.installArtifact(exe);

    // zig build run
    const run_cmd = b.addRunArtifact(exe);

    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    // zig test
    const unit_tests = b.addTest(.{
        .root_source_file = b.path("src/test.zig"),
        .target = target,
        .optimize = optimize,
    });

    unit_tests.root_module.addOptions("config", options);
    unit_tests.linkLibrary(regex_lib);
    unit_tests.addIncludePath(b.path("lib"));
    unit_tests.linkLibC();

    const run_unit_tests = b.addRunArtifact(unit_tests);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_unit_tests.step);
}
