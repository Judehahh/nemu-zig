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

    // Standard target options allows the person running `zig build` to choose
    // what target to build for. Here we do not override the defaults, which
    // means any target is allowed, and the default is native. Other options
    // for restricting supported target set are available.
    const target = b.standardTargetOptions(.{});

    // Standard optimization options allow the person running `zig build` to select
    // between Debug, ReleaseSafe, ReleaseFast, and ReleaseSmall. Here we do not
    // set a preferred release mode, allowing the user to decide how to optimize.
    const optimize = b.standardOptimizeOption(.{});

    const exe = b.addExecutable(.{
        .name = "nemu-zig",
        .root_source_file = .{ .path = "src/main.zig" },
        .target = target,
        .optimize = optimize,
    });

    // For expr.
    const regex_lib = b.addStaticLibrary(.{
        .name = "regex_slim",
        .target = target,
        .optimize = optimize,
    });
    regex_lib.addIncludePath(.{ .path = "lib" });
    regex_lib.addCSourceFile(.{
        .file = .{
            .path = "lib/regex_slim.c",
        },
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
        llvm_lib.addIncludePath(.{ .path = "lib" });
        llvm_lib.addCSourceFile(.{
            .file = .{
                .path = "lib/llvm_slim.c",
            },
            .flags = &.{"-std=c99"},
        });
        llvm_lib.linkLibC();
        exe.linkLibrary(llvm_lib);
        exe.linkSystemLibrary("LLVM");
            }

    exe.addIncludePath(.{ .path = "lib" });
    exe.linkLibC();
    exe.root_module.addOptions("config", options);

    // This declares intent for the executable to be installed into the
    // standard location when the user invokes the "install" step (the default
    // step when running `zig build`).
    b.installArtifact(exe);

    // This *creates* a Run step in the build graph, to be executed when another
    // step is evaluated that depends on it. The next line below will establish
    // such a dependency.
    const run_cmd = b.addRunArtifact(exe);

    // By making the run step depend on the install step, it will be run from the
    // installation directory rather than directly from within the cache directory.
    // This is not necessary, however, if the application depends on other installed
    // files, this ensures they will be present and in the expected location.
    run_cmd.step.dependOn(b.getInstallStep());

    // This allows the user to pass arguments to the application in the build
    // command itself, like this: `zig build run -- arg1 arg2 etc`
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    // This creates a build step. It will be visible in the `zig build --help` menu,
    // and can be selected like this: `zig build run`
    // This will evaluate the `run` step rather than the default, which is "install".
    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    // Creates a step for unit testing. This only builds the test executable
    // but does not run it.
    const unit_tests = b.addTest(.{
        .root_source_file = .{ .path = "src/test.zig" },
        .target = target,
        .optimize = optimize,
    });

    unit_tests.root_module.addOptions("config", options);
    unit_tests.linkLibrary(regex_lib);
    unit_tests.addIncludePath(.{ .path = "lib" });
    unit_tests.linkLibC();

    const run_unit_tests = b.addRunArtifact(unit_tests);

    // Similar to creating the run step earlier, this exposes a `test` step to
    // the `zig build --help` menu, providing a way for the user to request
    // running the unit tests.
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_unit_tests.step);
}
