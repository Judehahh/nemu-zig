const std = @import("std");

// Although this function looks imperative, note that its job is to
// declaratively construct a build graph that will be executed by an external
// runner.
pub fn build(b: *std.Build) void {
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

    // For regex clib.
    const lib = b.addStaticLibrary(.{
        .name = "regex_slim",
        .target = target,
        .optimize = optimize,
    });

    lib.addIncludePath(.{ .path = "lib" });
    lib.addCSourceFile(.{
        .file = .{
            .path = "lib/regex_slim.c",
        },
        .flags = &.{"-std=c99"},
    });
    lib.linkLibC();
    exe.linkLibrary(lib);
    exe.addIncludePath(.{ .path = "lib" });
    exe.linkLibC();

    // Build Configs.
    const ISA = b.option([]const u8, "ISA", "ISA running in NEMU") orelse "riscv32";
    const ISA64 = b.option(bool, "ISA64", "whether it is a 64-bit architecture(true or flase)") orelse false;
    const MBASE = b.option(u32, "MBASE", "memory base") orelse 0x80000000;
    const MSIZE = b.option(u32, "MSIZE", "memory size") orelse 0x8000000;
    const PC_RESET_OFFSET = b.option(u32, "PC_RESET_OFFSET", "pc reset offset") orelse 0;

    const options = b.addOptions();
    options.addOption([]const u8, "ISA", ISA);
    options.addOption(bool, "ISA64", ISA64);
    options.addOption(u32, "MBASE", MBASE);
    options.addOption(u32, "MSIZE", MSIZE);
    options.addOption(u32, "PC_RESET_OFFSET", PC_RESET_OFFSET);

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
}
