const std = @import("std");
const Build = std.Build;

pub fn build(b: *Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const file_path = b.option([]const u8, "file-path", "Output root for installed artifacts") orelse "./out";

    const mod = b.addModule("stb_clib", .{
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    mod.addCSourceFile(.{ .file = b.path("stb.c"), .flags = &.{} });

    const lib = b.addLibrary(.{
        .name = "stb",
        .root_module = mod,
        .linkage = .dynamic,
    });

    const tgt = target.result;
    b.lib_dir = std.mem.concat(b.allocator, u8, &.{
        file_path,
        if (tgt.cpu.arch.isWasm()) "/libs/runtimes/browser-wasm/native"
        else if (tgt.os.tag.isDarwin()) "/libs/runtimes/osx-arm64/native"
        else if (tgt.os.tag == .linux) "/libs/runtimes/linux-x64/native"
        else if (tgt.os.tag == .windows) "/libs/runtimes/win-x64/native"
        else "/libs/runtimes/unknown/native",
    }) catch @panic("install path concat failed");

    b.installArtifact(lib);
}
