const std = @import("std");
const builtin = @import("builtin");
const Builder = std.build.Builder;
const LibExeObjStep = std.build.LibExeObjStep;
const CrossTarget = std.zig.CrossTarget;
const Mode = std.builtin.Mode;

// Although this function looks imperative, note that its job is to
// declaratively construct a build graph that will be executed by an external
// runner.
pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const lib = b.addSharedLibrary(.{
        .name = "cute",
        .target = target,
        // Standard optimization options allow the person running `zig build` to select
        // between Debug, ReleaseSafe, ReleaseFast, and ReleaseSmall. Here we do not
        // set a preferred release mode, allowing the user to decide how to optimize.
        .optimize = b.standardOptimizeOption(.{}),
    });
    lib.linkLibC();

    // const csources = [_][]const u8 {
    //     "stb.c"
    // };
    lib.addCSourceFile(.{
        .file = .{ .path = "cute.c" },
        .flags = &[_][]const u8{},
    });

    const opts = b.addOptions();
    const file_path = b.option([]const u8, "file-path", "Path to the file") orelse "./out";
    opts.addOption([]const u8, "file-path", file_path);
    b.lib_dir = std.mem.concat(std.heap.page_allocator, u8, &[_][]const u8{ file_path, if (target.result.isWasm()) "/libs/runtimes/wasi-wasm/native" else if (target.result.isDarwin()) "/libs/runtimes/osx-arm64/native" else if (lib.rootModuleTarget().os.tag == .linux) "/libs/runtimes/linux-x64/native" else if (lib.rootModuleTarget().os.tag == .windows) "/libs/runtimes/win-x64/native" else "/libs/runtimes/unknown/native" }) catch |err| {
        std.debug.print("Failed to concatenate strings: {}\n", .{err});
        return;
    };

    b.installArtifact(lib);
}
