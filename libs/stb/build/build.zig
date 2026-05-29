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

    // Tell zinc_export.h we're compiling the DLL side (so ZINC_EXPORT becomes dllexport on
    // Windows / default visibility on Mach-O/ELF). Mirrors sokol's SOKOL_DLL convention; one
    // build flag controls every TU in this lib instead of each .c file rolling its own.
    const c_flags = [_][]const u8{"-DZINC_BUILDING_DLL"};

    mod.addCSourceFile(.{ .file = b.path("stb.c"), .flags = &c_flags });

    // Native GPU->CPU readback for screenshots used to live here; it moved to
    // libs/zinc_platform/build/ so this DLL is just stb_image + stb_image_write.

    const lib = b.addLibrary(.{
        .name = "stb",
        .root_module = mod,
        .linkage = .dynamic,
    });

    const tgt = target.result;
    const native_dir = std.mem.concat(b.allocator, u8, &.{
        file_path,
        if (tgt.cpu.arch.isWasm()) "/libs/runtimes/browser-wasm/native"
        else if (tgt.os.tag.isDarwin()) "/libs/runtimes/osx-arm64/native"
        else if (tgt.os.tag == .linux) "/libs/runtimes/linux-x64/native"
        else if (tgt.os.tag == .windows) "/libs/runtimes/win-x64/native"
        else "/libs/runtimes/unknown/native",
    }) catch @panic("install path concat failed");
    b.lib_dir = native_dir;
    // Windows separates the .dll (bin) from its import .lib (lib). Force both into the same
    // single "native" directory so consumers don't have to know about that split — the .NET
    // DllImport runtime only looks alongside the import lib, and Zinc bundles everything from
    // libs/runtimes/<rid>/native/ into the published app.
    b.exe_dir = native_dir;

    b.installArtifact(lib);
}
