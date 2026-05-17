const std = @import("std");
const builtin = @import("builtin");
const Build = std.Build;

pub fn build(b: *Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const lib = b.addSharedLibrary(.{
        .name = "stb",
        .target = target,
        .optimize = optimize,
    });
    lib.linkLibC();

    lib.addCSourceFile(.{
        .file = .{ .path = "stb.c" },
        .flags = &[_][]const u8{},
    });

    const file_path = b.option([]const u8, "file-path", "Path to the file") orelse "./out";
    b.lib_dir = std.mem.concat(std.heap.page_allocator, u8, &[_][]const u8{
        file_path,
        if (target.result.isWasm())
            "/libs/runtimes/browser-wasm/native"
        else if (target.result.isDarwin())
            "/libs/runtimes/osx-arm64/native"
        else if (lib.rootModuleTarget().os.tag == .linux)
            "/libs/runtimes/linux-x64/native"
        else if (lib.rootModuleTarget().os.tag == .windows)
            "/libs/runtimes/win-x64/native"
        else
            "/libs/runtimes/unknown/native",
    }) catch |err| {
        std.debug.print("Failed to concatenate strings: {}\n", .{err});
        return;
    };

    b.installArtifact(lib);
}
